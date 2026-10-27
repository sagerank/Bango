# Third-party notices

## History

Bingo started as a prototype built on top of an existing open source menu bar app (nocnoc,
shaircast/nocnoc), which has no license file. The tap detector, the update wrapper and the permission helpers
that came from that starting point have since been rewritten from scratch with a different design, and the
published history of this repository starts after that rewrite. Bingo's detector is built on a jump-and-ringing
model of its own (see docs/ARCHITECTURE.md). The maintainers thank the nocnoc author for the idea of reading the
Mac's motion sensor from a menu bar app.

## olvvier/apple-silicon-accelerometer (MIT)

The AppleSPU device identifiers and report layout (vendor usage page 0xFF00,
usage 3 for the accelerometer, usage 9 for the gyroscope, 22-byte reports with
Q16.16 values) come from this research project. Bingo has not yet confirmed
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
