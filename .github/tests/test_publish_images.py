import copy
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import warnings
import zipfile

spec = importlib.util.spec_from_file_location('publish_images', Path(__file__).parents[1] / 'scripts/publish_images.py')
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)


def plan():
    return dict(kind='preview', sha='a' * 40, runId=123, runAttempt=2, artifactId=456,
                artifactDigest='sha256:' + 'b' * 64, prNumber=199,
                tag='pr-199-aaaaaaaaaaaa-run-17-attempt-2')


def archive(entries=None):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as z:
        for name in entries if entries is not None else [f'{name}.tar.gz' for name in images.IMAGES]:
            z.writestr(name, b'image archive data')
    output.seek(0)
    return output


class PublishingTests(unittest.TestCase):
    def test_only_run_specific_preview_and_commit_release_tags(self):
        valid = plan()
        images.validate_plan(valid)
        for key, value in [('kind', 'production'), ('tag', 'latest'), ('sha', 'main; command'),
                           ('prNumber', '../199'), ('artifactId', '456'), ('runAttempt', 3)]:
            invalid = copy.deepcopy(valid)
            invalid[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                images.validate_plan(invalid)
        release = {**valid, 'kind': 'release', 'tag': 'sha-aaaaaaa'}
        images.validate_plan(release)

    def test_preview_destinations_cannot_touch_production_repositories(self):
        for image in images.IMAGES:
            self.assertEqual(images.destinations(plan(), image),
                             [f'ghcr.io/ropewiki/{image}-preview:{plan()["tag"]}'])
            release = {**plan(), 'kind': 'release', 'tag': 'sha-aaaaaaa'}
            self.assertEqual(images.destinations(release, image),
                             [f'ghcr.io/ropewiki/{image}:sha-aaaaaaa',
                              f'ghcr.io/ropewiki/{image}:github-master-latest'])
            self.assertTrue(set(images.destinations(plan(), image)).isdisjoint(
                images.destinations(release, image)))

    def test_fixed_regular_archives_are_copied(self):
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / 'images'
            images.unpack_images(archive(), destination)
            self.assertEqual({p.name for p in destination.iterdir()},
                             {f'{name}.tar.gz' for name in images.IMAGES})

    def test_reject_extra_missing_traversal_duplicate_and_symlink_entries(self):
        expected = [f'{name}.tar.gz' for name in images.IMAGES]
        link = zipfile.ZipInfo(expected[0])
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entries in [expected + ['script.py'], expected[1:],
                        ['../webserver.tar.gz'] + expected[1:],
                        [expected[1]] + expected[1:], [link] + expected[1:]]:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as tmp:
                with warnings.catch_warnings():
                    warnings.filterwarnings('ignore', message='Duplicate name:')
                    with self.assertRaises(ValueError):
                        images.unpack_images(archive(entries), Path(tmp) / 'images')
                self.assertFalse((Path(tmp) / 'images').exists())

    def test_reject_large_artifacts_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(images, 'MAX_ARTIFACT_BYTES', 1):
            with self.assertRaises(ValueError):
                images.unpack_images(archive(), Path(tmp) / 'images')

    def test_digest_mismatch_is_fatal_and_leaves_no_images(self):
        payload = archive().getvalue()
        with tempfile.TemporaryDirectory() as tmp, \
                patch.dict(os.environ, {'GH_TOKEN': 'test-only-token'}), \
                patch.object(images, 'artifact_url', return_value='https://example.com/blob'), \
                patch.object(images.urllib.request, 'urlopen', return_value=io.BytesIO(payload)):
            destination = Path(tmp) / 'images'
            with self.assertRaisesRegex(ValueError, 'digest'):
                images.download(plan(), destination)
            self.assertFalse(destination.exists())
            self.assertFalse(destination.with_suffix('.zip').exists())

    def test_verified_download_uses_no_authorization_on_blob_request(self):
        payload = archive().getvalue()
        approved = {**plan(), 'artifactDigest': 'sha256:' + hashlib.sha256(payload).hexdigest()}
        with tempfile.TemporaryDirectory() as tmp, \
                patch.dict(os.environ, {'GH_TOKEN': 'test-only-token'}), \
                patch.object(images, 'artifact_url', return_value='https://example.com/blob'), \
                patch.object(images.urllib.request, 'urlopen', return_value=io.BytesIO(payload)) as urlopen:
            destination = Path(tmp) / 'images'
            images.download(approved, destination)
            urlopen.assert_called_once_with('https://example.com/blob', timeout=60)
            self.assertEqual(len(list(destination.iterdir())), 5)

    def test_api_request_cannot_follow_redirect_with_token(self):
        error = urllib.error.HTTPError('https://api.github.com/', 302, 'redirect',
                                      {'Location': 'https://example.com/signed'}, None)
        with patch.object(images.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = error
            self.assertEqual(images.artifact_url(456, 'test-only-token'), 'https://example.com/signed')
            self.assertIs(opener.call_args.args[0], images.NoRedirect)
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.get_header('Authorization'), 'Bearer test-only-token')

    def test_copy_invokes_only_skopeo_with_fixed_sources_and_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for image in images.IMAGES:
                (directory / f'{image}.tar.gz').write_bytes(b'test archive')
            def copied(command, **kwargs):
                self.assertEqual(command[:2], ['skopeo', 'copy'])
                self.assertNotIn('shell', kwargs)
                Path(command[command.index('--digestfile') + 1]).write_text('sha256:' + 'd' * 64)
            summary = directory / 'summary.md'
            with patch.dict(os.environ, {'DOCKER_CONFIG': tmp, 'GITHUB_STEP_SUMMARY': str(summary)}), \
                    patch.object(images.subprocess, 'run', side_effect=copied) as run:
                images.publish(plan(), directory)
            self.assertEqual(run.call_count, 5)
            for image, call in zip(images.IMAGES, run.call_args_list):
                self.assertEqual(call.args[0][-2], f'docker-archive:{directory / (image + ".tar.gz")}:ropewiki/{image}:latest')
                self.assertEqual(call.args[0][-1], f'docker://{images.destinations(plan(), image)[0]}')
            self.assertIn('sha256:' + 'd' * 64, summary.read_text())


if __name__ == '__main__':
    unittest.main()
