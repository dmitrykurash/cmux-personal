"""Behavioral checks for self-service projects; no network or real user state."""
import importlib.util
import json
from pathlib import Path
import os
import signal
import sys
import time
import tempfile
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location('projects_bridge', Path(__file__).parents[1] / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'state'
        p = patch.object(bridge, 'ROOT', self.root)
        p.start()
        self.addCleanup(p.stop)

    def test_new_folder_and_existing_folder_return_canonical_location(self):
        target = self.base / 'My project'
        result = bridge.dispatch({'op': 'project_prepare', 'mode': 'empty', 'project': str(target)})
        self.assertTrue(target.is_dir())
        self.assertEqual(result['path'], str(target))
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        opened = bridge.dispatch({'op': 'project_prepare', 'mode': 'existing', 'project': str(target)})
        self.assertEqual(opened['path'], str(target))

    def test_creation_never_overwrites_existing_files_or_symlinks(self):
        existing = self.base / 'existing'
        existing.mkdir()
        (existing / 'keep.txt').write_text('keep me')
        link = self.base / 'link'
        link.symlink_to(existing, target_is_directory=True)
        for target in (existing, link):
            for mode in ('empty', 'clone'):
                with self.subTest(target=target, mode=mode), self.assertRaises(ValueError):
                    bridge.dispatch({'op': 'project_prepare', 'mode': mode, 'project': str(target), 'repository': 'https://github.com/owner/repo.git', 'id': str(uuid.uuid4())})
        self.assertEqual((existing / 'keep.txt').read_text(), 'keep me')

    def test_remote_folder_picker_lists_only_visible_directories(self):
        (self.base / 'project').mkdir()
        (self.base / '.hidden').mkdir()
        (self.base / 'file').write_text('x')
        (self.base / 'link').symlink_to(self.base / 'project')
        result = bridge.dispatch({'op': 'folders', 'project': str(self.base)})
        self.assertIn('project', result['directories'])
        self.assertNotIn('.hidden', result['directories'])
        self.assertNotIn('file', result['directories'])
        self.assertNotIn('link', result['directories'])

    def test_reject_credential_bearing_urls_and_executable_transports_before_spawning(self):
        urls = ['--upload-pack=bad', 'ext::sh -c bad', '/tmp/repo', 'file:///tmp/repo',
                'http://github.com/a/b', 'https://secret@github.com/a/b',
                'https://github.com/a/b?token=secret', 'ssh://git:secret@github.com/a/b', 'ssh://git:@github.com/a/b',
                'git@-bad:a/b', 'https://github.com/a/b\n--config=bad']
        with patch.object(bridge.subprocess, 'Popen') as spawn:
            for url in urls:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    bridge.dispatch({'op': 'project_prepare', 'mode': 'clone', 'project': str(self.base/'new'), 'repository': url, 'id': str(uuid.uuid4())})
            spawn.assert_not_called()
        self.assertFalse((self.base/'new').exists())

    def test_missing_existing_folder_does_not_create_it(self):
        missing = self.base/'missing'
        with self.assertRaises(ValueError):
            bridge.dispatch({'op':'project_prepare', 'mode':'existing', 'project':str(missing)})
        self.assertFalse(missing.exists())

    def test_clone_job_is_recoverable_and_duplicate_start_does_not_spawn_twice(self):
        bridge.private_dir(self.root)
        (self.root/'bridge.py').write_text('# test worker')
        target = self.base/'checkout'
        request = {'op':'project_prepare','mode':'clone','project':str(target),'repository':'https://github.com/octocat/Hello-World.git','id':str(uuid.uuid4())}
        with patch.object(bridge, 'executable', return_value='/usr/bin/git'), patch.object(bridge.subprocess, 'Popen') as spawn:
            one = bridge.dispatch(request)
            two = bridge.dispatch(request)
            self.assertEqual(one['id'], two['id'])
            self.assertEqual(spawn.call_count, 1)
            self.assertTrue(target.is_dir())
        # A worker that never starts must not be reported as completed.
        state = bridge.dispatch({'op':'project_wait','id':one['id']})
        self.assertEqual(state['phase'], 'failed')
        self.assertNotEqual(state.get('phase'), 'done')


    def worker_request(self, script):
        # A private fake Git executable exercises real detached workers/locks,
        # without network access or touching the user's Git configuration.
        git = self.base/'.local/bin/git'
        git.parent.mkdir(parents=True, exist_ok=True)
        git.write_text('#!' + sys.executable + '\n' + script)
        git.chmod(0o700)
        source = (Path(__file__).parents[1]/'bridge.py').read_text()
        source = source.replace('ROOT = Path.home() / ".local/share/cmux-personal"', 'ROOT = Path(' + repr(str(self.root)) + ')')
        return {'op':'project_prepare', 'mode':'clone', 'project':str(self.base/'checkout'),
                'repository':'https://github.com/owner/repo.git', 'id':str(uuid.uuid4()), 'source':source}

    def test_detached_worker_completes_and_retry_returns_same_checkout(self):
        request = self.worker_request("from pathlib import Path\nimport sys\n(Path(sys.argv[-1])/'README').write_text('cloned')\n")
        with patch.dict(os.environ, {'HOME':str(self.base)}):
            bridge.dispatch(request)
            result = bridge.dispatch({'op':'project_wait', 'id':request['id']})
            repeated = bridge.dispatch(request)
        self.assertEqual(result['phase'], 'done')
        self.assertEqual(repeated['phase'], 'done')
        self.assertEqual((Path(result['path'])/'README').read_text(), 'cloned')

    def test_failed_worker_keeps_partial_files_and_does_not_return_git_credentials(self):
        request = self.worker_request("from pathlib import Path\nimport sys\n(Path(sys.argv[-1])/'partial').write_text('preserve')\nsys.stderr.write('Authentication failed: secret-test-value')\nsys.exit(128)\n")
        with patch.dict(os.environ, {'HOME':str(self.base)}):
            bridge.dispatch(request)
            result = bridge.dispatch({'op':'project_wait', 'id':request['id']})
        self.assertEqual(result['phase'], 'failed')
        self.assertEqual(result['code'], 'git_access')
        self.assertNotIn('secret-test-value', json.dumps(result))
        self.assertEqual((Path(result['path'])/'partial').read_text(), 'preserve')

    @unittest.skipUnless(Path('/proc/self/stat').exists(), 'VPS cancellation identity uses Linux /proc')
    def test_cancellation_stops_the_worker_and_git_but_preserves_partial_files(self):
        request = self.worker_request("from pathlib import Path\nimport os, signal, sys\n(Path(sys.argv[-1])/'partial').write_text(str(os.getpid()))\nsignal.pause()\n")
        with patch.dict(os.environ, {'HOME':str(self.base)}):
            bridge.dispatch(request)
            partial = Path(request['project'])/'partial'
            deadline = time.monotonic() + 5
            while not partial.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            try:
                self.assertTrue(partial.exists(), 'Git did not start')
                git_pid = int(partial.read_text())
                cancelled = bridge.dispatch({'op':'project_cancel','id':request['id']})
                self.assertEqual(cancelled['phase'], 'cancelling')
                result = bridge.dispatch({'op':'project_wait','id':request['id']})
                self.assertEqual(result['phase'], 'cancelled')
                self.assertTrue(partial.exists())
                with self.assertRaises(ProcessLookupError):
                    os.kill(git_pid, 0)
            finally:
                bridge.cancel_import(request['id'])
                bridge.wait_import(request['id'])


if __name__ == '__main__':
    unittest.main()
