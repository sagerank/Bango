# Plan: dictation, workflows, desk setup

Decided with the owner. Each step is one build. After each build the owner tests on a real Mac and reports
before the next step starts. Nothing is built or pushed between steps unless asked.

## Step 1: Dictation (0.10.0)

Goal: a double tap starts dictation, the same double tap stops it. On means off, off means on.

Design
- New action `dictation-toggle`, "Dictation: start or stop", in a new "Voice" group.
- TapDeck tracks the state itself, so one gesture always does the opposite of the current state.
- Built-in engine: Apple speech recognition with the microphone, on-device only. If the language has no
  on-device model the action says so and does nothing. Audio never leaves the Mac.
- While listening: a pill with a pulsing microphone, a level meter and the words so far.
- On stop: the final text is typed into the app and field that was in front. If Accessibility is missing the
  text is copied to the clipboard instead and the message says so.
- Safety: stops by itself after 2 minutes. The macOS orange microphone dot stays on while recording.
- Permissions, asked only when the owner presses Allow in Setup: Microphone and Speech Recognition.
  The action refuses with a clear message if they are missing and never prompts by itself.
- Starter profile "Voice": double tap is dictation. Existing profiles are not changed.

Testable here (unit tests): the on/off state machine, the rules for what text is typed and how it is split,
which permissions the action needs, which animation fits. Not testable here: the microphone, the speech engine and
typing into other apps. These need the owner's Mac.

Done when: CI is green and the DMG is delivered. Accepted when the owner confirms on a Mac that double tap starts
and stops dictation and the text appears.

## Step 2: Workflows, if and else (0.11.0)

- A workflow is bound to a gesture: When (gesture), If (conditions, all or any), Then (actions), Else (actions),
  with else-if branches.
- Conditions: just started (restart or login within N minutes), front app, app running, time and weekday, power source
  and battery level, external display, Wi-Fi name.
- All evaluation logic lives in TapCore and is unit tested. The Mac supplies the facts (a snapshot of the state).
- A workflow editor in plain words, templates, a preview of what would run, and test mode applies.

## Step 3: Desk setup (0.12.0)

- Actions: open several apps, files, folders and links in order with waits; arrange windows (halves, maximise, saved
  position per app); "Save my current layout".
- Needs Accessibility. Limits: macOS gives no public way to control Spaces or the display arrangement; some apps
  cannot be moved or resized.
- A template "Desk after restart": two knocks, then if just started, open the apps and arrange them.

## Not in this plan

Signing and notarization, the final name, the detector licence, soft and hard and zone verification. These stay
on the open list.
