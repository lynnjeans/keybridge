# Third-Party Notices

KeyBridge is Copyright © 2026 Lei Sun and KeyBridge contributors, and is licensed under
**GPL-3.0** (see [LICENSE](LICENSE)).

## Dependencies

KeyBridge links against Apple's system frameworks (Foundation, AppKit, SwiftUI,
CoreGraphics, ApplicationServices, IOKit, Carbon, OSLog and the like), which are part of
macOS and fall under GPL-3.0's System Libraries exception, and includes one library:

| Library | Version | License | Used for |
|---|---|---|---|
| [Sparkle](https://sparkle-project.org) | 2.10 | MIT, with the licenses of the code it includes (BSD, MIT, zlib) | Automatic updates (KB-101) |

Sparkle is added as a Swift package (`project.yml`) and ships as `Sparkle.framework` inside
the app. Its license is reproduced in full at the end of this file, as it requires.

This file must be kept current: **every time a dependency is added or code is taken from an
external project, add it here** with its license and copyright notice, and keep upstream
copyright headers on any file derived from it.

## Artwork

The word **Ctrl** on the app icon (`KeyBridge/Resources/AppIcon.icon/Assets/legends.svg`, and
the website's `site/favicon.svg`) is the outline of the text set in
[Inter](https://github.com/rsms/inter) Bold, converted to a vector path; no font file is
included. Inter is Copyright © 2016 The Inter Project Authors, licensed under the
[SIL Open Font License 1.1](https://openfontlicense.org), which places no restriction on
artwork made with the font.

---

## Projects studied as references

KeyBridge was designed after studying how the projects below approach the same problems.
No code from them is included; each is credited here as a courtesy, and all are
license-compatible with GPL-3.0 should code ever be taken from them.

| Project | License | What was studied |
|---|---|---|
| [LinearMouse](https://github.com/linearmouse/linearmouse) | GPL-3.0 | Mouse handling: side buttons, scroll reversal, per-device settings |
| [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) | The Unlicense | Event handling patterns, HID device enumeration |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) | MIT | Intercepting scroll events with an event tap and posting keystrokes (modifier + scroll → `⌘±`) |
| [Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser) | Apache-2.0 | Scroll direction reversal, telling a mouse wheel from a trackpad |
| [Maccy](https://github.com/p0deje/Maccy) | MIT | Clipboard history design; KeyBridge uses the same default shortcut, ⌘⇧C |

---

## Deliberately not used

These are excellent references, but their licenses do **not** permit reuse here. Do not
copy code from them.

- **Mos** — CC BY-NC 4.0 (NonCommercial; also not intended as a software license)
- **Mac Mouse Fix** — custom "MMF License" (source-available, commercial use restricted)

Studying their behaviour is fine; copying their source is not.

**Checked 2026-09-19 (KB-103):** KeyBridge's Swift sources were compared line by line
with the current source of both projects (github.com/Caldis/Mos and
github.com/noah-nuebling/mac-mouse-fix, every `.swift`, `.m`, `.h`, `.mm` and `.c` file).
No run of three or more consecutive lines matches either project. The only single lines in
common are standard Apple API idioms, such as `RunLoop.main.add(timer, forMode: .common)`,
`let formatter = DateFormatter()` and Codable boilerplate.

---

## Trademarks

Names and logos of the projects above, and of Apple, Microsoft, Razer, Logitech and any
other company, are the property of their respective owners and are **not** used as part of
KeyBridge's own branding. KeyBridge names some of these tools only to tell users when one of
them is running alongside it.

---

## Sparkle license

The text below is Sparkle's `LICENSE` file, unchanged.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```
