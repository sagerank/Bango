# TapDeck roadmap

## Status (version 0.13.0)

All milestones through v2 are written. **None of the app code has been compiled or run on a Mac yet.**
It was written on a Linux machine with no Swift toolchain. What has been checked:

| Check | Result |
|---|---|
| Syntax of all 48 Swift files, with a Swift parser | Clean |
| Detector, grouping, rhythm and zone logic, with an equivalent Python model on synthetic signals | Behaves as the tests expect |
| `swift test` (66 tests) and `swift build` | **Not run.** First thing to do on a Mac, see docs/VERIFY_ON_MAC.md |
| Sensor reads, key posting, every action, zones, launch at login, notarization | **Not run** |

Delivered against this plan: 4 and 5 taps, two-layer typing guard, 43 actions, profiles with per-app
overrides, action chains with delays, 24 hour test mode, practice and calibration, JSON import and
export with code-running steps disabled, CSV record and replay, tap zones, soft and hard taps, rhythm
patterns, launch at login, native key posting instead of osascript, own signing and update setup.

Not delivered: dictation, switch-app and URL-scheme-trigger actions; a VoiceOver and Reduce Motion
audit; contributor hardware reports (docs/HARDWARE.md starts empty).

Blocking items: 3 (update feed) and 4 (rename) are done in code. 1 (nocnoc licence) and 2 (provenance)
are **still open** and need a message to the nocnoc author before a public release. The final name is
still undecided; TapDeck is a working title.

The text below is the original plan, kept for reference.

---

Working title. Choose the final name before the first commit (see Naming).

## Pitch

A free, open-source menu bar app that turns taps on an Apple Silicon MacBook into actions. Up to four taps, typing protection, profiles, a dry-run mode, and a codebase anyone can clone, build and test.

## Where it can differ

| Gap in existing apps | Our answer |
|---|---|
| Best ones are paid or closed | Free, MIT, build from source |
| Most stop at 3 taps | 4 taps in v1.0 |
| False triggers while typing or moving | Typing guard, motion lockout, dry-run mode, destructive actions only on 4 taps |
| Contributors cannot test a hardware detector | Synthetic test signals plus record and replay (CSV) |
| Short action lists | 40+ actions, plus Shortcuts, shell, URL scheme |
| Neon or cluttered UI | Black, one accent, 8pt grid |

Honest note: none of this is a moat. Any competitor can copy it. The value is being free, open and well tested.

## Base: fork of nocnoc (verified by reading all 3,238 lines)

Already there: in-process sensor read via IOKit HID (no root daemon), adaptive detector with motion lockout, single/double/triple tap, menu bar app, dashboard, waveform, calibration wizard, launch at login (SMAppService), Sparkle updates, notarization script, dark theme.

Missing: 4+ taps (count capped at 3), any typing suppression, gyroscope, profiles, per-app rules, chains, most actions, detector tests.

Weak spot: every key action spawns osascript. v1.0 replaces that with native CGEvent posting (faster, no Automation prompt, still needs Accessibility).

## Blocking items before the first commit

1. Licence: no LICENSE file in nocnoc, only a README line saying MIT. Ask the author to add one. Keep their notice.
2. Provenance: identifiers use "tryknock", a commercial app. Ask the author how they relate. If no answer, switch base to Slaptop (clear MIT file, but needs a signing team for its root helper).
3. Update feed: build.sh and generate-appcast.sh use the original author's bundle ID, feed URL and Sparkle account. Replace all, or our app updates itself to their binary.
4. Rename every Knock, nocnoc and tryknock identifier and string, including the UserDefaults key and the dispatch queue label.

## Architecture

```
Sources/AppName/
  Sensor/      SPUAccelerometerService (keep); GyroService (v2)
  Detection/   TapDetector (count up to 5), TypingGuard (new), Gesture model
  Actions/     ActionCatalog, ActionRunner (typed: keyEvent, shell, shortcut, native), ActionChain
  Profiles/    ProfileStore, AppOverrides (frontmost app via NSWorkspace)
  UI/          Theme, MenuBar, Dashboard, Onboarding, Calibration, Practice
Tests/         Detector tests, replay fixtures
```

TypingGuard uses seconds since the last keyboard or pointer event (CGEventSource idle time). It never sees which keys were pressed and needs no Input Monitoring permission.

## Action catalog for v1.0

| Category | Actions | Method | Permission |
|---|---|---|---|
| Clipboard | Copy, paste, cut, undo, redo, select all | CGEvent keys | Accessibility |
| Media | Play/pause, next, previous | Media key events | Accessibility |
| Sound | Volume up/down, mute, mic mute | AppleScript standard additions | None |
| Display | Brightness up/down, sleep display, dark mode toggle | Key events, pmset, System Events | Accessibility, Automation |
| Power | Caffeine toggle, lock screen, start screensaver | IOPMAssertion, CGEvent | Accessibility |
| Capture | Area screenshot, full screenshot, recording toolbar | CGEvent shortcuts | Accessibility |
| Apps and windows | Launch or focus app, open URL, Mission Control, show desktop, switch app, hide all | NSWorkspace, CGEvent | Accessibility |
| Input | Dictation, emoji picker, paste saved snippet | CGEvent, pasteboard | Accessibility |
| Connectivity (optional tools) | Wi-Fi toggle, Bluetooth toggle, audio output switch | networksetup, blueutil, SwitchAudioSource | None |
| Automation | Run Shortcut, shell command, URL scheme trigger | shortcuts CLI, zsh | None |

Default safety rule: lock, Wi-Fi off, Bluetooth off and eject are offered only on 4 taps unless the user overrides with a confirmation.

Excluded: camera capture of any kind.

## Milestones

Estimates are Claude's writing time. Calendar time depends on how fast you test on your Mac, because every detector change needs real taps.

| Milestone | Scope | Estimate | Acceptance (proposed targets) |
|---|---|---|---|
| v0.1 Fork | Clear the 4 blocking items, rename, LICENSE and NOTICE | 0.5 day | Builds unsigned with `build.sh --unsigned`; no original identifiers remain |
| v0.2 Detector | 4 taps, TypingGuard, detector tests | 1 day | Tests pass on synthetic signals; on your Mac, 4 taps recognized 8 of 10 tries and typing 5 minutes causes 0 triggers |
| v1.0 Release | Full catalog, profiles (Work, Media, Meeting), dry-run mode, practice screen, onboarding, JSON import/export, CI, README, notarized release | 1 to 2 days | Fresh Mac install works end to end; every action tested once on hardware |
| v1.1 | Per-app overrides, action chains with delays, record and replay | 1 day | Replay of a recorded session reproduces the same events |
| v2 | Tap zones (left, right, top) via gyroscope, soft versus hard tap, rhythm patterns | Open ended | Ships as experimental; needs a learn-your-zones step |

Dry-run mode: for the first 24 hours the app logs which action each tap would run but executes nothing. This lets a new user see false triggers before anything dangerous fires.

## Design spec

- Background #000000, surface #111113, border white at 10%, text #F2F2F3, secondary text #8E8E93
- One accent only, #0A84FF. Drop nocnoc's neon green and orange
- SF Pro, SF Symbols, 8pt spacing grid, no gradients
- One menu bar template icon; popover shows on/off, active profile, last gesture
- Settings window: Gestures, Profiles, Sensitivity, General
- VoiceOver labels, full keyboard navigation, Reduce Motion respected

## Privacy and security

- No telemetry. Only network call is the Sparkle update check, with a switch to turn it off
- No microphone, no camera, no keystroke content
- Sensor data stays in memory and is never written to disk (except explicit CSV recordings the user starts)
- Imported profiles that contain shell commands arrive disabled until the user reviews and approves each one, so a shared profile cannot run code silently
- Shell command action runs as the user and shows a warning when set

## Repository hygiene

LICENSE (MIT), NOTICE crediting nocnoc and any research reused, CONTRIBUTING, SECURITY, issue template asking for a hardware report (model, chip, macOS, did detection work), HARDWARE.md compatibility table filled by contributors, CI that builds unsigned on a macOS runner. Notarized releases are built by the maintainer with their own Developer ID, not in public CI.

Hardware note: reports conflict on base M1 support. Treat M2 and newer as supported until contributors confirm otherwise.

## Naming

Not Slapmac: SlapMac already exists, "slap" signals a prank toy, and Apple's trademark rules discourage "Mac" in a product name (verify). Unchecked shortlist: Tapkey, Thump, Tapdeck. Search GitHub, the App Store, domains and trademarks before committing.

## Not doing

Mac App Store release, silent camera capture, a root daemon unless the in-process sensor read proves unreliable on real machines.

## Needed from the owner

Final name, MacBook model and chip, whether a Developer ID certificate exists, a connected project folder.
