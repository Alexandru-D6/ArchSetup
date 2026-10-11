# Resume checkpoint — 2026-10-11 (latest)

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
