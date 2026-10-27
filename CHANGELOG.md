# Changelog

## 1.0.2

- Permissions now have a guided wizard: one permission per screen (Accessibility, Screen Recording, Dictation, Open at login), what it is for, one button, and it moves on by itself once macOS says yes. It is the permissions step of the welcome tour, and a "Guided setup" button on the Setup page. The full list stays on Setup for anyone who wants it.
- The wizard covers every row of the Setup list (it also does Automation and the screenshot folder), so it and the list always agree. Guided setup opens by itself on the Setup page when Accessibility or Screen Recording is still off.
- Fix: the olive keyboard focus ring around the selected sidebar item is off.
- Fix: the Microphone and Speech step could wait forever (its button stayed greyed out) if macOS never answered. It now gives up after 40 seconds, says what to do, and opens the right System Settings page. The step also lists each permission with its own status, so you can see which one is holding it up.
- Branding: the sidebar header is the wordmark BANGO. with the tagline "Tweak with the banger.", and the hand icon is gone.
- Fix: the macOS Accessibility dialog appeared four times. It is now shown at most once per launch.
- **Not yet seen on a Mac.** If Accessibility is switched on in System Settings but Bango still says it is missing, remove Bango from the list with the minus button and add it again (the wizard says this after 15 seconds).

## 1.0.1

- Fix: the detector could report a phantom tap in the first fraction of a second after start, before its noise floor had learned the room (the test `testLiftingAndCarryingTheMacIsNotATap` caught it, and CI on 1.0.0 was red because of it). Nothing is accepted for the first 0.4 s now.

## 1.0.0

First release under this version number. Same code as 0.15.0:

- New tap detector, rewritten update checker and permission helpers
- Tap rhythms match human timing, with a note in Activity when a rhythm is missed
- Bango macros have their own section on the Gestures page
- New installs start in test mode: gestures are logged and nothing runs until you turn it off in General
- **Known limits:** detector tuned on one MacBook so far, zones (left, right, top) are experimental, and unsigned builds need a right-click Open the first time

## 0.15.0

- **New tap detector, written from scratch.** The old one followed the structure of the open source app this project started from. The new one works on two signal envelopes: a tap is an abrupt jump above the recent level. It also uses a bucketed noise floor and a slow-gravity check for carrying. Checked on the real 26-tap MacBook recording (all taps found within 30 ms, also at half the sample rate), on the existing synthetic tests, and on 1,836 generated cases across seeds, spacings, strengths and ring lengths.
- **Update wrapper and permission helpers rewritten** in new code (Sparkle, Accessibility, Automation).
- Notices now say plainly where the project began and what was rewritten.
- **Not yet run on a Mac:** nothing in this version has been compiled. Run `swift test` first.

## 0.14.1

- Tap rhythms: matching now allows normal human timing. The same rhythm played a bit faster or slower still counts, and each gap may be off by half its length (at least 80 ms). What must stay the same is the pattern of short and long gaps. Before, a rhythm was missed unless every gap landed within about 35 percent, and a miss quietly ran the plain tap-count action instead.
- When a rhythm is missed and the plain tap count runs, Activity now says so and shows your gaps next to the recorded ones.
- When two rhythms both fit, the closer one wins.
- Gestures page: "Record a tap rhythm" is its own button, no longer inside the Add a gesture menu, and it is greyed out with a reason when monitoring is paused. The page uses one sheet for the recorder and the editor, which fixes the menu choice that did nothing.
- Bango macros (before: "Workflow from a template") have their own section on the Gestures page with a card for each ready-made macro and a "Build your own Bango macro" button. The if/else card in the gesture editor is now called Bango macro.
- Bigger Bango name and tagline at the top of the sidebar.

## 0.14.0

- New name: Bango (was TapDeck). The app, installer and window titles use it.
- New identity: the bundle id is now app.bango.Bango, so macOS treats this as a new app. You will be asked for Accessibility, Microphone and the others once more. Delete the old TapDeck from Applications; Bango closes a running TapDeck at launch.
- Your settings, profiles and gestures are copied from the old TapDeck folder on first launch (the old folder is left alone).
- Profile files now save as .bango.json; files exported by TapDeck still import.
- Inside the code the Swift target is still called TapDeck. That is not user visible.

## 0.13.2

- Faster tap detection: the detector no longer allocates on every sensor sample. Same results (bit-identical on the real recording, 26 of 26 taps, 7 gestures), about 5x less CPU per sample on the benchmark machine (about 1.9 microseconds against 9 to 10).
- The dictation "Listening" pill now sits at the top centre under the menu bar, so it no longer covers the confirmation that appears after a double or triple tap (that stays at the bottom).

## 0.13.1

Dictation typed text that was not exactly what you said, and lagged. **Compiled by CI, not yet seen on a Mac.**

- Cause of the wrong text, reproduced in a test: the recogniser adds capitals and punctuation to words it has already shown. TapDeck had typed the earlier draft, and its end-of-dictation correction could delete only 24 characters. Past that it gave up and added the final text from the wrong place, which scrambled it. A long sentence came out as "hello world how are you doing today , my friend? I hope all is well." when the pill showed "Hello world. How are you doing today, my friend? I hope all is well."
- Now at the end the field is made exactly equal to the final text: only what TapDeck itself typed is deleted, from the first difference onwards, and the rest is typed again. Up to 600 characters. If the difference is bigger than that, nothing is deleted and the final text goes to the clipboard with a message
- Less lag: when you pause for half a second, the last word is typed too, instead of waiting for the next word. At the end TapDeck waits for the recogniser's final result and continues the moment it arrives, and typing is a little faster
- Listening still never deletes anything. Only the final correction does
- Tests (191 in total): the reproduced case, pause typing, exact result for several sentences with and without pause typing, deleting only typed text, and an absurd difference being reported instead of wiped

## 0.13.0

Dictation now types straight into the text box as you speak, like macOS dictation, and no longer uses the clipboard. **Compiled by CI, not yet seen on a Mac. The typing itself could not be tested here.**

- The words appear in the text box of the app you were using while you speak. The pill is only a status display now. Double tap again to finish: the last words are typed and any small correction is made
- The earlier clipboard approach is gone. It felt like a copy and paste tool, and it is replaced
- Each character is sent as its own key press, which is what web-based and Electron apps (chat and AI apps) need. Earlier, whole words were sent in one piece and such apps dropped them
- The recogniser keeps revising its last words, so only words that stayed the same across two updates are typed, and nothing is ever deleted while you are speaking. At the end the text is made to match the final transcript, deleting at most 24 characters of what TapDeck itself typed
- Safe stops: if you switch to another app, typing stops and the rest is put on the clipboard with a message. If TapDeck itself is in front, or Accessibility is off, nothing is typed and the words go to the clipboard, so they are never lost. This is the only time the clipboard is used
- The pill says where the words are going, for example "Typing into Notes"
- New in Setup: "Check that dictation can type". Press it, click into any text box within 3 seconds, and TapDeck types a sentence there, so you can see at once whether typing works in a given app
- 7 new tests (188 in total) for what is typed and when: stable words only, never deleting while listening, the field always ending equal to the final text, a bounded correction, and nothing typed when nothing was heard

## 0.12.3 (replaced the same day by 0.13.0, do not use)

Dictation heard you and showed the words in the pill, but they did not arrive in the text box. **Compiled by CI, not yet seen on a Mac.**

- The words are now pasted into the app in front instead of being sent as typed key presses. Typing worked in native apps but is ignored by many web-based and Electron apps, such as chat and AI apps. Pasting works wherever text can be pasted
- How: the dictated text goes on the clipboard, Command V is pressed, and your own clipboard is put back (everything that was on it, not only text, and only if nothing else changed it in the meantime). Clipboard managers are told the dictated text is temporary
- Without the Accessibility permission nothing can press keys, so the words stay on the clipboard and the message says so
- The log and the toast say "Pasted 12 words"
- Known limit: on newer macOS versions that ask before an app reads the clipboard, TapDeck may trigger that question when it saves your clipboard

## 0.12.2

Screen Recording still looped on "Allowed. Restart TapDeck". **Compiled by CI, not yet seen on a Mac.**

- The word "Allowed" was wrong: TapDeck only knows that it asked, not what you did in System Settings. It now says "Asked, not confirmed" until macOS itself reports the permission after a restart
- Cause of the loop: macOS shows its permission prompt only once for an entry. After a restart that still ended in "refused", pressing Allow asked again, got no prompt, and the row jumped back to "Restart". Now, when the permission is still refused after a restart, Allow first clears TapDeck's old Screen Recording entry (what a stale entry from an earlier build needs), then asks again and opens the right System Settings page
- The row shows when this copy of TapDeck started, so you can tell whether a restart really happened. If the time did not change, it did not
- Screen Recording turns green only when macOS reports it as allowed

## 0.12.1

Setup kept asking for Automation, and Screen Recording said "Restart TapDeck" for ever. **Compiled by CI, not yet seen on a Mac.**

- Automation (System Events and Finder): the answer is now remembered for the build and read quietly when the Setup list opens, without starting System Events and without prompting. Before, every launch showed "Not checked yet" even when macOS had already allowed it. A new build is a different app to macOS, so the memory is per build
- Screen Recording: "Allowed. Restart TapDeck to finish" now shows only until TapDeck has been restarted. If macOS still refuses after a restart, the row says so plainly: the entry in System Settings is an old one from an earlier build, remove it with the minus button, add TapDeck again, restart. It has a button that opens that Settings page
- 4 new tests (181 in total) for the Screen Recording states

## 0.12.0

Step 3 of docs/PLAN_DICTATION_WORKFLOWS.md: desk setup. **The layout maths and the parsing are tested on this machine. Moving real windows through Accessibility could not be tested and needs a Mac.**

- New Desk page: "Save current windows" remembers every app with a visible window and where it is on its screen, as fractions of that screen, so a layout still fits after a change of resolution. Rename, update from the current windows, delete, and "Apply now"
- New actions in Apps and windows: "Apply a saved window layout" (opens apps that are not running, waits for their windows, moves each one), "Arrange the front window" (left, right, top and bottom half, thirds, maximise, centre), "Open several apps, in order", and "Open files, folders and links"
- Open files, folders and links accepts only web and mail links and full paths, and is switched off when a profile is imported, like Open a link
- The "Desk after restart" template now opens Mail, Calendar and Safari and then applies your first saved layout. With no layout yet it says so and carries on
- Results say what happened: "Arranged 4 of 5 windows. Notes is full screen"
- Needs Accessibility. macOS gives apps no way to switch desktops (Spaces) or rearrange screens, so layouts place windows on the screens you have; full-screen windows and apps that refuse are skipped
- 15 new tests (177 in total): presets that fill a screen exactly, odd sizes, saving and applying on a different screen size, windows kept on the screen and usable, parsing, the allow list

## 0.11.0

Step 2 of docs/PLAN_DICTATION_WORKFLOWS.md: workflows with if and else. **The rules are tested on this machine. The screens are compiled by CI and have not been seen running.**

- Any gesture can now choose what runs with if and else: "If these conditions, then these actions. Else if ... Otherwise ...". The gesture's own actions are the "otherwise", so switching workflows off loses nothing
- Conditions: the Mac just started (minutes since it was started, for "after a restart"), an app is in front, an app is running, the time of day (also across midnight), the day of the week, on battery or plugged in, the battery level, an external display connected. Each can be turned around ("is not")
- A branch can need all of its conditions or any of them. The first branch that matches runs
- "Check against right now" shows which branch would run at this moment and the facts it decided on (time, minutes since start, battery, displays)
- Three templates to start from: Desk after restart, Evening wind-down, Dim when the battery is low. Add them from "Add a gesture, Workflow from a template"
- The gesture list and the activity log say which branch ran ("Double tap · if 1")
- Safety and permissions look at every branch, not only the one that would run now. Imported profiles switch off code-running steps inside branches too
- Not included: Wi-Fi name (macOS asks for Location permission to read it), so it is left out for now
- 20 new tests (162 in total)

## 0.10.0

Step 1 of docs/PLAN_DICTATION_WORKFLOWS.md: dictation. **Compiled by CI. The microphone, the speech engine and the typing into other apps could not be tested by the author and need to be tried on a Mac.**

- New action "Dictation: start or stop", in a new Voice group. The same gesture turns it on when it is off and off when it is on. TapDeck keeps the state, so it does not depend on the app in front
- While listening a pill shows a pulsing microphone, a level meter and the words so far. It never takes focus, so the words go to the app you were using
- Double tap again: the final words are typed into the front app. Without the Accessibility permission they are copied to the clipboard and the message says so
- Speech is recognised on this Mac only. If the language has no on-device model the action says so and does nothing, so audio never leaves the Mac
- Stops by itself after 2 minutes. A tap that arrives while it is starting or finishing is ignored
- New Setup items Microphone and Speech Recognition, each with its own Allow button. The action never prompts by itself and says which one is missing
- New "Voice" starter profile: double tap is dictation. Use "Add starter profiles" to get it in an existing setup. Other profiles are untouched
- The app now declares microphone and speech use (Info.plist and entitlements) and Clear permissions covers both
- 15 new tests (142 in total): on and off, ignoring taps while busy, the safety stop, cleaning and splitting typed text, the permissions the action needs

## 0.9.9

Four copies of the app running at once, four sets of permission prompts, four menu bar icons, and Quit closing only one. **Compiled by CI, not yet seen on a Mac by the author.**

- Builds before 0.9.6 had no protection, so every launch added another hidden copy. From 0.9.6 a new copy closes older ones. 0.9.9 makes that safe when two copies start in the same instant: only the older one is ever closed, so they cannot close each other, and the newest always survives
- Quit TapDeck in the menu bar window now closes every copy, not only the one you clicked in, so one press really quits
- The Restart TapDeck button waits until this copy has really exited before opening a new one, and opens nothing if this copy does not quit. Before, it started the new copy first, which could itself leave two running
- 4 new tests (127 in total) for which copy is closed, including four copies and two starting together

## 0.9.8

A guided way to learn the taps, so the app says what to do instead of naming gestures. **Compiled by CI, not yet seen on a Mac by the author.**

- New guided practice in the welcome tour and on the Setup page. Each step shows a laptop with the exact spot pulsing, says in plain words what to do ("Knock once on the palm rest, like knocking on a door"), shows how many taps to make, and answers the moment you tap: "Heard a tap", then a green tick and the next step
- When a try is wrong it says why and what to change: "That counted as 3 taps. Tap exactly 2, then stop", "Too slow, tap faster", "That felt like the right side. Try the left"
- Steps: tap once, twice, three times. Left side, right side and near the hinge appear when zones are set up, with a button to teach them right there
- Zone teaching now shows the laptop and the spot, says "Spot 1 of 3", counts "3 of 5 taps", and explains how to tap
- A short do and do not line under every step: one fingertip, a light knock; not while typing, not hard, not on the screen
- The main window is taller by default and the welcome tour shrinks to fit, so its buttons are never pushed off a small screen
- 6 new tests (123 in total) for what counts as success and what each wrong try says

## 0.9.7

The action dropdown could not be clicked, and setup acted on its own. **Compiled by CI, not yet seen on a Mac by the author.**

- The action picker in the gesture editor is now a searchable list in a popover. The nested menus it used could not be clicked inside the editor on some Macs. The editor also fits small windows now
- Setup never starts by itself. It is a list showing each permission and whether it is allowed, with an Allow button on each line. Nothing is requested until a button is pressed. "Allow all, one by one" is there for people who want it, and is never run automatically
- The welcome tour opens by itself on first run only. Anyone else who lost permissions, for example after a new build, is taken to the Setup page once per build, with no pop-up
- The Setup page no longer starts System Events and Finder in the background to check Automation. Those two show "Not checked yet" until you press Allow or Check Automation too
- Cause of setup "running several times": two copies of the app were running (fixed in 0.9.6) and the permissions step started requesting as soon as it appeared

## 0.9.6

Two menu bar icons, no way to quit, and missing from the Force Quit list. **The cause is inferred from screenshots, not reproduced; the fix is compiled by CI but not yet seen on a Mac.**

- Only one TapDeck can run now. A copy left over from an earlier install is asked to quit when a newer one starts, and forced to if it does not. Before, a hidden old copy kept its own menu bar icon, could hold the motion sensor, and made Quit look broken because it only closed one copy
- While the window is open TapDeck is a normal app: Dock icon, Cmd+Tab, the Force Quit list, and a Quit TapDeck menu with Cmd+Q. When the window closes it goes back to the menu bar only
- Settings are saved immediately when the app is told to quit

## 0.9.5

Fixes for soft and hard taps, rhythms and per-app gestures, which were reported as not working. **The tap-matching logic is tested on real data. The screens are compiled by CI but not yet seen running by the author.**

What was wrong, found by reading the code against the real recording:

- Rhythms could not be given to an app. "Add a gesture, Tap rhythm" under an app only jumped to another page, and a recorded rhythm was always saved to the main profile. It now records inside the app you chose
- After recording a rhythm the editor could fail to appear, because it opened while the recorder was still closing. It now opens after a short wait
- Soft and hard used a guessed level of 0.15 g. On the real recording every tap measures 0.15 to 0.27 g, so everything would have counted as hard. Turning it on now runs a teach-in (five light taps, five firm taps) and sets the line between them, and refuses with the numbers if the two are too alike
- The "How hard" picker was greyed out until a switch in Tuning was found. It is now always usable and offers the teach-in right there
- The old calibration raised the sensitivity threshold to about 0.09 g, which would drop soft taps. Calibration now never raises it
- A gesture set to soft, hard, left, right or top silently never fired while that detection was off, and the log said only "No action assigned". It now says what is missing and where to set it up
- Tuning shows the measured strength of the last tap and whether it counts as soft or hard
- Activity shows which app's own gesture fired ("Double tap in Safari")
- 14 new tests (117 in total): teach-in maths, a rhythm learned from one real burst matching the other, a rhythm inside an app override, app override choice, and the setup hints

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
