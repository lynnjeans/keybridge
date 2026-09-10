# KeyBridge

**A Mac shortcut bridge for Windows users.**

KeyBridge lets people who just moved from Windows to macOS keep their muscle memory:
`Ctrl+C` still copies, `Home`/`End` still jump to line start/end, mouse side buttons still
go back and forward, `Ctrl`/`fn` + scroll still zooms the page, and `⌘⇧V` brings up a
Windows-style clipboard history.

> Status: **pre-alpha — under active development.** Nothing is released yet.

---

## Why

macOS is missing, or does differently, a lot of what Windows users do by reflex:

| Windows habit | On macOS |
|---|---|
| `Ctrl+C` / `Ctrl+V` | `⌘C` / `⌘V` |
| `Home` / `End` | `⌘←` / `⌘→` |
| `Delete` removes a file | does nothing in Finder (`⌘⌫`) |
| `F2` renames | `Enter` renames, `Enter` doesn't open |
| Mouse side buttons | not mapped at all |
| `Ctrl` + scroll zooms a page | zooms the whole screen, or nothing |
| `Win+V` clipboard history | doesn't exist |

Existing tools each solve a slice: Karabiner-Elements owns deep keyboard remapping but
can't see scroll events; BetterTouchTool can do scroll-to-keystroke but is closed source
and weak on keyboard depth; LinearMouse and Mac Mouse Fix cover the mouse only.
KeyBridge aims at the one audience none of them targets directly: **the migrant**.

## Scope (v1.0)

- Configurable **combo → combo** remapping engine (`Ctrl→⌘`, key swaps, `fn` combos — all just rules)
- **Windows presets**, one click to apply, every entry still individually editable
- **Mouse side buttons** → back / forward or any shortcut
- **Modifier + scroll → `⌘+` / `⌘−`** (page zoom) — the feature no free tool has
- **Scroll direction reversal**, mouse only, trackpad untouched
- **Finder key suite** — `Delete`, `F2`, `Enter`, `Ctrl+X/V` move, `Backspace` up
- **Clipboard history** with search, pinning, and password-manager exclusion
- **Per-device** (VID/PID) and **per-app** scoping
- English / 简体中文 / 日本語

Planned: window snapping (`Win+←/→/↑`) in v1.1; deep keyboard remapping (tap/hold, layers)
via DriverKit in v2.

## Requirements

- macOS 14+ (developed against macOS 26)
- Two system permissions: **Accessibility** and **Input Monitoring**

KeyBridge needs global input interception, which cannot run inside the App Store sandbox.
It is therefore distributed **outside the Mac App Store**, signed and notarized, via GitHub
Releases and Homebrew Cask.

## Building

Requires Xcode (full install, not just Command Line Tools).

```bash
git clone https://github.com/<owner>/keybridge.git
cd keybridge
open KeyBridge.xcodeproj
```

## Project docs

Design and planning documents live in [`docs/`](docs/).

## License

**GPL-3.0** — see [LICENSE](LICENSE).

KeyBridge is free software and always will be. If it saves you some frustration,
donations are welcome, but never required.

Third-party components and their licenses are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
