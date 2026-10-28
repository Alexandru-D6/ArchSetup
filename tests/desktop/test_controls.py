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
sys.path.insert(0, str(FILES))
loader = importlib.machinery.SourceFileLoader('controls', str(FILES / 'desktop-controls'))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)


class ControlTests(unittest.TestCase):
    def test_audio_volume_and_monitor_filter(self):
        data = [dict(name='mic', description='USB microphone', mute=True, volume={'left': {'value': 32768}, 'right': {'value': 65536}}),
                dict(name='sink.monitor', volume={})]
        with patch.object(controls, 'command', return_value=json.dumps(data)):
            self.assertEqual(controls.audio('sources'), [dict(id='mic', name='USB microphone', muted=True, volume=75)])

    def test_audio_device_must_still_exist(self):
        with patch.object(controls, 'audio', return_value=[]), patch.object(controls, 'command') as command:
            with self.assertRaises(ValueError): controls.apply(dict(action='output', value='disconnected'))
            command.assert_not_called()

    def test_actions_validate_values_before_running_commands(self):
        for request in [dict(action='volume', value=-1), dict(action='volume', value=101), dict(action='volume', value=True),
                        dict(action='wifi', value='off'), dict(action='mic', value='toggle'), dict(action='bad')]:
            with self.subTest(request=request), patch.object(controls, 'command') as command:
                with self.assertRaises(ValueError): controls.apply(request)
                command.assert_not_called()

    def test_command_failures_are_not_reported_as_success(self):
        with patch.object(controls.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'Permission denied')):
            with self.assertRaisesRegex(ValueError, 'Permission denied'): controls.apply(dict(action='bluetooth', value=False))
            self.assertEqual(controls.command('nmcli', optional=True), '')

    def test_missing_services_return_disabled_controls(self):
        with patch.object(controls, 'command', return_value=''), patch.object(controls.shutil, 'which', return_value=None):
            state = controls.snapshot()
        self.assertFalse(state['wifiAvailable'])
        self.assertFalse(state['bluetoothAvailable'])
        self.assertFalse(state['nightAvailable'])
        self.assertEqual(state['outputs'], [])
        self.assertGreater(state['uptime'], 0)

    def test_wifi_actions_use_networkmanager_backend(self):
        value = dict(device='wlan0', ssid='Home', security='psk')
        with patch.object(controls.desktop_wifi, 'apply') as wifi, patch.object(controls, 'command') as command:
            controls.apply(dict(action='wifi-connect', value=value))
            wifi.assert_called_once_with('wifi-connect', value)
            command.assert_not_called()

    def test_quickshell_sends_requests_over_stdin_and_refreshes_after_errors(self):
        if not shutil.which('qs') or not shutil.which('dbus-run-session'):
            self.skipTest('Quickshell and D-Bus are required')
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            (fixture / 'bin').mkdir()
            shutil.copy2(FILES / 'shell/ControlSource.qml', fixture)
            shutil.copy2(Path(__file__).parent / 'controls/shell.qml', fixture)
            helper = fixture / 'bin/desktop-controls'
            helper.write_text('''#!/usr/bin/env python3
import json, sys
from pathlib import Path
request = json.loads(sys.stdin.readline() if sys.argv[1:] == ['--stdin'] else sys.argv[1])
statefile = Path(__file__).parent / 'state.json'
state = json.loads(statefile.read_text()) if statefile.exists() else dict(wifiAvailable=True, wifiName='')
if request.get('action') == 'wifi-connect':
    assert sys.argv[1:] == ['--stdin']
    assert request['value']['passphrase'] == 'test password'
    state['wifiName'] = 'Home'
    statefile.write_text(json.dumps(state))
if request.get('action') == 'wifi-disconnect':
    print(json.dumps(dict(ok=False, error='Test failure')))
else:
    state['wifiDevice'] = request.get('device') or 'wlan0'
    print(json.dumps(dict(ok=True, state=state)))
''')
            helper.chmod(0o755)
            runtime = fixture / 'runtime'
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime))
            result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', directory], env=environment,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('ARCHSETUP_CONTROLS_PASSED', result.stdout + result.stderr)


if __name__ == '__main__': unittest.main()
