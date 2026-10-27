# Contributing

Thank you. The most valuable contributions right now are, in order:

1. **Hardware reports**: try Bango on your Mac and fill in the [hardware report](../../issues/new?template=hardware-report.yml)
2. **Recordings of problems**: missed taps or false triggers, as a CSV from Activity, Lab
3. **Compile fixes and bug fixes**: the app was first written without a compiler, so the first Mac builds will find errors
4. New actions, tests, translations, accessibility

## Setup

```sh
git clone https://github.com/your-name/TapDeck.git
cd TapDeck
swift test
./scripts/build.sh --unsigned
```

TapCore (the logic) also builds and tests on Linux. The Bango app target needs macOS 14 and Swift 6.

## Ground rules

- **Logic goes in TapCore, and gets a test.** If it needs no system call, it belongs there
- **Detector changes need evidence.** Add a fixture recording or a synthetic-signal test that fails before and passes after. Please do not tune a magic number because it felt better on your desk
- **Safety first.** A new action that can lose data or change connectivity must be marked `caution` or `destructive` in the catalog
- **No telemetry, no network calls** other than the optional update check
- **Never read what the user types.** The typing guard may only use how long ago input happened
- Keep the interface minimal: black, one accent, no extra colors

## Pull requests

Small and focused. Say what you ran: `swift test`, and on a Mac, what you tried by hand and on which model.

## Licence

By contributing you agree that your work is released under the MIT license of this project.
