#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

FILES = Path(__file__).resolve().parents[2] / 'roles/desktop/files'
loader = importlib.machinery.SourceFileLoader('proton_controls', str(FILES / 'desktop-protonvpn'))
spec = importlib.util.spec_from_loader(loader.name, loader)
proton = importlib.util.module_from_spec(spec)
loader.exec_module(proton)


class ProtonTests(unittest.TestCase):
    def snapshot(self, responses):
        with patch.object(proton.shutil, 'which', return_value='/usr/bin/protonvpn'), patch.object(proton, 'command', side_effect=responses):
            return proton.snapshot()

    def test_missing_cli_and_network_manager_have_explicit_states(self):
        with patch.object(proton.shutil, 'which', return_value=None), patch.object(proton, 'command') as command:
            self.assertEqual(proton.snapshot()['vpnStatus'], 'install')
            command.assert_not_called()
        state = self.snapshot(['not running'])
        self.assertEqual(state['vpnStatus'], 'network')
        self.assertFalse(state['vpnReady'])

    def test_signed_out_and_signed_in_disconnected_states(self):
        for account, status in [('None', 'signin'), ('', 'signin'), ('test-user', 'disconnected')]:
            with self.subTest(account=account):
                state = self.snapshot(['running', 'Status: Disconnected', f"Account: '{account}'"])
                self.assertEqual(state['vpnStatus'], status)
                self.assertEqual(state['vpnReady'], status == 'disconnected')
                self.assertFalse(state['vpnConnected'])

    def test_connected_server_and_protocol(self):
        state = self.snapshot(['running', 'Refreshing server list…\nStatus: Connected\nServer: ES#1 in Madrid, Spain\nLoad: 42%\nProtocol: wireguard'])
        self.assertTrue(state['vpnConnected'])
        self.assertEqual(state['vpnServer'], 'ES#1 in Madrid, Spain')
        self.assertEqual(state['vpnProtocol'], 'wireguard')

    def test_unknown_and_timed_out_status_never_claim_disconnected_or_connected(self):
        for output in ['unexpected output', ValueError('Keyring is locked'), subprocess.TimeoutExpired(['protonvpn'], 15)]:
            state = self.snapshot(['running', output])
            self.assertEqual(state['vpnStatus'], 'unknown')
            self.assertFalse(state['vpnReady'])
            self.assertTrue(state['vpnError'])

    def test_success_exit_with_gui_conflict_is_an_error(self):
        result = subprocess.CompletedProcess([], 0, 'Error: Proton VPN desktop app is currently running\nThe CLI and GUI cannot run simultaneously.', '')
        with patch.object(proton.subprocess, 'run', return_value=result) as run:
            with self.assertRaisesRegex(ValueError, 'currently running'):
                proton.command('protonvpn', 'connect')
            self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)

    def test_connect_fastest_or_country_and_disconnect(self):
        for action, value, connected, expected in [('connect', '', False, ('protonvpn', 'connect')),
                                                  ('connect', 'United States', False, ('protonvpn', 'connect', '--country', 'United States')),
                                                  ('disconnect', None, True, ('protonvpn', 'disconnect'))]:
            with self.subTest(action=action, value=value), patch.object(proton, 'snapshot', return_value=dict(vpnReady=True, vpnConnected=connected)), patch.object(proton, 'command') as command:
                proton.apply(action, value)
                self.assertEqual(command.call_args.args, expected)

    def test_invalid_input_and_unsigned_account_cannot_connect(self):
        for action, value in [('connect', True), ('connect', '--random'), ('connect', 'ES; touch /tmp/test'), ('disconnect', 'uuid'), ('vpn', '')]:
            with self.subTest(action=action, value=value), patch.object(proton, 'command') as command:
                with self.assertRaises(ValueError): proton.apply(action, value)
                command.assert_not_called()
        with patch.object(proton, 'snapshot', return_value=dict(vpnReady=False, vpnError='')), patch.object(proton, 'command') as command:
            with self.assertRaisesRegex(ValueError, 'Sign in'): proton.apply('connect', '')
            command.assert_not_called()

    def test_signin_delegates_password_and_2fa_to_proton(self):
        with patch.object(proton.shutil, 'which', return_value='/usr/bin/protonvpn'), patch('builtins.input', return_value='test@example.org'), patch.object(proton.subprocess, 'call', return_value=0) as command:
            self.assertEqual(proton.signin(), 0)
            command.assert_called_once_with(['protonvpn', 'signin', '--', 'test@example.org'])

    def test_helper_runs_cli_and_reports_final_state_after_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / 'protonvpn'
            helper.write_text('''#!/usr/bin/env python3
import json, sys
from pathlib import Path
state = Path(__file__).with_name('connected')
with Path(__file__).with_name('calls').open('a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1:] == ['status']:
    print('Status: Connected\\nServer: ES#1 in Madrid\\nProtocol: wireguard' if state.exists() else 'Status: Disconnected')
elif sys.argv[1:] == ['info']: print("Account: 'test'")
elif sys.argv[1:] == ['connect', '--country', 'FAIL']:
    print('Error: Test connection failed', file=sys.stderr)
    sys.exit(1)
elif sys.argv[1] == 'connect': state.touch()
elif sys.argv[1:] == ['disconnect']: state.unlink(missing_ok=True)
else: sys.exit(2)
''')
            helper.chmod(0o755)
            nmcli = root / 'nmcli'
            nmcli.write_text('#!/bin/sh\nprintf "running\\n"\n')
            nmcli.chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'], XDG_RUNTIME_DIR=directory)
            def request(action, value):
                result = subprocess.run([sys.executable, str(FILES / 'desktop-protonvpn'), '--stdin'],
                                        input=json.dumps(dict(action=action, value=value)) + '\n',
                                        text=True, capture_output=True, timeout=10, env=env, check=True)
                return json.loads(result.stdout)
            response = request('connect', 'FAIL')
            self.assertFalse(response['ok'])
            self.assertIn('Test connection failed', response['error'])
            self.assertEqual(response['state']['vpnStatus'], 'disconnected')
            self.assertTrue(request('connect', '')['state']['vpnConnected'])
            self.assertFalse(request('disconnect', None)['state']['vpnConnected'])
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            self.assertIn(['connect'], calls)
            self.assertIn(['connect', '--country', 'FAIL'], calls)
            self.assertIn(['disconnect'], calls)

    def test_quickshell_serializes_reads_and_writes_and_keeps_connection_when_closed(self):
        if not shutil.which('qs') or not shutil.which('dbus-run-session'):
            self.skipTest('Quickshell and D-Bus are required')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            (root / 'runtime').mkdir(mode=0o700)
            shutil.copy2(FILES / 'shell/ProtonSource.qml', root)
            shutil.copy2(Path(__file__).parent / 'controls/proton-source.qml', root / 'shell.qml')
            helper = root / 'bin/desktop-protonvpn'
            helper.write_text('''#!/usr/bin/env python3
import json, sys, time
from pathlib import Path
root = Path(__file__).parent
guard = root / 'guard'
with guard.open('x'):
    try:
        statefile = root / 'connected'
        request = json.loads(sys.stdin.readline()) if sys.argv[1:] == ['--stdin'] else {}
        action = request.get('action')
        time.sleep(.15)
        if action == 'connect':
            assert request['value'] == 'ES'
            statefile.touch()
        elif action == 'disconnect': statefile.unlink(missing_ok=True)
        connected = statefile.exists()
        print(json.dumps(dict(ok=True, state=dict(vpnReady=True, vpnConnected=connected, vpnStatus='connected' if connected else 'disconnected'))))
    finally: guard.unlink()
''')
            helper.chmod(0o755)
            result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', directory], capture_output=True, text=True, timeout=10,
                                    env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(root / 'runtime')))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('ARCHSETUP_PROTON_SOURCE_PASSED', result.stdout + result.stderr)


if __name__ == '__main__': unittest.main()
