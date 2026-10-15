# Desktop shortcuts

The managed JSON map is the source of both Hyprland bindings and Super+/ help.
This list covers the supported non-AI shortcuts from the reference desktop, with
physical-key/keypad aliases. Existing ArchSetup shortcuts remain compatible.

Super+D stays the launcher; maximize uses Super+Alt+D. Super+Equal stays the
calculator; zoom-in uses Ctrl+Super+Equal. Super+Shift+S selects a region and copies
the screenshot to the clipboard; Ctrl+Super+Shift+S and Print also select a region.
Super+Alt+S moves a window to scratch. Super+Space remains reserved for
keyboard-layout switching.

Super alone toggles the launcher on release: press it again to close the launcher.
Super+D uses the same toggle. Repeating clipboard, emoji, calculator, wallpaper
picker keys dismisses that menu; choosing a different launcher menu replaces the
current one. Overview, settings, utilities, media, shortcut help and the on-screen
keyboard also toggle with their opening shortcuts.

Super+/ opens a centered shortcut window with category headings and keycap labels.
Its search field receives keyboard focus immediately. Search matches keys, action
descriptions and categories without regard to case; multiple words must all match.
Only matching shortcut rows and their categories remain in the window. Clear or
Ctrl+A followed by Backspace restores the list; Ctrl+F returns focus to search.
Escape, Close, a click outside the window or Super+/ dismisses it. Reopening shows
the complete list. The window reads the same managed map as the compositor and
refreshes when that file changes.

Utilities replace the upstream AI
sidebar. Ctrl+Super+P cycles top/bottom placement of the existing bar; it does not
load a separate upstream shell. AI summaries, cloud screen translation, Google
Lens, developer test notifications and upstream-only workspace grouping helpers
are omitted. Screenshot/OCR and recording shortcuts never start while locked.
Media/brightness keys and Super+Shift+L (suspend) remain available while locked.
Locking stops an active recording. Recordings stop and save when the same recording
shortcut is pressed again, or Ctrl+Super+Shift+R is pressed.

Screenshot files are saved under the configured Pictures directory's Screenshots
folder. Recordings use the configured Videos directory plus Recordings; unconfigured
accounts fall back to ~/Pictures/Screenshots and ~/Videos/Recordings. OCR is local and copies its
text to the clipboard; English data is installed by default. Add language-data
packages before changing archsetup_desktop_ocr_language. Code/text/office apps use
configurable desktop IDs, with Geany, Mousepad and LibreOffice defaults. The task
manager runs btop in Kitty. No third-party assets are bundled with this map.

Resize tiled or floating windows by dragging a border or the gap between tiles
with the left mouse button, or by holding Super and dragging with the right mouse
button inside a window. Super+Alt+Left/Right shrinks/grows the focused window's
width; Super+Alt+Up/Down shrinks/grows its height. Each press adjusts by 40 pixels;
hold the arrow key to keep resizing. Tiles adjust their shared splits, so
neighbouring windows share the remaining space. A single tile fills its workspace.

Window pin and exact-size controls apply to floating windows. VM passthrough
(Super+Alt+F1) suspends normal desktop bindings until the same key is pressed again;
this escape binding is universal within the compositor's submaps. The on-screen
keyboard sends keys to the focused application and does not grab keyboard focus.

Bindings use the [native Hyprland API](https://wiki.hypr.land/configuring/core/dispatchers/).
Recording uses [wf-recorder](https://github.com/ammen99/wf-recorder/wiki), with output
monitor audio through its pulse backend for the audio variant. Shell controls are implemented by the original
Quickshell configuration, not upstream code.

## Applications

| Shortcut | Action |
| --- | --- |
| Super + Return | Terminal |
| Super + W | Browser |
| Super + E | Files |
| Super + D | Launcher |
| Super + equal | Calculator |
| Super + T | Terminal |
| Ctrl + Alt + T | Terminal |
| Super + C | Code editor (VSCodium by default) |
| Super + X | Text editor |
| Ctrl + Super + Shift + Alt + W | Office |
| Ctrl + Super + V | Volume mixer |
| Super + I | Configuration window |
| Ctrl + Shift + Escape | Task manager |
| Super + Super_L | Launcher on left Super release |
| Super + Super_R | Launcher on right Super release |

## Shell

| Shortcut | Action |
| --- | --- |
| Super + A | Utilities |
| Super + B | Utilities |
| Super + O | Utilities |
| Super + Alt + A | Detach utilities |
| Super + K | On-screen keyboard |
| Super + M | Media controls |
| Super + G | Show / hide desktop clock |
| Super + J | Show / hide taskbar |
| Ctrl + Super + P | Top / bottom taskbar |
| Ctrl + Super + R | Restart this desktop shell |
| Ctrl + Super + T | Choose wallpaper |
| Ctrl + Super + Alt + T | Random personal wallpaper |
| Ctrl + Super + Shift + D | Light / dark theme |
| Super + Shift + Alt + Slash | Shortcut help |
| Ctrl + Super + Alt + Slash | Edit personal bindings |

## Utilities

| Shortcut | Action |
| --- | --- |
| Super + Tab | Window overview |
| Super + Slash | Shortcut help |
| Super + V | Clipboard |
| Super + Period | Emoji |
| Super + N | Notifications |
| Super + Comma | Quick settings |
| Super + L | Lock |
| Super + Shift + Escape | Session menu |
| Print | Region screenshot |
| Shift + Print | Full screenshot |
| Super + Shift + C | Color picker |
| Super + Print | Focused-monitor screenshot |
| Ctrl + Print | Save and copy focused-monitor screenshot |
| Ctrl + Shift + Print | Save and copy screen snip |
| Super + Shift + S | Screen snip |
| Ctrl + Super + Shift + S | Screen snip |
| Super + Shift + X | Read screen text into clipboard |
| Super + Shift + R | Start / stop region recording |
| Super + Alt + R | Start / stop region recording |
| Ctrl + Alt + R | Start / stop monitor recording |
| Super + Shift + Alt + R | Start / stop monitor recording with output audio |
| Ctrl + Super + Shift + R | Stop recording |

## Screen

| Shortcut | Action |
| --- | --- |
| Super + Minus | Zoom out |
| Ctrl + Super + Equal | Zoom in |
| Super + code:82 | Zoom out (keypad) |
| Super + code:86 | Zoom in (keypad) |
| Ctrl + Super + 0 | Reset zoom |

## Media

| Shortcut | Action |
| --- | --- |
| XF86AudioRaiseVolume | AudioRaiseVolume |
| XF86AudioLowerVolume | AudioLowerVolume |
| XF86AudioMute | AudioMute |
| XF86AudioMicMute | AudioMicMute |
| XF86MonBrightnessUp | MonBrightnessUp |
| XF86MonBrightnessDown | MonBrightnessDown |
| XF86AudioPlay | AudioPlay |
| XF86AudioNext | AudioNext |
| XF86AudioPrev | AudioPrev |
| Super + Shift + N | Next track |
| Super + Shift + B | Previous track |
| Super + Shift + P | Play / pause |
| Super + Shift + M | Speaker mute |
| Super + Alt + M | Microphone mute |
| XF86AudioPause | Play / pause |
| Alt + XF86AudioMute | Microphone mute |
| Super + Shift + Alt + mouse:275 | Previous track (mouse) |
| Super + Shift + Alt + mouse:276 | Next track (mouse) |

## Windows

| Shortcut | Action |
| --- | --- |
| Super + Q | Close window |
| Super + F | Fullscreen |
| Super + Shift + F | Floating |
| Super + left | Focus left |
| Super + Shift + left | Move left |
| Super + right | Focus right |
| Super + Shift + right | Move right |
| Super + up | Focus up |
| Super + Shift + up | Move up |
| Super + down | Focus down |
| Super + Shift + down | Move down |
| Super + Alt + left | Shrink window width |
| Super + Alt + right | Grow window width |
| Super + Alt + up | Shrink window height |
| Super + Alt + down | Grow window height |
| Super + mouse:272 | Drag window |
| Super + mouse:273 | Resize window |
| Alt + F4 | Close window |
| Super + Alt + D | Maximize window |
| Super + Alt + Space | Float / tile window |
| Super + Alt + F | Client-only fullscreen |
| Super + P | Pin floating window |
| Ctrl + Super + Backslash | Resize window to 640 × 480 |
| Super + Semicolon | Decrease split ratio |
| Super + Apostrophe | Increase split ratio |
| Super + BracketLeft | Focus left |
| Super + BracketRight | Focus right |
| Super + mouse:274 | Drag window (middle button) |
| Super + Shift + Alt + Q | Select window to force-close |

## Workspaces

All window moves switch to the destination workspace and keep the moved window
focused, including number-row/keypad aliases, relative moves and scratch.

| Shortcut | Action |
| --- | --- |
| Super + S | Scratch workspace |
| Super + 1 | Workspace 1 |
| Super + Shift + 1 | Move to workspace 1 and follow |
| Super + 2 | Workspace 2 |
| Super + Shift + 2 | Move to workspace 2 and follow |
| Super + 3 | Workspace 3 |
| Super + Shift + 3 | Move to workspace 3 and follow |
| Super + 4 | Workspace 4 |
| Super + Shift + 4 | Move to workspace 4 and follow |
| Super + 5 | Workspace 5 |
| Super + Shift + 5 | Move to workspace 5 and follow |
| Super + 6 | Workspace 6 |
| Super + Shift + 6 | Move to workspace 6 and follow |
| Super + 7 | Workspace 7 |
| Super + Shift + 7 | Move to workspace 7 and follow |
| Super + 8 | Workspace 8 |
| Super + Shift + 8 | Move to workspace 8 and follow |
| Super + 9 | Workspace 9 |
| Super + Shift + 9 | Move to workspace 9 and follow |
| Super + 0 | Workspace 10 |
| Super + Shift + 0 | Move to workspace 10 and follow |
| Super + Alt + 1 | Move to workspace 1 and follow |
| Super + code:10 | Workspace 1 (physical key) |
| Super + Alt + code:10 | Move to workspace 1 and follow (physical key) |
| Super + Shift + code:10 | Move to workspace 1 and follow (physical key) |
| Super + code:87 | Workspace 1 (physical key) |
| Super + Alt + code:87 | Move to workspace 1 and follow (physical key) |
| Super + Shift + code:87 | Move to workspace 1 and follow (physical key) |
| Super + Alt + 2 | Move to workspace 2 and follow |
| Super + code:11 | Workspace 2 (physical key) |
| Super + Alt + code:11 | Move to workspace 2 and follow (physical key) |
| Super + Shift + code:11 | Move to workspace 2 and follow (physical key) |
| Super + code:88 | Workspace 2 (physical key) |
| Super + Alt + code:88 | Move to workspace 2 and follow (physical key) |
| Super + Shift + code:88 | Move to workspace 2 and follow (physical key) |
| Super + Alt + 3 | Move to workspace 3 and follow |
| Super + code:12 | Workspace 3 (physical key) |
| Super + Alt + code:12 | Move to workspace 3 and follow (physical key) |
| Super + Shift + code:12 | Move to workspace 3 and follow (physical key) |
| Super + code:89 | Workspace 3 (physical key) |
| Super + Alt + code:89 | Move to workspace 3 and follow (physical key) |
| Super + Shift + code:89 | Move to workspace 3 and follow (physical key) |
| Super + Alt + 4 | Move to workspace 4 and follow |
| Super + code:13 | Workspace 4 (physical key) |
| Super + Alt + code:13 | Move to workspace 4 and follow (physical key) |
| Super + Shift + code:13 | Move to workspace 4 and follow (physical key) |
| Super + code:83 | Workspace 4 (physical key) |
| Super + Alt + code:83 | Move to workspace 4 and follow (physical key) |
| Super + Shift + code:83 | Move to workspace 4 and follow (physical key) |
| Super + Alt + 5 | Move to workspace 5 and follow |
| Super + code:14 | Workspace 5 (physical key) |
| Super + Alt + code:14 | Move to workspace 5 and follow (physical key) |
| Super + Shift + code:14 | Move to workspace 5 and follow (physical key) |
| Super + code:84 | Workspace 5 (physical key) |
| Super + Alt + code:84 | Move to workspace 5 and follow (physical key) |
| Super + Shift + code:84 | Move to workspace 5 and follow (physical key) |
| Super + Alt + 6 | Move to workspace 6 and follow |
| Super + code:15 | Workspace 6 (physical key) |
| Super + Alt + code:15 | Move to workspace 6 and follow (physical key) |
| Super + Shift + code:15 | Move to workspace 6 and follow (physical key) |
| Super + code:85 | Workspace 6 (physical key) |
| Super + Alt + code:85 | Move to workspace 6 and follow (physical key) |
| Super + Shift + code:85 | Move to workspace 6 and follow (physical key) |
| Super + Alt + 7 | Move to workspace 7 and follow |
| Super + code:16 | Workspace 7 (physical key) |
| Super + Alt + code:16 | Move to workspace 7 and follow (physical key) |
| Super + Shift + code:16 | Move to workspace 7 and follow (physical key) |
| Super + code:79 | Workspace 7 (physical key) |
| Super + Alt + code:79 | Move to workspace 7 and follow (physical key) |
| Super + Shift + code:79 | Move to workspace 7 and follow (physical key) |
| Super + Alt + 8 | Move to workspace 8 and follow |
| Super + code:17 | Workspace 8 (physical key) |
| Super + Alt + code:17 | Move to workspace 8 and follow (physical key) |
| Super + Shift + code:17 | Move to workspace 8 and follow (physical key) |
| Super + code:80 | Workspace 8 (physical key) |
| Super + Alt + code:80 | Move to workspace 8 and follow (physical key) |
| Super + Shift + code:80 | Move to workspace 8 and follow (physical key) |
| Super + Alt + 9 | Move to workspace 9 and follow |
| Super + code:18 | Workspace 9 (physical key) |
| Super + Alt + code:18 | Move to workspace 9 and follow (physical key) |
| Super + Shift + code:18 | Move to workspace 9 and follow (physical key) |
| Super + code:81 | Workspace 9 (physical key) |
| Super + Alt + code:81 | Move to workspace 9 and follow (physical key) |
| Super + Shift + code:81 | Move to workspace 9 and follow (physical key) |
| Super + Alt + 0 | Move to workspace 10 and follow |
| Super + code:19 | Workspace 10 (physical key) |
| Super + Alt + code:19 | Move to workspace 10 and follow (physical key) |
| Super + Shift + code:19 | Move to workspace 10 and follow (physical key) |
| Super + code:90 | Workspace 10 (physical key) |
| Super + Alt + code:90 | Move to workspace 10 and follow (physical key) |
| Super + Shift + code:90 | Move to workspace 10 and follow (physical key) |
| Ctrl + Super + Left | Focus relative workspace r-1 |
| Ctrl + Super + Right | Focus relative workspace r+1 |
| Ctrl + Super + Alt + Left | Focus relative workspace m-1 |
| Ctrl + Super + Alt + Right | Focus relative workspace m+1 |
| Super + Page_Up | Focus relative workspace r-1 |
| Super + Page_Down | Focus relative workspace r+1 |
| Ctrl + Super + Page_Up | Focus relative workspace r-1 |
| Ctrl + Super + Page_Down | Focus relative workspace r+1 |
| Super + mouse_up | Focus relative workspace -1 |
| Super + mouse_down | Focus relative workspace +1 |
| Ctrl + Super + mouse_up | Focus relative workspace r-1 |
| Ctrl + Super + mouse_down | Focus relative workspace r+1 |
| Ctrl + Super + BracketLeft | Focus relative workspace -1 |
| Ctrl + Super + BracketRight | Focus relative workspace +1 |
| Ctrl + Super + Up | Focus relative workspace r-5 |
| Ctrl + Super + Down | Focus relative workspace r+5 |
| Super + Shift + mouse_up | Move window to relative workspace r-1 and follow |
| Super + Shift + mouse_down | Move window to relative workspace r+1 and follow |
| Super + Alt + mouse_up | Move window to relative workspace r-1 and follow |
| Super + Alt + mouse_down | Move window to relative workspace r+1 and follow |
| Super + Shift + Page_Up | Move window to relative workspace r-1 and follow |
| Super + Shift + Page_Down | Move window to relative workspace r+1 and follow |
| Super + Alt + Page_Up | Move window to relative workspace r-1 and follow |
| Super + Alt + Page_Down | Move window to relative workspace r+1 and follow |
| Ctrl + Super + Shift + Left | Move window to relative workspace r-1 and follow |
| Ctrl + Super + Shift + Right | Move window to relative workspace r+1 and follow |
| Ctrl + Super + S | Toggle scratch workspace |
| Super + mouse:275 | Toggle scratch workspace |
| Super + Alt + S | Move to scratch and follow |

## Session

| Shortcut | Action |
| --- | --- |
| Ctrl + Alt + Delete | Session menu |
| Super + Shift + L | Suspend |
| Ctrl + Shift + Alt + Super + Delete | Session menu with Shut down selected |

The session menu uses arrow keys or Tab to select an action and Enter/Space to
execute it. Click an icon to choose it directly. Escape or a background click
cancels without taking a power action.

## Virtual machines

| Shortcut | Action |
| --- | --- |
| Super + Alt + F1 | Toggle VM shortcut passthrough |

Total: **224 bindings**, including aliases.
