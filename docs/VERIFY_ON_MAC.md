# First run on a Mac

The app has compiled and run on one Mac (single taps worked, multi-tap did not, which 0.9.2 targets). Not everything has been run yet. This is the order to find out what is broken, cheapest checks first. Stop at the first failure and fix or report it before going on.

## 1. Build and unit tests (about 5 minutes)

```sh
swift --version        # needs 6.0 or newer
swift test
```

Expected: 191 tests pass. TapCore uses only Foundation, so these should behave the same as on Linux.
If a test fails, the test and the detector disagree. Tell me which one. The detector was modelled in Python and agreed with the tests, so a failure points at a Swift translation slip.

```sh
swift build -c release
```

Expected: the Bingo app target compiles. Compile errors here are likely, because the app code was never given to a compiler. Typical suspects: concurrency annotations, SwiftUI initializer labels, `IOKit` types. Send me the first few errors verbatim.

## 2. Build the app

```sh
./scripts/build.sh --unsigned
open dist/Bingo.app
```

Expected: a hand icon appears in the menu bar and the welcome window opens.

## 3. Does the sensor work?

Open the welcome window, step 1, or General, "This Mac".

| You see | Meaning |
|---|---|
| Motion sensor found, gyroscope found | Best case |
| Motion sensor found, no gyroscope | Everything works except possibly zones |
| No motion sensor found | Report your model. The sensor lookup may differ on your Mac |
| Opening failed with a code | Possibly needs root or an entitlement. Report the code |

If the accelerometer is not found: `ioreg -l -w0 | grep -i AppleSPUHID` and attach the output to a hardware report.

## 4. Do taps register? (Tuning screen)

1. Open Tuning. The waveform should show a small noise line.
2. Tap the palm rest. A spike should appear and "Try it" should show "Single tap".
3. Tap twice, three times, four times and five times quickly. Each should show the right count.
4. If nothing registers, drag Sensitivity up. If it registers by itself, drag it down.
5. Press Calibrate and follow the steps.

Targets from the roadmap: 4 taps recognized 8 times out of 10.

## 5. Typing guard

1. With test mode on (the default after the welcome tour), type in a text editor for five minutes with the Mac on a desk, then on your lap.
2. Open Activity. Expected: no gestures logged from typing. Any that did appear, note when and what you were doing.
3. Then tap once while not typing. It should appear.

## 6. Actions

Turn off test mode in General first, and save your work. Then test each action once from Gestures. Give permission to Accessibility when asked, then retry.

- [ ] copy, paste, cut, undo, redo, select all
- [ ] play and pause, next, previous (use Music or a browser video)
- [ ] volume up, volume down, mute
- [ ] microphone mute (check System Settings, Sound, Input)
- [ ] brightness up and down
- [ ] sleep display, dark mode, screen saver
- [ ] keep awake on and off (`pmset -g assertions` should list "Bingo keep awake")
- [ ] lock screen
- [ ] screenshots, macOS shortcuts: area, full, toolbar
- [ ] captures (need Screen Recording; quit and reopen Bingo after allowing it): full screen saved, full screen copied, area saved, area copied, window saved, area and full screen with markup in Preview
- [ ] Screenshots profile: 3 taps saves the full screen to your screenshot folder
- [ ] open an app, open a link, Mission Control, show desktop, hide other apps
- [ ] emoji picker, paste a snippet (your clipboard should come back afterwards)
- [ ] Wi-Fi toggle (turn it back on!)
- [ ] Bluetooth toggle and audio output (need `brew install blueutil switchaudio-osx`)
- [ ] eject drives (use a spare USB stick)
- [ ] run a Shortcut, run a Terminal command

## 6b. Dictation

0. Setup, "Check that dictation can type": press it and click into a text box in the app you care about. The test sentence should appear there. If it does not, dictation cannot type in that app: tell me which app.

1. Setup: press Allow on Microphone and Speech Recognition (and Accessibility if it is not on).
2. Gestures, Add starter profiles, then switch to the Voice profile and turn test mode off.
3. Click into a text field (Notes, a browser box). Double tap: a "Listening" pill should appear.
4. Say a sentence. Words should appear in the pill. Double tap again: the pill goes and the words appear in the field while you speak and nothing touches the clipboard.
5. Try: Accessibility off (words go to the clipboard), a double tap with Microphone off (a clear message), talking for more than 2 minutes (it stops by itself).

## 6c. Workflows

1. Gestures, Add a gesture, Workflow from a template, Desk after restart. Save it.
2. Open it again and press "Check against right now". It should say whether "if 1" matches and show the facts (time, minutes since start, battery, displays). Compare them with reality.
3. Change the condition (for example "The Mac just started" to 100000 minutes) and check again: it should now match.
4. With test mode off, make the gesture and look at Activity: it should say "Double tap · if 1" when a branch ran.
5. Try a second branch and "any of these". Try switching the workflow off: the gesture's own actions must remain.

## 6d. Desk

1. Open a few apps and arrange them. Desk, "Save current windows". The list should show those apps with sizes.
2. Move the windows around, then press "Apply now" (Accessibility must be on). They should return. The result line says how many were arranged and which were not.
3. Add a gesture with "Arrange the front window", position "left half". Make it with a window in front: it should snap to the left half.
4. Add "Apply a saved window layout" with the layout name. Quit one of the apps, run the gesture: the app should open and move into place.
5. The "Desk after restart" template: add it, and use "Check against right now". Restart the Mac and double tap soon after: apps open and arrange.

## 7. Everything else

- [ ] Profiles: switch from the menu bar, rename, duplicate, delete, export, import
- [ ] Import a profile with a shell command: it must arrive switched off
- [ ] Per-app gestures: add an app, confirm its double tap wins while it is in front
- [ ] A chain of two actions with a pause
- [ ] Risky action on 2 taps is blocked until confirmed
- [ ] Soft and hard taps after calibration
- [ ] Rhythm: record, bind, trigger
- [ ] Zones: set up, check the test step, bind a left tap and a right tap
- [ ] Record 10 seconds in Activity, Lab, then replay the file
- [ ] Open at login, then log out and in
- [ ] Quit and reopen: settings are kept
- [ ] Sleep and wake the Mac: taps still work after wake

## 8. Signed release (needs your Apple Developer ID)

See RELEASING.md. After notarization, check on a second Mac that the downloaded app opens without warnings and that taps work. Library validation under the hardened runtime is the likeliest thing to fail: if the app crashes at launch with a code signature error mentioning Sparkle, add the `com.apple.security.cs.disable-library-validation` entitlement to entitlements.plist and rebuild.

## Reporting

For anything that fails, send: Mac model and chip, macOS version, the step number, what you expected, what happened, and for tap problems a 10 second recording from Activity, Lab.
