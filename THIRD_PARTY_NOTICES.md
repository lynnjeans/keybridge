# Third-Party Notices

KeyBridge is licensed under **GPL-3.0**. It draws on, and where noted incorporates code
from, the projects below. All are license-compatible with GPL-3.0.

This file must be kept current: **every time code or a substantial idea is taken from an
external project, add it here** with its license and copyright notice.

---

## Incorporated / referenced

### LinearMouse — GPL-3.0
- https://github.com/linearmouse/linearmouse
- Used for: mouse handling — side buttons, scroll reversal, per-device (VID/PID) config,
  pointer acceleration.
- GPL-3.0 is copyleft; because KeyBridge is itself GPL-3.0, incorporating this code is
  permitted. Retain upstream copyright headers on any file derived from it.

### Karabiner-Elements — The Unlicense (public domain)
- https://github.com/pqrs-org/Karabiner-Elements
- Used for: event handling patterns, HID device enumeration, per-device mechanics.
- Public domain dedication; no obligations. Attribution given here as courtesy.

### Hammerspoon — MIT
- https://github.com/Hammerspoon/hammerspoon
- Used for: `hs.eventtap` approach to intercepting scroll events and synthesizing
  keystrokes (the basis for modifier + scroll → `⌘±`).
- MIT requires the copyright notice and permission notice be retained.

### Scroll Reverser — Apache-2.0
- https://github.com/pilotmoon/Scroll-Reverser
- Used for: scroll direction reversal, trackpad vs. mouse discrimination.
- Apache-2.0 requires retaining notices and **stating significant changes** made to the
  original files.

### Maccy — MIT
- https://github.com/p0deje/Maccy
- Used for: clipboard history manager design and implementation approach.
- MIT requires the copyright notice and permission notice be retained.

---

## Deliberately NOT used

These are excellent references but their licenses do **not** permit reuse here.
Do not copy code from them.

- **Mos** — CC BY-NC 4.0 (NonCommercial; also not intended as a software license)
- **Mac Mouse Fix** — custom "MMF License" (source-available, commercial use restricted)

Studying their behaviour is fine; copying their source is not.

---

## Trademarks

Names and logos of the projects above, and of Apple, Microsoft, Razer, Logitech and any
other company, are the property of their respective owners and are **not** used as part of
KeyBridge's own branding.
