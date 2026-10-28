#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'roles/desktop/files'))
import desktop_wifi as wifi


class WifiTests(unittest.TestCase):
    def test_snapshot_uses_ssid_instead_of_connection_name_and_deduplicates_aps(self):
        replies = ['enabled', 'wlan0:wifi:connected\nwlan1:wifi:disconnected\neth0:ethernet:connected',
                   'uuid1:802-11-wireless\nuuid2:802-11-wireless\nuuid3:wireguard',
                   r'Home\: Office' + '\nwpa-psk', 'Cafe\n',
                   r'*:Home\: Office:WPA2:90' + '\n:Home\\: Office:WPA2:95\n:Cafe::40']
        with patch.object(wifi.shutil, 'which', return_value='nmcli'), patch.object(wifi, 'run', side_effect=replies):
            state = wifi.snapshot()
        self.assertEqual(state['wifiDevice'], 'wlan0')
        self.assertEqual(state['wifiName'], 'Home: Office')
        self.assertEqual(state['wifiNetworks'], [dict(ssid='Home: Office', security='psk', signal=4, connected=True, known=True),
                                                dict(ssid='Cafe', security='open', signal=2, connected=False, known=True)])

    def test_nmcli_escape_parser_preserves_spaces_colons_and_backslashes(self):
        self.assertEqual(wifi.fields(r'  A\:B\\C  :WPA2:90'), ['  A:B\\C  ', 'WPA2', '90'])
        for source, expected in [('WPA2 802.1X', '8021x'), ('WPA3', 'psk'), ('sae', 'psk'),
                                 ('wpa-eap', '8021x'), ('OWE', 'open'), ('WEP', 'wep')]:
            self.assertEqual(wifi.security_type(source), expected)

    def test_radio_off_does_not_query_networks(self):
        with patch.object(wifi.shutil, 'which', return_value='nmcli'), patch.object(wifi, 'run', side_effect=[
                'disabled', 'wlan0:wifi:unavailable\nwlan1:wifi:unavailable']) as run:
            state = wifi.snapshot('wlan1')
        self.assertEqual(state['wifiDevice'], 'wlan1')
        self.assertTrue(state['wifiAvailable'])
        self.assertFalse(state['wifiEnabled'])
        self.assertEqual(run.call_count, 2)

    def test_unmanaged_adapters_and_missing_service_have_inline_errors(self):
        with patch.object(wifi.shutil, 'which', return_value='nmcli'), patch.object(wifi, 'run', side_effect=[
                'enabled', 'wlan0:wifi:unmanaged']):
            self.assertIn('No Wi-Fi adapter', wifi.snapshot()['wifiError'])
        with patch.object(wifi.shutil, 'which', return_value='nmcli'), patch.object(wifi, 'run', side_effect=ValueError('NetworkManager unavailable')):
            self.assertEqual(wifi.snapshot()['wifiError'], 'NetworkManager unavailable')

    def test_actions_validate_before_mutation_and_reject_removed_adapters(self):
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

    def test_radio_is_global_but_scan_and_disconnect_use_selected_adapter(self):
        for action, extra, expected in [('wifi-scan', {}, ('--wait', '20', '-f', 'SSID', 'device', 'wifi', 'list', 'ifname', 'wlan1', '--rescan', 'yes')),
                ('wifi-power', dict(enabled=False), ('radio', 'wifi', 'off')),
                ('wifi-disconnect', {}, ('device', 'disconnect', 'wlan1'))]:
            with self.subTest(action=action), patch.object(wifi, 'devices', return_value=[dict(id='wlan1')]), patch.object(wifi, 'run') as run:
                wifi.apply(action, dict(device='wlan1', **extra))
                run.assert_called_once_with(*expected, **({'timeout': 25} if action == 'wifi-scan' else {}))

    def test_scan_finishes_before_snapshot_reads_new_nearby_networks(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'nmcli'
            executable.write_text('''#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
args = sys.argv[1:]
finished = Path(os.environ['WIFI_SCAN_FINISHED'])
if 'radio' in args:
    print('enabled')
elif 'status' in args:
    print('wlan0:wifi:connected\\nwlan1:wifi:disconnected')
elif 'connection' in args:
    pass
elif 'rescan' in args:
    pass  # Request accepted, but results have not arrived yet.
elif 'list' in args:
    assert args[args.index('ifname') + 1] == 'wlan1'
    if args[args.index('--rescan') + 1] == 'yes':
        if os.environ.get('WIFI_SCAN_FAIL') == '1':
            print('Scan failed', file=sys.stderr)
            sys.exit(1)
        time.sleep(0.1)
        finished.touch()
    print('*:Home:WPA2:90')
    if finished.exists(): print(':Nearby Cafe::60')
else:
    raise AssertionError(args)
''')
            executable.chmod(0o755)
            marker = Path(directory) / 'finished'
            with patch.dict(os.environ, {'PATH': directory + os.pathsep + os.environ['PATH'],
                                         'WIFI_SCAN_FINISHED': str(marker)}):
                before = wifi.snapshot('wlan1')
                self.assertEqual(len(before['wifiNetworks']), 1)
                wifi.apply('wifi-scan', dict(device='wlan1'))
                after = wifi.snapshot('wlan1')
                self.assertEqual([network['ssid'] for network in after['wifiNetworks']], ['Home', 'Nearby Cafe'])
                self.assertEqual(after['wifiError'], '')
                with patch.dict(os.environ, WIFI_SCAN_FAIL='1'):
                    with self.assertRaisesRegex(ValueError, 'Scan failed'):
                        wifi.apply('wifi-scan', dict(device='wlan1'))

    def test_enterprise_requires_a_saved_profile(self):
        with patch.object(wifi, 'saved_networks', return_value={}), patch.object(wifi, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'enterprise'):
                wifi.connect('wlan0', 'Work', '8021x', '')
            run.assert_not_called()
        with patch.object(wifi, 'saved_networks', return_value={('Work', '8021x'): 'saved-uuid'}), patch.object(wifi, 'run') as run:
            wifi.connect('wlan0', 'Work', '8021x', '')
            run.assert_called_once_with('--wait', '40', 'connection', 'up', 'uuid', 'saved-uuid', 'ifname', 'wlan0', timeout=45)

    def test_password_uses_stdin_and_never_leaks_through_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'nmcli'
            executable.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
secret = sys.stdin.read()
Path(os.environ['WIFI_TEST_RESULT']).write_text(json.dumps(dict(argv=sys.argv[1:], secret=secret)))
print(secret, file=sys.stderr)
sys.exit(int(os.environ['WIFI_TEST_FAILURE']))
''')
            executable.chmod(0o755)
            result_path = Path(directory) / 'result.json'
            for saved in [False, True]:
                for failure in [0, 1]:
                    with self.subTest(saved=saved, failure=failure), patch.dict(os.environ, {
                            'PATH': directory + os.pathsep + os.environ['PATH'], 'WIFI_TEST_RESULT': str(result_path),
                            'WIFI_TEST_FAILURE': str(failure)}), patch.object(wifi, 'saved_networks', return_value={('Home', 'psk'): 'uuid'} if saved else {}):
                        if failure:
                            with self.assertRaises(ValueError) as raised: wifi.connect('wlan0', 'Home', 'psk', 'test secret')
                            self.assertNotIn('test secret', str(raised.exception))
                        else:
                            wifi.connect('wlan0', 'Home', 'psk', 'test secret')
                    result = json.loads(result_path.read_text())
                    self.assertNotIn('test secret', ' '.join(result['argv']))
                    self.assertEqual(result['secret'], ('802-11-wireless-security.psk:' if saved else '') + 'test secret\n')

    def test_ssid_is_a_literal_argument(self):
        name = '--Cafe "open"; $(id)'
        with patch.object(wifi, 'saved_networks', return_value={}), patch.object(wifi.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            wifi.connect('wlan0', name, 'open', '')
        self.assertIn(name, run.call_args.args[0])
        self.assertNotIn('shell', run.call_args.kwargs)


if __name__ == '__main__': unittest.main()
