"""NetworkManager Wi-Fi controls; secrets travel over stdin, never argv."""
import os
import shutil
import subprocess


def run(*args, timeout=8, secret=None):
    command = ['nmcli', '--terse', '--escape', 'yes', '--colors', 'no']
    if secret is not None:
        command += ['--ask']
    try:
        result = subprocess.run(command + list(args), capture_output=True, text=True,
                                input=secret + '\n' if secret is not None else '',
                                timeout=timeout, env=dict(os.environ, LC_ALL='C'))
    except subprocess.TimeoutExpired:
        raise ValueError('Wi-Fi did not respond. Check NetworkManager and try again.') from None
    if result.returncode:
        # Interactive nmcli output can include echoed input. Never return it.
        raise ValueError('Could not connect. Check the password and try again.' if secret is not None
                         else result.stderr.strip() or 'NetworkManager command failed.')
    return result.stdout.rstrip('\n')


def fields(line):
    """Decode nmcli's escaped colons/backslashes without trimming SSIDs."""
    values, value, escaped = [], '', False
    for char in line:
        if escaped:
            value += char
            escaped = False
        elif char == '\\':
            escaped = True
        elif char == ':':
            values.append(value)
            value = ''
        else:
            value += char
    values.append(value + ('\\' if escaped else ''))
    return values


def devices():
    powered = run('radio', 'wifi') == 'enabled'
    return [dict(id=name, name=name, powered=powered, state=state)
            for name, kind, state in (fields(line) for line in
                run('-f', 'DEVICE,TYPE,STATE', 'device', 'status').splitlines())
            if kind == 'wifi' and state != 'unmanaged']


def security_type(value):
    if '802.1X' in value or 'EAP' in value:
        return '8021x'
    if 'WPA' in value or value in ('wpa-psk', 'sae'):
        return 'psk'
    if value in ('wpa-eap', 'wpa-eap-suite-b-192', 'ieee8021x'):
        return '8021x'
    if value in ('', '--', 'owe') or 'OWE' in value:
        return 'open'
    return 'wep'


def saved_networks():
    result = {}
    for line in run('-f', 'UUID,TYPE', 'connection', 'show').splitlines():
        uuid, kind = fields(line)
        if kind != '802-11-wireless':
            continue
        details = run('-g', '802-11-wireless.ssid,802-11-wireless-security.key-mgmt',
                      'connection', 'show', 'uuid', uuid).split('\n')
        if details[0]:
            result[(fields(details[0])[0], security_type(details[1] if len(details) > 1 else ''))] = uuid
    return result


def snapshot(device=''):
    state = dict(wifiAvailable=False, wifiEnabled=False, wifiName='', wifiDevice='',
                 wifiDevices=[], wifiNetworks=[], wifiState='', wifiScanning=False, wifiError='')
    if not shutil.which('nmcli'):
        state['wifiError'] = 'Install NetworkManager to manage Wi-Fi here.'
        return state
    try:
        adapters = devices()
        state['wifiDevices'] = adapters
        if not adapters:
            state['wifiError'] = 'No Wi-Fi adapter is managed by NetworkManager.'
            return state
        adapter = next((item for item in adapters if item['id'] == device), adapters[0])
        device = adapter['id']
        state.update(wifiAvailable=True, wifiDevice=device, wifiEnabled=adapter['powered'],
                     wifiState='connecting' if adapter['state'].startswith('connecting') else adapter['state'])
        if not adapter['powered']:
            return state
        known = saved_networks()
        found = {}
        for line in run('-f', 'IN-USE,SSID,SECURITY,SIGNAL', 'device', 'wifi', 'list',
                        'ifname', device, '--rescan', 'no').splitlines():
            active, ssid, security, signal = fields(line)
            if not ssid:
                continue
            security = security_type(security)
            key = (ssid, security)
            strength = int(signal)
            network = dict(ssid=ssid, security=security, signal=max(1, min(4, (strength + 24) // 25)),
                           connected=active == '*', known=key in known)
            if network['connected']:
                state['wifiName'] = ssid
            previous = found.get(key)
            if not previous or (network['connected'], network['signal']) > (previous['connected'], previous['signal']):
                found[key] = network
        state['wifiNetworks'] = list(found.values())
    except (OSError, ValueError) as error:
        state['wifiError'] = str(error)
    return state


def connect(device, ssid, security, passphrase):
    uuid = saved_networks().get((ssid, security))
    if uuid:
        # passwd-file accepts /dev/stdin and avoids asking again for a stored key.
        if passphrase:
            command = ['nmcli', '--wait', '40', 'connection', 'up', 'uuid', uuid,
                       'ifname', device, 'passwd-file', '/dev/stdin']
            try:
                result = subprocess.run(command, input='802-11-wireless-security.psk:' + passphrase + '\n',
                                        capture_output=True, text=True, timeout=45,
                                        env=dict(os.environ, LC_ALL='C'))
            except subprocess.TimeoutExpired:
                raise ValueError('Wi-Fi connection timed out. Try again.') from None
            if result.returncode:
                raise ValueError('Could not connect. Check the password and try again.')
        else:
            run('--wait', '40', 'connection', 'up', 'uuid', uuid, 'ifname', device, timeout=45)
    elif security == '8021x':
        raise ValueError('Configure this enterprise network in NetworkManager settings first.')
    else:
        run('--wait', '40', 'device', 'wifi', 'connect', ssid, 'ifname', device,
            timeout=45, secret=passphrase or None)


def apply(action, value):
    if not isinstance(value, dict) or not isinstance(value.get('device'), str) or not value['device']:
        raise ValueError('Select a Wi-Fi adapter first.')
    device = value['device']
    if action == 'wifi-power':
        if type(value.get('enabled')) is not bool:
            raise ValueError('Expected an on/off value')
    elif action == 'wifi-connect':
        ssid, security, passphrase = value.get('ssid'), value.get('security'), value.get('passphrase', '')
        if not isinstance(ssid, str) or not 1 <= len(ssid.encode()) <= 32 or any(ord(c) < 32 for c in ssid):
            raise ValueError('Select a valid network name.')
        if security not in ('open', 'psk', '8021x'):
            raise ValueError('This network security type is not supported.')
        if not isinstance(passphrase, str) or (passphrase and (security != 'psk' or not 8 <= len(passphrase.encode()) <= 63
                                                              or any(ord(c) < 32 or ord(c) == 127 for c in passphrase))):
            raise ValueError('Wi-Fi passwords must contain 8–63 characters.')
    elif action not in ('wifi-scan', 'wifi-disconnect'):
        raise ValueError('Unknown Wi-Fi action')
    if device not in [item['id'] for item in devices()]:
        raise ValueError('This Wi-Fi adapter is no longer available.')
    if action == 'wifi-power':
        # NetworkManager's software Wi-Fi switch applies to every adapter.
        run('radio', 'wifi', 'on' if value['enabled'] else 'off')
    elif action == 'wifi-scan':
        # `wifi rescan` only queues a scan. Keep the UI busy until nmcli has
        # fresh results, before desktop-controls reads the AP cache again.
        run('--wait', '20', '-f', 'SSID', 'device', 'wifi', 'list',
            'ifname', device, '--rescan', 'yes', timeout=25)
    elif action == 'wifi-disconnect':
        run('device', 'disconnect', device)
    else:
        connect(device, ssid, security, passphrase)
