# KeyBridge Project Documentation

These documents define **what** we are building and **why**. They are the basis for
development; they do not track progress. Progress lives in
[GitHub Issues](https://github.com/lynnjeans/keybridge/issues).

## Language convention

KeyBridge targets an international audience, so **everything in this project is written in
English**: documentation, issues, commit messages, code comments, and identifiers. The
shipped application is localized separately (English, Simplified Chinese, Japanese) through
its String Catalog — that is product content, not project language.

## Documents

| Document | Purpose |
|---|---|
| Market Research | Capability matrix of 11 competing tools, the architectural gap they leave, and where this product fits |
| Design Spec | Visual language, layout, interaction, permissions, clipboard, localization, licensing and distribution |
| UI Mockup | Clickable high-fidelity prototype with live language switching |
| Opportunity Map | Brainstorm of what Windows users miss on macOS, ranked by value against feasibility |
| Development Plan | v1.0 broken into 12 modules and 55 issues, with critical path and estimates |

> These currently live as private Claude Artifacts. They are internal planning material:
> the Development Plan is in English, the other four are in Chinese. Everything that ships
> in this repository follows the English convention above. Export them to Markdown or HTML
> into this directory if you want them versioned alongside the code.

## Key decisions

- **Positioning** — a shortcut bridge for people migrating from Windows to macOS, not a
  general-purpose input tweaker.
- **License** — GPL-3.0, funded by donations. No closed-source commercial edition.
- **Distribution** — **not on the Mac App Store.** Global input interception cannot run
  inside the App Store sandbox, so we ship a Developer ID signed and notarized build via
  GitHub Releases and Homebrew Cask.
- **Architecture** — a single CGEventTap engine, now and later. Deep keyboard remapping
  (tap/hold, layers, chords) is **out of scope**: it needs a root daemon that seizes the
  keyboard plus a DriverKit virtual keyboard to re-emit input, which would trade two
  permission toggles for an admin-password install and a driver-extension approval.
  KeyBridge only maps combinations to combinations, such as `Ctrl+C` or `fn+C` to `⌘C`.
- **Core interaction** — effective rules are the preset layer merged with a user override
  layer. Re-applying a preset **never** overwrites what the user has customized.
- **Differentiator** — modifier + scroll wheel to `⌘+` / `⌘−` page zoom, which no other
  free tool offers.

## Milestone order

```
M0 Foundation → M1 Engine → M3 Rules → M4 Keyboard → M6 Presets → M7 UI → M9 i18n → M10 Release
```

Runs in parallel: M2 Device Identification, M5 Mouse & Scroll, M8 Clipboard (fully
independent), M11 Quality (throughout).

## Start with the walking skeleton (~3–4 weeks)

`KB-001 · 002 · 003 · 006 · 010 · 011 · 012 · 030 · 013 · 040 · 050 · 052`

That narrow end-to-end path proves the product's core value before anything is built out
sideways: **permission onboarding → Ctrl+C becomes ⌘C → side buttons navigate →
modifier+scroll zooms the page.**

## Scripts

| Script | What it does |
|---|---|
| `scripts/bootstrap-github.sh` | Creates the repository, labels, 14 milestones and the full 62-issue backlog |
| `scripts/reset-github.sh` | Deletes every issue and milestone so the backlog can be rebuilt. **Permanent — no undo.** |
