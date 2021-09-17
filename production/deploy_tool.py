#!/usr/bin/env python

import argparse
from dataclasses import dataclass
import datetime
import json
import os
import sys
from typing import Callable, Dict


@dataclass
class SiteConfig(object):
  db_password: str
  hostname: str
  protocol: str
  logs_folder: str
  sql_backup_folder: str
  images_folder: str
  proxy_config_folder: str

deploy_commands: Dict[str, Callable[[SiteConfig], None]] = {}

def deploy_command(func: Callable[[SiteConfig], None]):
  global deploy_commands
  deploy_commands[func.__name__] = func
  return func

def make_argparse() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(
    usage="%(prog)s [SITE_CONFIG_NAME] [COMMAND]",
    description="Perform a RopeWiki deployment action"
  )
  parser.add_argument('site_config_name')
  parser.add_argument('command', choices=list(deploy_commands))
  return parser

@dataclass
class UserArgs(object):
  site_config: SiteConfig
  command: str

def get_args() -> UserArgs:
  args = make_argparse().parse_args()
  config_name = args.site_config_name
  config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'site_configs', config_name + '.json')
  with open(config_path, 'r') as f:
    config = json.load(f)
  config['db_password'] = os.environ.get('RW_DB_PASSWORD', None)
  return UserArgs(site_config=SiteConfig(**config), command=args.command)

def log(msg: str):
  print("{} {}".format(datetime.datetime.now().isoformat(), msg))

@deploy_command
def get_images(site_config: Dict):
  """Retrieve latest files in /images folder from remote server at ropewiki.com

  Requires SSH access to ropewiki.com.
  """

  # NOTE: this requires public key authentication to the remote server
  log("Copying latest /images content locally...")
  log_file = os.path.join(site_config.logs_folder, 'images_backup.log')
  os.system('touch {}'.format(log_file))
  cmd = (
    'rsync -arv ' +
    'root@ropewiki.com:/usr/share/nginx/html/ropewiki/images/ ' +
    '{}'.format(site_config.image_folder) +
    '2>&1 > {}'.format(log_file))
  os.system(cmd)
  log('  -> Latest /images content copied locally.')

def main():
  args = get_args()
  if args.command not in deploy_commands:
    sys.exit('Command not recognized: {}'.format(args.command))
  deploy_commands[args.command](args.site_config)

if __name__ == '__main__':
  main()
