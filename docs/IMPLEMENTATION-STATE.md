# Resume checkpoint — 2026-10-13 (latest)

Latest task: replaced the desktop session list with the supplied reference's
full-screen, centered two-row icon grid. The Power button and session shortcuts
open it; the shutdown shortcut/helper preselects Shut down and waits for a
selection before executing poweroff. Arrow/Tab navigation, Enter/Space, mouse
selection and Escape/background cancellation work. The initial pointer position
does not override the requested selection. Hibernate is disabled when logind
reports it unavailable. Both themes use original vector icons.

Validation: 48 Python regressions pass across the full run and one focused retry
of the unrelated background-clock timing check. All 20 Qt checks pass, including
actual key/mouse events, disabled actions, small screens and light/dark rendering.
The two new components pass qmllint; the complete shell retains only its existing
dynamic qs-import/PanelWindow warnings. Rendered previews were visually inspected.
The standalone Qt component was tested offscreen; workstation deployment, the
complete Wayland shell and actual power actions were not exercised. Reapply the
desktop profile to activate the change; its handler refreshes the running shell.

Previous task: enabled resizing tiled and floating windows with border/gap dragging
and repeating Super+Alt+arrow shortcuts. Left/Right shrink/grow width; Up/Down
shrink/grow height in 40-pixel steps. Super+right-drag remains available. The shared
shortcut map, help reference, README and source count now cover 228 bindings.

Validation: all 46 existing tests pass with the approved socket access, including
native Hyprland 0.56.2 configuration parsing and shortcut uniqueness. Desktop and
desktop-verify syntax checks, resize reference/metadata checks and whitespace
checks pass. No workstation deployment or interactive resize acceptance was
performed. Reapply the desktop profile, then run `hyprctl reload` to activate.

Previous task: emptied the left side of the taskbar. Removed the complete left row:
Apps, View, the wide-screen Web/Files buttons and all running-window buttons and
their close menus. Centered workspace/clock controls and right-side tray, audio,
notification and power controls remain available. The overview is accessible by
Super+Tab and application launching by Super/Super+D.

Validation: 23 existing tests pass. Qt 6 qmlformat parses the updated shell and
qmllint exits successfully with only the existing runtime qs-import/PanelWindow
warnings. The unqualified /usr/bin Qt 5 tools cannot parse either the old or new
configuration; use /usr/lib/qt6/bin for these checks. Whitespace checks pass. The
VM was not started for this simple QML removal and remains powered off. No
LittleArchy/workstation deployment was performed. Apply the desktop role, then
press Ctrl+Super+R to restart the managed shell.

Previous task: fixed shortcut-help startup on installed LittleArchy. The user
reported `The popup failed to start` with Fuzzel 1.15.0. This message came from the
new controller's immediate /proc identity check, which could reject and terminate
its own popup. Replaced process-file checks with a private, session/profile-scoped
Unix socket: the owning helper retains a PID file descriptor for its own child
and accepts only close requests from the same UID. PID fields on disk are now
diagnostic only. Unique controller tokens prevent older cleanup from deleting a
replacement popup. The original open/close toggle behavior remains.

Validation: 23 tests pass, including real open/close cycles with /proc-style reads
denied, stale/tampered diagnostic records, menu replacement and rejection of
foreign users/unknown control requests. Native configuration parsing passes.
QEMU physical key acceptance confirms Super+/ opens/closes help, other menus toggle,
and switching menus leaves one active popup. VM apply:
`ok=42 changed=1 failed=0 skipped=21`; log `/tmp/desktop-help-fix-apply.log`.
Host acceptance helper: `/tmp/archsetup-popup-acceptance.py`; guest probe:
`/tmp/desktop-popup-state.py`. No deployment to LittleArchy or the workstation was
made; apply the updated repository on LittleArchy. Source changes are uncommitted.
The test VM is powered off, idle behavior is restored, the temporary account is
locked and temporary host credentials were removed.

Previous task: Super alone and Super+D toggle the launcher; pressing the opening
shortcut again dismisses Fuzzel menus (clipboard, emoji, calculator, wallpaper,
shortcut help). A session/profile-owned controller serializes opens/closes, waits
for the previous menu to exit before switching and checks UID, executable,
namespace and process start time before signaling through a PID file descriptor.
Cancellation returns no selection; old-menu cleanup cannot remove a newer menu's
state. Added `dont_inhibit` to 21 popup/panel bindings and the native Lua renderer;
they remain unavailable while the session is locked. The toggle scope is desktop
popups and panels.

Validation: 22 local tests pass, including stale/reused/unrelated PID rejection,
popup cancellation and cleanup-race coverage. QEMU physical key tests pass for
left/right Super and Super+D, clipboard, emoji, calculator, help and wallpaper;
switching launcher → clipboard → emoji leaves one managed popup. Overview,
settings, utilities, media, session menu and on-screen keyboard toggle correctly
with the panel focused. Host acceptance helper:
`/tmp/archsetup-popup-acceptance.py`; guest state probe:
`/tmp/desktop-popup-state.py`. Initial VM apply:
`ok=43 changed=3 failed=0 skipped=20`; logs are
`/tmp/desktop-popup-apply.log` and `/tmp/desktop-popup-repeat.log` in the guest.
Repeat apply: `ok=42 changed=0 failed=0 skipped=21`; verify:
`ok=20 changed=0 failed=0 skipped=2` (`/tmp/desktop-popup-verify.log`).
No workstation deployment was performed.
The acceptance helper restored idle behavior and closed the test popups. The VM
is powered off, its temporary test account is locked and host credentials were
removed.

Previous task: default Kitty launches now use the managed desktop theme, including
the app launcher, CLI and terminal shortcuts. The role backs up the previous
`~/.config/kitty/kitty.conf` once as `kitty.conf.pre-archsetup`, generates the current
theme and replaces the default configuration with a link to
`~/.config/archsetup/theme/kitty.conf`. Theme generation runs after template changes
or if the generated Kitty theme is missing. Verification checks this link.
`confirm_os_window_close` is now zero, disabling window/tab close confirmation.
README and ownership/recovery documentation reflect the managed default config.

Validation: all 20 local tests, both desktop playbook syntax checks and a fresh
Kitty check-mode preview pass. Real Kitty parsing in the VM confirms matching
default/shortcut settings and disabled confirmation; the original backup hash is
unchanged. CLI, shortcut helper and `gtk-launch kitty` each opened and closed after
adding a tab, without confirmation; the CLI case also had a running foreground
job. First VM apply: `ok=44 changed=4 failed=0 skipped=19`; repeat:
`ok=42 changed=0 failed=0 skipped=21`; verify:
`ok=20 changed=0 failed=0 skipped=2`. VM helpers/logs are
`/tmp/desktop-kitty-launch-test.py`, `/tmp/desktop-kitty-launch.log`,
`/tmp/desktop-kitty-apply.log`, `/tmp/desktop-kitty-repeat.log` and
`/tmp/desktop-kitty-verify.log`. No workstation deployment was performed.
The VM is powered off, the temporary test account is locked, idle inhibition was
restored by the acceptance helper and temporary host credentials were removed.

Previous task: new Kitty terminals open as normal tiles. A named native window rule
sets `tile=true`, initializes `fullscreen_state="0 0"` and suppresses client
maximize/fullscreen requests. Explicit `on_focus_under_fullscreen=2` and
`exit_window_retains_fullscreen=false` prevent fullscreen takeover/retention.
Reproduced the second normally launched terminal becoming maximized in the VM;
after apply/reload, six terminals tile without overlap and both compositor/client
fullscreen states remain zero. Forced client maximize/fullscreen requests are
ignored; explicit compositor maximize/fullscreen still work, and opening another
terminal restores tiling. All 20 local tests pass, including the native parser.
VM apply: `ok=39 changed=2 failed=0 skipped=19`, including the earlier workspace
follow change. No workstation deployment was performed. Temporary acceptance
helper: `/tmp/desktop-terminal-tiling-test.py` in the guest and
`/tmp/archsetup-terminal-tiling-test.py` on the host; apply log:
`/tmp/desktop-terminal-apply.log` in the guest. Test terminals were closed, idle
inhibition restored, the guest test account locked and temporary credentials
removed. The VM is powered off; administrative shutdown was used because a remote
SSH session cannot invoke the ordinary power helper without interactive Polkit
authentication.

Previous task: moving a window now follows it to the destination workspace.
All 72 workspace-move bindings explicitly use `follow=true`: numbered workspaces,
physical/keypad aliases, relative moves and scratch, with both Shift and Alt
variants. Shortcut-help descriptions and the reference are updated. All 20 local
tests pass, including the native compositor parser; the reference matches every
changed binding and whitespace checks pass. This change was first deployed to the
saved VM during the terminal fix above; the older silent-move acceptance below is
historical. No workstation deployment was made.
Apply using `./setup.sh desktop-apply -e @inventory/profiles/LittleArchy.yml
--ask-become-pass`, then run `hyprctl reload` in the managed desktop session.

Previous task: expanded the single-source shortcut map to **224 bindings**, including
physical number-row/keypad aliases and relative workspace controls. Existing
launcher/calculator/scratch keys are preserved; maximize, zoom-in and snip have
nonconflicting alternatives. Implemented local OCR/screenshot saving, session-owned
recording start/stop (including output-monitor audio), native on-screen keyboard,
utilities/detached tools, media controls, shell/clock toggles, editor/office/task
launchers, zoom and universal VM passthrough escape. Added official app/capture
packages and configurable desktop-entry preferences. No upstream code/assets or
AI/cloud shortcuts were imported. Full key reference: docs/desktop-shortcuts.md.

Validation: **20 local tests pass**, native Lua parsing and playbook syntax pass.
The VM registered all 224 entries. Tested modifier-only launcher without chord
interference, utilities/detachment, keyboard key delivery, app aliases (Geany,
Mousepad, LibreOffice, btop), relative and silent workspace movement, floating /
640x480 sizing / pinning, zoom and reset, bar/clock/placement toggles, shell restart,
VM-mode entry/escape, saved screenshot, local OCR fixture copied to clipboard,
video record/stop and audio capture with a generated tone on a VM null sink.
ffprobe confirmed H.264 + AAC in the final audio recording. Physical audio and
hardware-specific keys remain subject to the older hardware acceptance limits.

Runtime fixes: moved utilities into a separately imported QML component; created
VM submap through its universal escape bind (empty submaps were ineffective);
corrected wf-recorder backend to pulse; bounded capture/OCR waits; isolated
clipboard daemon output streams; retained default media folders when XDG folders
are unconfigured. Keep-awake now belongs to the always-mapped background surface,
so taskbar hiding does not remove the inhibitor. Added IPC awake/status hooks for
acceptance checks. Temporary validation helpers are /tmp/desktop-shortcut-session.py
in the VM and corresponding /tmp/archsetup-* files on the host. Latest guest logs:
/tmp/desktop-shortcuts-final.log, /tmp/desktop-shortcuts-repeat.log and
/tmp/desktop-shortcuts-verify.log. Final repeated apply: ok=39 changed=0 failed=0 skipped=19. Verify: ok=18
changed=0 failed=0 skipped=2. Test clipboard cleared and VM account password
locked again; temporary host credential files removed. VM disk flushed and
poweroff completed cleanly using the direct helper. No workstation deployment
was made.

Latest user requests: remove bundled third-party assets and remove power-action
confirmation. The copied wallpaper/font and accompanying files are removed from
the working tree and Git index. Default backgrounds are generated gradients;
clock and UI text use installed system fonts. Role apply removes the previously
deployed copies at their known ArchSetup paths and refreshes the font cache.
Personal wallpaper choices are preserved. Shutdown/reboot/suspend/logout now run
directly. 17 local tests pass, including mocked direct-power execution and actual
gradient/clock rendering without bundled assets. VM migration confirmed the old
copies absent; repeated apply reports `ok=39 changed=0 failed=0 skipped=19` and
verify reports `ok=18 changed=0 failed=0 skipped=2`. Updated screenshots show only
the original gradient and system-font rendering. Used the direct poweroff helper
to shut down the VM after locking its temporary test account; host credential
files were removed. No workstation desktop changes were applied.

Appearance overview (see latest changes above): the desktop now follows end-4's default ii look: top
40px bar, grouped workspace/clock controls, neutral Material surfaces, 18px window
corners, 1px borders, an original generated gradient and installed system fonts.
Third-party font/wallpaper copies and their accompanying files were removed.
`docs/desktop-source.json` records an empty bundled-assets list. No upstream
shell/AI code was imported.

Hyprlock now adapts the default Quickshell lock appearance: centered 14-scallop
clock, blurred shared wallpaper, date/Locked labels and bottom password/user/layout
islands. `bin/lock-visuals` draws the clock via Pillow once per minute and supplies
Caps Lock/battery status. Ordinary password dots remain, power actions stay in the
desktop menu. Animation and PAM/keyring settings are preserved. Theme colors are
generated before compositor startup; old user wallpaper/light choices survive.

Validation: 16 local tests and syntax/whitespace checks pass; runtime QML loads
without errors; live overview and Kitty geometry inspected. Greetd locked boot
tested, wrong password rejected, correct password accepted; VM PAM logs explicitly
report login-keyring unlock. Repeat VM apply `ok=40 changed=0 failed=0 skipped=19`,
verify `ok=18 changed=0 failed=0 skipped=2` with Firefox and network opt-out. Final
startup-color change was boot-tested; screenshot in `/tmp/archsetup-ii-final-boot.png`.
Previews are persisted in `docs/images/desktop-preview.png`, `desktop-lock.png`
and `desktop-overview.png`. Temporary VM test password is locked/removed at the
end of this run. No workstation deployment was performed. Earlier checkpoints
below describe superseded theme/boot behavior. Hardware/suspend limitations remain.
Final shutdown completed cleanly (`System Power Off`, QEMU exited). Temporary
credential files were removed. The saved VM disk contains the latest theme.

Latest keyring integration: managed Hyprlock uses the separate
`/etc/pam.d/archsetup-hyprlock` profile, with `auth substack hyprlock` followed by
optional `pam_gnome_keyring.so auto_start`. This preserves existing authentication
policy and unlocks/starts the keyring during PAM authentication (Hyprlock does not
open a PAM session). The Login keyring password must match the account password.
Existing PAM files/keyring contents are not replaced. Theme selection now rejects
stale generated configurations so newly deployed authentication settings take
effect on the next lock. Real PAM control-flow tests use temporary policies and
require execution outside the sandbox because PAM audit returns a system error
inside it. Actual graphical authentication plus keyring decryption is still to
be validated on the target; no workstation PAM configuration was modified.

Latest browser change: selecting Brave now automatically installs it when missing.
`tasks/brave.yml` builds reviewed AUR revision
`21e2273a1bc003bf35d00aebb40ef8c22b1a53fa` (1.97.56) as the regular user in a
temporary directory, checks source checksums via makepkg, and installs via pacman.
Existing browser entries skip installation. Check mode only previews the build;
read-only verification still rejects a missing browser. All 14 local tests and
desktop syntax validation pass. The actual package download/build/install has
NOT been exercised in the VM yet. Browser upgrades remain separate maintenance.
LittleArchy selects Brave and reduced-motion defaults now disable compositor,
Hyprlock and notification animations.

Latest user change: skip Greetd's boot prompt and show Hyprlock. Implemented
`archsetup_desktop_autologin_locked: true` by default, a Greetd initial_session
for the selected user, and `archsetup-session --locked` passing Hyprland's native
`--locked-cmd`. Authenticated greeter remains the post-logout/failure fallback.
13 local tests pass, including parsed Greetd TOML and captured launcher arguments;
syntax checks pass. This new boot flow has NOT yet been exercised graphically
or deployed to the workstation. Earlier Greetd authentication results below
describe the previous boot flow. Also fixed missing-service check-mode failures
for Greetd, NetworkManager and Bluetooth, covered by an Ansible regression test.

User authorized continuation. Repository changes remain uncommitted and the
workstation is untouched. This section supersedes the historical checkpoint below.

- Reproduced suspend failure; captured a kernel DRM commit worker blocked in
  `virtio_gpu_queue_fenced_ctrl_buffer`. Evidence is in
  `docs/validation/virtio-resume-blocked-task.txt`. DPMS reset hangs on enable;
  do not install it as a workaround. Physical GPU acceptance is still required.
- Found NetworkManager competing with systemd-networkd in the cloud VM. Added
  a preflight guard for active/enabled systemd-networkd, dhcpcd and ConnMan, plus
  `archsetup_desktop_manage_network=false` to preserve existing service ownership.
  Opt-out does not stop an already-running NetworkManager from earlier installs.
- Synced latest implementation into VM `/home/archsetup/desktop-test`.
- Conflict test: expected rejection, `ok=9 changed=0 failed=1`.
- Apply with network opt-out: `ok=37 changed=0 failed=0 skipped=4`.
- Verify with network opt-out: `ok=18 changed=0 failed=0 skipped=2`.
- Local 10 tests, desktop syntax, shell syntax and whitespace checks pass.
- VM test account remains password-locked. No new credentials were created.
- VM disk was flushed and poweroff requested after tests; see shutdown note below.

Shutdown note: the guest stalled stopping user managers after the graphics hang.
After the successful `sync` and shutdown request, QMP `quit` stopped the VM.
The checkpoint disk is preserved; this was not a clean completed guest shutdown.

Next: review target-machine deployment/adoption diff and validate actual GPU,
input, audio, Bluetooth and portals. VM graphics hang is narrowed down but not
fixed; do not claim the full hardware acceptance complete. For further cloud VM
apply/verify commands add `-e archsetup_desktop_manage_network=false`. Temporary
diagnostic systemd unit was `archsetup-resume-diagnostic` on tty7. New guest logs:
`/tmp/desktop-network-guard.log`, `/tmp/desktop-network-optout.log`,
`/tmp/desktop-resume-verify.log`. These logs disappear after reboot; results above
and kernel evidence are persisted in the repository.

## Historical checkpoint — 2026-10-10

Stopped at the user's explicit request: "Stop and save the current state for the
next session". Do not resume work until asked. All code is saved in the working
tree; no commit was made. The workstation's desktop/packages/login were untouched.

## Latest status (supersedes historical notes below)

Implementation is present and substantially VM-tested. Primary entry points:
`docs/hyprland-desktop.md`, `docs/desktop-validation.md`, `roles/desktop`, and
`playbooks/desktop.yml`. The user permits Lua and requires no AI integrations.

Since the earlier checkpoint:

- Added validation BEFORE replacing Lua via `bin/validate-config`, preserving
  `.lua` suffix and checking parser output as well as exit status.
- Added Kitty configuration/theme support and corrected CLI boolean handling.
- Fixed overview keyboard focus and Return/Enter activation; verified window focus
  and overview dismissal. Session-menu Escape verified.
- Added a `desktop status` IPC endpoint (page/window counts/focus diagnostics).
- Replaced missing-glyph controls with readable View/Power labels.
- Made Hyprlock's empty password field visible and corrected notification text
  contrast for light themes. No further UI redesign is needed for those fixes.
- Unit tests now total **10 passing**, including CLI booleans and invalid candidate
  rejection. Syntax checks and `git diff --check` pass.
- VM Greetd boot, rejection of a wrong password and successful password login
  were tested. Idle Hyprlock, wrong-password rejection and successful unlock were
  tested. A temporary random password was used only on the disposable VM.
- Taskbar window tracking, live preview, terminal/launcher shortcuts, calculator
  result copied to clipboard, notification delivery, theme generation and menu
  dismissal were exercised. Screenshots are under `docs/images/`.
- Drift test altered Fuzzel config and deleted the action helper: apply restored
  both and original SHA-256 checksums. Subsequent apply: `ok=38 changed=0 failed=0`.
- Check mode: `ok=35 changed=0 failed=0`; verify: `ok=18 changed=0 failed=0`.
- Invalid compositor candidate: expected failure with `changed=0`, previous
  configuration checksum unchanged.

## Unresolved result — investigate next

**Suspend/resume did not pass.** QMP confirmed suspended state; after wake,
Hyprlock remained running and Hyprland reported DPMS enabled / LOCK inhibition,
but the display remained black. A subsequent VT-switch recovery attempt became
unresponsive, as did SSH diagnostics. Cause is NOT conclusively established.
The software-rendered virtio VM had earlier reported DMA-BUF fallback to shared
memory and Qt portal/text-input warnings; do not assert those caused this failure.
The VM required QMP `quit` after a shutdown request did not complete, then was
rebooted from the same checkpoint disk. A clean shutdown was requested at this
latest stop. Check the shutdown status note at the end of this document.

Next steps when authorized:

1. Investigate resume using the VM and/or validate on actual graphics hardware;
   do not claim suspend/resume is working. Physical monitor/input/audio/Bluetooth,
   portal screen sharing, multi-monitor, hotplug and scaling remain untested.
2. Sync the latest repository into `/home/archsetup/desktop-test` before testing.
   The final boolean-normalization source edits have local tests; they were made
   after the last VM source sync. They preserve the tested profile's generated
   defaults. Documentation updates also postdate the last sync.
3. Finish review and decide whether the initial profile is ready for workstation
   adoption. Workstation deployment has NOT been performed. Existing host
   Greetd adoption changes autologin to password login and needs a reviewed diff.
4. App-grouped pinning and grouped workspace previews remain enhancements; the
   current shell has individual task buttons, Web/Files pins, workspace selectors
   and live window previews. Emoji list is a small starter set.

## Current saved VM and tools

Disk: `vm/disks/desktop-checkpoint.qcow2` (Git-ignored), backing on
`vm/disks/archsetup.qcow2`, then the original cloud image. Keep the backing chain.
It contains all provisioning changes up through UI/lock fixes, plus VM test logs.
RAM is not saved. Original pre-resume test overlay remains in
`/tmp/archsetup-desktop-test.qcow2` as an earlier fallback.

Temporary host utilities (may disappear across reboot):
`/tmp/archsetup-validation` (Ansible/Python venv), `/tmp/archsetup-collections`,
`/tmp/archsetup-ansible`, `/tmp/archsetup-vm-console.py` (QMP console helper),
`/tmp/archsetup-vm-session.py` (run commands with VM compositor environment),
`/tmp/archsetup-vm-acceptance.sh` (drift/rerun/check/invalid-candidate tests).
Do not run the VM acceptance script on the workstation. Test credentials are not
stored in the repository. Temporary credential files are removed at checkpoint.

See the historical section below for QEMU/SSH commands. QMP socket is
`/tmp/archsetup-desktop-qmp.sock`; VM SSH is localhost:2223 with the existing VM key.
After reboot, Greetd starts on tty1. If account password is locked, set a new
random test-only credential inside the disposable VM before testing login.

## Historical checkpoint (retain commands, superseded where noted)

## User decisions

Implement the end-4-inspired Hyprland desktop in ArchSetup, removing AI features.
The user's latest correction explicitly ALLOWS LUA (supersedes the no-Lua request).
Preserve Brave and local input settings. Include a login manager and Hyprlock.
Greetd and Hyprlock already exist on the workstation; its Greetd currently has
autologin. Workstation deployment has not been performed.

## Implemented

- Optional `roles/desktop` with defaults, preflight/adoption guards, official
  package installation, configuration, Greetd and read-only verification.
- `playbooks/desktop.yml`, `desktop-verify.yml`, optional role in `site.yml`,
  `desktop-check`, `desktop-apply`, `desktop-verify` wrapper commands.
- `inventory/profiles/alex-desktop.yml`: Brave, existing Quickshell package,
  DP-2 at 144 Hz and HDMI-A-1 disabled; default role uses automatic monitors.
- Isolated profile under `~/.config/archsetup`, separate session entry; original
  `~/.config/hypr` stays untouched. Native Hyprland 0.56 Lua and single-source
  JSON shortcut definitions.
- Original Quickshell shell: taskbar, workspaces, live window overview, tray,
  quick settings, notification access, session menu, light/dark and wallpapers.
- Fuzzel, SwayNC, clipboard/emoji/screenshot/color/calculator helpers, supervised
  session children, Hyprlock and Hypridle before-sleep integration.
- Wallpaper-derived theme shared across shell/Fuzzel/SwayNC/Hyprlock/window
  borders; latest source also adds Kitty configuration/theming.
- End-4 reference SHA c4f0582cbf4ad29607dbf3c20337815de8690b34. After finding AI
  references in about 195 upstream files, implementation uses original code,
  not a copied/patched upstream shell. Source manifest: docs/desktop-source.json.

## Validation completed

- Eight Python tests pass (`tests/desktop/test_desktop.py`): actual compositor
  parsing, bindings, clipboard command safety, cancelled screenshots, power
  confirmation, theme-state preservation, calculator bounds/code rejection,
  and absence of AI provider references in deployment payload.
- Hyprland 0.56.2 accepts rendered Lua (`config ok`).
- Ansible syntax checks pass for desktop, desktop-verify and site playbooks.
- Disabled role check: changed=0, failed=0; all desktop tasks skipped.
- Qt qmllint: only the expected PanelWindow dynamic-platform uncreatable-type
  warning remains. Runtime compositor testing is required for that type.
- Disposable VM first apply succeeded. Second apply after fixes:
  ok=38 changed=0 failed=0 skipped=1.
- VM desktop-verify passed with changed=0.
- VM native Hyprland/Quickshell session launched successfully; shell log says
  `Configuration Loaded`, with no QML errors. Portal registration warnings under
  the systemd-run test harness remain to investigate in a normal Greetd session.
- Screenshot captured and inspected: dark gradient background, bottom taskbar,
  workspace buttons, Web/Files, volume/notifications/clock/session controls.
  Saved to docs/images/desktop-preview.png. No application windows were opened.

Bugs found and fixed in testing: use pacman metadata rather than `Hyprland
--version` without XDG_RUNTIME_DIR; supply a private runtime directory for config
verification; skip starting Bluetooth when /sys/class/bluetooth is absent;
pass compositor arguments using `start-hyprland -- --config ...`.

## Remaining work (do not claim the full project is complete)

1. Sync latest source to VM. The latest Kitty theme/config additions are in the
   repository and pass unit tests, but have NOT been deployed/retested in the VM.
2. Open each shell surface; test overview with real application windows, keyboard
   focus/navigation, tray menus, screenshot/clipboard helpers, theme changes,
   calculator, notifications, media and power menu cancellation.
3. Exercise managed file drift/deletion repair, check mode and another unchanged
   rerun after final code edits.
4. Test actual Greetd boot/login and Hyprlock authentication. VM test account has
   a locked password from cloud-init; do not assume password authentication works
   until a temporary test credential is explicitly set in the disposable VM.
5. Test suspend/resume, scaling/hotplug, portals and hardware-dependent behavior.
6. Review robustness: child supervisor cleanup; configuration ownership/adoption;
   failed configuration validation currently happens after writing isolated
   profile files; interrupted fresh installation may need explicit adoption of
   the newly installed stock Greetd config on retry. Consider staging validation.
7. Update docs/desktop-source.json with validated VM versions and final test
   results. Reconcile broader plan with current limitations in usage docs.
8. Final diff review and `git diff --check`. Do not deploy to the workstation as
   an incidental part of testing. If deployment is requested, review actual
   upgrade/adoption changes and use required sandbox privilege approval.

Current limitations: overview displays all windows with workspace buttons rather
than workspace-grouped previews; running windows have individual task buttons,
with Web/Files pinned separately; emoji list is small. Full application-grouped
pinning is not implemented. No arbitrary upstream installer or AUR build runs.
Fresh-machine Brave installation is a documented prerequisite; VM uses Firefox.

## Saved environments

Host validation tools (temporary; recreate if gone):

- /tmp/archsetup-validation: Python venv with ansible-core 2.20.1, Jinja2, PyYAML.
- /tmp/archsetup-collections: community.general 13.4.0 and its dependency.
- /tmp/archsetup-ansible: Ansible temp/cache home.
- /tmp/archsetup-upstream: read-only reference checkout.
- /tmp/archsetup-preview: generated test profile (may lag latest source).

Run checks with:

```bash
/tmp/archsetup-validation/bin/python tests/desktop/test_desktop.py
ANSIBLE_HOME=/tmp/archsetup-ansible ANSIBLE_LOCAL_TEMP=/tmp/archsetup-ansible/tmp \
ANSIBLE_COLLECTIONS_PATH=/tmp/archsetup-collections \
/tmp/archsetup-validation/bin/ansible-playbook playbooks/desktop.yml --syntax-check
```

## VM checkpoint and resume

The disposable VM was cleanly powered off for this checkpoint. Its disk was
copied to `vm/disks/desktop-checkpoint.qcow2` (ignored by Git). This overlay depends
on the existing `vm/disks/archsetup.qcow2`, which in turn depends on the cloud
image. Keep those backing files unchanged; do not run the ordinary VM reset.
The original running test disk also remains in /tmp/archsetup-desktop-test.qcow2.
RAM/process state is not saved; this is a clean disk checkpoint.

Start the checkpoint with a separate local port (requires the normal execution
approval for QEMU/network access):

```bash
qemu-system-x86_64 -enable-kvm -cpu host -m 4096 -smp 4 \
  -display none -vga virtio \
  -serial file:/tmp/archsetup-desktop-console.log \
  -pidfile /tmp/archsetup-desktop-qemu.pid -daemonize \
  -qmp unix:/tmp/archsetup-desktop-qmp.sock,server=on,wait=off \
  -drive file=vm/disks/desktop-checkpoint.qcow2,format=qcow2,if=virtio \
  -drive file=vm/disks/seed.iso,format=raw,media=cdrom,readonly=on \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2223-:22 \
  -device virtio-net-pci,netdev=net0
```

SSH (existing key is not copied into documentation):

```bash
ssh -F /dev/null -p 2223 -i vm/keys/archsetup_vm_ed25519 \
  -o UserKnownHostsFile=vm/keys/known_hosts \
  -o HostKeyAlias='[127.0.0.1]:2222' -o StrictHostKeyChecking=yes \
  archsetup@127.0.0.1
```

VM repo is `/home/archsetup/desktop-test`. Apply options:
`-e archsetup_desktop_enabled=true -e archsetup_desktop_user=archsetup
-e archsetup_desktop_browser=firefox.desktop`.
Login management is enabled; Greetd is enabled for next boot, no autologin.
Logs: /tmp/desktop-apply.log, /tmp/desktop-second.log, /tmp/desktop-verify.log,
/tmp/hyprland-test.log. Installed test stack:
Hyprland 0.56.2-4, Quickshell 0.3.2-1, Hyprlock 0.9.6-3, Hypridle 0.1.8-2.
The VM was fully upgraded before installing desktop packages.

To launch a diagnostic graphical session without logging through the greeter,
activate tty7 (`sudo chvt 7`) BEFORE starting the compositor. Otherwise logind
reports an inactive session and Aquamarine fails to acquire the DRM backend.
Use a unique transient service name per run:

```bash
sudo systemd-run --unit=archsetup-graphical-resume --uid=archsetup \
  --property=PAMName=login --property=TTYPath=/dev/tty7 \
  --property=StandardInput=tty --setenv=XDG_RUNTIME_DIR=/run/user/1000 \
  --setenv=XDG_SESSION_TYPE=wayland --setenv=LIBGL_ALWAYS_SOFTWARE=1 \
  /bin/bash -c 'exec /usr/local/bin/archsetup-session > /tmp/hyprland-test.log 2>&1'
```

Read logs using `XDG_RUNTIME_DIR=/run/user/1000 qs log --any-display
-p /home/archsetup/.config/archsetup/shell -t 80 --no-color`.
The prior Wayland socket was `wayland-1`; rediscover after boot.
Host approval prefix for SSH to this test port is already saved.
