# Changelog

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
