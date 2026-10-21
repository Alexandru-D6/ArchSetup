#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


class BluetoothTests(unittest.TestCase):
    def test_quickshell_discovery_prompt_and_process_lifecycle(self):
        if not shutil.which('qs') or not shutil.which('dbus-run-session'):
            self.skipTest('Quickshell and D-Bus are required')
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            (fixture / 'bin').mkdir()
            (fixture / 'runtime').mkdir(mode=0o700)
            files = Path(__file__).resolve().parents[2] / 'roles/desktop/files'
            shutil.copy2(files / 'shell/BluetoothSource.qml', fixture)
            shutil.copy2(Path(__file__).parent / 'controls/bluetooth-source.qml', fixture / 'shell.qml')
            helper = fixture / 'bin/desktop-bluetooth'
            helper.write_text('''#!/usr/bin/env python3
import json, sys
packet = dict(state=dict(bluetoothAvailable=True, bluetoothEnabled=True, bluetoothAdapter='hci0', bluetoothScanning=False), busy=False, prompt=None, error='')
print(json.dumps(packet), flush=True)
for line in sys.stdin:
    request = json.loads(line)
    action, value = request['action'], request.get('value')
    if action == 'scan':
        packet['state']['bluetoothScanning'] = value
        packet['state']['scanCount'] = packet['state'].get('scanCount', 0) + 1
    elif action == 'pair':
        assert value == 'test-device'
        packet.update(busy=True, operation='pair', prompt=dict(kind='pin', name='Keyboard'))
    elif action == 'respond':
        assert value == '1234'
        packet.update(busy=False, prompt=None, operation='')
        packet['state']['testConnected'] = True
    elif action == 'cancel': packet.update(busy=False, prompt=None, operation='')
    print(json.dumps(packet), flush=True)
''')
            helper.chmod(0o755)
            result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', directory], capture_output=True, text=True, timeout=10,
                                    env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(fixture / 'runtime')))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('ARCHSETUP_BLUETOOTH_SOURCE_PASSED', result.stdout + result.stderr)

    def test_bluez_protocol_pairing_discovery_and_device_lifecycle(self):
        if not shutil.which('dbus-run-session'):
            self.skipTest('D-Bus is required')
        try:
            import gi
        except ImportError:
            self.skipTest('PyGObject is required')
        result = subprocess.run(['dbus-run-session', '--', sys.executable,
                                 str(Path(__file__).parent / 'controls/check_bluetooth.py')],
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('ARCHSETUP_BLUETOOTH_PASSED', result.stdout)


if __name__ == '__main__': unittest.main()
