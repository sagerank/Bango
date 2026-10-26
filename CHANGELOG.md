# Changelog

## 0.9.4

Setup that cannot be missed, and a proper installer window. **Not yet seen running on a Mac by the author.**

- Cause of the silent start in 0.9.3: settings survive an uninstall, so the app believed the welcome tour was done, hid its window and had no permissions, because macOS forgets them for every new unsigned build. Now the window opens by itself, on the permissions step, whenever the tour was never finished, or this build has not been through setup and Accessibility or Screen Recording is missing
- Setup starts asking by itself when the permissions step opens, with a Skip button for each item
- New Setup page at the top of the sidebar, with an orange dot while something is missing, showing the sensor, its rate, and every permission
- The menu bar popover shows "Setup is not finished" with a Finish setup button
- Clicking the app icon again, or opening it from Applications while it runs, brings the window back
- The disk image has a designed window: background, arrow, TapDeck on the left and the Applications shortcut on the right. If the styling tool fails, a plain disk image is made instead
- 4 new tests (103 in total) for when setup must appear

## 0.9.3

One-screen setup and animated feedback. **The new interface code is compiled by CI but has not been seen running on a Mac by the author. Treat the look and the permission flow as unverified until you have tried them.**

- Setup asks for everything in one place: Accessibility, Automation for System Events (dark mode) and Finder (eject), Screen Recording, access to the screenshot folder, and open at login. One "Set up everything" button asks in the order that needs the fewest trips to System Settings, notices when each switch is flipped, and shows what each permission is used for
- Each permission shows which of your gestures use it. Microphone mute needs no permission, because it only sets the input volume
- Screen Recording shows "Restart TapDeck" once, since macOS applies it only after a restart
- "Clear TapDeck's permissions" for the case where a new build looks allowed but is not. macOS ties each permission to the exact app, and an unsigned build counts as a new app every time it changes
- The same panel is in General, replacing the old two-row list
- Screenshots flash the screen like a shutter after the picture is taken, and the confirmation shows a thumbnail of the saved file
- Microphone mute and unmute have their own animation (rings when live, a slash when muted)
- Opening an app shows that app's own icon, so voice and dictation apps you launch by name show up clearly
- Other actions get a springy icon. Animations stop when macOS Reduce Motion is on
- 24 new tests (99 in total) for the permission plan and the animation choice

## 0.9.2

Fixes from the first multi-tap recording on a real MacBook (800 Hz, 26 taps at about 0.21 s apart). Before: 1 of 26 taps found. After: 26 of 26, in a replay of that recording. **Still checked against one recording from one Mac, not yet confirmed live in the app.**

- The ring-prediction filter from 0.9.1 is removed. On real data it scored follow-up taps at 0.02 to 0.03 against a gate of 0.04, so it rejected them. Real taps ring for only 0.1 to 0.2 s, much shorter than the simulation assumed
- Every tap must now jump to at least 1.5 times the ringing level of the previous 40 ms. Measured: taps 2.1 to 3.0, ringing alone below 1.0. A smoothly building vibration scores about 1 and is ignored
- The noise floor now follows the signal at a fixed speed per second. It used to step per sample, which at 800 Hz made it about 8 times too fast, so a tap raised its own threshold from 0.03 to 0.13 before it was accepted
- The noise floor stays put while a just-accepted tap is still ringing
- The "Mac was moving" lockout no longer counts the Mac's own tap ringing or the slow push of the arriving tap as motion. This locked out every gesture after the first
- Wiggles in the ringing of a tap are no longer listed as ignored bumps
- Tuning diagnostics show "rise" in place of "surprise"
- The recording contains gyroscope data on every sample, so the gyroscope is readable on that Mac
- 9 new tests (84 in total): the real recording as a fixture, replay at half the sample rate, and false-positive checks for steady vibration, lifting and carrying, setting down, typing on the table and long ringing

## 0.9.1

Fixes found by running 0.9.0 on a real MacBook, where only single taps were recognised. **The fix is checked against simulated signals only, not yet against a real Mac.**

- Follow-up taps are now judged by a prediction filter that learns the ringing of the previous tap and flags what it cannot predict. Before, the leftover ringing made the detector reject every tap after the first.
- The noise floor no longer rises while a tap sequence is open
- Tuning shows why a bump was ignored (too close, Mac moving, too gradual, typing) and how often
- Seven new capture actions: full screen saved or copied, area saved or copied, window saved, and area or full screen opened in Preview for markup. They use the macOS `screencapture` tool and need Screen Recording
- New "Screenshots" starter profile: 1 tap area to clipboard, 2 area saved, 3 full screen saved, 4 area and markup, 5 capture toolbar
- "Add starter profiles" button in Profiles adds starter profiles missing from an existing setup
- Tests for long ringing and for the new profile and actions

## 0.9.0

First complete version, written through the roadmap's v2. **Not yet compiled or run on a Mac.**

- Tap detection for 1 to 5 taps with a two-layer typing guard
- 36 actions, action chains with pauses, per-app gestures, profiles
- Soft and hard taps, tap rhythms, tap zones (experimental)
- Test mode, practice and calibration, activity log
- Profile import and export with code-running steps switched off on import
- CSV record and replay
- Launch at login, menu bar popover, dark interface, confirmation toast
- 66 unit tests on synthetic sensor signals, CI for Linux and macOS
- Build, notarize and optional update scripts with no baked-in identity or feed
