# ArchSetup

Ansible setup for an installed Arch Linux system: Hyprland, a Quickshell taskbar
and window overview, Brave, VSCodium, notifications, shortcuts, themes, and Hyprlock.
The default ii-inspired theme includes a top bar, rounded windows, system typography,
and an original generated gradient background. Hyprlock uses a centered scalloped clock and
a bottom password toolbar. Desktop animations are disabled by default. The custom desktop shell has no AI
integrations.

## Install the desktop after cloning

For the full environment, use `check` and `apply` with your desktop profile:
they cover both the base command-line tools and the desktop. `desktop-check`
and `desktop-apply` are shortcuts for updating only the desktop and include its
dependencies. Verification is separate: `verify` checks the base tools and
`desktop-verify` checks the desktop. Only bootstrap/apply/upgrade install packages;
check previews changes and verify inspects the installed state.

### 1. Prepare the computer

Start from a bootable Arch Linux installation with internet access, graphics
support for your GPU, and a regular user account with a working password and sudo
access. This project does not partition disks, install Arch, create users, or
install GPU drivers. Run the following commands as the user who will use the desktop.

Open a terminal in your cloned repository:

```bash
cd ArchSetup
./setup.sh bootstrap
./setup.sh upgrade --ask-become-pass
```

`bootstrap` installs missing Ansible prerequisites and required collections. If
sudo is not installed yet, run bootstrap as root, configure sudo access for your
regular user, then return to that user for the remaining steps. `upgrade` performs
a full Arch upgrade; desktop installation does not refresh package databases.

The current desktop configuration targets **Hyprland 0.56.x**. Installation stops
if the installed compositor is outside that series; a newer series needs project
compatibility work before proceeding.

### 2. Create your machine profile

Create a profile for the currently logged-in regular user:

```bash
cat > inventory/profiles/my-desktop.yml <<EOF
---
archsetup_desktop_enabled: true
archsetup_desktop_user: "$(id -un)"
archsetup_desktop_browser: brave-browser.desktop
archsetup_desktop_install_brave: true
archsetup_desktop_quickshell_package: quickshell
archsetup_desktop_manage_login: true
archsetup_desktop_autologin_locked: true
archsetup_desktop_manage_network: false
archsetup_desktop_reduced_motion: true
archsetup_desktop_monitors:
  - {output: "", mode: preferred, position: auto, scale: auto}
EOF
```

This preserves your existing network service, detects monitors automatically,
installs Brave when missing, and boots to Hyprlock. If NetworkManager should manage
networking, set `archsetup_desktop_manage_network: true`; preflight rejects active
or enabled competing network managers. With network management disabled, the
panel's NetworkManager settings only work for interfaces it already manages.

The supplied input defaults use US keyboard variants, Super+Space layout switching,
and flat mouse acceleration. Review [desktop defaults](roles/desktop/defaults/main.yml)
and override `archsetup_desktop_input` in your profile if needed.

**Already using LittleArchy?** Skip profile creation and replace
`my-desktop.yml` with `LittleArchy.yml` in every command below. That profile is for
user `alex` and already selects Brave, automatic monitors, and disabled animations.

### 3. Preview changes

```bash
./setup.sh check \
  -e @inventory/profiles/my-desktop.yml --ask-become-pass
```

Review the diff before applying. Check mode predicts package installation; it does
not download/build Brave or VSCodium or start services that have not been installed yet.

If preflight detects an existing **unmanaged** Greetd configuration or ArchSetup
profile, review those files and add `archsetup_desktop_adopt: true` to your machine
profile, then repeat the preview. Adoption backs up existing configuration before
replacing it. A competing display manager needs a separate migration; this role
will not stop your current graphical session.

### 4. Install

```bash
./setup.sh apply \
  -e @inventory/profiles/my-desktop.yml --ask-become-pass
```

The installer creates `~/.config/archsetup`, registers the desktop session, and
configures Greetd for the next boot. Your existing `~/.config/hypr` is retained.
Browser web/HTML associations are updated to Brave.

Kitty uses the desktop theme from shortcuts, the app launcher and command-line
launches, with window/tab close confirmation disabled. The installer links
`~/.config/kitty/kitty.conf` to the managed theme and saves an existing configuration
once as `~/.config/kitty/kitty.conf.pre-archsetup`.

Missing Brave is built from a reviewed, pinned AUR `brave-bin` revision as your
regular user, with source checksum verification, then installed through pacman.
No AUR helper or passwordless sudo is required. The first installation downloads
the browser archive and needs temporary disk space. Existing Brave is retained;
Firefox is not uninstalled.

VSCodium is the default code editor for Super+C, the tools menu and editing shortcut
configuration. Missing VSCodium uses the same reviewed, pinned AUR build workflow
(`vscodium-bin`); existing installations are retained. Override
`archsetup_desktop_code_editor` in your profile to select another installed editor.

If package installation reports stale metadata or pending updates, run
`./setup.sh upgrade --ask-become-pass`, then repeat the preview and installation.

### 5. Verify and reboot

```bash
./setup.sh verify --ask-become-pass
./setup.sh desktop-verify \
  -e @inventory/profiles/my-desktop.yml --ask-become-pass
```

Continue only after verification succeeds. Save your work, note any Greetd backup
path shown during installation, then reboot:

```bash
sudo reboot
```

Greetd starts your Hyprland session in locked mode. **Unlock Hyprlock with your
regular user's password.** Greetd's login prompt is the fallback after logout or
session failure. To require Greetd authentication at boot instead, set
`archsetup_desktop_autologin_locked: false` and reapply.

Password unlock also unlocks your GNOME **Login** keyring when its password
matches your account password. If you have an older keyring with a different
password, change it to match using Passwords and Keys (Seahorse). Installation
preserves existing keyring contents.

### 6. Try the desktop

| Shortcut | Action |
| --- | --- |
| Super+D | Application launcher |
| Super+W | Brave |
| Super+C | VSCodium |
| Super+Tab | Window overview; arrows select, Enter focuses |
| Super+Comma | Quick settings, theme and wallpaper |
| Super+N | Notification history |
| Super+L | Lock the screen |
| Super+/ | All shortcuts |
| Super + right mouse drag | Resize a tiled or floating window |
| Super+Alt+Left / Right | Shrink / grow window width |
| Super+Alt+Up / Down | Shrink / grow window height |

You can also resize windows by left-dragging their borders or gaps between tiles.
Hold a resize arrow shortcut to keep adjusting the size.

See the [complete shortcut reference](docs/desktop-shortcuts.md) for all 228 bindings,
including app launchers, local OCR/recording, window/workspace controls, shell
toggles, zoom and VM shortcut passthrough. Super+Alt+F1 restores desktop shortcuts
when passthrough is enabled.

The Power menu's Shutdown, Reboot, Suspend and Logout actions run immediately
when selected, without a second confirmation prompt.

Check mouse feel, display resolution/refresh rate, audio and Bluetooth. Save your
work before testing suspend. The QEMU test guest has a reproduced virtual GPU
resume hang; physical GPU suspend/resume remains unverified. Automatic Brave
installation still needs an end-to-end package-install test. The boot-to-Hyprlock
flow and keyring-unlock PAM result were exercised in the VM.
See [validation results](docs/desktop-validation.md)
and the [latest implementation state](docs/IMPLEMENTATION-STATE.md).

If the graphical session fails, switch to a TTY with Ctrl+Alt+F3 and log in. Restore
the recorded Greetd configuration backup if needed. See
[ownership and recovery](docs/hyprland-desktop.md#ownership-and-recovery).

## Apply later changes

Update this repository on the target computer, retain your machine profile, then
repeat **check → apply → verify → desktop-verify** with the same profile on check,
apply and desktop-verify. For desktop-only changes, use **desktop-check →
desktop-apply → desktop-verify** instead; these still install desktop dependencies.
Log out and back in to refresh all desktop components; reboot for changes to the
boot login flow. Reapplying an unchanged installation should report `changed=0`.

System upgrades are explicit (`./setup.sh upgrade --ask-become-pass`). Brave and
VSCodium are AUR packages: maintain them through your AUR update workflow separately;
desktop reapplication does not upgrade existing installations. User wallpaper/theme choices
and `overrides.lua` are retained. See the [desktop guide](docs/hyprland-desktop.md)
for configuration details and current feature limits.

## Optional command-line tools

To install the additional command-line tool set without enabling the desktop, run:

```bash
./setup.sh bootstrap
./setup.sh check
./setup.sh apply
./setup.sh verify
```

`bootstrap` installs Git, Python, Ansible, and sudo if missing. Because Arch only
supports full upgrades, that initial prerequisite installation uses `pacman -Syu`.
`apply` does not refresh package databases or upgrade packages; it only ensures the
declared tools are present. Use `./setup.sh upgrade` separately for a deliberate
full system upgrade. Supply normal Ansible options after each command, such as
`./setup.sh apply --ask-become-pass`.

Run bootstrap as root when sudo is not yet installed. Later commands can run as a
regular sudo-enabled user. The first `apply` needs current package metadata; if
pacman cannot install a missing tool because the local metadata is stale, run the
explicit upgrade command and retry.

To change the tool set, edit
[inventory/group_vars/all.yml](inventory/group_vars/all.yml). Removing a name from
the installation list leaves an already installed package in place. To uninstall a
package, add it to `archsetup_cli_packages_absent` and run `./setup.sh apply`.
The removal list takes precedence, so adding `zip` there removes it even if it is
also included in the default installation list. Removal uses pacman's normal
dependency checks and preserves modified package configuration as `.pacsave`.


## Disposable Arch VM

Use the official Arch cloud image to test safely in a local QEMU virtual machine.
Install the host dependencies first:

```bash
sudo pacman -S qemu-desktop cloud-image-utils
```

Then create an already-installed Arch VM and connect to it:

```bash
./scripts/vm.sh init
./scripts/vm.sh start
./scripts/vm.sh ssh
```

`init` creates a 30 GB virtual disk by default. It downloads the official image and
its SHA-256 file, verifies the image, creates a local SSH key under `vm/keys/`, and
builds a writable overlay. The VM is available only at `127.0.0.1:2222`; its console is recorded in
`vm/run/console.log`. The `archsetup` VM user has passwordless sudo solely to make
this disposable test environment convenient.

Use `./scripts/vm.sh status`, `console`, and `stop` to manage it. Run
`./scripts/vm.sh reset` to discard the writable VM disk and start again with a
fresh machine. Generated images, disks, keys, and logs are ignored by Git.

Set a different initial size with `ARCHSETUP_VM_DISK_SIZE=40G ./scripts/vm.sh init`.
To expand an existing stopped VM and its root filesystem, use, for example,
`./scripts/vm.sh resize 30G`. QCOW2 is sparse, so the host file grows as the guest
writes data rather than occupying its full virtual capacity immediately.


See the [development plan](docs/development-plan.md) and [desktop project plan](docs/hyprland-project-plan.md) for project scope.
