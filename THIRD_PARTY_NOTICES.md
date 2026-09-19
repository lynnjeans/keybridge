# Third-Party Notices

KeyBridge is Copyright © 2026 Lei Sun and KeyBridge contributors, and is licensed under
**GPL-3.0** (see [LICENSE](LICENSE)).

## Dependencies

**None.** KeyBridge includes no third-party code or libraries. It links only against
Apple's system frameworks (Foundation, AppKit, SwiftUI, CoreGraphics, ApplicationServices,
IOKit, Carbon, OSLog and the like), which are part of macOS and fall under GPL-3.0's
System Libraries exception.

This file must be kept current: **every time a dependency is added or code is taken from an
external project, add it here** with its license and copyright notice, and keep upstream
copyright headers on any file derived from it. The next expected entry is Sparkle (MIT),
for automatic updates (KB-101).

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
