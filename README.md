# Bango

Tap your MacBook to control it. One tap, two, three, four or five, on the palm rest or the lid, and the action you chose runs: copy, paste, volume, play and pause, lock the screen, screenshot, keep the Mac awake, run a Shortcut, and more.

Free, open source (MIT), no account, no telemetry. Bango was called TapDeck until 0.14.

> **Status: version 1.0.0.** The tap detector was rewritten for this release and has been checked on one real MacBook recording and on simulated signals, but it has had little time on other Macs. New installs start in test mode (gestures are logged, nothing runs) until you switch it off in General. If it misses or invents taps, open Tuning and send a [hardware report](../../issues/new?template=hardware-report.yml) with the "ignored bumps" list. See docs/VERIFY_ON_MAC.md.

## What it does

- **Dictation on a double tap**: double tap to start listening, words are typed straight into the text box of the app you were in as you speak, and a second double tap stops it. The same gesture turns it on or off. Speech is recognised on this Mac, nothing is sent away
- **1 to 5 taps** mapped to actions, in profiles you switch from the menu bar (Work, Voice, Media, Meeting and Screenshots come built in)
- **Typing guard**: taps are ignored while you type or click, because typing shakes the chassis. It reads only how long ago the last key or click happened, never which key
- **48 actions**: dictation, open several apps, open files and links, arrange windows, apply a saved layout,  copy, paste, cut, undo, redo, select all, play and pause, next and previous track, volume, mute, microphone mute, brightness, sleep display, dark mode, keep awake, lock screen, screen saver, ten ways to take a screenshot (full screen or an area, saved to a file or copied to the clipboard, a window, or captured and marked up in Preview), open an app, open a link, Mission Control, show desktop, hide other apps, emoji picker, paste a saved snippet, Wi-Fi toggle, Bluetooth toggle, audio output switch, eject drives, run a Shortcut, run a Terminal command
- **Action chains**: one gesture can run several actions, with pauses between them
- **Desk setup**: save where your windows are and put them back with one gesture, open several apps in order, snap the front window to a half or third of the screen
- **If and else workflows**: a gesture can choose what runs from the time, the app in front, the battery, whether the Mac just started, and more. For example, two knocks soon after a restart open your apps, and at any other time do something else
- **Per-app gestures**: a double tap can copy in one app and undo in another
- **Soft and hard taps**: a soft double tap and a hard double tap can do different things (calibrated from your own taps)
- **Tap rhythms**: record a pattern such as tap, tap, pause, tap
- **Tap zones** (experimental): left, right and top of the Mac, learned from your own taps
- **Test mode**: for 24 hours gestures are recognized and logged, but nothing runs, so you can check for false triggers first
- **Safety**: actions that are hard to undo, such as turning Wi-Fi off, are only allowed on 4 or more taps unless you confirm
- **Sharing**: export and import profiles as JSON. Imported actions that can run commands or open links arrive switched off
- **Record and replay**: save 10 seconds of raw sensor data to a CSV and replay it through the detector, so detection bugs can be reproduced without the reporter's Mac
- Launch at login, a dark minimal interface, a menu bar popover with a live signal

## Requirements

- A MacBook with an Apple Silicon chip. Bango reads the built-in motion sensor, which Intel Macs and desktop Macs do not expose in the same way. M2 and newer are the expected targets, and base M1 support is unconfirmed
- macOS 14 or newer
- To build: Xcode 16 or newer (or the Swift 6 toolchain)

## Build and run

```sh
git clone https://github.com/your-name/TapDeck.git
cd TapDeck
swift test                       # 66 tests, no Mac sensor needed
./scripts/build.sh --unsigned    # creates dist/Bango.app and an installer DMG, signed for this Mac only
open dist/Bango.app
```

If macOS refuses to open the app, right-click it, choose Open, then Open again.

For your own bundle identifier: `TAPDECK_BUNDLE_ID=com.yourname.TapDeck ./scripts/build.sh --unsigned`. macOS ties permissions to the bundle identifier, so keep it stable once you have granted them.

Signed and notarized builds, and optional automatic updates, need your own Apple Developer ID. See [docs/RELEASING.md](docs/RELEASING.md). Bango is not on the Mac App Store and cannot be: reading the motion sensor uses an undocumented system interface that App Store rules do not allow.

## Permissions

| Permission | Why | When it is asked |
|---|---|---|
| Accessibility | To press keys for you: copy, paste, media keys, lock screen | First time such an action runs, or from General |
| Screen Recording | Only for the "Full screen", "Area" and "Window" capture actions that save, copy or mark up a picture | First time one of those runs. Quit and reopen Bango after allowing it |
| Microphone and Speech Recognition | Only for the dictation action. The microphone is on only between the two double taps | When you press Allow in Setup |
| Automation | Only for dark mode and ejecting drives | First time one of those runs |
| Login Items | Only if you turn on Open at login | When you turn it on |

Nothing is requested until you press Allow in Setup. Bango needs Screen Recording only for the capture actions and Microphone and Speech Recognition only for dictation. It never asks for Input Monitoring or Camera.

## Privacy

Everything stays on your Mac. Dictation uses on-device recognition and refuses to run if a language has no on-device model, so audio is never sent away. There is no analytics, no account and no network use, apart from update checks, which exist only if the build you run was given an update feed. Motion data lives in memory. It is written to disk only when you press Record in Activity, and the file holds motion numbers and the time since your last key press, never what you typed.

## Hardware reports

Sensor access differs between Mac models and macOS versions, and I could not test any of them. If you try Bango, a [hardware report](../../issues/new?template=hardware-report.yml) with your model, what General shows under "This Mac", and how tapping behaves is the most useful thing you can send. Results go into [docs/HARDWARE.md](docs/HARDWARE.md).

## Known limits

- Detection is physical. A very light tap on a heavy desk, or a tap while the Mac is moving in a bag or on a lap, may not register. Raise the sensitivity in Tuning, or recalibrate
- Tap zones depend on the gyroscope and on how your Mac feels when tapped. They may be unreliable on some models. The setup screen tells you if it could not tell the zones apart
- The undocumented sensor interface can change with any macOS update
- Show Desktop, Mission Control and brightness keys follow your keyboard shortcut settings in System Settings
- Microphone mute sets the system input level to zero, it does not mute inside each app

## Project layout

```
Sources/TapCore/     Detector, gesture rules, profiles, safety, zones, rhythm (Foundation only, tested on Linux too)
Sources/TapDeck/     The app: sensors, actions, engine, interface
Tests/TapCoreTests/  66 tests on synthetic sensor signals
scripts/             build.sh, generate-appcast.sh, make-icns.sh
docs/                ARCHITECTURE, HARDWARE, RELEASING, VERIFY_ON_MAC, ROADMAP
```

More in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Contributions are welcome: [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and license

MIT, see [LICENSE](LICENSE). Bango uses the sensor research of [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) and the [Sparkle](https://sparkle-project.org) update framework. Details and license texts in [NOTICE.md](NOTICE.md).
