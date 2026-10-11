# Desktop validation — 2026-10-10

## Terminal startup tiling — 2026-10-11

Reproduced the second normally launched Kitty terminal entering maximized state
and covering the first in the VM. The native terminal window rule now tiles Kitty,
clears initial compositor/client fullscreen state and suppresses client
maximize/fullscreen requests. Fullscreen focus/retention defaults are explicit.

After apply/reload, six terminal windows shared the desktop with no overlapping
rectangles and zero compositor/client fullscreen state. Explicit Kitty
`--start-as maximized` and `--start-as fullscreen` requests were ignored. Manual
compositor maximize/fullscreen dispatchers still worked; opening another terminal
restored ordinary tiling. All 20 local tests and whitespace checks pass.
VM apply: `ok=39 changed=2 failed=0 skipped=19`; the two changes also include the
workspace-follow update below. No workstation configuration was modified.

## Follow window moves — 2026-10-11

All 72 workspace-move bindings now explicitly follow the window, including
numbered/physical/keypad, relative and scratch moves. The Super+Alt variants follow
as well. All 20 local tests pass, including real compositor configuration parsing.
An audit confirms every workspace-move binding has `follow=true` and matches the
shortcut reference; whitespace checks pass. This change is included in the VM
deployment above. No workstation deployment was made. The silent-move VM result
below predates this change.

## Expanded shortcuts — 2026-10-11

The shortcut map now contains 224 entries including physical-key/keypad aliases.
All entries are registered in the VM. Existing launcher/calculator/scratch keys
are retained, with documented alternatives for upstream conflicts. See the
[complete key reference](desktop-shortcuts.md) for coverage and exclusions.

20 local tests pass, covering native compositor parsing, canonical key uniqueness,
reserved layout switching, capture cancellation, local OCR stdin/clipboard data
flow, recording PID ownership/start-time checks, direct power commands and prior
desktop regressions. Playbook syntax and whitespace checks pass.

VM acceptance exercised modifier-only search without opening it after chords,
utilities/detachment, on-screen keyboard key delivery, editor/office/task-manager
launchers, relative workspace focus, silent workspace movement, floating/exact
640×480 sizing/pinning, zoom/reset, shell restart, bar/widget/placement toggles and
VM-submap entry/escape. Screenshot-save created a PNG; local OCR copied the terminal
fixture to the clipboard using a deterministic region selector (headless VM mouse
selection was unreliable). Video recording start/stop produced a playable H.264
file; an original tone on a VM null sink produced H.264 + AAC for the audio variant.
Physical audio/input and multi-monitor keys remain subject to hardware acceptance.

Runtime testing caught and fixed QML component import, empty VM-submap registration,
recorder backend naming, media-directory fallback and clipboard daemon stream
ownership. Keep-awake is attached to the persistent background surface so taskbar
hiding does not remove it. Final repeated apply: `ok=39 changed=0 failed=0 skipped=19`;
read-only verification: `ok=18 changed=0 failed=0 skipped=2`.

## Asset removal and direct power actions — 2026-10-11

Removed bundled third-party wallpaper/font files and their accompanying texts.
The default background is now an original generated gradient, and typography
comes from installed system fonts. Updated all preview screenshots to remove
depictions of the old copied wallpaper. The migration removed the prior deployed
copies in the test VM; explicit path checks confirmed they are absent.

Shutdown, reboot, suspend and logout now execute directly without the extra
confirmation picker. Mocked command checks cover all four actions without taking
power actions on the workstation. The updated poweroff helper also successfully
requested shutdown of the disposable VM without opening a picker.

17 local tests pass, including original background/system-font clock rendering
and preservation of a personal wallpaper. Repeat VM apply:
`ok=39 changed=0 failed=0 skipped=19`; verify:
`ok=18 changed=0 failed=0 skipped=2`. The new default lock screen boots and unlocks;
the original gradient, system-font text, clock and overview render correctly.
Earlier results below are historical where their asset/power behavior differs.

## Default ii appearance — 2026-10-11

The general desktop appearance follows end-4's default ii layout, using an
original generated gradient, system fonts, 40-pixel top bar, grouped workspace/clock
controls, 18-pixel window corners, thin borders and muted Material colors.
Native Hyprlock reproduces the centered scalloped clock and bottom password
toolbar, with blurred wallpaper, user/layout labels and Caps Lock status.
The original animations-disabled setting and PAM/keyring integration remain.

Validated in the graphical QEMU guest:

- Greetd initial session boots directly into the themed Hyprlock screen.
- Incorrect password rejected; correct password unlocks. GNOME Keyring's PAM log
  reports `unlocked login keyring` after the successful password entry.
- Quickshell loads/reloads with no QML errors; expected portal registration
  warnings remain. Monitor reservation is `[0, 40, 0, 0]` for the top bar.
- Clock image, default background, system font, task buttons, rounded Kitty
  window and live overview preview render. Fixed light-mode lock-label contrast
  and workspace 10 text clipping after screenshot inspection.
- Repeat apply: `ok=40 changed=0 failed=0 skipped=19`; read-only verification:
  `ok=18 changed=0 failed=0 skipped=2` with network management opted out.
- 16 local tests, playbook/shell syntax and whitespace checks pass. Qt's static
  linter retains only the expected runtime PanelWindow warning.

Screenshots: [desktop](images/desktop-preview.png), [lock](images/desktop-lock.png),
[overview](images/desktop-overview.png). This is a native Hyprlock adaptation of
the default upstream Quickshell lock appearance: shaped password glyphs and lock
toolbar power buttons are omitted in this first visual pass. Physical GPU,
multi-monitor/scaling and suspend checks remain as documented below.

## Follow-up — 2026-10-11

Reproduced the suspend failure in a fresh diagnostic session. QMP confirmed S3;
systemd logged successful resume and thawing of user.slice. Hyprlock remained
running and Hyprland reported DPMS enabled, while the QEMU display reported
"Display output is not active". A bounded DPMS off/on probe timed out on enable.
SysRq's blocked-task dump showed a DRM commit worker waiting in
`virtio_gpu_queue_fenced_ctrl_buffer`, via `virtio_gpu_primary_plane_update`.
The [saved kernel excerpt](validation/virtio-resume-blocked-task.txt) narrows the
observed hang to the virtual GPU path; the underlying cause and behavior on
physical hardware remain unverified. No speculative resume workaround was added.

The VM also exposed competing NetworkManager/systemd-networkd ownership of eth0.
Added a preflight guard against active or enabled competing network services and
an explicit `archsetup_desktop_manage_network=false` opt-out. The real VM conflict
is rejected before changes (`ok=9 changed=0 failed=1`, expected). Local Python
tests remain 10/10; the updated desktop playbook passes syntax validation.
With the network opt-out, VM apply passes (`ok=37 changed=0 failed=0 skipped=4`)
and verification passes (`ok=18 changed=0 failed=0 skipped=2`). The opt-out leaves
previously started services unchanged; it does not migrate the VM's networking.

The implementation is opt-in and has not been deployed to the workstation.
Validation used a disposable overlay of the existing Arch VM, with a full system
upgrade before desktop package installation. Firefox was the VM test browser;
the personal profile retains Brave.

## Results

| Check | Result |
| --- | --- |
| Python tests | 10 pass: compositor parsing, invalid-candidate rejection, boolean CLI values, unique shortcuts, reserved layout switch, clipboard command safety, screenshot cancellation, power confirmation, theme state, bounded calculator and AI provider exclusion |
| Ansible syntax | Desktop, desktop-verify and site playbooks pass |
| Disabled desktop | `changed=0`, `failed=0`; desktop tasks skipped |
| Fresh provisioning | Passed in the VM, including package install and session registration |
| Repeat apply | `ok=38 changed=0 failed=0` |
| Preview/check mode | `ok=35 changed=0 failed=0` |
| Read-only desktop verification | `ok=18 changed=0 failed=0` |
| Drift/deletion repair | Deliberately changed Fuzzel config and deleted action helper; apply repaired both, original SHA-256 checksums restored |
| Invalid Lua candidate | Rejected with `changed=0`, expected failure; previous configuration checksum unchanged |
| Greetd boot | Booted to authenticated greeter; no autologin |
| Greetd authentication | Incorrect password rejected; temporary random VM password accepted |
| Normal desktop session | Custom Quickshell configuration loaded under Greetd |
| Taskbar and overview | Running terminal tracked; live preview rendered; Enter focuses the selected window |
| Launcher and terminal shortcuts | Fuzzel and Kitty started using managed configuration |
| Calculator | Local expression entered through picker; result `42` verified on clipboard |
| Notifications and themes | Notification delivered; light/dark generation and CSS reload succeeded; fixed low-contrast label styling |
| Session menu | Escape dismisses it without taking a power action |
| Idle locking / authentication | Hyprlock started on idle, rejected incorrect password, accepted correct password |
| Suspend/resume | **Not passed**: guest reached suspended state, resumed with lock process held and DPMS enabled, but display remained black; attempted VT recovery became unresponsive |

The final boolean-input normalization changes have unit coverage and preserve the
VM profile's generated defaults. Hardware checks and the suspend failure remain
outside the passed results. Never interpret package/configuration verification
as proof that a particular GPU, display or suspend implementation works.

Test versions: Hyprland 0.56.2-4, Quickshell 0.3.2-1, Hyprlock 0.9.6-3 and Hypridle
0.1.8-2. The VM used QEMU's virtio display with software rendering. Quickshell
reported a DMA-BUF render-device fallback to shared memory and Qt portal/text-input
warnings; live previews still rendered. These facts do not conclusively establish
the cause of the suspend failure.

Qt's static linter reports only that PanelWindow is not creatable. Quickshell
provides that type's platform implementation at runtime; the real Wayland session
loaded successfully. Offscreen Qt is insufficient for this check.

## Remaining acceptance work

Before making this the everyday workstation session, verify suspend/resume on its
actual GPU and investigate any black-screen behavior. Also check DP-2 at 144 Hz,
physical pointer feel, audio devices, Bluetooth, portal screen sharing, multiple
monitors, hotplug and fractional scaling. Those tests were not covered by the
single-output software-rendered VM.

The broader plan's app-grouped pinning and grouped workspace preview layout remain
future enhancements; this implementation provides separate running-window buttons,
pinned Web/Files actions, live window previews and workspace selectors. The emoji
picker has a small starter list. See the usage document for these explicit limits.
