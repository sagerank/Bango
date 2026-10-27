# Third-party notices

## nocnoc (shaircast/nocnoc)

Parts of this project are derived from nocnoc: the structure of the impact
detector (adaptive threshold, motion lockout, brief-impulse gate), the
IOKit HID reading of the AppleSPUHIDDevice accelerometer, the Sparkle updater
wrapper, and the Accessibility and Automation permission helpers.

nocnoc's README declares the MIT license. At the time of the fork the repository
contained no LICENSE file and no copyright line. Before the first public release
the maintainers must confirm the license and holder with the nocnoc author, add
their notice here, and replace this paragraph.

## olvvier/apple-silicon-accelerometer (MIT)

The AppleSPU device identifiers and report layout (vendor usage page 0xFF00,
usage 3 for the accelerometer, usage 9 for the gyroscope, 22-byte reports with
Q16.16 values) come from this research project. Bango has not yet confirmed
the gyroscope details on real hardware (see docs/HARDWARE.md).

    MIT License

    Copyright (c) 2026 olvvier

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Sparkle (MIT-style license)

Update framework, bundled with signed release builds. See the Sparkle license
shipped inside the app bundle.
