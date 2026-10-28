# Desktop validation — 2026-10-10

## Configuration reapplication with pending upgrades — 2026-10-28

The desktop package guard now checks installed dependencies before requiring a
full system upgrade. When all desktop, enabled login/network dependencies and
selected applications are present, package transactions and the upgrade guard
are skipped. Missing repository dependencies or Brave/VSCodium builds retain the
full-upgrade requirement. The standalone network playbook uses the same guard.

All 21 Ansible regression scenarios pass across normal and check mode, including
configuration-only runs, missing dependencies, disabled optional components,
missing AUR applications, clean installations and failed package queries. Both
desktop and standalone network playbooks pass syntax checks. A live check-mode
run of the desktop package tasks on LittleArchy, with 95 pending upgrades and all
required dependencies installed, finished with changed=0 and failed=0. No system
upgrade or package installation was performed during this validation.


## NetworkManager migration — 2026-10-23

This supersedes the earlier iwd and VPN-only NetworkManager configuration below.
Wi-Fi controls now use nmcli, including saved profiles, adapter selection, scanning,
and passwords passed over stdin. Ansible imports supported iwd profiles, masks
competing manager services and removes the VPN-only restriction. Migration checks
previous uplinks and restores configuration and service states after failure.
Packages and old credentials are retained for recovery.

Migration tests cover installed/instantiated competing services, encoded SSIDs,
existing-profile preservation, real libnm keyfile validation, unsupported active
connections, static IPv4 protection, rollback, private backups and idempotence.
They also exercise actual Ansible preview/async command execution, recreate Wi-Fi
interfaces removed by iwd, follow udev renames and wait for NM device discovery.
Wi-Fi backend tests cover nmcli escaping, SSIDs distinct from profile names,
duplicate access points, enterprise profiles and password/error handling.


The full desktop suite passed (134 tests); the final migration suite passed all
13 tests after the live handover fixes. All three desktop/network/verification
playbooks pass syntax checks. The disabled-desktop check produced zero changes.

Applied successfully on LittleArchy. NetworkManager is enabled and owns the
connected `wlan0` interface; iwd, systemd-networkd and its socket are inactive and
masked. NetworkManager's wpa_supplicant backend and systemd-resolved are active.
One saved iwd network was imported with no skipped profiles. A real DNS lookup
through wlan0 succeeded. The installed panel helper reports available/enabled,
connected Wi-Fi, one connected saved network and no error. A subsequent migration
check reports `changed: false`, with no competing services or pending imports.
The automatic recovery path was also exercised on the workstation before fixing
iwd interface deletion and the supplicant startup race; it restored connectivity.

## Proton VPN control center integration — 2026-10-21

The VPN tile now connects or disconnects through the official Proton VPN CLI.
Its arrow opens an inline submenu with status, server/protocol details, refresh,
optional country selection and a first-use sign-in action. Sign-in delegates
password and two-factor handling to Proton in a terminal; the panel stores no
account credentials. Closing the panel preserves the VPN connection.

All 10 Proton backend/source tests, 7 general control backend tests and the
desktop QML interaction suite pass. Coverage includes fastest/country connection,
disconnection, setup/account/error states, invalid inputs, a GUI conflict reported
with exit status zero, serialized reads and writes, duplicate clicks and connection
persistence when the panel closes. The fresh-install service preview regression,
both desktop playbook syntax checks, component lint and whitespace checks pass.
Sign-in and connection layouts were visually checked at 420×760.

Proton VPN CLI 1.0.5-1 and its signed Arch dependencies are installed on the
workstation. NetworkManager runs with only WireGuard, TUN and dummy interfaces
eligible for management; the existing Wi-Fi interface remains unmanaged by it,
and the previous default route is preserved. iwd/systemd-networkd still own the
physical connection. The real helper correctly reports that Proton sign-in is
required. The profile files were backed up and deployed. Quickshell's previously
documented shutdown crash recurred during reload; the replacement loaded the
configuration and answers IPC. Account authentication and a live VPN connection
remain untested pending the user's sign-in.

## Inline Bluetooth connections — 2026-10-21

The Bluetooth tile toggles adapter power; only its arrow opens the connections
submenu within the control center. The submenu supports adapter selection,
discovery, pairing, connection, disconnection and confirmed device removal.
Pairing confirmations, PINs and passkeys stay in the panel. Discovery stops and
pending pairing or connection attempts are cancelled when leaving the submenu.
The helper uses BlueZ with an application-scoped agent and does not change the
system's default agent or discoverability.

The two Bluetooth integration tests and the complete desktop QML interaction
suite pass. A private BlueZ service covers pairing confirmation, PIN/passkey
validation, cancellation, discovery cleanup, saved-device connections, device
removal and failures. The production Quickshell source test checks process
lifecycle and preserves typed PINs across discovery updates. Component lint and
whitespace checks pass; device-list and pairing previews were visually inspected
at 420×760.

The installed files match the tested source. A live scan found five devices,
preserved existing connections and stopped discovery cleanly. Quickshell reloaded
successfully and answers IPC without QML load errors. Physical device pairing,
disconnection and adapter power changes were not performed on the workstation.

## Inline iwd Wi-Fi controls — 2026-10-20

The Control center Wi-Fi tile toggles adapter power; its arrow opens Wi-Fi controls
within the side panel. The helper uses `iwctl` for adapter discovery, numeric signal
strength, scanning, power, connection and disconnection. Saved networks reuse iwd credentials;
new WPA-Personal passwords travel over stdin and a private terminal, never argv.
The panel shows adapter/service errors, handles multiple adapters, clears passwords
on submission and navigation, and returns to quick actions with Escape or Back.

All 17 focused Python checks and 18 focused Qt checks pass, as does the existing
desktop QML suite. The production ControlSource test verifies stdin requests,
error recovery, adapter selection and rejection of stale polls. A private mock iwd
service exercises the real installed `iwctl` client with spaces, quotes, asterisks,
Unicode passwords and authentication rejection; it does not touch host networking.
The panel was visually inspected at 420×760, QML lint and whitespace checks pass,
and the installed helper identifies the workstation's active iwd connection.
A live scan succeeded while preserving that connection.
The running profile was updated with backups and the reloaded shell answers IPC.
The previously documented Quickshell teardown crash recurred during restart; its
automatic replacement loaded successfully and remains responsive.
Live disconnect/power-off operations were not exercised on the active connection.

## Unified control center — 2026-10-19

The bar's three right-side controls are replaced by one control-center button.
The panel separates uptime/session controls, quick settings and notifications.
All 71 desktop regressions (including the Qt interaction suite) and 7 control
backend tests pass. The private D-Bus integration check covers notification
replacement, timeout/history behavior, transient notifications, actions,
application close requests, DND and clearing. New visual components pass lint;
Quickshell's dynamic model/screen types retain their existing tooling warnings.

Light, dark and 600-pixel-height previews were inspected. The installed desktop
was checked for panel opening/closing, live device discovery, native notification
delivery/dismissal and 4000 K night light with restoration after termination.
The host reports no NetworkManager Wi-Fi adapter or saved VPN profiles; their
hardware connection paths remain untested here. Bluetooth and audio state are
read successfully. `hyprsunset` 0.4.0-3 is installed.

During deployment, the exiting Quickshell process hit a Qt 6.12 shortcut-destructor
crash after its IPC shutdown request. Its automatic restart loaded the new shell;
subsequent panel, notification and night-light checks passed. The crash was in
process teardown, not a QML load error.

## General timezone, layouts and clock placement — 2026-10-16

General now edits the system timezone, ordered keyboard layout/variant pairs and
independent desktop/lock-screen clock positions. Timezone preview derives the
current UTC offset, including daylight saving and fractional-hour offsets.
Default restores the original position; presets, percentages and Randomize save
normalized coordinates for the complete clock/date group. Randomize samples once
and the chosen point persists through Apply. Clock images, full dates and compact
bar dates use explicit timezone snapshots.

All 27 settings tests, 67 desktop regressions and 86 Qt interaction checks pass.
Coverage includes native XKB compilation/Lua parsing, installed variants, four-pair
limits, typed Qt list arguments, ordered edits, independent positions, DST rollback,
midnight and fractional offsets, cancelled authorization, atomic failures, external
revisions, rollback/recovery and busy-writer detection. Scaled, rotated, portrait
and small-screen placement checks keep clock groups clear of password controls.
The real Ansible initialization and input-sync tasks preserve saved layouts on
repeat runs with `changed=0`. Component/locker lint, both desktop playbook syntax
checks, native Lua parsing and whitespace checks pass.

Actual keyboard/pointer events in a disposable graphical VM verified timezone
selection, Polkit authorization and cancellation, focus return, retained drafts,
independent random placements, adding a fourth layout, applying it live and
Super+Space without a revision conflict. The existing active pair survived a
reordered live reload. The timezone changed from UTC to Asia/Kathmandu; the bar,
preview and clock captions agreed after the date changed to the following day.
Qt signal containers are normalized before draft validation for compatibility
with the VM's Qt version.

Both the animated locker and a directly started native locker displayed the saved
clock position and matching Kathmandu date, kept password controls clear, and
accepted the temporary VM password. A separate forced-crash handoff from the
animated locker to Hyprlock did not recover: Hyprland retained its crashed-lock
screen and Hyprlock reported `onLockFinished`. That handoff remains an unresolved
VM acceptance case; direct native startup passed after restarting the test session.

Updated previews show [timezone selection](images/desktop-configuration.png),
[clock placement](images/desktop-configuration-clock.png),
[keyboard layouts](images/desktop-configuration-keyboard.png) and the
[dark palette](images/desktop-configuration-dark.png).

The VM was shut down afterward. The implementation is prepared for desktop-profile
reapplication; the workstation profile was not deployed. Date-format presets remain planned.

## Configuration window, first General setting — 2026-10-15

Super+I and the session menu's Settings tile open a persistent Configuration
window. Super+Comma retains Quick settings. A shared frame supplies the shortcut
window's geometry and palette. The new sidebar searches implemented setting
metadata, groups matches by category and reveals/focuses the selected control.
Drafts live outside category loaders. Apply/Revert, layered Escape handling and
Apply/Discard/Stay close choices preserve edits until explicitly saved or discarded.
The first General field exposes the existing lock-screen power policy.

The `desktop-settings` JSON interface resolves managed defaults and versioned,
user-owned `settings.json`. Writes are serialized, atomic and revision checked.
Defaults and appearance files remain unchanged by interactive Apply. The lock
helper enforces the effective policy; both lockers read the override, and native
configuration is generated for the next lock session. Incomplete settings
templates cannot block locker startup. Repeated initialization through the real
Ansible copy task preserves saved values and reports `changed=0`.

All 12 settings regressions pass, covering malformed/unsupported documents,
invalid values, duplicate JSON keys/non-finite numbers, concurrent processes,
stale/default revisions, write failures, unchanged applies, native configuration
and a production Quickshell read/apply/watch/conflict/recovery fixture. All 67
desktop regressions pass across full and focused runs: existing session-menu
mouse and background-clock timing checks each needed one focused retry. The final
Qt suite passes all 81 checks, including 24 Configuration checks, light/dark
rendering, keyboard close choices and independent scrolling down to 320×240 with
long status messages. New component/test lint, rendered locker lint, both desktop
playbook syntax checks, native Lua parsing and whitespace checks pass. The full
shell retains its existing dynamic `qs` import/PanelWindow tooling warnings.

In a temporary overlay of the graphical Arch VM, actual keyboard and pointer
events verified Super+I, typed search, Enter/Space edits, outside clicks,
Apply/Revert, Escape and close choices, the session Settings tile and restoration
of focus after shortcut help or another application. Repeated opening reused the
same Wayland surface. Two-output checks verified that an open form stays on its
original monitor, a new opening follows the focused monitor and removal of that
monitor recenters the still-open form. Saved overrides survived a shell restart.
The compositor reported no configuration errors. The VM was shut down afterward.

The [light preview](images/desktop-configuration.png) and
[dark preview](images/desktop-configuration-dark.png) were visually inspected.
No workstation deployment, new password authentication cycle, real lock-screen
power action or full logout/login persistence trial was performed for this change.
Date/time, clock placement and keyboard editing remain the next implementation
stages in the [settings plan](desktop-settings-plan.md).

## Lock startup and optional power controls — 2026-10-14

The lock launcher starts the locker before requesting recording cleanup. Cleanup
runs in a separate worker, has a two-second timeout and reports failures without
interrupting locker startup or native fallback. Isolated process tests reproduce
a pending region selection holding the recorder guard; both the animated locker
and fallback start while that selection is still pending. Cleanup times out and
exits without cancelling the lock. Error-injection checks cover a missing recorder,
nonzero exit and timeout.

`archsetup_desktop_lock_require_auth_for_power` defaults to `true`. Both lock
screens hide shutdown/reboot controls; the user unlocks and uses the desktop
session menu. An explicit `false` restores the existing confirmation controls.
The visual helper checks the policy on requests and execution, rejects direct
socket requests when unlocking is required, and denies power actions when its
preferences are missing or malformed. Changing the policy to require unlocking
cancels pending confirmations. The Configuration window plan includes the setting
in General and its search metadata.

All 66 desktop regressions pass. New checks cover both policies, native template rendering, direct helper
and socket requests, confirmation cancellation and QML button visibility/layout
while retaining password focus. Component/test lint, both desktop playbook syntax
checks and whitespace checks pass. Tests use isolated processes, synthetic PAM
policies and offscreen Qt rendering; no real power action or authentication was
performed. Workstation deployment and a complete Wayland lock cycle were not run.
Reapply the desktop profile and start a new lock session to use these changes.

## Searchable shortcut window — 2026-10-14

Super+/ and the shortcut-help aliases now toggle a centered Quickshell window
inspired by the supplied cheatsheet reference. Category columns, keycap labels,
the current palette and a vertical scrollbar replace the launcher list. There
is no periodic-table page. Search receives focus on opening and filters keys,
descriptions, action names and categories as you type; unmatched rows and empty
categories are removed. Clear restores the list, Ctrl+F focuses search, and
Escape, Close, backdrop clicks or the opening shortcut dismiss it. Reopening
resets the query. All 228 managed bindings remain available.

All 60 desktop regressions pass across the full run and focused verification.
Qt checks cover typed input, case/spacing, key combinations, displayed key names,
multiple terms, empty results, clearing, focus, dismissal, reopening, small
screens, scrolling and the production map. An isolated Quickshell fixture uses
the production data loader and window, verifying live map updates, invalid data,
malformed JSON and recovery while preserving the active query. Native compositor
parsing, shortcut uniqueness, component/test lint and whitespace checks pass.
The [full window](images/desktop-shortcuts.png) and
[filtered window](images/desktop-shortcuts-search.png) were visually inspected
in light mode, along with a dark-mode rendering.

UI rendering uses the offscreen software backend. A complete Wayland desktop
session and workstation deployment were not performed. Reapply the desktop
profile to install the components and refresh the running shell.

## Clock reloads and fixed lock pills — 2026-10-14

The animated clock retains its current frame until the next asynchronous image
load completes. The password pill stays at 15% of each screen's width regardless
of prompt, password length or authentication progress. Power off/Reboot remain
136/120 pixels wide through Confirm/Cancel states, with stable heights and
positions. Removed the password submit button; keyboard Enter still submits.

All 58 desktop regressions pass. The clock rendering fixture delays replacement
images, samples the displayed frame during loading, checks the new frame after
completion and verifies typing remains responsive. Disabling frame retention
reproduces a missing clock frame that the fixture detects. Control checks cover
320/1024/1920/3840-pixel widths, long passwords, confirmation/cancellation,
padding and keyboard submission. Component/test lint and whitespace checks pass;
the refreshed [control preview](images/desktop-lock-controls.png) was visually
inspected.

Rendering checks use the offscreen software backend. A full Wayland lock/unlock
cycle and workstation deployment were not performed. Reapply the desktop profile
and start a new lock session to load the changes.

## Password shapes, scrolling layouts and fitted lock pills — 2026-10-14

The animated lock screen uses an independent Quickshell Wayland session lock,
with the existing PAM/keyring policy and native Hyprlock as its failure fallback.
Each newly entered character receives a random geometric shape; editing retains
existing shapes. Keyboard events scroll the previous label upward and its
replacement into view over 180 ms. Reduced motion switches immediately.
Identity, password and power pills measure their content, keeping 16-pixel
horizontal and at least 10-pixel vertical padding. Narrow screens wrap the toolbar;
long labels elide and long passwords scroll inside their field. Confirmation
captions resize their buttons and retain the existing power-control behavior.

All 57 desktop regressions pass, including 29 Qt checks for rendering, editing,
submission, layout switching, typography, padding and small screens. Quickshell
loads the production configuration offscreen. Isolated PAM fixtures cover prompt
responses, acceptance/rejection, required failures, missing users/policies,
duplicate submissions and response cleanup; responses never appear in logs.
Launcher tests cover authenticated exit, crash/early-exit fallback, a missing
Quickshell runtime, updater cleanup and the native refresh-signal mask.
Component lint and whitespace checks pass. The
[rendered control preview](images/desktop-lock-controls.png) was visually inspected.
Both desktop playbook syntax checks pass.

Rendering and PAM checks use the offscreen backend and synthetic policies.
A complete Wayland lock/unlock cycle and workstation deployment were not performed.
Reapply the desktop profile and start a new lock session to load the controls.

## Rose color theme — 2026-10-14

The supplied reference informed the new default Rose palette: warm white surfaces,
blush and peach controls, raspberry highlights and rose-brown text. It defaults
to light mode and includes a matching dark palette. Quick settings selects Rose
or the previous Material palette, while the Light / dark control changes mode.
Saved choices and personal wallpapers survive refreshes; Rose keeps its pink
accent independently of wallpaper colors. The palette covers shell surfaces,
session tiles, launcher/terminal selections, notifications, compositor borders
and native lock-screen controls. The identity badge receives a generated themed
copy; substitutions leave identity text and file paths intact.

All 50 desktop regressions and 20 Qt checks pass, including theme persistence,
mode toggling, personal wallpaper preservation and session interaction/rendering.
Both desktop playbook syntax checks pass. A focused three-test rerun passes after
the final substitution adjustment. Generated configuration checks and native
compositor parsing pass for Rose light/dark. Measured ordinary text contrast is
at least 4.56:1 in light mode and 5.55:1 in dark mode, with large clock text and
control outlines above 3:1. Both session previews were visually inspected; the
[default session preview](images/desktop-session.png) now shows Rose light mode.
Component lint, shell formatting and whitespace checks pass. No workstation
deployment or complete Wayland desktop session was performed.

## Text-only lock power buttons — 2026-10-14

Removed the Power off/Reboot icon widgets and image generation. Native captions
are centered within their buttons; confirmation and cancellation remain immediate.

All 50 desktop regressions pass. Rendered configuration checks confirm that only
the clock image remains and each power button has a centered caption and one
click handler. Whitespace checks pass. No workstation deployment was performed;
reapply the desktop profile and start a new lock session to load the change.

## Lock-screen shutdown routing and immediate confirmation — 2026-10-13

Lock-screen confirmation previously invoked `desktop-action poweroff`, which had
been changed to open the session menu. That menu appeared behind Hyprlock instead
of shutting down. Confirmed lock power actions now call `systemctl poweroff` or
`systemctl reboot` directly, with an explicit action whitelist.

Removed the 1.5-second confirmation guard. Button backgrounds/hit areas are
native shapes, and captions are native 12-point labels reading private files
on a 100 ms asynchronous timer. Default labels are written before Hyprlock starts;
confirmation never waits for image generation or the one-second image timer.
Static icons and the clock remain asynchronous decorations. Each button has
exactly one clickable widget because Hyprlock dispatches clicks to all overlapping
widgets. SIGUSR2 remains blocked, and no refresh signals are sent.

All 50 regressions and both desktop playbook syntax checks pass. The process/socket
tests keep the real helpers and stub only systemctl/Quickshell, verifying shutdown
and reboot reach the power command rather than opening a session menu. Both
confirmed commands are recorded within one second of an immediate second click;
cancellation, duplicate execution, failure reset, credential validation and
per-lock state cleanup pass. Native caption paths, fixed hit areas and one callback
per button are verified. Whitespace checks pass. A complete Wayland lock session
and actual host shutdown/reboot were not exercised for this change.

## Shared session and lock typography — 2026-10-13

Ordinary text on both screens now uses `archsetup_desktop_control_font_size`,
defaulting to 12 points (16 pixels at 96 dpi). Qt and native lock labels use
points; generated button/layout text converts that size for the Pillow canvas.
Password placeholder/failure markup fixes its size explicitly, because Hyprlock
derives the default from input-field height. Names are shortened at the shared
size instead of shrinking. Power off/Reboot buttons are 136/120 pixels wide with
12-pixel gaps, including their Confirm/Cancel states. Day/month clock badges both
use 28-pixel text; time digits retain their deliberate larger size.

The rendered password field remains 320 x 50 pixels, with `halign = center`,
`valign = bottom` and `position = 0, 20`: horizontally centered, 20 pixels above
the bottom edge. The decorative clock is centered vertically and horizontally.

All 49 Python regressions and 20 Qt checks pass, including label fitting,
confirmation hit areas, small screens and rendering. Both desktop playbook syntax
checks and whitespace checks pass. Rendered label/prompt sizes and button spacing
were inspected, as were the session snapshot and generated lock buttons.
Component qmllint passes; the shell retains its existing dynamic import/type
warnings. The complete Wayland lock screen and workstation deployment were not
exercised for this change.

## Settings position and BIOS / UEFI access — 2026-10-13

Settings is now the bottom-left session tile. The bottom-right tile has a firmware
chip icon and the label Restart to BIOS / UEFI. It dispatches
`systemctl reboot --firmware-setup`; logind's CanRebootToFirmwareSetup capability
enables the tile only for `yes` or `challenge` results. Unsupported or disallowed
firmware access is disabled and skipped by keyboard navigation.

All 49 Python regressions and 20 Qt checks pass. Firmware reboot and its failure
path are mocked; a failed request does not fall back to an ordinary reboot.
Qt tests exercise the new positions, mouse/key activation, capability changes,
cancellation and rendering in both themes. Component/test qmllint and whitespace
checks pass, and the refreshed preview was visually inspected. No workstation
deployment or actual firmware reboot was performed.

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
