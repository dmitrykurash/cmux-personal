"""Real private worker/pipe lifecycle with a fake gh; no GitHub credentials/network."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location('github_bridge', Path(__file__).parents[1] / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class GitHubTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'state'
        self.jid = str(uuid.uuid4())
        for p in [patch.object(bridge, 'ROOT', self.root), patch.dict(os.environ, {'HOME': str(self.base)})]:
            p.start(); self.addCleanup(p.stop)
        bridge.private_dir(self.root)
        source = Path(__file__).parents[1].joinpath('bridge.py').read_text()
        source = source.replace('ROOT = Path.home() / ".local/share/cmux-personal"', 'ROOT = Path(' + repr(str(self.root)) + ')')
        (self.root / 'bridge.py').write_text(source)

    def fake_gh(self, script):
        binary = self.base / '.local/bin/gh'
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text('#!' + sys.executable + '\nimport os, sys\nfrom pathlib import Path\n'
                          'if sys.argv[1:3] == ["auth", "status"]: sys.exit(1)\n'
                          'if sys.argv[1:3] == ["auth", "setup-git"]: sys.exit(0)\n' + script)
        binary.chmod(0o700)

    def test_device_code_reconnect_and_success_do_not_return_or_store_cli_output(self):
        gate = self.base / 'finish'
        self.fake_gh('import signal\n'
                     'assert sys.argv[1:] == ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"]\n'
                     'assert os.environ["GH_BROWSER"] == "/usr/bin/true"\n'
                     f'os.mkfifo({str(gate)!r})\n'
                     'print("sensitive-test-token", flush=True)\n'
                     'print("! First copy your one-time code: ABCD-1234", flush=True)\n'
                     f'with open({str(gate)!r}) as stream: stream.read()\n')
        bridge.begin_github(self.jid)
        try:
            state = bridge.wait_github(self.jid)
            self.assertEqual(state, {'id': self.jid, 'phase': 'waiting', 'deviceCode': 'ABCD-1234'})
            resumed = bridge.begin_github(str(uuid.uuid4()))
            self.assertEqual(resumed, state, 'Reopening must resume the existing login')
        finally:
            with gate.open('w') as stream: stream.write('finish')
            done = bridge.wait_github(self.jid)
        self.assertEqual(done, {'id': self.jid, 'phase': 'connected'})
        self.assertEqual(bridge.begin_github(self.jid), done, 'Lost reply retry must not sign in twice')
        persisted = (bridge.github_folder(self.jid) / 'status.json').read_text()
        self.assertNotIn('sensitive-test-token', persisted)
        self.assertNotIn('ABCD-1234', persisted)
        self.assertEqual((bridge.github_folder(self.jid) / 'status.json').stat().st_mode & 0o777, 0o600)

    def test_failure_and_worker_never_started_are_retryable_without_secret_output(self):
        self.fake_gh('print("Authentication failed sensitive-test-token", file=sys.stderr)\nsys.exit(1)\n')
        bridge.begin_github(self.jid)
        failed = bridge.wait_github(self.jid)
        self.assertEqual(failed['phase'], 'failed')
        self.assertNotIn('sensitive-test-token', json.dumps(failed))
        other = str(uuid.uuid4())
        with patch.object(bridge, 'github_status', return_value={'phase': 'signedOut'}), patch.object(bridge.subprocess, 'Popen'):
            bridge.begin_github(other)
        self.assertEqual(bridge.wait_github(other)['phase'], 'failed')

    @unittest.skipUnless(Path('/proc/self/stat').exists(), 'VPS cancellation uses Linux process identity')
    def test_cancel_terminates_only_its_worker_and_child_and_removes_code(self):
        self.fake_gh('import signal\nPath.home().joinpath("child.pid").write_text(str(os.getpid()))\n'
                     'print("one-time code: ABCD-1234", flush=True)\nsignal.pause()\n')
        bridge.begin_github(self.jid)
        try:
            self.assertEqual(bridge.wait_github(self.jid)['phase'], 'waiting')
            pid = int((self.base / 'child.pid').read_text())
            self.assertEqual(bridge.cancel_github(self.jid)['phase'], 'cancelling')
            self.assertEqual(bridge.wait_github(self.jid), {'id': self.jid, 'phase': 'cancelled'})
            with self.assertRaises(ProcessLookupError): os.kill(pid, 0)
        finally:
            bridge.cancel_github(self.jid)
            bridge.wait_github(self.jid)

    def test_missing_cli_and_stale_active_job_do_not_break_start(self):
        with patch.object(bridge, 'executable', return_value=None):
            self.assertEqual(bridge.begin_github(self.jid), {'phase': 'unavailable'})
        bridge.atomic_json(bridge.private_dir(self.root / 'github') / 'active.json', {'id': str(uuid.uuid4())})
        self.fake_gh('sys.exit(1)\n')
        bridge.begin_github(self.jid)
        self.assertEqual(bridge.wait_github(self.jid)['phase'], 'failed')


if __name__ == '__main__': unittest.main()
