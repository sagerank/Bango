# Hardware compatibility

Bango reads the built-in motion sensors of Apple Silicon MacBooks through an undocumented system interface (`AppleSPUHIDDevice`, vendor usage page 0xFF00, usage 3 for the accelerometer and usage 9 for the gyroscope).

**No Mac has been tested yet.** The table starts empty and is filled by hardware reports.

| Mac | Chip | macOS | Accelerometer | Gyroscope | Taps | Zones | Reported by |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

How to add a row: open a [hardware report](../../issues/new?template=hardware-report.yml). A maintainer adds it here.

## What is believed, and how sure

| Claim | Source | Confidence |
|---|---|---|
| Accelerometer is readable in-process, no root needed | Works on the maintainer's MacBook (recording in the test fixtures) | Medium: one machine so far |
| M2 and newer expose it | Community reports | Medium |
| Base M1 exposes it | Conflicting reports | Unknown |
| Gyroscope is usage 9 with the same report layout | olvvier research | Low: not confirmed by Bango |
| Intel Macs and desktop Macs | Not exposed the same way | Not supported |

## If the sensor is not found

```sh
ioreg -l -w0 | grep -i -B2 -A12 AppleSPUHIDDevice
```

Attach the output to the hardware report. It shows which sensors exist and their usage numbers.
