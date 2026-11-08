"""Provider registry and persistent selection for the desktop VPN controls.

Providers expose metadata, request({action, value}) -> {ok, state, error}, and
signin(). Selecting a provider never changes any provider's connection.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from desktop_tailscale import TailscaleProvider


class ProtonProvider:
    id = 'proton'
    name = 'Proton VPN'
    location_kind = 'country'
    setup_url = 'https://protonvpn.com/support/linux-vpn-arch'
    location_hint = 'Type to filter countries, or leave blank for the fastest server. Choosing a country requires a paid Proton plan.'
    signin_hint = 'Sign in opens Proton’s terminal prompt for your password and two-factor authentication.'

    def __init__(self, root):
        self.helper = Path(root) / 'bin/desktop-protonvpn'

    def request(self, request):
        # Retain Proton's CLI parsing, sign-in handling and operation lock.
        result = subprocess.run([str(self.helper), '--stdin'], input=json.dumps(request) + '\n',
                                capture_output=True, text=True, timeout=150)
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'The Proton VPN helper failed.')
        response = json.loads(result.stdout)
        if not isinstance(response, dict) or not isinstance(response.get('state'), dict) or type(response.get('ok')) is not bool:
            raise ValueError('The Proton VPN helper returned an invalid response.')
        state = response['state']
        state['vpnLocations'] = state.pop('vpnCountries', [])
        state['vpnLocationsError'] = state.pop('vpnCountriesError', '')
        state.setdefault('vpnLocation', '')
        return response

    def signin(self):
        return subprocess.call([str(self.helper), '--signin'])


class VpnService:
    def __init__(self, root, providers=None):
        self.root = Path(root)
        self.path = self.root / 'vpn.json'
        self.providers = providers if providers is not None else {
            provider.id: provider for provider in [ProtonProvider(root), TailscaleProvider(root)]}

    def provider(self, identifier):
        if not isinstance(identifier, str) or identifier not in self.providers:
            raise ValueError('Choose an available VPN provider.')
        return self.providers[identifier]

    def selected(self):
        try:
            data = json.loads(self.path.read_text())
        except FileNotFoundError:
            return 'proton'
        if not isinstance(data, dict):
            raise ValueError('Invalid VPN preference. Select a provider to repair it.')
        return self.provider(data.get('provider')).id

    def select(self, identifier):
        provider = self.provider(identifier)
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        namespace = hashlib.sha256(str(self.root).encode()).hexdigest()[:16]
        with (runtime / ('archsetup-vpn-preferences-' + namespace + '.lock')).open('a') as guard:
            fcntl.flock(guard, fcntl.LOCK_EX)
            with tempfile.NamedTemporaryFile(mode='w', dir=self.root, prefix='.vpn-', delete=False) as output:
                temporary = Path(output.name)
                try:
                    json.dump({'provider': provider.id}, output)
                    output.write('\n')
                    output.flush()
                    os.fsync(output.fileno())
                    os.replace(temporary, self.path)
                finally:
                    temporary.unlink(missing_ok=True)
        return provider

    def describe(self, provider):
        return dict(id=provider.id, name=provider.name)

    def decorate(self, response, provider):
        state = response.setdefault('state', {})
        state.update(vpnProvider=provider.id, vpnProviderName=provider.name,
                     vpnProviders=[self.describe(item) for item in self.providers.values()],
                     vpnLocationKind=provider.location_kind, vpnSetupUrl=provider.setup_url,
                     vpnLocationHint=provider.location_hint, vpnSigninHint=provider.signin_hint)
        return response

    def error(self, message, identifier='proton'):
        provider = self.providers.get(identifier, self.providers['proton'])
        return self.decorate(dict(ok=False, error=str(message), state=dict(vpnStatus='unknown',
            vpnReady=False, vpnConnected=False, vpnError=str(message))), provider)

    def request(self, request):
        if not isinstance(request, dict):
            raise ValueError('Invalid VPN request.')
        action = request.get('action')
        if action == 'select-provider':
            provider = self.select(request.get('value'))
            payload = {}
        else:
            provider = self.provider(request['provider'] if 'provider' in request else self.selected())
            if action not in (None, 'connect', 'disconnect', 'set-location'):
                raise ValueError('Unknown VPN action.')
            payload = {key: request[key] for key in ('action', 'value') if key in request}
        try:
            return self.decorate(provider.request(payload), provider)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            return self.error(error, provider.id)
