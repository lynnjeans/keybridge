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

Planned: window snapping (`Win+←/→/↑`) in v1.1.

**Out of scope:** deep keyboard remapping — tap/hold dual-role keys, layers, chords. KeyBridge
maps combinations to combinations (`Ctrl+C` → `⌘C`, `fn+C` → `⌘C`) and nothing more. That
keeps it on a single event tap with two permission toggles, instead of the root daemon and
virtual keyboard driver that deep remapping requires. If you need those, use
Karabiner-Elements.

## Requirements

- macOS 14+ (developed against macOS 26)
- Two system permissions: **Accessibility** and **Input Monitoring**

KeyBridge needs global input interception, which cannot run inside the App Store sandbox.
It is therefore distributed **outside the Mac App Store**, signed and notarized, via GitHub
Releases and Homebrew Cask.

## Building

Requires Xcode 16 or later — the full install, not just the Command Line Tools.

```bash
git clone https://github.com/lynnjeans/keybridge.git
cd keybridge
open KeyBridge.xcodeproj
```

The Xcode project is generated from [`project.yml`](project.yml) by
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated project is committed so a
fresh clone builds with no extra tools, but to change build settings, edit `project.yml`
and regenerate rather than editing the project in Xcode:

```bash
brew install xcodegen
xcodegen generate
```

### Code signing

KeyBridge needs Accessibility and Input Monitoring permissions, and macOS ties those grants
to the app's code signature. An ad-hoc signed build gets a new identity every time it is
rebuilt, so the grants are lost on each build. To keep them, sign development builds with
your own certificate — a free Apple ID is enough:

1. In Xcode › Settings › Accounts, add your Apple ID, select its Personal Team, choose
   **Manage Certificates…** and create an **Apple Development** certificate.
2. Copy the template and fill in your Team ID (instructions are inside it):

   ```bash
   cp Config/Local.xcconfig.template Config/Local.xcconfig
   ```

`Config/Local.xcconfig` is git-ignored, so your Team ID never enters the repository.
Without it the build falls back to ad-hoc signing: everything still runs, but you will
have to re-grant permissions after every build.

## Project docs

Design and planning documents live in [`docs/`](docs/).

## License

**GPL-3.0** — see [LICENSE](LICENSE).

KeyBridge is free software and always will be. If it saves you some frustration,
donations are welcome, but never required.

Third-party components and their licenses are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
