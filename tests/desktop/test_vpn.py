#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

FILES = Path(__file__).resolve().parents[2] / 'roles/desktop/files'
sys.path.insert(0, str(FILES))
from desktop_vpn import ProtonProvider, VpnService
import desktop_tailscale as tailscale


def status(backend='Running', selected=False):
    data = dict(BackendState=backend, TailscaleIPs=['100.64.0.1', 'fd7a:115c:a1e0::1'],
                CurrentTailnet={'Name': 'test.example'}, Peer={
        'one': dict(ID='n1', DNSName='paris.test.ts.net.', TailscaleIPs=['100.64.0.2'],
                    ExitNodeOption=True, Online=True, ExitNode=selected),
        'two': dict(ID='n2', HostName='offline', TailscaleIPs=['100.64.0.3'], ExitNodeOption=True, Online=False),
        'other': dict(ID='n3', HostName='ordinary', TailscaleIPs=['100.64.0.4'], Online=True)})
    if selected:
        data['ExitNodeStatus'] = dict(ID='n1', Online=True, TailscaleIPs=['100.64.0.2'])
    return data


class TailscaleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.provider = tailscale.TailscaleProvider(self.directory.name)

    def snapshot(self, data):
        with patch.object(tailscale.shutil, 'which', return_value='/usr/bin/tailscale'), \
             patch.object(tailscale, 'command', return_value=json.dumps(data)):
            return self.provider.snapshot()

    def test_missing_cli_service_and_invalid_status_are_explicit(self):
        with patch.object(tailscale.shutil, 'which', return_value=None), patch.object(tailscale, 'command') as command:
            self.assertEqual(self.provider.snapshot()['vpnStatus'], 'install')
            command.assert_not_called()
        for error, expected in [(ValueError('failed to connect to local tailscaled'), 'service'),
                                (subprocess.TimeoutExpired(['tailscale'], 15), 'unknown')]:
            with self.subTest(error=error), patch.object(tailscale.shutil, 'which', return_value='tailscale'), \
                 patch.object(tailscale, 'command', side_effect=error):
                state = self.provider.snapshot()
                self.assertEqual(state['vpnStatus'], expected)
                self.assertFalse(state['vpnReady'])
                self.assertFalse(state['vpnConnected'])
        for data in [{}, [], {'BackendState': 'Unrecognized'}, {'BackendState': 'Running', 'Peer': []}]:
            with self.subTest(data=data):
                state = self.snapshot(data)
                self.assertEqual(state['vpnStatus'], 'unknown')
                self.assertFalse(state['vpnReady'])
                self.assertFalse(state['vpnConnected'])

    def test_backend_states_distinguish_authentication_and_connection(self):
        for backend, expected, ready in [('NeedsLogin', 'signin', False), ('NeedsMachineAuth', 'approval', False),
                                         ('Stopped', 'disconnected', True), ('Starting', 'connecting', False),
                                         ('Running', 'connected', True)]:
            with self.subTest(backend=backend):
                state = self.snapshot(status(backend))
                self.assertEqual(state['vpnStatus'], expected)
                self.assertEqual(state['vpnReady'], ready)
                self.assertEqual(state['vpnConnected'], backend == 'Running')

    def test_exit_nodes_only_include_online_capable_peers(self):
        state = self.snapshot(status(selected=True))
        self.assertEqual(state['vpnLocations'], [{'id': '100.64.0.2', 'name': 'paris.test.ts.net'}])
        self.assertEqual(state['vpnLocation'], '100.64.0.2')
        self.assertEqual(state['vpnServer'], 'paris.test.ts.net')
        self.assertEqual(state['vpnNetwork'], 'test.example')
        self.assertEqual(state['vpnAddress'], '100.64.0.1, fd7a:115c:a1e0::1')
        self.assertEqual(state['vpnProtocol'], 'WireGuard')
        state = self.snapshot(status())
        self.assertEqual(state['vpnLocation'], '')
        self.assertEqual(state['vpnServer'], 'Tailnet only')

    def test_stopped_without_an_account_requires_interactive_signin(self):
        state = self.snapshot({'BackendState': 'Stopped', 'Self': None, 'Peer': {}, 'TailscaleIPs': []})
        self.assertEqual(state['vpnStatus'], 'signin')
        self.assertFalse(state['vpnReady'])
        self.assertFalse(state['vpnSignedIn'])

    def test_selected_offline_exit_node_is_not_silently_reported_as_tailnet_only(self):
        data = status(selected=True)
        data['Peer']['one']['Online'] = False
        data['ExitNodeStatus']['Online'] = False
        state = self.snapshot(data)
        self.assertEqual(state['vpnLocations'], [])
        self.assertEqual(state['vpnLocation'], '100.64.0.2')
        self.assertIn('offline', state['vpnError'])
        data['Peer'] = {}
        state = self.snapshot(data)
        self.assertEqual(state['vpnLocation'], '100.64.0.2')
        self.assertIn('offline', state['vpnError'])

    def test_connect_and_route_changes_preserve_unrelated_preferences(self):
        disconnected = dict(vpnReady=True, vpnConnected=False, vpnLocations=[{'id': '100.64.0.2', 'name': 'Paris'}])
        for value in ['', '100.64.0.2']:
            with self.subTest(value=value), patch.object(self.provider, 'snapshot', return_value=disconnected), patch.object(tailscale, 'command') as command:
                self.provider.apply('connect', value)
                self.assertEqual([call.args for call in command.call_args_list],
                                 [('tailscale', 'set', '--exit-node=' + value), ('tailscale', 'up')])
        connected = dict(disconnected, vpnConnected=True)
        with patch.object(self.provider, 'snapshot', return_value=connected), patch.object(tailscale, 'command') as command:
            self.provider.apply('set-location', '')
            command.assert_called_once_with('tailscale', 'set', '--exit-node=', timeout=30)
        with patch.object(self.provider, 'snapshot', return_value=connected), patch.object(tailscale, 'command') as command:
            self.provider.apply('disconnect', None)
            command.assert_called_once_with('tailscale', 'down', timeout=30)

    def test_invalid_or_unavailable_locations_never_reach_a_mutation(self):
        state = dict(vpnReady=True, vpnConnected=False, vpnLocations=[])
        for action, value in [('connect', '--reset'), ('connect', '100.64.0.3'), ('connect', True),
                              ('connect', '100.64.0.2; touch /tmp/unwanted'), ('disconnect', 'id'),
                              ('set-location', ''), ('other', '')]:
            with self.subTest(action=action, value=value), patch.object(self.provider, 'snapshot', return_value=state), patch.object(tailscale, 'command') as command:
                with self.assertRaises(ValueError): self.provider.apply(action, value)
                command.assert_not_called()

    def test_status_confirmation_and_command_errors_return_observed_state(self):
        state = self.provider.empty_state()
        state.update(vpnReady=True, vpnStatus='disconnected')
        with patch.dict(os.environ, {'XDG_RUNTIME_DIR': self.directory.name}), patch.object(self.provider, 'apply'), patch.object(self.provider, 'snapshot', return_value=state):
            result = self.provider.request({'action': 'connect', 'value': ''})
        self.assertFalse(result['ok'])
        self.assertEqual(result['state']['vpnStatus'], 'disconnected')
        self.assertIn('not confirmed', result['error'])
        with patch.dict(os.environ, {'XDG_RUNTIME_DIR': self.directory.name}), patch.object(self.provider, 'apply', side_effect=ValueError('Permission denied')), patch.object(self.provider, 'snapshot', return_value=state):
            result = self.provider.request({'action': 'connect', 'value': ''})
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'], 'Permission denied')

    def test_busy_provider_cannot_race_another_operation(self):
        namespace = hashlib.sha256(str(self.provider.root).encode()).hexdigest()[:16]
        with (Path(self.directory.name) / ('archsetup-tailscale-' + namespace + '.lock')).open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': self.directory.name}), self.assertRaisesRegex(ValueError, 'busy'):
                self.provider.request({})

    def test_permissions_have_actionable_operator_message_and_no_shell(self):
        response = subprocess.CompletedProcess([], 1, '', 'Access denied: you must be root')
        with patch.object(tailscale.subprocess, 'run', return_value=response) as run:
            with self.assertRaisesRegex(ValueError, 'tailscale set --operator='):
                tailscale.command('tailscale', 'down')
            self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)
            self.assertNotIn('shell', run.call_args.kwargs)

    def test_signin_assigns_real_user_to_new_profile_and_elevates_only_native_cli(self):
        with patch.object(tailscale.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(tailscale.os, 'getuid', return_value=1000), \
             patch.object(tailscale.pwd, 'getpwuid', return_value=Mock(pw_name='alex')) as account, \
             patch.dict(os.environ, {'USER': 'root', 'LOGNAME': 'root'}), \
             patch.object(tailscale.subprocess, 'call', return_value=0) as call, \
             patch('builtins.input', return_value='') as prompt, patch('builtins.print'):
            self.assertEqual(self.provider.signin(), 0)
        account.assert_called_once_with(1000)
        call.assert_called_once_with(['sudo', '--', 'tailscale', 'login', '--operator=alex'])
        prompt.assert_called_once()

    def test_failed_or_cancelled_signin_does_not_retry_or_connect(self):
        for code in [1, 130]:
            with self.subTest(code=code), patch.object(tailscale.shutil, 'which', return_value='/usr/bin/tool'), \
                 patch.object(tailscale.subprocess, 'call', return_value=code) as call, \
                 patch('builtins.input', return_value=''), patch('builtins.print'):
                self.assertEqual(self.provider.signin(), code)
                self.assertEqual(call.call_count, 1)

    def test_signin_reports_missing_cli_or_sudo_before_running_commands(self):
        for missing in ['tailscale', 'sudo']:
            with self.subTest(missing=missing), patch.object(tailscale.shutil, 'which',
                    side_effect=lambda tool: None if tool == missing else '/usr/bin/' + tool), \
                 patch.object(tailscale.subprocess, 'call') as call, self.assertRaisesRegex(ValueError, missing):
                self.provider.signin()
            call.assert_not_called()


class ProviderSelectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.proton = Mock(id='proton', location_kind='country', setup_url='https://protonvpn.com')
        self.proton.name = 'Proton VPN'
        self.proton.location_hint = 'Choose a country.'
        self.proton.signin_hint = 'Use the native CLI.'
        self.tailscale = Mock(id='tailscale', location_kind='exit-node', setup_url='https://tailscale.com')
        self.tailscale.name = 'Tailscale'
        self.tailscale.location_hint = 'Choose an exit node.'
        self.tailscale.signin_hint = 'Use browser authorization.'
        self.proton.request.side_effect = lambda request: dict(ok=True, error='', state=dict(vpnConnected=True, vpnStatus='connected'))
        self.tailscale.request.side_effect = lambda request: dict(ok=True, error='', state=dict(vpnConnected=False, vpnStatus='disconnected'))
        self.service = VpnService(self.root, {'proton': self.proton, 'tailscale': self.tailscale})
        self.runtime = patch.dict(os.environ, {'XDG_RUNTIME_DIR': self.directory.name})
        self.runtime.start()
        self.addCleanup(self.runtime.stop)

    def test_switch_persists_selection_without_connecting_or_disconnecting(self):
        self.assertEqual(self.service.selected(), 'proton')
        response = self.service.request({'action': 'select-provider', 'value': 'tailscale'})
        self.proton.request.assert_not_called()
        self.tailscale.request.assert_called_once_with({})
        self.assertEqual(json.loads((self.root / 'vpn.json').read_text()), {'provider': 'tailscale'})
        self.assertEqual(VpnService(self.root).selected(), 'tailscale')
        self.assertEqual(response['state']['vpnProvider'], 'tailscale')
        self.assertEqual(response['state']['vpnLocationKind'], 'exit-node')
        self.assertEqual(response['state']['vpnProviders'], [{'id': 'proton', 'name': 'Proton VPN'}, {'id': 'tailscale', 'name': 'Tailscale'}])

    def test_actions_are_pinned_to_the_provider_shown_when_the_request_was_made(self):
        self.service.select('tailscale')
        self.service.request({'provider': 'proton', 'action': 'disconnect', 'value': None})
        self.proton.request.assert_called_once_with({'action': 'disconnect', 'value': None})
        self.tailscale.request.assert_not_called()
        self.assertEqual(self.service.selected(), 'tailscale')

    def test_invalid_provider_and_requests_do_not_mutate_preferences_or_connections(self):
        for value in ['unknown', '../proton', True, {}, []]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.service.request({'action': 'select-provider', 'value': value})
        for request in [[], None, {'action': 'shell'}, {'provider': 'missing'}, {'provider': False, 'action': 'disconnect'}]:
            with self.subTest(request=request), self.assertRaises(ValueError): self.service.request(request)
        self.assertFalse((self.root / 'vpn.json').exists())
        self.proton.request.assert_not_called()
        self.tailscale.request.assert_not_called()

    def test_selection_repairs_invalid_preferences_and_provider_errors_remain_selectable(self):
        (self.root / 'vpn.json').write_text('not JSON')
        with self.assertRaises(ValueError): self.service.selected()
        self.tailscale.request.side_effect = ValueError('daemon unavailable')
        response = self.service.request({'action': 'select-provider', 'value': 'tailscale'})
        self.assertFalse(response['ok'])
        self.assertEqual(response['state']['vpnProvider'], 'tailscale')
        self.assertEqual(len(response['state']['vpnProviders']), 2)
        self.assertEqual(self.service.selected(), 'tailscale')

    def test_proton_adapter_reuses_existing_cli_and_normalizes_location_data(self):
        state = {'vpnCountries': [{'id': 'ES', 'name': 'Spain'}], 'vpnCountriesError': '', 'vpnStatus': 'disconnected'}
        result = subprocess.CompletedProcess([], 0, json.dumps({'ok': True, 'state': state, 'error': ''}))
        with patch('desktop_vpn.subprocess.run', return_value=result) as run:
            response = ProtonProvider(self.root).request({'action': 'connect', 'value': 'ES'})
        self.assertEqual(run.call_args.args[0], [str(self.root / 'bin/desktop-protonvpn'), '--stdin'])
        self.assertEqual(json.loads(run.call_args.kwargs['input']), {'action': 'connect', 'value': 'ES'})
        self.assertEqual(response['state']['vpnLocations'], [{'id': 'ES', 'name': 'Spain'}])
        self.assertNotIn('vpnCountries', response['state'])


class VpnCliTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.root / 'runtime').mkdir(mode=0o700)
        for name in ['desktop-vpn', 'desktop_vpn.py', 'desktop_tailscale.py']:
            shutil.copy2(FILES / name, self.bin / name)
        proton = self.bin / 'desktop-protonvpn'
        proton.write_text('''#!/usr/bin/env python3
import json, sys
from pathlib import Path
root = Path(__file__).parent
request = json.loads(sys.stdin.readline())
with (root / 'proton-calls').open('a') as log: log.write(json.dumps(request) + '\\n')
print(json.dumps(dict(ok=True, state=dict(vpnReady=True, vpnConnected=True, vpnStatus='connected',
    vpnServer='ES#1', vpnCountries=[], vpnCountriesError=''), error='')))
''')
        proton.chmod(0o755)
        cli = self.bin / 'tailscale'
        cli.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(__file__).parent
path = root / 'tailscale-state.json'
state = json.loads(path.read_text()) if path.exists() else dict(BackendState='Stopped', selected='')
args = sys.argv[1:]
with (root / 'tailscale-calls').open('a') as log: log.write(json.dumps(args) + '\\n')
if args == ['status', '--json']:
    data = dict(BackendState=state['BackendState'], TailscaleIPs=['100.64.0.1'], CurrentTailnet={'Name': 'test.example'},
        Peer={'node': dict(ID='n1', HostName='Paris', TailscaleIPs=['100.64.0.2'], ExitNodeOption=True, Online=True,
                           ExitNode=bool(state['selected']))})
    if state['selected']: data['ExitNodeStatus'] = dict(ID='n1', Online=True, TailscaleIPs=['100.64.0.2'])
    print(json.dumps(data))
elif args[0:1] == ['set'] and len(args) == 2 and args[1].startswith('--exit-node='):
    state['selected'] = args[1].split('=', 1)[1]
elif args[0:1] == ['login']:
    # Login creates a profile; the old profile's operator is discarded.
    state['operator'] = ''
    if os.environ.get('ARCHSETUP_TEST_SUDO') != '1' or len(args) != 2 or not args[1].startswith('--operator='):
        path.write_text(json.dumps(state))
        print('Access denied: checkprefs access denied', file=sys.stderr)
        sys.exit(1)
    state['operator'] = args[1].split('=', 1)[1]
    state['BackendState'] = 'Running'
elif args == ['up']: state['BackendState'] = 'Running'
elif args == ['down']: state['BackendState'] = 'Stopped'
else: sys.exit(2)
path.write_text(json.dumps(state))
''')
        cli.chmod(0o755)
        self.environment = dict(os.environ, XDG_RUNTIME_DIR=str(self.root / 'runtime'),
                                PATH=str(self.bin) + os.pathsep + os.environ['PATH'])

    def request(self, payload):
        result = subprocess.run([sys.executable, str(self.bin / 'desktop-vpn'), '--stdin'],
            input=json.dumps(payload) + '\n', capture_output=True, text=True, timeout=10,
            env=self.environment, check=True)
        return json.loads(result.stdout)

    def test_real_json_helper_routes_selection_connection_and_location_operations(self):
        response = self.request({'action': 'select-provider', 'value': 'tailscale'})
        self.assertTrue(response['ok'])
        self.assertEqual(response['state']['vpnProvider'], 'tailscale')
        self.assertFalse((self.bin / 'proton-calls').exists())
        calls = [json.loads(line) for line in (self.bin / 'tailscale-calls').read_text().splitlines()]
        self.assertEqual(calls, [['status', '--json']])
        response = self.request({'action': 'connect', 'value': '100.64.0.2'})
        self.assertTrue(response['ok'], response)
        self.assertTrue(response['state']['vpnConnected'])
        self.assertEqual(response['state']['vpnLocation'], '100.64.0.2')
        response = self.request({'action': 'set-location', 'value': ''})
        self.assertTrue(response['ok'], response)
        self.assertEqual(response['state']['vpnServer'], 'Tailnet only')
        response = self.request({'action': 'select-provider', 'value': 'proton'})
        self.assertTrue(response['state']['vpnConnected'])
        self.assertEqual(json.loads((self.bin / 'tailscale-state.json').read_text())['BackendState'], 'Running')
        response = self.request({'provider': 'tailscale', 'action': 'disconnect', 'value': None})
        self.assertTrue(response['ok'], response)
        self.assertFalse(response['state']['vpnConnected'])
        self.assertEqual(json.loads((self.root / 'vpn.json').read_text()), {'provider': 'proton'})

    def test_invalid_json_request_is_reported_without_changing_any_connection(self):
        response = self.request(['connect', 'tailscale'])
        self.assertFalse(response['ok'])
        self.assertEqual(len(response['state']['vpnProviders']), 2)
        self.assertFalse((self.bin / 'proton-calls').exists())
        self.assertFalse((self.bin / 'tailscale-calls').exists())

    def test_interactive_helper_keeps_operator_on_the_new_login_profile(self):
        sudo = self.bin / 'sudo'
        sudo.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
assert sys.argv[1:3] == ['--', 'tailscale'], sys.argv
Path(__file__).with_name('sudo-calls').write_text(json.dumps(sys.argv[1:]))
os.execvpe(sys.argv[2], sys.argv[2:], dict(os.environ, ARCHSETUP_TEST_SUDO='1'))
''')
        sudo.chmod(0o755)
        state = self.bin / 'tailscale-state.json'
        state.write_text(json.dumps(dict(BackendState='NeedsLogin', selected='', operator='previous-operator')))
        result = subprocess.run([sys.executable, str(self.bin / 'desktop-vpn'), '--provider', 'tailscale', '--signin'],
            input='\n', capture_output=True, text=True, timeout=10,
            env=dict(self.environment, USER='wrong-user', LOGNAME='wrong-user'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        operator = tailscale.pwd.getpwuid(os.getuid()).pw_name
        self.assertEqual(json.loads(state.read_text())['operator'], operator)
        self.assertEqual(json.loads((self.bin / 'sudo-calls').read_text()),
                         ['--', 'tailscale', 'login', '--operator=' + operator])
        self.assertFalse((self.bin / 'proton-calls').exists())

    def test_provider_source_serializes_switches_and_keeps_connections_when_closed(self):
        if not shutil.which('qs') or not shutil.which('dbus-run-session'):
            self.skipTest('Quickshell and D-Bus are required')
        shutil.copy2(FILES / 'shell/VpnSource.qml', self.root)
        shutil.copy2(Path(__file__).parent / 'controls/vpn-source.qml', self.root / 'shell.qml')
        result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(self.root)],
            capture_output=True, text=True, timeout=12,
            env=dict(self.environment, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('ARCHSETUP_VPN_SOURCE_PASSED', result.stdout + result.stderr)
        self.assertEqual(json.loads((self.bin / 'tailscale-state.json').read_text())['BackendState'], 'Running')
        calls = [json.loads(line) for line in (self.bin / 'proton-calls').read_text().splitlines()]
        self.assertTrue(all(not call.get('action') for call in calls))


if __name__ == '__main__':
    unittest.main()
