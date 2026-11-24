# Third-party notices

Pregame is free software under the GNU General Public License, version 3 (see [LICENSE](LICENSE)). It includes or links the components below, each under its own licence. GPL-3.0 is compatible with all of them, and Pregame as a whole is distributed under GPL-3.0.

| Component | Use in Pregame | Licence | How it is included |
|---|---|---|---|
| [Rubber Band Library](https://breakfastquay.com/rubberband/) | Time-stretching and pitch-shifting | GPL-2.0-or-later | Linked statically |
| [Queen Mary DSP library](https://github.com/c4dm/qm-dsp) (as vendored in Mixxx 2.5) | Key and tempo detection | GPL-2.0-or-later | Source in `Sources/QMDSP` |
| [TagLib](https://taglib.org) | Reading and writing audio file tags | LGPL-2.1 (or MPL-1.1) | Dynamically linked, bundled in the app |
| [ONNX Runtime](https://onnxruntime.ai) 1.31.0 | Running the stem separation model | MIT | Dynamically linked, bundled in the app |
| [Demucs](https://github.com/facebookresearch/demucs) v4 (`htdemucs`) | Stem separation model weights, exported to ONNX | MIT | Model files in `Models/` |
| [LAME](https://lame.sourceforge.io) | MP3 encoding | LGPL-2.0-or-later | Linked statically |
| [mpg123](https://www.mpg123.de) | MP3 decoding for LAME | LGPL-2.1 | Linked statically |
| [Sparkle](https://sparkle-project.org) 2.10.1 | Checking for and installing updates | MIT | Framework bundled in the app |
| [Sentry](https://github.com/getsentry/sentry-cocoa) 9.33.0 | Crash reports, only if the Mix Host agrees | MIT | Framework bundled in the app |
| [libsamplerate](https://libsndfile.github.io/libsamplerate/) | Sample-rate conversion for Rubber Band | BSD-2-Clause | Linked statically |
| [KISS FFT](https://github.com/mborgerding/kissfft) | FFT inside QM DSP | BSD-3-Clause | Source in `Sources/QMDSP/ext/kissfft` |
| [Mixxx](https://mixxx.org) | Analysis settings and BPM post-processing ported from Mixxx 2.5 | GPL-2.0-or-later | Ported code in `Sources/PregameCore` |

## Licence texts and copyright

- **Rubber Band Library:** Copyright © Particular Programs Ltd. Released under the GNU GPL, version 2 or later.
- **Queen Mary DSP library:** Copyright © Centre for Digital Music, Queen Mary, University of London. Released under the GNU GPL, version 2 or later. Full text: [`Sources/QMDSP/COPYING`](Sources/QMDSP/COPYING).
- **TagLib:** Copyright © Scott Wheeler and the TagLib authors. Released under the GNU LGPL, version 2.1, or the Mozilla Public License, version 1.1. The app bundles TagLib as a separate dynamic library, so it can be replaced.
- **ONNX Runtime:** Copyright © Microsoft Corporation. Released under the MIT License. Full text and ONNX Runtime's own third-party notices: [`Vendor/onnxruntime/LICENSE`](Vendor/onnxruntime/LICENSE), [`Vendor/onnxruntime/ThirdPartyNotices.txt`](Vendor/onnxruntime/ThirdPartyNotices.txt).
- **Demucs:** Copyright © Meta Platforms, Inc. and affiliates. Released under the MIT License.
- **LAME:** Copyright © the LAME project. Released under the GNU LGPL, version 2 or later.
- **mpg123:** Copyright © the mpg123 project. Released under the GNU LGPL, version 2.1.
- **Sparkle:** Copyright © Andy Matuschak, Elgato Systems GmbH, Kornel Lesiński, Mayur Pawashe, C.W. Betts, Petroules Corporation, Big Nerd Ranch and the Sparkle Project contributors. Released under the MIT License. Full text, including the licences of the code Sparkle itself includes: `SPARKLE_LICENSE` in the app's resources, from [Sparkle's repository](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE).
- **Sentry:** Copyright © 2015 Sentry. Released under the MIT License. Full text: `SENTRY_LICENSE` in the app's resources, from [sentry-cocoa's repository](https://github.com/getsentry/sentry-cocoa/blob/9.33.0/LICENSE.md).
- **libsamplerate:** Copyright © Erik de Castro Lopo and contributors. Released under the BSD 2-Clause License.
- **KISS FFT:** Copyright © Mark Borgerding. Released under the BSD 3-Clause License. Full text: [`Sources/QMDSP/ext/kissfft/COPYING`](Sources/QMDSP/ext/kissfft/COPYING).
- **Mixxx:** Copyright © the Mixxx team. Released under the GNU GPL, version 2 or later.

The MIT, BSD and LGPL licences above require their copyright notices and licence texts to travel with binary copies. The app bundles this file and the licence files it links to.
