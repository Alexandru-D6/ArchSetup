"""Exercise the actual helper against a private BlueZ service, without hardware."""
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[3]
ADAPTER = 'org.bluez.Adapter1'
DEVICE = 'org.bluez.Device1'
HCI = '/org/bluez/hci0'
KEYBOARD = HCI + '/dev_AA_BB_CC_DD_EE_01'
HEADPHONES = HCI + '/dev_AA_BB_CC_DD_EE_02'
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
              GLib.Variant('(su)', ('org.bluez', 0)), None, 0, -1, None)
objects = {
    '/org/bluez': {'org.bluez.AgentManager1': {}},
    HCI: {ADAPTER: {'Alias': GLib.Variant('s', 'Laptop'), 'Address': GLib.Variant('s', '00:11:22:33:44:55'),
                   'Powered': GLib.Variant('b', True), 'Discovering': GLib.Variant('b', False)}},
    '/org/bluez/hci1': {ADAPTER: {'Alias': GLib.Variant('s', 'USB'), 'Powered': GLib.Variant('b', True)}},
}
for path, name, paired in [(KEYBOARD, 'Keyboard <test>', False), (HEADPHONES, 'Headphones', True)]:
    objects[path] = {DEVICE: {'Adapter': GLib.Variant('o', HCI), 'Alias': GLib.Variant('s', name),
                            'Address': GLib.Variant('s', 'AA:BB:CC:DD:EE:' + ('01' if path == KEYBOARD else '02')),
                            'Paired': GLib.Variant('b', paired), 'Connected': GLib.Variant('b', paired),
                            'Trusted': GLib.Variant('b', paired)}}
objects[HEADPHONES]['org.bluez.Battery1'] = {'Percentage': GLib.Variant('y', 80)}
agent = None
mode = 'confirm'
pair_calls = 0
scan_starts = 0
scan_stops = 0
fail_connect = False
received = []


def change(path, interface, name, value):
    objects[path][interface][name] = value
    bus.emit_signal(None, path, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                    GLib.Variant('(sa{sv}as)', (interface, {name: value}, [])))


def method(connection, sender, path, interface, name, parameters, invocation):
    global agent, pair_calls, scan_starts, scan_stops
    args = parameters.unpack()
    if name == 'GetManagedObjects':
        invocation.return_value(GLib.Variant('(a{oa{sa{sv}}})', (objects,)))
    elif name == 'RegisterAgent':
        assert args[1] == 'KeyboardDisplay'
        agent = (sender, args[0]); invocation.return_value(None)
    elif name in ('StartDiscovery', 'StopDiscovery'):
        scan_starts += name == 'StartDiscovery'
        scan_stops += name == 'StopDiscovery'
        change(path, ADAPTER, 'Discovering', GLib.Variant('b', name == 'StartDiscovery'))
        invocation.return_value(None)
    elif name == 'Pair':
        pair_calls += 1
        prompts = {'confirm': ('RequestConfirmation', '(ou)', (path, 123)),
                   'pin': ('RequestPinCode', '(o)', (path,)),
                   'passkey': ('RequestPasskey', '(o)', (path,)),
                   'display': ('DisplayPasskey', '(ouq)', (path, 123, 2)),
                   'authorize': ('RequestAuthorization', '(o)', (path,))}
        prompt, signature, values = prompts[mode]
        def replied(connection, result, _):
            try:
                value = connection.call_finish(result).unpack()
                received.append((mode, value))
                change(path, DEVICE, 'Paired', GLib.Variant('b', True))
                invocation.return_value(None)
            except GLib.Error:
                invocation.return_dbus_error('org.bluez.Error.AuthenticationCanceled', 'Pairing canceled')
        connection.call(agent[0], agent[1], 'org.bluez.Agent1', prompt, GLib.Variant(signature, values),
                        None, 0, 5000, None, replied, None)
    elif name in ('Connect', 'Disconnect'):
        if name == 'Connect' and fail_connect:
            invocation.return_dbus_error('org.bluez.Error.Failed', 'Device unavailable')
        else:
            change(path, DEVICE, 'Connected', GLib.Variant('b', name == 'Connect'))
            invocation.return_value(None)
    elif name == 'CancelPairing':
        invocation.return_value(None)
    elif name == 'RemoveDevice':
        interfaces = list(objects.pop(args[0]))
        bus.emit_signal(None, '/', 'org.freedesktop.DBus.ObjectManager', 'InterfacesRemoved', GLib.Variant('(oas)', (args[0], interfaces)))
        invocation.return_value(None)
    else:
        invocation.return_dbus_error('org.bluez.Error.NotSupported', name)


def get_property(connection, sender, path, interface, name):
    return objects[path][interface][name]


def set_property(connection, sender, path, interface, name, value):
    change(path, interface, name, value)
    return True


xml = '<node><interface name="org.freedesktop.DBus.ObjectManager"><method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method></interface></node>'
bus.register_object('/', Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, None, None)
for path, interfaces in objects.items():
    for interface, props in interfaces.items():
        members = ''.join(f'<property name="{name}" type="{value.get_type_string()}" access="readwrite"/>' for name, value in props.items())
        if interface == 'org.bluez.AgentManager1':
            members += '<method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>'
        elif interface == ADAPTER:
            members += '<method name="StartDiscovery"/><method name="StopDiscovery"/><method name="RemoveDevice"><arg type="o" direction="in"/></method>'
        elif interface == DEVICE:
            members += '<method name="Pair"/><method name="CancelPairing"/><method name="Connect"/><method name="Disconnect"/>'
        xml = f'<node><interface name="{interface}">{members}</interface></node>'
        bus.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, get_property, set_property)
loop = GLib.MainLoop()
threading.Thread(target=loop.run, daemon=True).start()
environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'])
worker = subprocess.Popen([sys.executable, str(ROOT / 'roles/desktop/files/desktop-bluetooth')],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment)
packets = queue.Queue()
history = []
def collect():
    for line in worker.stdout:
        packets.put(json.loads(line))
threading.Thread(target=collect, daemon=True).start()


def wait_for(predicate, description):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            packet = packets.get(timeout=0.1)
        except queue.Empty:
            continue
        history.append(packet)
        if predicate(packet):
            return packet
    raise AssertionError(description + ': ' + repr(history[-3:]))


def send(action, value=None):
    # Drain earlier status events so assertions refer to this request.
    while not packets.empty():
        history.append(packets.get())
    worker.stdin.write(json.dumps(dict(action=action, value=value)) + '\n')
    worker.stdin.flush()


def device(packet, path):
    return next((item for item in packet['state']['bluetoothDevices'] if item['id'] == path), {})


try:
    initial = wait_for(lambda p: p['state']['bluetoothAvailable'], 'initial state')
    assert initial['state']['bluetoothDevices'][0]['id'] == HEADPHONES
    assert device(initial, HEADPHONES)['battery'] == 80
    send('scan', True)
    wait_for(lambda p: p['state']['bluetoothScanning'] and scan_starts == 1, 'start scanning')
    send('select', '/org/bluez/hci1')
    wait_for(lambda p: p['state']['bluetoothAdapter'].endswith('hci1') and not p['state']['bluetoothScanning'] and scan_stops == 1, 'adapter switch stops scan')
    assert scan_stops == 1
    send('connect', KEYBOARD)
    wait_for(lambda p: 'no longer available' in p['error'], 'cross-adapter device rejection')
    send('select', HCI); wait_for(lambda p: p['state']['bluetoothAdapter'] == HCI, 'select laptop')
    send('power', False); wait_for(lambda p: not p['busy'] and not p['state']['bluetoothEnabled'], 'power off')
    send('power', True); wait_for(lambda p: not p['busy'] and p['state']['bluetoothEnabled'], 'power on')
    send('pair', KEYBOARD)
    prompt = wait_for(lambda p: p['prompt'] is not None, 'confirmation prompt')
    assert prompt['prompt']['code'] == '000123' and prompt['busy']
    send('respond', False)
    wait_for(lambda p: not p['busy'] and p['prompt'] is None, 'rejected pairing')
    assert not objects[KEYBOARD][DEVICE]['Paired'].unpack()
    for mode, answer in [('confirm', True), ('pin', 'A1 " B2'), ('passkey', '000123'), ('authorize', True), ('display', None)]:
        change(KEYBOARD, DEVICE, 'Paired', GLib.Variant('b', False))
        change(KEYBOARD, DEVICE, 'Connected', GLib.Variant('b', False))
        wait_for(lambda p: not device(p, KEYBOARD).get('paired') and not device(p, KEYBOARD).get('connected'), 'reset pairing')
        send('pair', KEYBOARD)
        if mode != 'display':
            wait_for(lambda p: p['prompt'] is not None, mode + ' prompt')
            if mode == 'passkey':
                send('respond', 'abc')
                wait_for(lambda p: p['prompt'] is not None and bool(p['error']), 'invalid passkey retains prompt')
            send('respond', answer)
        paired = wait_for(lambda p: not p['busy'] and device(p, KEYBOARD).get('connected'), 'pair and connect: ' + mode)
        assert not paired['error'] and device(paired, KEYBOARD)['trusted']
    assert ('pin', ('A1 " B2',)) in received and ('passkey', (123,)) in received
    assert any(p['prompt'] and p['prompt']['kind'] == 'display' and p['prompt']['code'] == '000123' for p in history)
    try:
        bus.call_sync(agent[0], agent[1], 'org.bluez.Agent1', 'RequestConfirmation',
                      GLib.Variant('(ou)', (HEADPHONES, 987654)), None, 0, 1000, None)
    except GLib.Error as error:
        assert 'Rejected' in str(error), str(error)
    else:
        raise AssertionError('Unrequested pairing was accepted')
    previous_pairs = pair_calls
    send('pair', KEYBOARD)
    wait_for(lambda p: p['busy'], 'saved device starts connection')
    wait_for(lambda p: not p['busy'] and device(p, KEYBOARD).get('connected'), 'saved device connect')
    assert pair_calls == previous_pairs, 'Saved pairing was overwritten'
    send('disconnect', KEYBOARD); wait_for(lambda p: not p['busy'] and not device(p, KEYBOARD).get('connected'), 'disconnect')
    fail_connect = True
    send('connect', KEYBOARD); wait_for(lambda p: not p['busy'] and 'unavailable' in p['error'], 'connection failure')
    send('forget', KEYBOARD); wait_for(lambda p: not p['busy'] and not device(p, KEYBOARD), 'forget')
    send('scan', True); wait_for(lambda p: p['state']['bluetoothScanning'], 'restart discovery')
    worker.stdin.close()
    worker.wait(timeout=5)
    assert worker.returncode == 0, worker.stderr.read()
    assert scan_stops >= 2, 'Discovery was not stopped on exit'
    print('ARCHSETUP_BLUETOOTH_PASSED')
finally:
    if worker.poll() is None:
        worker.kill(); worker.wait()
    loop.quit()
