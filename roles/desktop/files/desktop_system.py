"""Unprivileged adapters for timedate1, installed XKB data and Hyprland."""
import ctypes
import ctypes.util
from functools import lru_cache
import json
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from zoneinfo import available_timezones

TIME_SERVICE = ['org.freedesktop.timedate1', '/org/freedesktop/timedate1', 'org.freedesktop.timedate1']
MAX_LAYOUTS = 4  # Compatible with the compositor's XKB v1 keymaps.
INPUT_MARKER = 'local settings_input = root .. "/settings-input.lua"'


def command(arguments, timeout=5, **kwargs):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'The system command failed.')
    return result.stdout


def timezone_name():
    # timedate1 owns this link. Reading it also works during early session startup
    # without activating a system service or depending on the invoking process TZ.
    localtime = Path('/etc/localtime')
    try:
        target = localtime.readlink()
        target = Path(os.path.abspath(localtime.parent / target))
        return str(target.relative_to('/usr/share/zoneinfo'))
    except (OSError, ValueError):
        try:
            result = json.loads(command(['busctl', '--system', '--json=short', '--timeout=2',
                'get-property', *TIME_SERVICE, 'Timezone']))
            return result['data'][0]
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError):
            return 'Etc/UTC'


@lru_cache(maxsize=1)
def timezone_catalog():
    try:
        result = json.loads(command(['busctl', '--system', '--json=short', '--timeout=2',
            'call', *TIME_SERVICE, 'ListTimezones']))
        zones = result['data'][0]
        if not isinstance(zones, list) or not all(isinstance(zone, str) for zone in zones):
            raise ValueError('Invalid timezone catalog')
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError):
        zones = available_timezones()
    return sorted(zone for zone in zones if zone != 'localtime' and not zone.startswith(('posix/', 'right/')))


def set_timezone(zone, interactive=True):
    command(['busctl', '--system', '--allow-interactive-authorization=' + ('yes' if interactive else 'no'),
             '--timeout=120', 'call', *TIME_SERVICE, 'SetTimezone', 'sb', zone,
             'true' if interactive else 'false'], timeout=125)
    if timezone_name() != zone:
        raise RuntimeError('The timezone service did not retain the selected timezone.')


@lru_cache(maxsize=1)
def keyboard_catalog():
    root = ET.parse('/usr/share/X11/xkb/rules/evdev.xml').getroot()
    layouts = []
    for layout in root.findall('layoutList/layout'):
        code = layout.findtext('configItem/name')
        if not code:
            continue
        variants = [{'id': '', 'name': 'Default'}]
        for variant in layout.findall('variantList/variant'):
            name = variant.findtext('configItem/name')
            if name:
                variants.append({'id': name, 'name': variant.findtext('configItem/description') or name})
        layouts.append({'id': code, 'name': layout.findtext('configItem/description') or code, 'variants': variants})
    return sorted(layouts, key=lambda item: item['name'].casefold())


def layout_names(layouts, preferences):
    """Compile the exact ordered pairs; return compositor/XKB event names."""
    library = ctypes.CDLL(ctypes.util.find_library('xkbcommon'))
    class Names(ctypes.Structure):
        _fields_ = [(name, ctypes.c_char_p) for name in ('rules', 'model', 'layout', 'variant', 'options')]
    library.xkb_context_new.argtypes = [ctypes.c_int]
    library.xkb_context_new.restype = ctypes.c_void_p
    library.xkb_context_unref.argtypes = [ctypes.c_void_p]
    library.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(Names), ctypes.c_int]
    library.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    library.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
    library.xkb_keymap_num_layouts.argtypes = [ctypes.c_void_p]
    library.xkb_keymap_num_layouts.restype = ctypes.c_uint32
    library.xkb_keymap_layout_get_name.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    library.xkb_keymap_layout_get_name.restype = ctypes.c_char_p
    context = library.xkb_context_new(0)
    if not context:
        raise RuntimeError('Cannot initialize the keyboard compiler.')
    try:
        def encoded(value): return value.encode() if value else None
        names = Names(encoded(preferences.get('keyboardRules', '')), encoded(preferences.get('keyboardModel', '')),
            ','.join(item['layout'] for item in layouts).encode(),
            ','.join(item['variant'] for item in layouts).encode(), encoded(preferences.get('keyboardOptions', '')))
        keymap = library.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
        if not keymap:
            raise RuntimeError('The installed keyboard compiler rejected these layouts and variants.')
        try:
            count = library.xkb_keymap_num_layouts(keymap)
            if count != len(layouts):
                raise RuntimeError('The keyboard compiler changed the requested layout count.')
            return [library.xkb_keymap_layout_get_name(keymap, index).decode() for index in range(count)]
        finally:
            library.xkb_keymap_unref(keymap)
    finally:
        library.xkb_context_unref(context)


def in_session():
    signature = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    return bool(signature and (Path(os.environ.get('XDG_RUNTIME_DIR', '/nonexistent')) / 'hypr' / signature / '.socket.sock').is_socket())


def observe_keyboard():
    if not in_session():
        return None
    def option(name):
        value = json.loads(command(['hyprctl', '-j', 'getoption', 'input:' + name]))
        text = value.get('str', value.get('value', ''))
        return '' if text == '[[EMPTY]]' else text
    devices = json.loads(command(['hyprctl', '-j', 'devices']))
    return {'layout': option('kb_layout'), 'variant': option('kb_variant'), 'file': option('kb_file'),
            'keyboards': devices.get('keyboards', [])}


def input_text(layouts):
    if layouts is None:
        return '-- Generated by desktop-settings; managed input defaults are in use.\n'
    return '-- Generated by desktop-settings.\nhl.config({input={kb_layout=' + json.dumps(
        ','.join(item['layout'] for item in layouts)) + ',kb_variant=' + json.dumps(
        ','.join(item['variant'] for item in layouts)) + '}})\n'


def validate_input(root, content):
    source = (root / 'hyprland.lua').read_text()
    if source.count(INPUT_MARKER) != 1:
        raise RuntimeError('Reapply the desktop profile before changing keyboard layouts.')
    with tempfile.TemporaryDirectory(prefix='.input-validation-', dir=root) as folder:
        path = Path(folder)
        (path / 'settings-input.lua').write_text(content)
        candidate = path / 'hyprland.lua'
        candidate.write_text(source.replace(INPUT_MARKER, 'local settings_input = ' + json.dumps(str(path / 'settings-input.lua'))))
        command([str(root / 'bin/validate-config'), str(candidate)], timeout=20)


def reload_keyboard(layouts, previous=None):
    if not in_session():
        return
    command(['hyprctl', 'reload'])
    error = command(['hyprctl', 'configerrors']).strip()
    if error:
        raise RuntimeError('The compositor rejected the configuration: ' + error)
    actual = observe_keyboard()
    expected_layout = ','.join(item['layout'] for item in layouts)
    expected_variant = ','.join(item['variant'] for item in layouts)
    def variants(value):
        return (value.split(',') + [''] * len(layouts))[:len(layouts)]
    if actual['file'] or actual['layout'] != expected_layout or variants(actual['variant']) != variants(expected_variant):
        raise RuntimeError('Personal input configuration overrides these layouts. Review overrides.lua or a custom keymap.')
    for keyboard in actual['keyboards']:
        if (keyboard.get('layout', expected_layout) != expected_layout
                or variants(keyboard.get('variant', expected_variant)) != variants(expected_variant)):
            raise RuntimeError('A keyboard-specific configuration overrides these layouts. Review its device settings.')
    if previous:
        old_layouts = previous['layout'].split(',')
        old_variants = previous['variant'].split(',')
        pairs = [{'layout': layout, 'variant': old_variants[index] if index < len(old_variants) else ''}
                 for index, layout in enumerate(old_layouts)]
        old_names = layout_names(pairs, {})
        present = {keyboard['name'] for keyboard in actual['keyboards']}
        for keyboard in previous['keyboards']:
            if keyboard['name'] not in present:
                continue
            index = keyboard.get('active_layout_index')
            if index is None and keyboard.get('active_keymap') in old_names:
                index = old_names.index(keyboard['active_keymap'])
            if isinstance(index, int) and 0 <= index < len(pairs) and pairs[index] in layouts:
                command(['hyprctl', 'switchxkblayout', keyboard['name'], str(layouts.index(pairs[index]))])


def monitors():
    return json.loads(command(['hyprctl', '-j', 'monitors'])) if in_session() else []
