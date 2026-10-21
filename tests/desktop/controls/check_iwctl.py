import os
import sys
from pathlib import Path
import threading
from gi.repository import Gio, GLib

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'roles/desktop/files'))
import desktop_wifi

os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = os.environ['DBUS_SESSION_BUS_ADDRESS']
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
              GLib.Variant('(su)', ('net.connman.iwd', 0)), GLib.VariantType.new('(u)'), 0, -1, None)
device = '/net/connman/iwd/0/1'
network = device + '/486f6d65_psk'
agent = None
received = []
expected = ''
objects = {
    '/net/connman/iwd': {'net.connman.iwd.AgentManager': {}},
    device: {
        'net.connman.iwd.Device': {'Name': GLib.Variant('s', 'wlan0'), 'Address': GLib.Variant('s', 'aa:bb:cc:dd:ee:ff'),
            'Powered': GLib.Variant('b', True), 'Mode': GLib.Variant('s', 'station'), 'Adapter': GLib.Variant('o', '/net/connman/iwd/0')},
        'net.connman.iwd.Station': {'State': GLib.Variant('s', 'disconnected'), 'Scanning': GLib.Variant('b', False)}},
    network: {'net.connman.iwd.Network': {'Name': GLib.Variant('s', 'Home'), 'Type': GLib.Variant('s', 'psk'),
        'Device': GLib.Variant('o', device), 'Connected': GLib.Variant('b', False)}}}

def method(connection, sender, path, interface, name, parameters, invocation):
    global agent
    if name == 'GetManagedObjects':
        invocation.return_value(GLib.Variant('(a{oa{sa{sv}}})', (objects,)))
    elif name == 'RegisterAgent':
        agent = (sender, parameters.unpack()[0])
        invocation.return_value(None)
    elif name == 'UnregisterAgent':
        invocation.return_value(None)
    elif name == 'Connect':
        def replied(connection, result, _):
            try:
                secret = connection.call_finish(result).unpack()[0]
                received.append(secret)
                if secret == expected: invocation.return_value(None)
                else: invocation.return_dbus_error('net.connman.iwd.Error.Failed', 'Incorrect test password')
            except Exception as error:
                invocation.return_dbus_error('net.connman.iwd.Error.Failed', str(error))
        connection.call(agent[0], agent[1], 'net.connman.iwd.Agent', 'RequestPassphrase', GLib.Variant('(o)', (network,)),
                        GLib.VariantType.new('(s)'), 0, 5000, None, replied, None)
    else:
        invocation.return_dbus_error('net.connman.iwd.Error.NotSupported', name)

def prop(connection, sender, path, interface, name):
    return objects[path][interface][name]

xml = '<node><interface name="org.freedesktop.DBus.ObjectManager"><method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method></interface></node>'
bus.register_object('/', Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, None, None)
for path, interfaces in objects.items():
    for interface, props in interfaces.items():
        members = ''.join(f'<property name="{name}" type="{value.get_type_string()}" access="read"/>' for name, value in props.items())
        if interface.endswith('AgentManager'):
            members += ''.join(f'<method name="{name}"><arg type="o" direction="in"/></method>' for name in ('RegisterAgent', 'UnregisterAgent'))
        if interface.endswith('Network'): members += '<method name="Connect"/>'
        xml = f'<node><interface name="{interface}">{members}</interface></node>'
        bus.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, prop, None)
loop = GLib.MainLoop()
thread = threading.Thread(target=loop.run, daemon=True)
thread.start()
try:
    for expected in ['test passphrase', '********', 'quote " and $()', 'áéîø test']:
        desktop_wifi.connect('wlan0', 'Home', 'psk', expected)
        assert received[-1] == expected, 'iwctl did not send the complete password'
    try:
        desktop_wifi.connect('wlan0', 'Home', 'psk', 'incorrect password')
    except ValueError as error:
        assert 'incorrect password' not in str(error), 'Connection errors exposed credentials'
    else:
        raise AssertionError('Incorrect password was accepted')
    print('REAL_IWCTL_PASSWORD_PASSED')
finally:
    loop.quit()
