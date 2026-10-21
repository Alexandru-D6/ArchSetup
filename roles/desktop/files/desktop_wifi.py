"""Wi-Fi controls using iwctl, without shell evaluation or passwords in argv."""
import os
import pty
import re
import select
import shutil
import subprocess
import time


ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')


def clean(text):
    return ANSI.sub('', text).replace('\r', '')


def run(*args, timeout=8):
    try:
        result = subprocess.run(['iwctl', '--dont-ask', '--', *args],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=timeout, env=dict(os.environ, LC_ALL='C', TERM='dumb'))
    except subprocess.TimeoutExpired:
        raise ValueError('Wi-Fi did not respond. Check that iwd is running.') from None
    output = clean(result.stdout).strip()
    if result.returncode:
        raise ValueError(clean(result.stderr).strip() or output or 'Wi-Fi command failed.')
    return output


def devices():
    result = []
    for line in run('device', 'list').splitlines():
        match = re.fullmatch(r'\s*(\S+)\s+(?:[\da-fA-F]{2}:){5}[\da-fA-F]{2}\s+(on|off)\s+\S+\s+station\s*', line)
        if match:
            name, power = match.groups()
            result.append(dict(id=name, name=name, powered=power == 'on'))
    return result


def properties(output):
    result = {}
    for line in output.splitlines():
        # iwctl's show tables have a 12-character "Settable" column.
        parts = re.split(r'\s{2,}', line[12:].strip(), maxsplit=1)
        if len(parts) == 2:
            result[parts[0]] = parts[1].rstrip()
    return result


def networks(output):
    result = []
    for line in output.splitlines():
        # Read from the right so spaces, quotes and shell syntax in SSIDs survive.
        match = re.fullmatch(r'(.+?)\s{2,}(open|psk|8021x|wep(?: \(unsupported\))?)\s+(-?\d+)\s*', line[6:])
        if match:
            name, security, signal = match.groups()
            strength = int(signal)
            bars = 4 if strength >= -6000 else 3 if strength >= -6700 else 2 if strength >= -7500 else 1
            result.append(dict(ssid=name.rstrip(), security=security.split()[0],
                               signal=bars, connected='>' in line[:6]))
    return result


def known_networks(output):
    result = set()
    for line in output.splitlines():
        match = re.match(r'(.+?)\s{2,}(open|psk|8021x|wep)\s', line[2:])
        if match:
            result.add((match[1].rstrip(), match[2]))
    return result


def snapshot(device=''):
    state = dict(wifiAvailable=False, wifiEnabled=False, wifiName='', wifiDevice='',
                 wifiDevices=[], wifiNetworks=[], wifiState='', wifiScanning=False, wifiError='')
    if not shutil.which('iwctl'):
        state['wifiError'] = 'Install iwd to manage Wi-Fi here.'
        return state
    try:
        adapters = devices()
        state['wifiDevices'] = adapters
        if not adapters:
            state['wifiError'] = 'No Wi-Fi adapter is available in iwd.'
            return state
        adapter = next((item for item in adapters if item['id'] == device), adapters[0])
        device = adapter['id']
        state.update(wifiAvailable=True, wifiDevice=device, wifiEnabled=adapter['powered'])
        if not adapter['powered']:
            return state
        station = properties(run('station', device, 'show'))
        state.update(wifiName=station.get('Connected network', ''),
                     wifiState=station.get('State', ''), wifiScanning=station.get('Scanning') == 'yes')
        # iwctl's default bars encode weak stars using ANSI color, so request RSSI.
        found = networks(run('station', device, 'get-networks', 'rssi-dbms'))
        known = known_networks(run('known-networks', 'list'))
        for network in found:
            network['known'] = (network['ssid'], network['security']) in known
        state['wifiNetworks'] = found
    except (OSError, ValueError) as error:
        state['wifiError'] = str(error)
    return state


def connect(device, ssid, security, passphrase):
    if not passphrase:
        run('station', device, 'connect', ssid, security, timeout=45)
        return
    # iwctl's agent reads a masked readline prompt. Use a private terminal, wait
    # for that prompt, and send the secret through stdin, never argv or a file.
    master, slave = pty.openpty()
    try:
        # Let readline configure echo itself; disabling it beforehand makes
        # iwctl bypass the per-character masking callback and submit an empty key.
        with subprocess.Popen(['iwctl', '--', 'station', device, 'connect', ssid, security],
                              stdin=slave, stdout=slave, stderr=subprocess.STDOUT,
                              env=dict(os.environ, LC_ALL='C', TERM='xterm')) as process:
            output, sent, submitted = '', False, False
            deadline = time.monotonic() + 45
            try:
                while time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        chunk = os.read(master, 4096)
                        if not chunk:
                            break
                        output += chunk.decode('utf-8', errors='replace')
                        if not sent and 'Passphrase:' in clean(output):
                            os.write(master, passphrase.encode())
                            output = ''
                            sent = True
                        elif sent and not submitted and '*' * len(passphrase.encode()) in clean(output):
                            # Allow readline's masking callback to run before
                            # Enter. Sending a whole line at once bypasses it.
                            time.sleep(0.02)
                            os.write(master, b'\n')
                            submitted = True
                    if process.poll() is not None:
                        break
                else:
                    raise ValueError('Wi-Fi connection timed out. Check the password and try again.')
                if process.wait(timeout=1):
                    # readline output must never be returned; it may contain input.
                    raise ValueError('Could not connect. Check the password and try again.')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    finally:
        os.close(master)
        os.close(slave)


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
        run('device', device, 'set-property', 'Powered', 'on' if value['enabled'] else 'off')
    elif action == 'wifi-scan':
        run('station', device, 'scan')
    elif action == 'wifi-disconnect':
        run('station', device, 'disconnect')
    else:
        connect(device, ssid, security, passphrase)
