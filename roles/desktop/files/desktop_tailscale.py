"""Tailscale provider: native authentication and narrowly scoped CLI changes."""
import fcntl
import getpass
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess


def command(*args, timeout=15):
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=timeout, env=dict(os.environ, LC_ALL='C', NO_COLOR='1'))
    if result.returncode:
        message = result.stderr.strip() or result.stdout.strip() or 'Tailscale command failed.'
        if any(text in message.lower() for text in ('access denied', 'permission denied', 'must be root')):
            message = 'Allow your desktop user to manage Tailscale: sudo tailscale set --operator=' + getpass.getuser()
        raise ValueError(message)
    return result.stdout.strip()


class TailscaleProvider:
    id = 'tailscale'
    name = 'Tailscale'
    location_kind = 'exit-node'
    setup_url = 'https://tailscale.com/docs/quickstart'
    location_hint = 'An exit node routes internet traffic through that device. Without one, Tailscale connects your tailnet devices only.'
    signin_hint = 'Sign in opens Tailscale’s browser authorization flow in a terminal.'

    def __init__(self, root):
        self.root = Path(root)

    def empty_state(self):
        return dict(vpnAvailable=shutil.which('tailscale') is not None, vpnReady=False,
                    vpnConnected=False, vpnSignedIn=False, vpnStatus='unknown', vpnError='',
                    vpnServer='', vpnProtocol='', vpnAddress='', vpnNetwork='',
                    vpnLocations=[], vpnLocationsError='', vpnLocation='')

    def snapshot(self):
        state = self.empty_state()
        if not state['vpnAvailable']:
            state.update(vpnStatus='install', vpnError='Install tailscale and start tailscaled.service to use this provider.')
            return state
        try:
            data = json.loads(command('tailscale', 'status', '--json'))
            if not isinstance(data, dict) or not isinstance(data.get('BackendState'), str):
                raise ValueError('Tailscale returned an invalid connection status.')
            backend = data['BackendState']
            statuses = {'Running': 'connected', 'Stopped': 'disconnected', 'NeedsLogin': 'signin',
                        'NeedsMachineAuth': 'approval', 'Starting': 'connecting',
                        'NoState': 'unknown', 'InUseOtherUser': 'unknown'}
            state.update(vpnStatus=statuses.get(backend, 'unknown'), vpnConnected=backend == 'Running',
                         vpnReady=backend in ('Running', 'Stopped'), vpnSignedIn=backend in ('Running', 'Stopped', 'Starting', 'NeedsMachineAuth'))
            # A stopped daemon can also have no account yet. Do not start a
            # background up command that would wait for browser authentication.
            authenticated = data.get('HaveNodeKey') is True or bool((data.get('Self') or {}).get('ID')) or bool(data.get('TailscaleIPs'))
            if backend == 'Stopped' and not authenticated:
                state.update(vpnStatus='signin', vpnReady=False, vpnSignedIn=False)
            if backend == 'NeedsMachineAuth':
                state['vpnError'] = 'A tailnet administrator must approve this device before it can connect.'
            elif state['vpnStatus'] == 'unknown':
                state['vpnError'] = 'Tailscale is not ready. Check the daemon and refresh.'
            peers = data.get('Peer')
            if peers is None:
                peers = {}
            if not isinstance(peers, dict):
                raise ValueError('Tailscale returned an invalid peer list.')
            selected = data.get('ExitNodeStatus')
            if selected is None:
                selected = {}
            if not isinstance(selected, dict):
                raise ValueError('Tailscale returned an invalid exit node.')
            selected_id = selected.get('ID', '')
            selected_peer = None
            locations = []
            for peer in peers.values():
                if not isinstance(peer, dict) or not peer.get('ExitNodeOption'):
                    continue
                addresses = peer.get('TailscaleIPs') or []
                if not addresses:
                    continue
                address = str(ipaddress.ip_address(addresses[0]))
                name = (peer.get('DNSName') or peer.get('HostName') or address).rstrip('.')
                if peer.get('Online'):
                    locations.append(dict(id=address, name=name))
                if peer.get('ExitNode') or selected_id and peer.get('ID') == selected_id:
                    selected_peer = peer
                    state['vpnLocation'] = address
                    state['vpnServer'] = name
            state['vpnLocations'] = sorted(locations, key=lambda item: item['name'].casefold())
            if selected_id and not state['vpnLocation']:
                addresses = selected.get('TailscaleIPs') or []
                state['vpnLocation'] = str(addresses[0]) if addresses else str(selected_id)
                state['vpnServer'] = 'Selected exit node'
            state['vpnServer'] = state['vpnServer'] or 'Tailnet only'
            if (selected_id and not selected.get('Online', True)) or (selected_peer and not selected_peer.get('Online')):
                state['vpnError'] = 'The selected exit node is offline. Choose another exit node or use the tailnet only.'
            addresses = data.get('TailscaleIPs') or []
            state['vpnAddress'] = ', '.join(str(ipaddress.ip_address(address)) for address in addresses)
            state['vpnNetwork'] = (data.get('CurrentTailnet') or {}).get('Name', '')
            state['vpnProtocol'] = 'WireGuard' if state['vpnConnected'] else ''
        except (OSError, ValueError, TypeError, AttributeError, subprocess.TimeoutExpired) as error:
            message = 'Tailscale did not respond in time. Refresh to check its current state.' if isinstance(error, subprocess.TimeoutExpired) else str(error)
            if any(text in message.lower() for text in ('failed to connect to local tailscaled', 'tailscaled is not running', 'no such file or directory')):
                state.update(vpnStatus='service', vpnError='Start tailscaled.service to use Tailscale.')
            else:
                state.update(vpnStatus='unknown', vpnError=message)
            state.update(vpnReady=False, vpnConnected=False)
        return state

    def apply(self, action, value):
        if action not in ('connect', 'disconnect', 'set-location'):
            raise ValueError('Unknown Tailscale action.')
        if action == 'disconnect':
            if value is not None:
                raise ValueError('Unexpected disconnect value.')
        elif not isinstance(value, str) or len(value) > 128:
            raise ValueError('Choose an exit node, or leave it empty for tailnet access only.')
        state = self.snapshot()
        if not state['vpnReady']:
            raise ValueError(state['vpnError'] or 'Sign in to Tailscale first.')
        if action == 'disconnect':
            if state['vpnConnected']:
                command('tailscale', 'down', timeout=30)
            return
        if value and value not in [location['id'] for location in state['vpnLocations']]:
            raise ValueError('That exit node is unavailable. Refresh and choose an online exit node.')
        if action == 'set-location' and not state['vpnConnected']:
            raise ValueError('Connect to Tailscale before changing the active exit node.')
        if action == 'connect' and state['vpnConnected']:
            raise ValueError('Tailscale is already connected. Use Apply exit node to change its route.')
        # Set changes only the exit-node preference. Bare up preserves all other
        # preferences, including DNS, subnet routes, SSH and custom login servers.
        command('tailscale', 'set', '--exit-node=' + value, timeout=30)
        if action == 'connect':
            command('tailscale', 'up', timeout=45)

    def request(self, request):
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        namespace = hashlib.sha256(str(self.root).encode()).hexdigest()[:16]
        with (runtime / ('archsetup-tailscale-' + namespace + '.lock')).open('a') as guard:
            try:
                fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Tailscale is busy. Wait for the current operation.') from None
            error = ''
            action = request.get('action')
            if action:
                try:
                    self.apply(action, request.get('value'))
                except (OSError, ValueError, subprocess.TimeoutExpired) as exception:
                    error = 'Tailscale timed out. Refresh before retrying.' if isinstance(exception, subprocess.TimeoutExpired) else str(exception)
            state = self.snapshot()
            if not error and action in ('connect', 'disconnect', 'set-location'):
                if action == 'set-location':
                    confirmed = state['vpnConnected'] and state['vpnLocation'] == request.get('value')
                else:
                    confirmed = state['vpnStatus'] == ('connected' if action == 'connect' else 'disconnected')
                if not confirmed:
                    error = state['vpnError'] or 'Tailscale has not confirmed the requested connection state. Refresh before retrying.'
            return dict(ok=not error, state=state, error=error)

    def signin(self):
        if not shutil.which('tailscale'):
            raise ValueError('Install tailscale and start tailscaled.service first.')
        code = subprocess.call(['tailscale', 'login'])
        input('\nPress Enter to close. Then refresh the VPN panel.')
        return code
