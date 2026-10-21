#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'roles/desktop/files'))
import desktop_wifi as wifi


DEVICES = '''                                    Devices
--------------------------------------------------------------------------------
  Name                  Address               Powered     Adapter     Mode
--------------------------------------------------------------------------------
  wlan0                 aa:bb:cc:dd:ee:ff     on          phy0        station
  wlan1                 aa:bb:cc:dd:ee:00     off         phy1        station
'''
STATION = '''                                 Station: wlan0
--------------------------------------------------------------------------------
  Settable  Property              Value
--------------------------------------------------------------------------------
            Scanning              no
            State                 connected
            Connected network     Home  Office
'''


def network_row(name, security='psk', signal='-5800', connected=False):
    return f'  {"> " if connected else "":2}  {name:32}  {security:18}  {signal:6}\n'


class WifiTests(unittest.TestCase):
    def test_real_iwctl_password_prompt_on_private_bus(self):
        if not shutil.which('iwctl') or not shutil.which('dbus-run-session'):
            self.skipTest('iwctl and D-Bus are required')
        try:
            import gi
        except ImportError:
            self.skipTest('PyGObject is required for the private iwd test service')
        result = subprocess.run(['dbus-run-session', '--', sys.executable,
                                 str(Path(__file__).parent / 'controls/check_iwctl.py')],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('REAL_IWCTL_PASSWORD_PASSED', result.stdout)

    def test_iwctl_snapshot_handles_ansi_spaces_and_saved_networks(self):
        name = 'Home  Office'
        replies = [DEVICES, STATION, 'Available networks\n' + network_row(name, connected=True)
                   + network_row('Cafe "open"; $(id)', 'open', '-7100'),
                   f'Known Networks\n  {name:32}  psk          Oct 20, 8:33 PM\n']
        def run(*args, **kwargs):
            return subprocess.CompletedProcess(args, 0, '\x1b[1;90m' + replies.pop(0) + '\x1b[0m', '')
        with patch.object(wifi.shutil, 'which', return_value='/usr/bin/iwctl'), patch.object(wifi.subprocess, 'run', side_effect=run):
            state = wifi.snapshot()
        self.assertTrue(state['wifiAvailable'])
        self.assertTrue(state['wifiEnabled'])
        self.assertEqual(state['wifiDevice'], 'wlan0')
        self.assertEqual(state['wifiName'], name)
        self.assertEqual(state['wifiNetworks'], [dict(ssid=name, security='psk', signal=4, connected=True, known=True),
            dict(ssid='Cafe "open"; $(id)', security='open', signal=2, connected=False, known=False)])

    def test_powered_off_adapter_can_be_selected_without_station_queries(self):
        with patch.object(wifi.shutil, 'which', return_value='iwctl'), patch.object(wifi, 'run', return_value=DEVICES) as run:
            state = wifi.snapshot('wlan1')
        self.assertEqual(state['wifiDevice'], 'wlan1')
        self.assertTrue(state['wifiAvailable'])
        self.assertFalse(state['wifiEnabled'])
        self.assertEqual(state['wifiNetworks'], [])
        run.assert_called_once_with('device', 'list')

    def test_missing_service_reports_an_inline_error(self):
        with patch.object(wifi.shutil, 'which', return_value='iwctl'), patch.object(wifi, 'run', side_effect=ValueError('iwd is unavailable')):
            state = wifi.snapshot()
        self.assertFalse(state['wifiAvailable'])
        self.assertEqual(state['wifiError'], 'iwd is unavailable')

    def test_actions_validate_before_mutating_and_reject_removed_adapters(self):
        for action, value in [('wifi-power', dict(device='wlan0', enabled='off')),
                              ('wifi-connect', dict(device='wlan0', ssid='Home', security='psk', passphrase='short')),
                              ('wifi-connect', dict(device='wlan0', ssid='Home', security='psk', passphrase='bad\npassword')),
                              ('wifi-connect', dict(device='wlan0', ssid='x' * 33, security='open')),
                              ('wifi-connect', dict(device='wlan0', ssid='Home', security='wep')),
                              ('wifi-scan', {})]:
            with self.subTest(action=action, value=value), patch.object(wifi, 'run') as run:
                with self.assertRaises(ValueError): wifi.apply(action, value)
                run.assert_not_called()
        with patch.object(wifi, 'devices', return_value=[]), patch.object(wifi, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'no longer available'):
                wifi.apply('wifi-scan', dict(device='removed'))
            run.assert_not_called()

    def test_scan_power_and_disconnect_target_selected_adapter(self):
        for action, extra, expected in [('wifi-scan', {}, ('station', 'wlan1', 'scan')),
                ('wifi-power', dict(enabled=False), ('device', 'wlan1', 'set-property', 'Powered', 'off')),
                ('wifi-disconnect', {}, ('station', 'wlan1', 'disconnect'))]:
            with self.subTest(action=action), patch.object(wifi, 'devices', return_value=[dict(id='wlan1')]), patch.object(wifi, 'run') as run:
                wifi.apply(action, dict(device='wlan1', **extra))
                run.assert_called_once_with(*expected)

    def test_open_or_saved_network_uses_argv_without_interactive_prompt(self):
        name = '--Cafe "open"; $(id)'
        with patch.object(wifi.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            wifi.connect('wlan0', name, 'open', '')
        self.assertEqual(run.call_args.args[0], ['iwctl', '--dont-ask', '--', 'station', 'wlan0', 'connect', name, 'open'])
        self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)

    def test_password_is_sent_only_to_prompt_and_errors_do_not_echo_it(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'iwctl'
            # A fake client exercises the actual subprocess + private terminal path.
            executable.write_text('''#!/usr/bin/env python3
import json, os, sys, tty
from pathlib import Path
tty.setraw(sys.stdin.fileno())
print('Passphrase:', end=' ', flush=True)
secret = ''
while True:
    char = sys.stdin.read(1)
    if char == '\\n': break
    secret += char
    print('*', end='', flush=True)
Path(os.environ['WIFI_TEST_RESULT']).write_text(json.dumps(dict(argv=sys.argv[1:], secret=secret)))
print(secret, flush=True)  # Even a misbehaving client must not leak its output.
sys.exit(int(os.environ['WIFI_TEST_EXIT']))
''')
            executable.chmod(0o755)
            result = Path(directory) / 'result.json'
            environment = dict(PATH=directory + os.pathsep + os.environ['PATH'], WIFI_TEST_RESULT=str(result))
            for status in (0, 1):
                with self.subTest(status=status), patch.dict(os.environ, dict(environment, WIFI_TEST_EXIT=str(status))):
                    if status:
                        with self.assertRaises(ValueError) as error: wifi.connect('wlan0', 'Home', 'psk', 'secret "phrase"')
                        self.assertNotIn('secret "phrase"', str(error.exception))
                    else:
                        wifi.connect('wlan0', 'Home', 'psk', 'secret "phrase"')
                received = json.loads(result.read_text())
                self.assertEqual(received['secret'], 'secret "phrase"')
                self.assertEqual(received['argv'], ['--', 'station', 'wlan0', 'connect', 'Home', 'psk'])


if __name__ == '__main__': unittest.main()
