# Hyprland desktop implementation project

Status: planned, with local discovery completed on 2026-10-10. This document is
the implementation backlog; it does not install packages or change the live desktop.

## Decisions and scope

Build an optional ArchSetup desktop profile inspired by
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland), using Hyprland and a
curated Quickshell graphical shell. Include window management, taskbar, launcher,
overview, notifications, quick settings, shortcuts, appearance, login and locking.
Remove AI functionality from the deployed source and dependency manifest, rather
than merely hiding its buttons.

The latest user instruction permits Lua. Use native Lua configuration for the
selected modern Hyprland release; do not downgrade to a historical stack.
[Hyprland documents the configuration transition beginning with 0.55](https://wiki.hypr.land/Configuring/Start/).
Pin the reviewed dotfiles commit and shell version, and record the tested package
versions. Do not hold individual Hyprland libraries back during Arch upgrades:
test full upgrades in a VM and advance the compatible stack together.

Reuse Greetd for login and Hyprlock for session locking. A login manager is not a
prerequisite for Hyprlock: they serve different stages of the session. Greetd is
already installed here; the new-machine role must install it when absent.
See [Greetd](https://github.com/kennylevinsen/greetd) and
[Hyprlock](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/).

## Local discovery and preference baseline

Read-only inspection found the following. These are observed files and package
records, not proof that every setting is effective in the running compositor.

| Item | Observed state | Implementation decision |
| --- | --- | --- |
| Hyprland | `0.56.2-1`; `hyprland.lua` exists, `hyprland.conf` absent | Native Lua modules, validated against the selected version |
| Shell | `illogical-impulse-quickshell-git 0.1.0.r1-8` installed | Resolve a compatible, reviewed build and immutable upstream source revision |
| Lock/idle | Hyprlock `0.9.6-2`, Hypridle `0.1.8-1` | Reuse these components; verify configuration and authentication |
| Login | Greetd `0.10.3-2`; display-manager symlink selects Greetd | Ensure Greetd exists on fresh installs; do not add a competing manager |
| Browser | `xdg-settings get default-web-browser` returns `brave-browser.desktop` | Brave is authoritative; upstream's Chrome-first fallback is not the preference |
| Pointer | `follow_mouse=1`, `off_window_axis_events=2`, `accel_profile=flat`, `force_no_accel=1`, `sensitivity=0.0` | Preserve semantic values in valid Lua |
| Keyboard | `us,us`; variants `euro,altgr-intl`; `grp:win_space_toggle`; numlock enabled; repeat delay 250/rate 35 | Preserve and reserve Super+Space for layout switching |
| Touchpad | Natural scroll, disable while typing, clickfinger enabled | Preserve; use active-file scroll factor `0.7` as provisional baseline |
| Touchpad discrepancy | Old `custom/general.conf` has scroll factor `0.5`; current `hyprland/general.lua` has `0.7` | Confirm effective value during implementation before adoption |
| Displays | Legacy monitor file specifies DP-2, 2560×1440 at 144 Hz, scale 1; HDMI-A-1 disabled | Host-only candidate; verify current Lua/runtime state; VM uses automatic output |

Sources: `/home/alex/.config/hypr/custom/general.conf`,
`hyprland/general.lua`, `hyprland/variables.lua`, `custom/variables.lua`,
`monitors.conf`, package records, and `/etc/greetd/config.toml`.
The current Lua input section contains bare `flat`; render the profile as the
string `"flat"`, and check effective settings instead of copying source blindly.
Legacy cursor preferences are candidates for version validation, not unconditional
settings: hardware cursors disabled, zoom 1, rigid zoom disabled, AA disabled,
hotspot padding 1.

Greetd currently launches `start-hyprland --config /etc/greetd/hyprland.conf` as
its greeter and has an initial autologin session for `alex`. Verify that greeter's
configuration against the installed compositor. The proposed managed profile uses
authenticated login by default, with autologin an explicit optional variable.
Adoption must show this behavior change in its diff and preserve a backup.

## Desktop specification

| Area | Required behavior |
| --- | --- |
| Windows | Dwindle tiling, floating toggle, fullscreen, directional focus/move, mouse drag/resize, workspaces 1–10 and scratch workspace |
| Taskbar | Bottom panel with launcher, workspace indicators, pinned/running applications, active/urgent indicators, tray, clock and status controls; click to launch/focus and context menu to close |
| Overview | Workspace/window previews and keyboard navigation; selecting a window focuses its workspace |
| Launcher | Local application search, deterministic calculator, emoji and clipboard actions; no model-backed search |
| Quick settings | Audio volume/output/microphone, network, Bluetooth, brightness when supported, idle inhibition and session actions |
| Notifications | One notification daemon, history, dismissal, do-not-disturb and actionable notifications |
| Utilities | Region/full screenshots, color picker, media controls and clipboard history with clear-history action |
| Session | Authenticated login, manual lock, idle lock, lock before suspend, resume and logout; power actions require a deliberate UI choice |
| Integration | Polkit agent, desktop portal, screen sharing, keyring integration and default application associations |

Design direction: Material-inspired rounded surfaces, a coherent wallpaper-derived
palette with a fixed fallback, dark/light modes, readable text and distinct focus
indicators. Initial design tokens: panel height 44 px, outer gap 8 px, window radius
12 px, surface radius 16 px, 2 px active border, 150–250 ms transitions. These are
project choices, not claims of exact upstream values. Use configurable fonts,
icons and cursor assets with recorded licenses. Include reduced motion and an
opaque/high-contrast option. Apply shared tokens to shell, compositor, terminal,
launcher and lock screen. Keep login visually consistent without requiring a
user's session services or home-directory access.

Taskbar behavior must work at 100%, 125% and 150% scale, on multiple outputs and
after hotplug. Panel reserves usable screen space and avoids duplicate trays.
Battery and brightness controls disappear when unsupported. Initial scope uses
one coherent shell style rather than shipping every upstream alternative.

## Proposed shortcuts

Generate configuration and the shortcut help view from one mapping. Audit every
binding against the retained shell's IPC interface; do not guess upstream commands.

| Shortcut | Action |
| --- | --- |
| Super+Enter | Terminal |
| Super+W | Default browser through XDG; resolves to Brave |
| Super+E | File manager |
| Super+D | Application launcher |
| Super+Tab | Overview |
| Super+/ | Shortcut help |
| Super+Q | Close focused window |
| Super+F / Super+Shift+F | Fullscreen / floating toggle |
| Super+arrows / Super+Shift+arrows | Focus / move window |
| Super+1…9,0 | Workspaces 1…10 |
| Super+Shift+1…9,0 | Move window to workspace |
| Super+S | Scratch workspace |
| Super+left drag / right drag | Move / resize window |
| Super+V | Clipboard history |
| Super+N | Notification center |
| Super+Comma | Quick settings |
| Super+L | Hyprlock |
| Super+Shift+Escape | Session menu |
| Print / Shift+Print | Region / full screenshot |
| Media and brightness keys | Playback, volume/mute, microphone mute and brightness |
| Super+Space | Existing keyboard layout switch, reserved |

Volume/media bindings may work while locked; application, clipboard and shell
launchers must not. Clipboard contents must never be sent to remote services.

## Source selection and AI removal

Select a compatible upstream commit during milestone H1, record its SHA, license,
patch set and shell/package compatibility in a source manifest. Do not run the
upstream installer wholesale. Build a curated, independently deployable shell
under a distinct configuration name such as `archsetup`, retaining license and
attribution for copied code. Exact commit and package checksums remain unresolved
until the compatibility spike; no moving `main` reference is a deployment pin.

The local shell confirms concrete audit targets: `services/Ai.qml`,
`services/ai/`, `services/GoogleCloud.qml`, `services/gCloud/`,
`services/Translation.qml`, and Hyprland's `scripts/ai/` and AI mouse binding.
Inspect the chosen upstream revision because its paths may differ.

Removal includes chat/model services, Gemini/OpenAI-compatible/Mistral/Ollama
providers, assistant panels, API key settings, model selection/downloads,
selection-to-AI actions, screen translation/Lens entry points and AI editor
fallbacks. Remove associated imports, singletons, settings schema fields,
launcher providers, IPC handlers, scripts, documentation links in the UI and
dependencies used only by those features. Remove now-unused cloud credential
helpers after checking other consumers. Exclude optional online content modules
from the initial profile to keep the audit bounded.

Trace the QML import graph and process/network launch sites, not just filenames.
Scan deployed files and dependency lists for provider names, endpoints and model
commands; review matches so ordinary words do not cause false positives. Launch
every retained surface with networking unavailable and check QML logs for missing
imports. Observe network/process activity with networking available as well.
Acceptance requires no AI controls, requests, model processes or credentials.
Do not remove unrelated existing applications or personal credentials globally.

## Planned Ansible implementation

Extend the existing local execution model and idempotency contract. Desktop is
opt-in, disabled by default; the existing CLI playbook behavior must remain intact.

| Planned component | Responsibility |
| --- | --- |
| `roles/desktop_preflight` | User/home discovery, GPU/session checks, package compatibility, existing display manager and configuration conflicts |
| `roles/desktop_packages` | Official packages plus reviewed unprivileged AUR builds only where needed; explicit dependency manifests |
| `roles/hyprland` | Lua modules for input, apps, monitors, bindings, rules, appearance and session startup |
| `roles/desktop_shell` | Curated Quickshell files, assets, theme tokens and required services |
| `roles/session_security` | Hyprlock, Hypridle, PAM integration checks and suspend/lock orchestration |
| `roles/display_manager` | Greetd and a greeter, session entry, authentication default and boot enablement |
| `playbooks/desktop-verify.yml` | Read-only package/configuration/service checks and session diagnostics |
| `inventory/host_vars/` | Explicit personal input/browser values and machine-specific display overrides |

Expose variables for enablement, target user, source revision, browser desktop ID,
input settings, display layout, theme, shortcuts, login/autologin and idle timeouts.
Resolve the actual account home; do not hardcode `/home/alex` in reusable roles.
Manage only declared files; keep personal overrides separate. Back up existing
files during explicit adoption, and record each managed path and previous state.
Do not recursively copy the current user configuration or include credentials.

Candidate package groups, to validate against selected Arch repositories:
Hyprland, Quickshell/Qt runtime, Hyprlock, Hypridle, Greetd and greetd-tuigreet,
PipeWire/WirePlumber, NetworkManager, BlueZ, a Polkit agent, portal backends,
wl-clipboard/cliphist, grim/slurp, playerctl, brightnessctl, terminal/file manager,
fonts/icons and a wallpaper/color generator. Verify existing providers before
enabling services. Retain Brave and verify its desktop entry and HTTP/HTTPS
associations; resolve its package source separately for fresh installs.

Use a simple tuigreet login initially so login does not depend on the custom
Quickshell UI. Register and test the selected Hyprland session command rather
than assuming `start-hyprland` exists in every package version. Enable Greetd for
next boot after validation; never restart the active display manager during apply.
If another manager is found, report the planned service transition before adoption.

Start the shell, idle daemon, clipboard watcher and Polkit agent exactly once per
session; tie their lifetime to logout and ensure restarts do not create duplicates.
Avoid competing notification or authentication agents. Initial idle policy:
lock after 5 minutes, displays off after 10, no automatic suspend by default.
Manual suspend must wait for successful locking; test the selected Hypridle
integration and inhibitor behavior. Restore displays on resume and preserve PAM
defaults unless a demonstrated integration change is necessary.

## Sequenced backlog and acceptance gates

| ID | Depends on | Deliverable and completion evidence |
| --- | --- | --- |
| H1 | — | Compatibility/source spike: immutable upstream SHA, package manifest, licenses, retained QML graph and AI removal patch; a minimal shell loads without errors |
| H2 | H1 | Optional roles and configuration ownership/adoption support; check mode changes nothing, CLI-only runs unchanged |
| H3 | H2 | Hyprland session, correct pointer/keyboard/browser, monitor fallback, basic bindings and portal/Polkit; login from TTY works and compositor reports no config errors |
| H4 | H3 | Taskbar, launcher, overview, notification center, quick settings and utility actions; all shortcuts and click actions exercised |
| H5 | H4 | Shared theme, wallpaper, fonts, scaling, hotplug and accessibility; visual checks at required scales, no missing icons or clipped text |
| H6 | H3 | Greetd, authenticated login, Hyprlock and Hypridle; wrong password rejected, correct password accepted, suspend/resume remains locked, logout returns to greeter |
| H7 | H4,H5,H6 | Fresh VM installation, unchanged second apply, drift repair, offline shell test and complete AI audit; record logs and versions |
| H8 | H7 | Workstation adoption with backups, reviewed diff and recovery instructions; reboot and hardware acceptance, then second apply reports changed=0 |

H1 is the first implementation task. Do not claim compatibility or a usable
desktop before its recorded checks pass. Package source/AUR selection and the
effective touchpad value are outstanding technical discovery items.

## Verification and recovery

Use syntax/lint checks for implemented Ansible, shell, Lua and QML files and
validate rendered compositor configuration with the chosen version's supported
validation mechanism. Exercise runtime IPC and QML imports in a real session.
Add meaningful tests for disabled-desktop behavior, no AI source/dependency
reachability, configuration adoption and duplicate-free service startup.

The existing disposable VM workflow needs a graphical, accelerated display path
for desktop acceptance. SSH/package tests alone cannot validate the shell,
locking or GPU behavior. Snapshot before provisioning, test first and second
apply, repair a modified/deleted managed file, reboot through Greetd and test
authentication. Record config errors, journal output and screenshots without
capturing passwords or private notifications. Hardware tests cover DP-2 at 144 Hz,
mouse feel, browser associations, sound, screen sharing and suspend/resume.

Before workstation adoption, save the existing managed configs, default-browser
associations, display-manager enablement, package versions and source revision.
Keep a working TTY login. Recovery restores the previous configuration and login
service from TTY, disables the new desktop services and reboots deliberately.
File backups do not undo package changes: use a system/VM snapshot for a stack
rollback, not a partial downgrade of Hyprland and its libraries. Rehearse recovery
in the VM and document exact paths/commands once roles are implemented.

Completion means the full retained desktop works without AI integrations, uses
the requested personal settings, authenticates and locks correctly, survives a
reboot and converges on a second Ansible apply with `changed=0`, `failed=0`.
