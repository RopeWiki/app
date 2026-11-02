"""Copy approved image archives to fixed registries; never execute their content."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile

IMAGES = ('backup_manager', 'database', 'mailserver', 'reverse_proxy', 'webserver')
MAX_ARTIFACT_BYTES = 8 * 1024**3


def validate_plan(plan):
    if plan['kind'] not in ('preview', 'release'):
        raise ValueError('Unexpected publication kind')
    if not re.fullmatch(r'[a-f0-9]{40}', plan['sha']):
        raise ValueError('Invalid commit SHA')
    for key in ('runId', 'runAttempt', 'artifactId'):
        if type(plan[key]) is not int or plan[key] <= 0:
            raise ValueError(f'Invalid {key}')
    if not re.fullmatch(r'sha256:[a-f0-9]{64}', plan['artifactDigest']):
        raise ValueError('Invalid artifact digest')
    if plan['kind'] == 'preview':
        if type(plan['prNumber']) is not int or plan['prNumber'] <= 0:
            raise ValueError('Invalid PR number')
        pattern = rf"pr-{plan['prNumber']}-{plan['sha'][:12]}-run-[1-9][0-9]*-attempt-{plan['runAttempt']}"
    else:
        pattern = f"sha-{plan['sha'][:7]}"
    if not re.fullmatch(pattern, plan['tag']):
        raise ValueError('Invalid image tag')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def artifact_url(artifact_id, token):
    # Do not forward the repository token to GitHub's signed blob-storage URL.
    request = urllib.request.Request(
        f'https://api.github.com/repos/RopeWiki/app/actions/artifacts/{artifact_id}/zip',
        headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json'},
    )
    try:
        urllib.request.build_opener(NoRedirect).open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        location = error.headers['Location']
        if not location.startswith('https://'):
            raise ValueError('Artifact download must use HTTPS')
        return location
    raise ValueError('Expected a signed artifact download redirect')


def unpack_images(archive, destination):
    expected = {f'{image}.tar.gz' for image in IMAGES}
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if len(entries) != len(expected) or {entry.filename for entry in entries} != expected:
            raise ValueError('Artifact must contain exactly the five expected image archives')
        if sum(entry.file_size for entry in entries) > MAX_ARTIFACT_BYTES:
            raise ValueError('Image artifact is too large')
        # Copy only fixed, ordinary files. Never extract paths or symlinks from a PR.
        for entry in entries:
            mode = entry.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG) or entry.file_size == 0:
                raise ValueError('Expected a nonempty regular image archive')
        destination.mkdir(parents=True, exist_ok=False)
        for entry in entries:
            with source.open(entry) as src, (destination / entry.filename).open('xb') as dst:
                shutil.copyfileobj(src, dst, length=1024 * 1024)


def download(plan, destination):
    archive = destination.with_suffix('.zip')
    digest = hashlib.sha256()
    size = 0
    url = artifact_url(plan['artifactId'], os.environ['GH_TOKEN'])
    try:
        with urllib.request.urlopen(url, timeout=60) as response, archive.open('xb') as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_ARTIFACT_BYTES:
                    raise ValueError('Image artifact is too large')
                digest.update(chunk)
                output.write(chunk)
        if f'sha256:{digest.hexdigest()}' != plan['artifactDigest']:
            raise ValueError('Artifact digest does not match the approved GitHub artifact')
        unpack_images(archive, destination)
    finally:
        archive.unlink(missing_ok=True)


def destinations(plan, image):
    if plan['kind'] == 'preview':
        return [f"ghcr.io/ropewiki/{image}-preview:{plan['tag']}"]
    return [f"ghcr.io/ropewiki/{image}:{plan['tag']}",
            f'ghcr.io/ropewiki/{image}:github-master-latest']


def publish(plan, directory):
    authfile = Path(os.environ['DOCKER_CONFIG']) / 'config.json'
    rows = []
    for image in IMAGES:
        source = directory / f'{image}.tar.gz'
        if source.is_symlink() or not source.is_file():
            raise ValueError('Missing regular image archive')
        for target in destinations(plan, image):
            digest_file = directory / f'{image}.digest'
            subprocess.run([
                'skopeo', 'copy', '--authfile', str(authfile), '--retry-times', '3',
                '--digestfile', str(digest_file),
                f'docker-archive:{source}:ropewiki/{image}:latest', f'docker://{target}',
            ], check=True)
            digest = digest_file.read_text().strip()
            if not re.fullmatch(r'sha256:[a-f0-9]{64}', digest):
                raise ValueError('Unexpected published image digest')
            rows.append(f'| `{target}` | `{digest}` |')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write(f"## Published images\n\nSource head: `{plan['sha']}`\n\n")
        summary.write(f"Build: {plan['runId']}, attempt {plan['runAttempt']}\n\n")
        summary.write('| Image | Digest |\n| --- | --- |\n' + '\n'.join(rows) + '\n')


if __name__ == '__main__':
    build_plan = json.loads(os.environ['BUILD_PLAN'])
    validate_plan(build_plan)
    image_directory = Path(os.environ['IMAGE_ARCHIVES'])
    if sys.argv[1:] == ['download']:
        download(build_plan, image_directory)
    elif sys.argv[1:] == ['publish']:
        publish(build_plan, image_directory)
    else:
        sys.exit('Expected download or publish')
