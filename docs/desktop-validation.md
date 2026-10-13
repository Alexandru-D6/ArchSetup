# Desktop validation — 2026-10-10

## Session icon grid and shutdown selection — 2026-10-13

The Power/session menu now renders a centered two-row icon grid over a dimmed
full-screen background, following the supplied reference. The selected tile is
circular and shows its label beneath the grid. Shutdown requests open this menu
with Shut down selected; the actual poweroff command runs only after selection.
Keyboard arrows/Tab navigate, Enter/Space select, and Escape/background clicks
cancel. Hibernate is disabled unless logind reports `yes` or `challenge` support.

The 48 Python regressions cover shutdown routing, confirmed execution and logind
capability handling. The full run passed 47; the unrelated background-clock
image-change timing check passed on a focused retry. All 20 Qt test checks pass,
including keyboard/mouse interaction, cancellation, repeated activation,
unsupported hibernation, a 320 x 240 viewport, vector rendering and light/dark
snapshots. Opening under a stationary pointer keeps the requested action
selected. The rendered component was visually inspected in both themes.
`qmllint` passes for both new components; the complete shell retains only its
existing dynamic `qs` import and PanelWindow warnings. Whitespace checks pass.

Qt tests render the standalone component with the offscreen software backend.
Workstation deployment, the full Wayland shell and actual system power actions
were not exercised for this change. The lock-screen power controls keep their
separate confirmation behavior.

## Window resizing — 2026-10-13

Enabled border/gap dragging with a 10-pixel border grab area and retained
Super+right-drag resizing. Added repeating Super+Alt+arrow bindings for relative
width/height changes of 40 pixels. The shared map now contains 228 bindings;
the new entries appear in generated Hyprland configuration and shortcut help.

All 46 existing tests pass, including the native Hyprland 0.56.2 parser and
shortcut conflict checks. The full suite requires access outside the sandbox
for Ansible RPC and the temporary popup sockets. Both desktop playbook syntax
checks, resize reference/metadata checks and whitespace checks pass. Interactive
mouse/key acceptance and workstation deployment were not performed.

## Faster keyboard-layout label — 2026-10-13

The one-second image timer restored lock stability but delayed the keyboard
badge. It now uses Hyprlock's
[native layout substitution](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/#variable-substitution)
in an asynchronous text label. Wayland keyboard events request an immediate
update. A 100 ms native label timer catches the final layout when rapid switches
arrive while the previous label is still loading. The command only prints the
selected, quoted text; layout changes no longer invoke hyprctl or Pillow.
SIGUSR2 remains blocked, and clock/power images retain their one-second timers.

Ansible records the ordered layout/variant pairs in preferences and generates
lock-identity.conf before installing the referencing lock template. It measures
the username and every configured label to fit one compact native border, with
10–13 px text and a 196 px width limit. Long usernames shorten before layout
variants. The companion configuration lives outside the runtime theme cache;
unchanged generation preserves its contents and timestamp. Fast locking does
not perform font measurement.

All 45 regressions pass, including layout/variant order, empty variant slots,
bounded badge sizing, preserved variant names, markup/argument quoting, cached
and uncached lock startup, updater ownership and the refresh-signal guard.
Desktop, desktop-verify and site syntax checks pass.

Eight settled native VM layout switches measured 41.45 ms median and 53.4 ms
maximum visible feedback, including screenshot polling. Nine rapid switches
25 ms apart left the correct final label. Twenty unsubmitted dummy keys measured
41.05 ms median and 63.7 ms maximum feedback. No password was submitted.
A fresh lock using the final companion configuration also passed eight switches
and the rapid-switch check: 41.25 ms median and 137.1 ms maximum feedback.

An uninterrupted five-minute native lock passed 68 clock-update checks, 25
further dummy keystrokes, five layout updates and five alternating power
confirmation/cancellation cycles. The same PID remained responsive after 100
stray SIGUSR2 signals, which were blocked in every inspected locker thread.
Maximum sampled typing feedback was 54.9 ms; maximum layout feedback during
this run was 163.3 ms. Resident memory stayed within 8 KiB across the sampled
281-second interval. Repeated Ansible apply: ok=46 changed=0 failed=0.

Reapply and a fresh lock are required on LittleArchy; no workstation
configuration was changed. This layout check did not repeat full S3 suspend;
the earlier Virtio limitation below remains separate.

## Hyprlock refresh deadlock — 2026-10-12

LittleArchy's journal records Hyprlock aborting at 19:13:30, with image/timer
callbacks running inside the forced-refresh signal handler on several threads.
Arch Hyprlock 0.9.6-3 debug symbols map offset 0x63609 to
handleForceUpdateSignal. The long-running VM lock also stopped updating while
the helper kept generating current clock images. Its main and timer threads
were blocked in that handler after interrupting normal timer work. No full
system suspend occurred in that VM boot. The earlier short lock tests below
did not establish prolonged stability.

The updater now only writes images; it no longer receives a locker descriptor
or sends refresh signals. All four dynamic images use positive one-second
[native image timers](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/#image).
The launcher blocks SIGUSR2 before exec so locker threads inherit the mask,
then restores its own mask on success or failure. This also prevents an old
updater or manual refresh from entering the unsafe handler. The updater ignores
the retired descriptor argument during a partial deployment, and its existing
owner/socket cleanup and PAM policy remain.

The layout file still updates on keyboard events, but visible image changes now
wait for the next native check. Confirmation is delayed for 1.5 seconds so a
rapid second click cannot commit before the changed button label loads;
cancellation remains immediate. Cached launch and background image generation
preserve fast locking and immediate password feedback.

All 44 regressions pass, including a real child receiving a blocked refresh
signal, parent-mask restoration on both successful and failed spawn, image
updates with a retired locker descriptor, controller messages and cleanup.
The two mask tests explicitly start with SIGUSR2 unblocked. Desktop,
desktop-verify and site syntax checks pass; repeat apply:
ok=45 changed=0 failed=0.

An uninterrupted 20-minute native VM lock passed 267 visible clock-update
checks, 100 unsubmitted dummy keystrokes, 20 layout switches and 20 alternating
confirmation/cancellation cycles. Rapid second presses did not commit either
power action. The same locker remained running after a burst of 100 SIGUSR2
signals; every inspected locker thread had the signal blocked. Maximum sampled
password feedback was 57.1 ms; maximum visible layout delay was 1,087.1 ms,
including screenshot polling overhead.

Full S3 resume still did not pass in the Virtio VM: the guest returned from
sleep and thawed user.slice, Hyprland reported the display enabled and locked,
and clock generation continued, but QEMU reported no active display output.
The [new blocked-task excerpt](validation/virtio-resume-after-lock-refresh-fix.txt)
again shows a DRM commit worker waiting in virtio_gpu_queue_fenced_ctrl_buffer,
via virtio_gpu_primary_plane_update. Hyprlock remained alive, with SIGUSR2
blocked and pending. The three-cycle resume test stopped at its first failed
display check; this result must not be counted as a successful suspend test.
The physical AMD laptop's resume path still needs acceptance after deployment.
The VM was reset after its graphics hang prevented a normal reboot from
finishing. Its fresh boot returned to a responsive lock; 20 further unsubmitted
dummy keys measured 40.25 ms median and 43.1 ms maximum feedback.

Apply the desktop profile and start a new locker to load both the signal mask
and the native image timers. An already crashed lock requires session recovery
or a reboot. No workstation deployment or password submission was made.

## Cursor visibility after display wake — 2026-10-12

The user reports that the pointer stays invisible after the locked display wakes,
including while moving the mouse. Hyprlock already has `hide_cursor = false`.
The profile now defaults to [software cursor rendering](https://wiki.hypr.land/configuring/core/config-options/#cursor)
(`cursor.no_hardware_cursors = 1`) to avoid relying on the GPU cursor plane
across display-off/wake transitions. Setting
`archsetup_desktop_software_cursor: false` selects Hyprland's automatic mode (`2`).
Both generated modes pass native Hyprland configuration validation.

All 42 regressions and the desktop, desktop-verify and site syntax checks pass.
The Ansible-managed VM profile reloads without configuration errors and reports
`hardwareCursorsInUse: false`. A temporary three-second idle listener exercised
five real display-blank/wake cycles: three woke by keyboard and two by mouse.
Screenshots verified the pointer after wake and subsequent motion; the same
Hyprlock process and compositor lock remained active throughout. Power off
changed to Confirm, Reboot changed to Cancel, and cancellation restored both
buttons after the final wake. The temporary listener was removed afterward,
leaving the normal supervised idle service running.
Repeated Ansible apply: `ok=45 changed=0 failed=0`.

The original disappearance did not reproduce on the VM's virtual GPU, so this
is a validated rendering workaround pending confirmation on LittleArchy.
No workstation deployment or password submission was made. Apply the desktop
profile and run `hyprctl reload` to activate it in the existing session.

## Faster Super+L startup — 2026-10-12

Lock requests no longer rebuild the desktop theme or run synchronous Pillow/font
preparation. They copy cached idle button images into the private lock directory
and start Hyprlock. The updater generates current clock/layout/button images
afterward, maintains an idle-only button cache and signals image refreshes.
The existing recording-stop request still runs before launching the locker.
Hyprlock's [immediate-render mode](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/#general)
acquires the session lock before waiting for resources, showing its configured
background color while the wallpaper loads. Short fades and PAM policy remain.

All 42 regressions pass, including launching with missing/cached images,
background creation of controls and keeping confirmation labels out of the
idle cache. Three physical Super+L trials in the Arch VM reduced median time
to the first lock-screen frame from 2,428 ms to 192 ms; the clock was visible
by 262 ms. After moving all generated image caches aside, the first cold trial
showed a lock frame in 203 ms and the clock in 279 ms. Later screenshots confirmed
the wallpaper, identity pill and Confirm/Cancel controls rendered normally.
These timings include screenshot polling overhead and describe the VM, not
LittleArchy hardware. No password was submitted or workstation deployment made.
Desktop, desktop-verify and site syntax checks pass. Repeated Ansible apply:
`ok=45 changed=0 failed=0`.

## Lock-screen power confirmation — 2026-10-12

Power off and Reboot now reuse the two existing button positions for confirmation.
The selected button becomes Confirm, and the other becomes Cancel. Cancel
restores the original labels; Confirm runs the selected action once. Rapid
second presses during image replacement are ignored. Button hit areas remain
fixed while their text/icons change.

The lock launcher creates a private runtime directory for its control socket,
button images and generated Hyprlock configuration. Confirmation state stays in
the updater's memory and resets on the next lock. The updater checks socket-peer
credentials and refreshes the images through the existing owned-locker signal.
It cleans up on termination; PAM/keyring policy is unchanged.

All 41 regressions pass, covering both actions, cancellation, duplicate presses,
failed action recovery, fixed image sizes, message validation, live control
delivery, private configuration paths and cleanup. Desktop, desktop-verify and
site syntax checks pass. Native VM mouse tests verified both Confirm/Cancel
arrangements, cancellation without a power action, reset on reopening the lock,
confirmed reboot with a new boot ID, and confirmed power off shutting down QEMU.
Repeated Ansible apply: `ok=45 changed=0 failed=0`.

While confirmation was open, layout labels measured 52 ms median / 97 ms maximum
across eight switches, and unsubmitted dummy password input measured 41 ms median
/ 54 ms maximum across twenty keys. These include screenshot polling overhead
and describe the VM. Apply the desktop profile and reopen the lock screen to
load the controls. No workstation deployment was made.

## Keyboard-layout label responsiveness — 2026-10-12

The user confirmed the remaining delay affected the layout name. The updater's
one-second keyboard poll and Hyprlock's one-second image reload delayed that
label. The helper now subscribes to [Hyprland layout events](https://wiki.hypr.land/IPC/),
queries the main keyboard on a change, redraws the measured pill, and requests
Hyprlock's [SIGUSR2 image refresh](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/#image).
The clock continues ticking independently. The launcher passes a descriptor for
its own Hyprlock process; updates wait until that process installs its refresh
handler. A failed visual-helper start still waits for the password screen.

All 36 regressions pass, including event updates within 500 ms, partial IPC
messages, unrelated keyboard events, no keyboard polling on clock ticks,
startup signal readiness, exited lockers and helper cleanup/failure handling.
Eight physical Super+Space switches in the Arch VM measured the displayed
label's median delay dropping from 865 ms to 40 ms, and maximum delay from
1,078 ms to 85 ms. Nine rapid switches finished with the correct label.
Twenty unsubmitted dummy password keystrokes measured 41 ms median / 52 ms
maximum feedback afterward. These measurements include screenshot polling
overhead and describe the VM, not LittleArchy hardware.
The Reboot button returned to the updated boot lock screen, whose layout badge
also refreshed after switching. Closing the lock screen removed its updater.

Desktop, desktop-verify and site syntax checks pass. Repeated Ansible apply:
`ok=45 changed=0 failed=0`. Apply the desktop profile and reopen the lock screen
to load the changed helper and image configuration. No workstation deployment
was made.

## Password input responsiveness — 2026-10-12

The image `reload_cmd` hooks rebuilt the clock and keyboard badge synchronously
once a second. Local measurements took 152 ms for the clock and 91 ms for the
badge. Hyprlock's [image update implementation](https://github.com/hyprwm/hyprlock/blob/v0.9.6/src/renderer/widgets/Image.cpp)
waits for those commands before processing more input. The launcher now owns a
background updater; Hyprlock checks file timestamps and loads changed images
asynchronously. Font lookups are cached, PNG encoding uses faster lossless
compression, and the identity image is rewritten only when its layout changes.
Password-dot animation is disabled for immediate feedback; the short fades and
color effects remain enabled.

All 33 regressions pass, covering live clock/layout file updates, unchanged
identity images, cleanup after normal/failed locks and an already-exited updater
owner. Desktop, desktop-verify and site syntax checks pass in the Arch VM. A
20-keystroke QEMU trial measured visible dummy-input feedback at 76 ms median /
331 ms maximum with the previous lock configuration, and 41 ms median / 42 ms
maximum with the updated one. These include screenshot polling overhead and
are VM measurements, not LittleArchy hardware measurements; no password was
submitted. Screenshots confirmed the clock's second hand and the US Euro/AltGr
badge still refresh. Closing the lock screen removed its background updater.
Repeated Ansible apply reported `ok=45 changed=0 failed=0`.

The changes are in the Ansible-managed helpers and template. Apply the desktop
profile, then close and reopen the lock screen to load its updated configuration.
No workstation deployment was made.

## Lock-screen wallpaper, reference clock and power controls — 2026-10-12

The lock screen now deploys the user-provided 4K sunset image as its own asset;
desktop wallpaper state and generated background are preserved. Its clock uses
the supplied reference's blue dial, dot markers, hollow hour hand, pink minute
hand, second hand and separate day/month badges. The user/layout pill measures
its text and border together, with compact US Euro/AltGr labels. Native Hyprlock
images provide clickable Power off/Reboot controls; PAM/keyring authentication
is unchanged. The lock launcher prepares assets before starting Hyprlock and
honors the configured short fades.

All 31 regressions and the desktop/desktop-verify/site syntax checks pass. Live
VM testing confirmed the lock wallpaper, clock, password field and controls
render at boot, and Super+Space switches the compact layout label while locked.
The Reboot button changed the VM boot ID and returned to the updated locked
screen. Power off shut the VM down from that screen. Repeated Ansible apply:
`ok=45 changed=0 failed=0`. The refreshed screenshot is
[the lock-screen preview](images/desktop-lock.png). No workstation deployment
was made.

## Automatic shell refresh after apply — 2026-10-12

Shell-source and preference changes now notify one Ansible handler after the
apply succeeds. It selects the managed profile in the desktop user's runtime
directory, restarts Quickshell through the existing session supervisor and waits
for the desktop IPC endpoint to respond. Check mode and inactive desktops skip
the restart; unexpected command/startup failures remain Ansible errors.

All 28 regressions pass, including real Ansible notification coalescing, unchanged
applies, previews, missing runtime directories, inactive profiles, delayed
readiness and failure handling. Desktop, desktop-verify and site syntax checks
pass. In the graphical VM, repairing shell/preference drift produced
`ok=48 changed=3 failed=0`; the shell PID changed once, open terminal windows
survived, and workspace 11 remained active. The repeated apply reported
`ok=44 changed=0 failed=0` and retained the shell PID. Preview also retained it.
A separate inactive-profile apply succeeded with `failed=0` and left the other
active profile's process unchanged. These checks ran from SSH without a display
environment; no workstation deployment was made.

## Workspace ranges and running-shell refresh — 2026-10-12

The installed LittleArchy shell file contained the workspace-range update and
Hyprland reported workspace 11, but the running bar retained its old 1–10 layout.
Running `~/.config/archsetup/bin/desktop-action restart-shell` loaded the update;
the user confirmed the bar then displayed 11–20.

In the graphical VM with Hyprland 0.56.2 and Quickshell 0.3.2, live IPC checks
confirmed labels and highlights for workspaces 1, 2, 10, 11, 12, 20, 21 and 101,
including returning to workspace 1. Relative `r+1` and `+1` switches from 10
also selected and highlighted 11. A QEMU screenshot confirmed the rendered bar
displayed 11–20 with 11 highlighted. Temporary diagnostic instrumentation was
removed after validation.

## Shortcut-help startup repair — 2026-10-12

The installed LittleArchy desktop reported `The popup failed to start` with
Fuzzel 1.15.0. Removed the popup controller's immediate process-file identity
check. A private Unix socket now asks the owning helper to close its own child
through a retained PID file descriptor; disk metadata cannot select a process to
signal. Socket peers are checked by UID, and controller tokens protect replacements
from older cleanup.

23 tests pass, covering popup startup/toggling with process-file reads denied,
stale/tampered state, real menu replacement and control-request authentication.
Native compositor parsing passes. QEMU physical key tests confirm Super+/ opens
and closes shortcut help, alongside launcher, clipboard, emoji, calculator,
wallpaper and panel toggles. VM apply: `ok=42 changed=1 failed=0 skipped=21`.
The updated code has not been applied to the user's LittleArchy installation.

## Repeat-shortcut popup dismissal — 2026-10-12

Super alone and Super+D now open/close the same launcher. Clipboard, emoji,
calculator, wallpaper and help menus toggle through the same session-owned
controller; changing menus replaces the active menu. Popup bindings bypass
application shortcut inhibition while preserving the session-lock restriction.

22 local tests pass, including process identity checks against stale/reused PIDs,
unrelated executables/namespaces/users, cancellation and cleanup races. Physical
QEMU key tests confirm left/right Super, Super+D and all five menu shortcuts
open/close their surfaces. Switching launcher → clipboard → emoji leaves one
managed popup. Overview, quick settings, utilities, media, session menu and the
on-screen keyboard toggle correctly while focused. Whitespace checks pass.
Repeat VM apply: `ok=42 changed=0 failed=0 skipped=21`; read-only verification:
`ok=20 changed=0 failed=0 skipped=2`.
No workstation configuration was modified.

## Unified Kitty theme and immediate closing — 2026-10-11

The default Kitty configuration now links to the managed generated theme, with
an existing configuration saved once as `kitty.conf.pre-archsetup`. Theme
generation runs during apply after template changes or when the Kitty theme is
missing; read-only verification checks the link. Window/tab close confirmation
is disabled with `confirm_os_window_close 0`.

All 20 local tests and both playbook syntax checks pass. A fresh configuration
preview works before any theme/default Kitty files exist and writes no files.
In the VM, real Kitty parsing confirms matching default/shortcut settings and
zero confirmation threshold. The original configuration backup hash is preserved.
The CLI, terminal shortcut helper and Kitty app launcher each opened a terminal,
received a new-tab shortcut and closed without confirmation. The CLI case had a
running foreground job as well. Repeat apply makes no changes:
`ok=42 changed=0 failed=0 skipped=21`; verification:
`ok=20 changed=0 failed=0 skipped=2`. No workstation configuration was modified.

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
