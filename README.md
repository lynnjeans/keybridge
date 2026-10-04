# KeyBridge

[![Latest release](https://img.shields.io/github/v/release/lynnjeans/keybridge)](https://github.com/lynnjeans/keybridge/releases/latest)
[![License: GPL-3.0](https://img.shields.io/github/license/lynnjeans/keybridge)](LICENSE)
![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)

**A Mac shortcut bridge for Windows users.**

KeyBridge lets people who just moved from Windows to macOS keep their muscle memory:
`Ctrl+C` still copies, `Home`/`End` still jump to line start/end, mouse side buttons still
go back and forward, `Ctrl`/`fn` + scroll still zooms the page, and `⌥V` brings up a
Windows-style clipboard history.

Website: **[lynnjeans.github.io/keybridge](https://lynnjeans.github.io/keybridge/)** (English, 简体中文, 日本語)

> [Download the latest KeyBridge](https://github.com/lynnjeans/keybridge/releases/latest)
> or install it with Homebrew:
>
> ```bash
> brew install --cask lynnjeans/tap/keybridge
> ```
>
> Open the disk image and double-click KeyBridge: it installs itself in Applications and
> opens. From then on it keeps itself up to date.

---

## Why

macOS is missing, or does differently, a lot of what Windows users do by reflex:

| Windows habit | On macOS |
|---|---|
| `Ctrl+C` / `Ctrl+V` | `⌘C` / `⌘V` |
| `Win+V` clipboard history | doesn't exist |
| `Ctrl` + scroll zooms a page | zooms the whole screen, or nothing |
| Mouse side buttons go back / forward | do nothing |
| Mouse wheel and touchpad each scroll their own way | one setting flips both |
| `Delete`, `F2` and right-click › New in File Explorer | `Delete` does nothing in Finder, `Enter` renames, and there is no New Document |

Today the fixes are scattered across separate apps: a key remapper for the keyboard, another
tool for the mouse buttons and wheel, a clipboard manager, a window snapper, a Finder add-on.
Each one has to be found, installed, granted permissions and set up from scratch, and none of
them starts from Windows habits. Karabiner-Elements owns deep keyboard remapping but can't see
scroll events; BetterTouchTool covers a lot but is paid, closed source and built for
power users; LinearMouse and Mac Mouse Fix cover the mouse only.

**KeyBridge brings it all together in one app**, set up for Windows habits from the first
launch. That is why I made it: when I moved from Windows to the Mac, years of habits would not
go away, and I did not want five apps to keep them. KeyBridge is for one audience none of the
others targets directly: **the migrant**.

## What it does

- Configurable **combo → combo** remapping engine (`Ctrl→⌘`, key swaps, `fn` combos — all just rules)
- **Windows presets**, one click to apply, every entry still individually editable
- **Each keyboard its own way**: a MacBook's keyboard and a PC keyboard can press Ctrl and
  Win/Alt differently
- **Mouse side buttons** → back / forward or any shortcut
- **Modifier + scroll → `⌘+` / `⌘−`** (page zoom), on from the start with `fn`, or `Ctrl` if you prefer; no separate mouse tool needed
- **Scroll direction reversal**, mouse only, trackpad untouched
- **Finder key suite** — `Delete`, `F2`, `Enter`, `Ctrl+X/V` move, `Backspace` up
- **Clipboard history** on `Win+V` or `⌥V`, with search, pinning, and password-manager exclusion
- **Per-app** scoping: a rule for every app, or just one
- **Window snapping**: `⌥+←/→/↑` like `Win+←/→/↑`
- **Finder right-click menu**: new document, copy path, open in Terminal
- **Open and save dialogs**: `Ctrl+G` jumps to Finder's folder, `Ctrl+Shift+G` lists recent and favorite folders
- **Record Shortcuts**: when a shortcut misbehaves, record it and export what happened
- **Open at Login**, and **automatic updates**, signed and checked daily
- English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Polski

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

### Localization

Every string the UI shows lives in
[`KeyBridge/Resources/Localizable.xcstrings`](KeyBridge/Resources/Localizable.xcstrings),
KeyBridge's String Catalog, with English as the source language. Write UI text as
string literals in SwiftUI (`Text("…")`) or as `String(localized: "…")` where a `String`
is needed; building in Xcode adds new strings to the catalog and lists missing
translations. A command-line build only extracts them, so sync the catalog afterwards:

```bash
xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -derivedDataPath build build
scripts/sync-strings.sh
```

### App icon

[`KeyBridge/Resources/AppIcon.icon`](KeyBridge/Resources/AppIcon.icon) is an Icon Composer
document: three SVG layers (bridge, keycaps, legends) on a blue gradient. macOS 26 draws it in
Liquid Glass; the build derives the flat icon macOS 14 and 15 show. The layers are plain SVG, so
they can be edited by hand; render every appearance without opening Icon Composer with its
`ictool`:

```bash
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
  KeyBridge/Resources/AppIcon.icon --export-image --output-file /tmp/icon.png \
  --platform macOS --rendition Dark --width 512 --height 512 --scale 1
```

Renditions: `Default`, `Dark`, `ClearLight`, `ClearDark`, `TintedLight`, `TintedDark`. The
website's [`site/favicon.svg`](site/favicon.svg) is the same artwork, flattened: redo it after
changing a layer.

## Project docs

Design and planning documents live in [`docs/`](docs/).

## Website

The product website is plain HTML in [`site/`](site/), one page per language, published to
GitHub Pages by [`.github/workflows/pages.yml`](.github/workflows/pages.yml) whenever `site/`
changes on `main`. Nothing is built. To preview it at the address it will have:

```bash
mkdir -p /tmp/pages && ln -sfn "$PWD/site" /tmp/pages/keybridge
python3 -m http.server 8123 --directory /tmp/pages
```

and open `http://localhost:8123/keybridge/`. The three pages share one stylesheet but not their
markup: a change to one page's structure goes into all three.

The screenshots come from the Debug build, with a fresh settings folder and an example
clipboard history, so nothing of yours shows up in them. Retake them all after the UI changes:

```bash
xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -derivedDataPath build build
scripts/site/screenshots.sh
```

The image shown when a link to the website is shared is drawn from
[`scripts/site/social-preview.html`](scripts/site/social-preview.html), with the app icon and
each language's Shortcuts screenshot. Redo it after retaking the screenshots (it needs Google
Chrome), and upload `site/assets/social/en.png` as the repository's social preview in its GitHub
settings:

```bash
scripts/site/social-preview.sh
```

## License

Copyright © 2026 Lei Sun and KeyBridge contributors.

KeyBridge is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 3. It is
distributed in the hope that it will be useful, but **without any warranty**; without even
the implied warranty of merchantability or fitness for a particular purpose. See
[LICENSE](LICENSE) for the full terms.

KeyBridge is free software and always will be. If it saves you some frustration,
donations are welcome, but never required: [sponsor the project on GitHub](https://github.com/sponsors/lynnjeans).

The only third-party code in KeyBridge is [Sparkle](https://sparkle-project.org) (MIT), which
handles automatic updates. It, the projects KeyBridge was designed after, and the ones whose
licenses rule out reuse are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
