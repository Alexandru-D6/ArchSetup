Test them in stages. Your installed helpers still predate the fixes, so first reapply your profile:

./setup.sh desktop-apply -e @inventory/profiles/LittleArchy.yml --ask-become-pass
./setup.sh desktop-verify -e @inventory/profiles/LittleArchy.yml --ask-become-pass

Substitute your usual profile if different. Save your work and confirm you can log in through Ctrl+Alt+F3 before testing.

1. Correct and incorrect passwords

   Check existing failures:

   faillock --user alex

   With a clear tally, press Super+L, enter one incorrect password, then the correct password.

   Expected: the wrong password leaves everything locked; the correct password unlocks. Repeat separately with an empty password followed by the correct one. Check that Escape, application shortcuts and clicking other monitors cannot reach the desktop.

   Test native Hyprlock separately from the unlocked desktop:

   hyprlock -c "$HOME/.config/archsetup/theme/hyprlock.conf"

   Repeat the same password checks.
2. Power buttons

   With archsetup_desktop_lock_require_auth_for_power: true, lock again.

   Expected: Power off and Reboot are absent in both lock screens. After unlocking, they remain available in the desktop’s power menu. You can check their availability without actually shutting down.
3. The recording-related locking fix

   From an unlocked desktop terminal, run:

   (sleep 5; "$HOME/.config/archsetup/bin/desktop-action" lock) &
"$HOME/.config/archsetup/bin/desktop-action" record-region

   Leave the region selection unfinished.

   Expected: the lock screen appears after roughly five seconds despite the pending selection. Authenticate, then cancel any remaining selection with Escape.
4. Actual greetd authentication

   Save your work and log out normally. At the greeter, try one incorrect password, then the correct one.

   Expected: rejection first, followed by a successful session launch.

   Your current boot configuration automatically starts a locked session, so entering a password on that startup lock screen tests the locker’s PAM service. Logging out to the greeter tests greetd itself.
5. Suspend and resume

   From an unlocked desktop:

   systemctl suspend

   Wake the machine.

   Expected: the session is locked before you can interact with applications, all monitors remain protected, and the correct password unlocks normally. A persistent black screen is a recovery failure—our earlier VM suspend test encountered that problem, so save everything beforehand.
6. Account lockout — preferably in a disposable VM

   Your current policy uses defaults: three failed attempts within 15 minutes, followed by a 10-minute lockout. Correct passwords should also be rejected during that lockout. Linux-PAM policy reference

   Only deliberately trigger this with independent administrator recovery available: the same account’s TTY login and sudo can also be affected. After testing, wait out the lockout without further attempts, or have an administrator run as root:

   faillock --user alex --reset

   Then verify that authentication succeeds again. Failure-counter commands
7. Locker crash — disposable VM only

   Lock the VM, then use SSH or another TTY to identify the lock-screen process:

   qs list -p "$HOME/.config/archsetup/lock" --any-display

   Terminate only that instance’s PID using kill -KILL PID, replacing PID with the displayed number.

   Expected: the graphical desktop remains inaccessible. The session-lock protocol requires the compositor to preserve the lock after the client dies. Quickshell documentation

   Your current allow_session_lock_restore=false can prevent the fallback from taking over. A solid locked screen protects the desktop but fails recovery; the VM may need rebooting.

Passing these checks provides evidence for those specific behaviors. It does not establish complete PAM compliance or verify account-expiry enforcement, which remains a separate limitation of the native unlock path.