# Architecture

```
 sensors (HID)            TapCore (pure logic)                         app
┌──────────────┐   ┌────────────────────────────────────────────┐   ┌─────────────────────────┐
│ SensorService│──▶│ ImpactDetector ─▶ GestureRecognizer         │──▶│ Engine                  │
│ accel + gyro │   │  single taps       groups taps, guard,      │   │  profile + frontmost app│
│ InputIdle    │   │  + direction       strength, zone vote       │   │  safety, test mode      │
└──────────────┘   │ TapPipeline = detector + recognizer          │   │  ActionExecutor         │
                   └────────────────────────────────────────────┘   └─────────────────────────┘
```

## TapCore (Foundation only)

Everything with logic and no system calls. It builds and tests on Linux, which is why most of the 66 tests run in cheap CI.

| File | Job |
|---|---|
| ImpactDetector | Finds single taps in a stream of accelerometer samples. Port of the nocnoc structure: low pass to remove gravity, high pass and jerk, adaptive threshold, motion lockout, quiet-before and brief-impulse gates. Holds each tap for a 60 ms feature window to capture its direction |
| GestureRecognizer | Groups taps that follow within the grouping window. Second layer of the typing guard. Hard or soft from mean peak. Zone from a majority vote |
| TapPipeline | Detector plus recognizer. `Replay` runs recorded samples through it deterministically |
| Zones, Rhythm | Learned zone model (cosine similarity of 6 number direction vectors) and gap patterns |
| Profiles, Safety, Actions | Bindings, per-app overrides, specificity scoring, action catalog, danger levels |
| Exchange, Recording | Profile JSON with a sanitizer, CSV sensor recordings |
| AppConfig | Everything that is saved. Decoding is lenient so older or damaged files never lose all settings |

### Typing guard, two layers

1. **Detector**: a tap is not accepted if the last key or click was less than `guardWindow` (0.2 s) before it
2. **Recognizer**: a finished gesture is dropped if any key or click happened within `guardWindow` before or after any of its taps. This catches key presses that arrive just after the tap

The guard reads `CGEventSource.secondsSinceLastEventType` only: how long ago, never which key.

### Gesture matching

A binding matches on tap count, optional zone, optional strength, or on a rhythm. When several match, the most specific wins: rhythm (100), zone (+2), strength (+1). An app override is tried before the profile. Equal scores: the first binding wins, and the editor warns about duplicates.

### Safety

Actions have a danger level. `caution` and `destructive` actions are only allowed on 4 or more taps unless the user confirms for that binding. Imported profiles lose confirmations, get new ids, and have code-running steps (`runsCode`) and unknown steps disabled.

## TapDeck (macOS only)

| File | Job |
|---|---|
| Sensors/SensorService | IOKit HID. Accelerometer required, gyroscope optional, one context per device, latest gyro reading attached to each accelerometer sample |
| Sensors/MotionMonitor | Feeds the pipeline on the sensor thread, publishes a 30 Hz snapshot, supports recording, restarts after sleep |
| Actions/ActionExecutor | Maps each catalog id to behaviour. Key presses and media keys by CGEvent, processes without a shell except the Terminal action |
| Core/Engine | Gesture to binding to safety to test mode to chain. Practice screens register to swallow gestures |
| Core/ConfigStore | JSON in Application Support, atomic and debounced. A damaged file is moved aside, not deleted |
| UI/ | SwiftUI. Dashboard sections, binding editor, wizards, menu bar popover, HUD |

## Adding an action

1. Add an `ActionDefinition` to `ActionCatalog.all` in Actions.swift (id, name, symbol, category, danger, permission)
2. Add a `case` with its id in `ActionExecutor.perform`
3. A test already checks that ids are unique and that default profiles only use known actions

## Adding a detector improvement

Record a session (Activity, Lab), add the CSV under `Tests/Fixtures/`, and write a test that replays it with `Replay.run`. A fixture that shows the bug before your change and passes after is the best possible pull request.
