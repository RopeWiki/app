#!/usr/bin/env python3

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import IntEnum
import glob
import json
import os
import platform
import re
import shlex
import subprocess
import sys
import time
from typing import Callable, Dict, List, Optional, Tuple


class LogLevel(IntEnum):
  """Log levels for controlling output verbosity"""
  DEBUG = 10
  INFO = 20
  WARNING = 30
  ERROR = 40


# Global verbosity setting
_log_level: LogLevel = LogLevel.INFO


@dataclass
class SiteConfig(object):
  name: str

  hostname: str
  protocol: str

  robots: str

  logs_folder: str
  sql_backup_folder: str
  images_folder: str
  proxy_config_folder: str

  db_service = 'ropewiki_db'
  db_volume = 'ropewiki_database_storage'
  reverse_proxy_service = 'ropewiki_reverse_proxy'
  webserver_service = 'ropewiki_webserver'
  backup_manager_service = 'ropewiki_backup_manager'
  mailserver_service = 'ropewiki_mailserver'

  secrets: Dict[str, str] = field(repr=False)

  @property
  def db_container(self) -> str:
    return '{}-{}-1'.format(self.name, self.db_service)

  @property
  def db_hostname(self) -> str:
    return self.db_service

  @property
  def backup_manager_container(self) -> str:
    return '{}-{}-1'.format(self.name, self.backup_manager_service)

  @property
  def db_password(self) -> str:
    return self.secrets['WG_DB_PASSWORD']

  @property
  def root_db_password(self) -> str:
    return self.secrets['RW_ROOT_DB_PASSWORD']


deploy_commands: Dict[str, Callable[[SiteConfig, List[str]], None]] = {}

def deploy_command(func: Callable[[SiteConfig, List[str]], None]):
  global deploy_commands
  deploy_commands[func.__name__] = func
  return func

def make_argparse() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(
    usage="%(prog)s [SITE_CONFIG_NAME] [COMMAND]",
    description="Perform a RopeWiki deployment action"
  )
  parser.add_argument(
    'site_config_name',
    metavar='SITE_CONFIG_NAME',
    help='Site configuration name matching SITE_CONFIG_NAME.json in site_configs and site_configs/secrets')
  parser.add_argument(
    'command',
    metavar='COMMAND',
    choices=list(deploy_commands),
    help='Deployment command to execute: {{{}}}'.format('|'.join(deploy_commands)))
  parser.add_argument(
    'options',
    metavar='OPTIONS',
    nargs='*',
    help='Additional options for certain deployment commands')

  verbosity_group = parser.add_mutually_exclusive_group()
  verbosity_group.add_argument(
    '-v', '--verbose',
    action='store_true',
    help='Enable verbose output (DEBUG level)')
  verbosity_group.add_argument(
    '-q', '--quiet',
    action='store_true',
    help='Quiet mode - only show warnings and errors')

  return parser

@dataclass
class UserArgs(object):
  site_config: SiteConfig
  command: str
  options: List[str]

def get_args() -> UserArgs:
  global _log_level
  args = make_argparse().parse_args()

  # Set log level based on verbosity flags
  if args.verbose:
    _log_level = LogLevel.DEBUG
  elif args.quiet:
    _log_level = LogLevel.WARNING

  return UserArgs(site_config=load_site_config(args.site_config_name), command=args.command, options=args.options)

def load_site_config(config_name: str) -> SiteConfig:
  config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'site_configs', config_name + '.json')
  with open(config_path, 'r') as f:
    config = json.load(f)
  secrets_path = os.path.join(os.path.dirname(config_path), 'secrets', config_name + '.json')
  try:
    with open(secrets_path, 'r', encoding='utf-8-sig') as f:
      secrets = json.load(f)
  except FileNotFoundError:
    sys.exit(f'Missing secrets file: {secrets_path}. Copy site_configs/secrets/example.json.template '
             f'to this path and fill in the deployment credentials.')
  except json.JSONDecodeError as error:
    sys.exit(f'Invalid JSON in {secrets_path} at line {error.lineno}, column {error.colno}.')
  except UnicodeError:
    sys.exit(f'Secrets file {secrets_path} must use UTF-8 encoding.')
  except OSError:
    sys.exit(f'Could not read secrets file: {secrets_path}. Check its permissions.')
  if not isinstance(secrets, dict):
    sys.exit(f'Secrets file {secrets_path} must contain a JSON object.')
  required_keys = {'WG_DB_PASSWORD', 'RW_ROOT_DB_PASSWORD', 'RW_SMTP_USERNAME', 'RW_SMTP_PASSWORD'}
  optional_keys = {'RW_SMTP_HOST', 'RW_SMTP_PORT'}
  for key in sorted(required_keys | (secrets.keys() & optional_keys)):
    value = secrets.get(key)
    if not isinstance(value, str) or not value.strip() or any(c in value for c in '\r\n\0'):
      sys.exit(f'{key} in {secrets_path} must be a non-empty, single-line string.')
  config['name'] = config_name
  config['secrets'] = secrets
  return SiteConfig(**config)

def log(msg: str, level: LogLevel = LogLevel.INFO):
  """Log a message at the specified level.

  Args:
    msg: The message to log
    level: The log level (DEBUG, INFO, WARNING, ERROR). Defaults to INFO.
  """
  global _log_level
  if level < _log_level:
    return

  level_prefix = {
    LogLevel.DEBUG: "[DEBUG]",
    LogLevel.INFO: "[INFO] ",
    LogLevel.WARNING: "[WARN] ",
    LogLevel.ERROR: "[ERROR]"
  }.get(level, "[INFO] ")

  timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
  print("{} deploy_tool {} {}".format(timestamp, level_prefix, msg))

def run_cmd(cmd: str, capture_result=False) -> Optional[str]:
  log('  RUN {}'.format(cmd), LogLevel.DEBUG)
  if capture_result:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, shell=True)
    stdout = p.stdout
    if p.returncode != 0:
      print(stdout)
      log('Return code {}'.format(p.returncode), LogLevel.ERROR)
      sys.exit(p.returncode)
    if not isinstance(stdout, str):
      stdout = stdout.decode('utf-8')
    return stdout
  else:
    try:
      subprocess.check_call(cmd, shell=True)
    except subprocess.CalledProcessError as _:
      log(f"Error running command '{cmd}'; rerunning to capture result...", LogLevel.ERROR)
      run_cmd(cmd, capture_result=True)
      raise
    return None

def make_env_var_safe(s: str) -> str:
  return s.replace('\n', '<br>').replace('"', '&quot;')

_codebase_version = None
def get_codebase_version() -> str:
  global _codebase_version
  if _codebase_version is None:
    timestamp = 'Built {} UTC, {} local'.format(
      datetime.now(timezone.utc).isoformat('T', 'seconds'), datetime.now().isoformat('T', 'seconds'))
    gitlog = make_env_var_safe(run_cmd('git log -n 1', True))
    m = re.search(r'commit ([a-f0-9]+)', gitlog)
    if m:
      commit = 'https://github.com/RopeWiki/app/tree/{}'.format(m.group(1))
    else:
      commit = 'Could not determine commit'
    gitstatus = make_env_var_safe(run_cmd('git status', True).replace('\n', '<br>'))
    _codebase_version = ('<h2>Build</h2><p>{timestamp}</p>' +
                         '<h2>Commit</h2><p>{commit}</p>' +
                         '<h2>git log -n 1</h2><pre>{gitlog}</pre>' +
                         '<h2>git status</h2><pre>{gitstatus}</pre>').format(
      timestamp=timestamp, commit=commit, gitlog=gitlog, gitstatus=gitstatus)
  return _codebase_version

def make_docker_compose_script(cmd: str, site_config: SiteConfig) -> Tuple[str, str]:
  docker_compose_command = 'docker compose -p {name} {cmd}'.format(name=site_config.name, cmd=cmd)
  variables = {
    **site_config.secrets,
    'RW_SMTP_HOST': site_config.secrets.get('RW_SMTP_HOST', 'smtp.gmail.com'),
    'RW_SMTP_PORT': site_config.secrets.get('RW_SMTP_PORT', '587'),
    'MYSQL_ROOT_PASSWORD': site_config.root_db_password,
    'WG_HOSTNAME': site_config.hostname,
    'WG_PROTOCOL': site_config.protocol,
    'SQL_BACKUP_FOLDER': site_config.sql_backup_folder,
    'IMAGES_FOLDER': site_config.images_folder,
    'PROXY_CONFIG_FOLDER': site_config.proxy_config_folder,
    'CODEBASE_VERSION': get_codebase_version(),
    'RW_ROBOTS': site_config.robots,
  }
  if platform.system() == 'Windows':
    # Disable delayed expansion and escape batch-file metacharacters in values.
    declarations = ['@echo off', 'setlocal DisableDelayedExpansion']
    for key, value in variables.items():
      escaped = value.replace('^', '^^').replace('%', '%%')
      for char in '&|<>()"':
        escaped = escaped.replace(char, '^' + char)
      declarations.append(f'set {key}={escaped}')
  else:
    declarations = [f'export {key}={shlex.quote(value)}' for key, value in variables.items()]
  variable_declarations = '\n'.join(declarations)
  return variable_declarations, docker_compose_command

def run_docker_compose(cmd: str, site_config: SiteConfig, capture_result=False) -> str:
  script_name = 'docker_compose_command.bat' if platform.system() == 'Windows' else 'docker_compose_command.sh'
  script = os.path.join(os.path.dirname(os.path.abspath(__file__)), script_name)
  variable_declarations, docker_compose_command = make_docker_compose_script(cmd, site_config)
  with open(script, 'w') as f:
    f.write(variable_declarations + '\n' + docker_compose_command + '\n')
  log('  SCRIPT {}'.format(docker_compose_command), LogLevel.DEBUG)
  run_script = '{script} && del {script}' if platform.system() == 'Windows' else 'sh {script} && rm {script}'
  return run_cmd(run_script.format(script=script), capture_result=capture_result)

def execute_sql(sql_cmd: str, user: str, site_config: SiteConfig):
  run_cmd('docker container exec {db_container} mysql -u{user} -p{password} --host {db_hostname} -e "{cmd}"'.format(
    db_container=site_config.db_container,
    user=user,
    password=site_config.root_db_password if user == 'root' else site_config.db_password,
    db_hostname=site_config.db_hostname,
    cmd=sql_cmd))

def get_docker_volumes() -> List[str]:
  lines = run_cmd('docker volume ls', capture_result=True).split('\n')
  offset = lines[0].index('VOLUME NAME')
  return [line[offset:] for line in lines[1:]]

def latest_sql_backup(site_config: SiteConfig) -> str:
  patterns = ('*.sql', '*.sql.zst')
  sql_backups = [f for pattern in patterns for f in glob.iglob(os.path.join(site_config.sql_backup_folder, pattern))]
  if not sql_backups:
      sys.exit(f'Could not find latest backup in {site_config.sql_backup_folder}')
  return max(sql_backups).strip()

@deploy_command
def get_sql_backup_legacy(site_config: SiteConfig, options: List[str]):
  if platform.system() == 'Windows':
    sys.exit('This operation cannot be performed on Windows.  Instead, using WinSCP to connect to db01.ropewiki.com ' +
             'and copy the latest .gz backup from /root/backups to {} and then unzip it.'.format(
               site_config.sql_backup_folder))
  log('Finding latest database backup...')
  latest_backup_zip = run_cmd(
    'ssh root@db01.ropewiki.com "cd /root/backups ; ls -1 -t *.gz | head -1"',
    capture_result=True).strip('\n')
  log('  -> Found {}.'.format(latest_backup_zip))
  latest_backup = latest_backup_zip[:-3]
  local_target = os.path.join(site_config.sql_backup_folder, latest_backup)
  if os.path.exists(local_target):
    log('{} is already present locally at {}'.format(latest_backup, local_target))
    log('  -> Using pre-existing {}.'.format(latest_backup))
  else:
    log('Copying latest database backup locally...')
    run_cmd('mkdir -p {}'.format(site_config.sql_backup_folder))
    log_file = os.path.join(site_config.logs_folder, 'get_sql.log')
    run_cmd('touch {}'.format(log_file))
    zip_target = os.path.join(site_config.sql_backup_folder, latest_backup_zip)
    cmd = (
      'rsync -arv' +
      ' root@db01.ropewiki.com:/root/backups/{} {}'.format(latest_backup_zip, zip_target) +
      ' 2>&1 | tee {}'.format(log_file))
    run_cmd(cmd)
    log('  -> Copied.')
    log('Unzipping {}...'.format(latest_backup_zip))
    run_cmd('gunzip -f {}'.format(zip_target))
    log('  -> Unzipped {}.'.format(latest_sql_backup(site_config)))

@deploy_command
def print_latest_sql_backup(site_config: SiteConfig, options: List[str]):
  print(latest_sql_backup(site_config))

@deploy_command
def get_images_legacy(site_config: SiteConfig, options: List[str]):
  """Retrieve latest files in /images folder from remote server at ropewiki.com

  Requires SSH access to ropewiki.com.
  """
  if platform.system() == 'Windows':
    sys.exit('This operation cannot be performed on Windows.  Instead, using WinSCP to connect to ropewiki.com and ' +
             'synchronize the contents of /usr/share/nginx/html/ropewiki/images/ to {}.'.format(
               site_config.images_folder))

  # NOTE: this requires public key authentication to the remote server
  log("Copying latest /images content locally...")
  log_file = os.path.join(site_config.logs_folder, 'images_backup.log')
  run_cmd('touch {}'.format(log_file))
  cmd = (
    'rsync -arv' +
    ' root@ropewiki.com:/usr/share/nginx/html/ropewiki/images/' +
    ' {}'.format(site_config.images_folder) +
    ' 2>&1 > {}'.format(log_file))
  run_cmd(cmd)
  log('  -> Latest /images content copied locally.')

@deploy_command
def create_db(site_config: SiteConfig, options: List[str]):
  """Intended to be run once to create an empty database while deploying a production system.

  It sets up the ropewiki_db service defined in docker-compose.yaml"""
  log('Deleting/cleaning up any existing database...')

  # Ensure the database is down
  run_docker_compose('stop {db_service}'.format(db_service=site_config.db_service), site_config)

  # Clean up any existing volumes
  run_docker_compose('rm -v -f {db_service}'.format(db_service=site_config.db_service), site_config)
  volumes = get_docker_volumes()
  if site_config.db_volume in volumes:
    run_cmd('docker volume rm {db_volume}'.format(db_volume=site_config.db_volume))

  # Bring the database and backup manager up
  run_docker_compose(f'up -d {site_config.db_service} {site_config.backup_manager_service}', site_config)

  # Wait for container to come up
  log('>> Waiting for MySQL database to initialize...')
  time.sleep(5)
  while True:
    db_status = run_cmd(
      'docker inspect --format "{{{{.State.Status}}}}" {}'.format(site_config.db_container),
      capture_result=True).strip()
    log('    DB status: ' + db_status, LogLevel.DEBUG)
    if db_status == 'running':
      # We *think* it's ready, but it's actually likely not.  It apparently has to effectively start twice >:|
      db_logs = run_cmd('docker container logs {}'.format(site_config.db_container), capture_result=True)
      ready_count = db_logs.count('ready for connections')
      log('    Ready count: {}'.format(ready_count), LogLevel.DEBUG)
      if ready_count >= 2:
        break
    if db_status == 'exited':
      log('Container exited unexpectedly; logs:', LogLevel.ERROR)
      run_cmd('docker container logs {}'.format(site_config.db_container))
      sys.exit('The container {} exited unexpectedly'.format(site_config.db_container))
    time.sleep(10)

  # Create an empty ropewiki database
  log('>> Creating empty ropewiki database...')
  run_cmd(
    'docker container exec {}'.format(site_config.db_container) +
    ' mysqladmin -u root -p{} create ropewiki'.format(site_config.root_db_password))

  # Create the ropewiki user
  log('>> Creating ropewiki user...')
  execute_sql("CREATE USER 'ropewiki'@'%' IDENTIFIED BY '{}';".format(
    site_config.db_password), 'root', site_config)
  execute_sql("GRANT ALL PRIVILEGES ON * . * TO 'ropewiki'@'%';", 'root', site_config)
  execute_sql("FLUSH PRIVILEGES;", 'root', site_config)

  log('RopeWiki database initialized successfully.')

def load_sql(site_config: SiteConfig, backup_path: str):
  if backup_path.endswith('.sql.zst'):
      cat_tool = 'unzstd -c'
  elif platform.system() == 'Windows':
      cat_tool = 'type'
  else:
      cat_tool = 'cat'

  response = input(f"Restore {backup_path}? (y/n): ").lower()
  if response not in ("y", "yes"):
    log('Aborting restore')
    sys.exit(1)

  log('Ensuring backup manager is available...')
  run_docker_compose('up -d {backup_manager_service}'.format(backup_manager_service=site_config.backup_manager_service), site_config)

  log('Loading {}...'.format(backup_path))
  log('  (NOTE: this operation usually takes a few minutes)')
  cmd = '{cat_tool} {backup_path} | docker container exec -i {db_container} mysql -uroot -p{root_db_password} --host {db_hostname} ropewiki'
  cmd = cmd.format(
    cat_tool=cat_tool, backup_path=backup_path, db_container=site_config.backup_manager_container,
    root_db_password=site_config.root_db_password, db_hostname=site_config.db_hostname)
  run_cmd(cmd)
  log('  -> Backup restored.')

@deploy_command
def restore_db(site_config: SiteConfig, options: List[str]):
  """Restore content from a .sql backup file into the database described in docker-compose.yaml.
  """

  latest_backup = latest_sql_backup(site_config)
  load_sql(site_config, latest_backup)

@deploy_command
def restore_empty_db(site_config: SiteConfig, options: List[str]):
  """Restore an empty db schema
  """

  dir_path = os.path.dirname(os.path.realpath(__file__))
  schema_file = os.path.join(dir_path, "database", "empty_schema.sql")
  load_sql(site_config, schema_file)

@deploy_command
def start_site(site_config: SiteConfig, options: List[str]):
  os.makedirs(site_config.proxy_config_folder, exist_ok=True)
  run_docker_compose('up -d', site_config)

@deploy_command
def enable_tls(site_config: SiteConfig, options: List[str]):
  variable_declarations, docker_compose_command = make_docker_compose_script(
    'exec {} certbot --nginx'.format(site_config.reverse_proxy_service), site_config)
  script_name = 'enable_tls.bat' if platform.system() == 'Windows' else 'enable_tls.sh'
  script = os.path.join(os.path.dirname(os.path.abspath(__file__)), script_name)
  with open(script, 'w') as f:
    f.write(variable_declarations + '\n' + docker_compose_command + '\n')
  log('Script generated.  To enable TLS, run:')
  log(('  {}' if platform.system() == 'Windows' else '  sh {}').format(script))

@deploy_command
def renew_certs(site_config: SiteConfig, options: List[str]):
  log('Starting cert renewal check...')
  run_docker_compose('exec {reverse_proxy_container} certbot renew'.format(
    reverse_proxy_container=site_config.reverse_proxy_service), site_config)

@deploy_command
def add_cert_cronjob(site_config: SiteConfig, options: List[str]):

  deploy_tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'deploy_tool.py')
  cert_renewal_log = os.path.join(site_config.logs_folder, 'cert_renewals.log')
  cmd_to_run = 'python3 {deploy_tool} {site_name} renew_certs >> {cert_renewal_log} 2>&1'.format(
    deploy_tool=deploy_tool, site_name=site_config.name,
    cert_renewal_log=cert_renewal_log)
  run_cmd('crontab -l | {{ cat; echo "0 */12 * * * {cmd}"; }} | crontab -'.format(cmd=cmd_to_run))

@deploy_command
def redeploy(site_config: SiteConfig, options: List[str]):
  redeploy_targets = {'webserver', 'db', 'reverse_proxy', 'backup_manager', 'mailserver'}
  if not options or options[0] not in redeploy_targets:
    sys.exit('Expected: redeploy {{{}}}'.format('|'.join(redeploy_targets)))
  log(f'Redeploying {options[0]} by rebuilding, taking down, then restarting service')
  if options[0] == 'webserver':
    run_docker_compose('build {}'.format(site_config.webserver_service), site_config)
    run_docker_compose('rm -f -s -v {}'.format(site_config.webserver_service), site_config)
    start_site(site_config, [])
  elif options[0] == 'db':
    run_docker_compose('build {}'.format(site_config.db_service), site_config)
    run_docker_compose('rm -f -s {}'.format(site_config.db_service), site_config)
    start_site(site_config, [])
  elif options[0] == 'reverse_proxy':
    run_docker_compose('build {}'.format(site_config.reverse_proxy_service), site_config)
    run_docker_compose('rm -f -s {}'.format(site_config.reverse_proxy_service), site_config)
    start_site(site_config, [])
  elif options[0] == 'backup_manager':
    run_docker_compose('build {}'.format(site_config.backup_manager_service), site_config)
    run_docker_compose('rm -f -s {}'.format(site_config.backup_manager_service), site_config)
    start_site(site_config, [])
  elif options[0] == 'mailserver':
    run_docker_compose('build {}'.format(site_config.mailserver_service), site_config)
    run_docker_compose('rm -f -s {}'.format(site_config.mailserver_service), site_config)
    start_site(site_config, [])

@deploy_command
def dc(site_config: SiteConfig, options: List[str]):
  dc_commands = {
    'build', 'bundle', 'config', 'create', 'down', 'events', 'exec', 'help', 'images', 'kill', 'logs', 'pause', 'port',
    'ps', 'pull', 'push', 'restart', 'rm', 'run', 'scale', 'start', 'stop', 'top', 'unpause', 'up', 'version'}
  if not options:
    raise ValueError('Usage: deploy_tool.py dc {{{}}}'.format('|'.join(dc_commands)))
  run_docker_compose(' '.join(options), site_config)

def main():
  args = get_args()
  if args.command not in deploy_commands:
    sys.exit('Command not recognized: {}'.format(args.command))
  deploy_commands[args.command](args.site_config, args.options)

if __name__ == '__main__':
  main()
