# Release Regression Checklist

A full pass through KeyBridge by hand, run on the release build before every release. Unit
tests cover the rule logic; this covers what only a real Mac, real apps and real keyboards
and mice can show. How to check things, and the traps that give confidently wrong results,
are in [testing-notes.md](testing-notes.md).

**How to use it:** open a tracking issue for the release with this file as its body, then tick
items off in the issue as you go:

```bash
gh issue create --title "Release regression pass: v<version>" --body-file docs/release-checklist.md
```

- Each item is **action → expected result**. An item passes only if everything after the
  arrow happens.
- Anything that fails gets its own issue, linked from the failed item. Do not release with an
  unticked item unless the release notes say why.
- Items tagged **[PC keyboard]**, **[mouse]**, **[Magic Mouse]** or **[2nd Mac user]** need
  that hardware or setup. Without it, write "not tested: no <hardware>" next to the item rather
  than ticking it.
- When a feature is added, add its items here in the same change.

## Test setup

| | |
|---|---|
| KeyBridge version (About) | |
| Build | Release · signed · notarized? |
| macOS version | |
| Mac model | |
| Keyboards | Mac built-in / Magic Keyboard / PC keyboard: … |
| Mice | trackpad / Magic Mouse / mouse with side buttons: … |
| Interface language(s) tested | |
| Tester, date | |

Before starting:

- [ ] Other remappers are quit: Karabiner-Elements, BetterTouchTool, mouse utilities and
      Logi Options+. The Overview names any it finds.
- [ ] Apps to test in are installed: Safari, Chrome (or Edge), Finder, TextEdit, Notes,
      Microsoft Word or Pages, VS Code, Terminal, and iTerm2 or another terminal.

---

## 1. Install and first run

Start from a clean slate: quit KeyBridge, then
`tccutil reset Accessibility io.github.lynnjeans.KeyBridge`,
`tccutil reset ListenEvent io.github.lynnjeans.KeyBridge`,
`defaults delete io.github.lynnjeans.KeyBridge` and
`rm -rf ~/Library/Application\ Support/KeyBridge`.

- [ ] Install the release build (DMG or `brew install --cask`) and open it → it opens without
      a Gatekeeper warning (notarized build), and the ⌘ icon appears in the menu bar, faded.
- [ ] The "Set Up KeyBridge" guide opens by itself, **in front of** other windows, on step 1
      Accessibility.
- [ ] Step 1's button → System Settings opens at Privacy & Security › Accessibility with
      KeyBridge listed. Switch it on → the guide moves to step 2 within about 2 s, with nothing
      else to click.
- [ ] Step 2 Input Monitoring → it is granted with no action, or after one switch in System
      Settings. The guide reaches **Ready**; the menu bar icon is no longer faded.
- [ ] "Start Using KeyBridge" closes the guide. Quit and reopen KeyBridge → the guide does not
      come back.
- [ ] Double-click KeyBridge in Finder while it runs → the main window opens in front, on
      Overview.
- [ ] The menu bar icon's menu → Open KeyBridge… → the main window opens **in front of** the
      app you were in. Repeat five times from different apps.
- [ ] While a window is open, KeyBridge has a Dock icon. Close the last window → the Dock icon
      goes away.

## 2. Permissions while running

- [ ] System Settings › Accessibility: switch KeyBridge **off** → within about 2 s the Overview
      shows "Action needed", the master switch greys out, the menu bar icon fades, and the
      keyboard and mouse still work normally (no stuck keys, nothing remapped).
- [ ] Switch it back **on** → remapping works again without relaunching (Ctrl+C copies in
      TextEdit).
- [ ] Input Monitoring: switch KeyBridge off and accept the relaunch System Settings offers →
      KeyBridge reopens showing the missing permission. Switch it back on → it works again.
- [ ] The menu bar menu lists the missing permission, and its "Open Settings…" item opens the
      right pane.

## 3. Master switch, pause, menu bar

- [ ] Overview › Windows Shortcut Mode **off** → Ctrl+C no longer copies in TextEdit, and the
      side buttons and fn+scroll do nothing special. **On** → all work again.
- [ ] Quit and reopen with the switch off → it stays off. Switch on, relaunch → on.
- [ ] Menu bar › Pause › For 5 Minutes → remapping stops; the Overview says "Paused until
      <time>" with a Resume button. Resume → remapping is back at once.
- [ ] Pause › Until I Resume → stays paused until Resume Now is chosen from the menu bar.
- [ ] Menu bar › Quit KeyBridge → the app quits, and keys behave as on a plain Mac.

## 4. Shortcuts: Editing group

Sections 4–8 use the default settings from section 1: Ctrl shortcuts pressed with **Ctrl**.
Section 9 covers fn.

In each of **TextEdit, Notes, Safari (a text field), Chrome, Word or Pages and VS Code**:

- [ ] Ctrl+C / Ctrl+X / Ctrl+V → copy, cut and paste.
- [ ] Ctrl+Z → undo; Ctrl+Y → redo.
- [ ] Ctrl+A → select all; Ctrl+S → save; Ctrl+F → find.
- [ ] Ctrl+N → new document or window; Ctrl+O → open; Ctrl+P → print dialog (then Cancel).
- [ ] Holding Ctrl+V repeats the paste, and releasing keys in any order leaves no key stuck:
      type afterwards and no stray ⌘ shortcuts fire.

In **Terminal** and **iTerm2**:

- [ ] Ctrl+C interrupts a running `sleep 100`; Ctrl+A / Ctrl+E move to the line start and
      end; Ctrl+W deletes a word. Terminals are left alone, so nothing is turned into ⌘.
- [ ] ⌘C / ⌘V still copy and paste there.

## 5. Shortcuts: Text Navigation

In **TextEdit** and a **Safari** text area, with several lines of text:

- [ ] Home / End → start and end of the line; Shift+Home / Shift+End select to them.
- [ ] Ctrl+Home / Ctrl+End → start and end of the document; with Shift they select.
- [ ] Ctrl+← / Ctrl+→ → previous and next word; with Shift they select.
- [ ] Ctrl+Backspace → deletes the previous word.
- [ ] In **Terminal**, Home, End and Ctrl+arrows reach the shell unchanged.

## 6. Shortcuts: File Management (Finder)

In a Finder window with a scratch folder of test files:

- [ ] Select a file, Delete (forward delete, fn+Backspace on a Mac keyboard) → it moves to the
      Trash.
- [ ] F2 → rename starts. Type a name, Enter → the rename is confirmed, and the file is **not**
      opened.
- [ ] Enter on a selected file → it opens; on a folder → Finder goes into it.
- [ ] Backspace (not renaming) → up to the enclosing folder.
- [ ] Ctrl+X on a file, go to another folder, Ctrl+V → the file is **moved** there.
- [ ] While renaming, and in Finder's search field: Enter, Backspace and Ctrl+V behave as in any
      text field (Ctrl+V pastes text, Backspace deletes a character).
- [ ] In a file Open/Save dialog of another app, these Finder keys do not apply.

## 7. Shortcuts: Windows & Apps, Browser, System

- [ ] Alt+Tab → switches apps (the ⌘Tab switcher). Alt+F4 → quits the front app (test with
      TextEdit).
- [ ] **[PC keyboard]** Print Screen → a full-screen screenshot goes to the clipboard: paste it
      in Notes, and it appears in the clipboard history if that is on.
- [ ] Ctrl+Shift+Esc → Activity Monitor opens.
- [ ] Ctrl+Alt+Delete (forward delete) → the Force Quit window opens.
- [ ] In Safari and Chrome: Ctrl+T new tab, Ctrl+W close tab, Ctrl+Shift+T reopen it, Ctrl+L
      address bar, Ctrl+R reload.

## 8. Shortcuts: Windows Key group (off by default)

- [ ] The group is off after a fresh install. Switching it on asks for confirmation first.
- [ ] **[PC keyboard]** Win+L → the screen locks. Win+E → Finder. Win+D → shows the desktop.
      Win+. → the emoji picker. Win+Shift+S → an area screenshot to the clipboard.
- [ ] With the group on, the Overview notes that ⌘L, ⌘E, ⌘D, ⌘. and ⌘⇧S are taken on a Mac
      keyboard too. Switch it off → ⌘L selects the Safari address bar again.

## 9. The Ctrl key choice (fn | Ctrl | Both)

On Shortcuts › "Press Ctrl shortcuts with":

- [ ] **fn**: fn+C copies in TextEdit **and in Terminal**; plain Ctrl+C in Terminal still
      interrupts; Ctrl+C in TextEdit is left to the Mac. Ctrl+←/→ still move by word.
- [ ] **Ctrl**: Ctrl+C copies outside terminals; fn+C does nothing special.
- [ ] **Both**: Ctrl+C and fn+C both copy outside terminals; only fn+C copies in Terminal.
- [ ] The choice survives a relaunch.

## 10. Editing the preset and custom rules

- [ ] Shortcuts: switch a group off → its entries grey out and stop working at once; on →
      they work again.
- [ ] Search "copy" → only matching entries show, with "1 of 11 mappings"-style counts. Clear
      it → everything is back.
- [ ] Open an entry, record a different trigger (e.g. Ctrl+Shift+C for Copy), Save → the new
      trigger copies, the old one no longer does, and the entry shows a "customized" badge.
- [ ] Switch a single entry off → it is struck through and does nothing.
- [ ] Restore Defaults… → confirm → the preset is back as shipped; custom rules and the Ctrl
      key choice are kept.
- [ ] Custom Rules › New Rule…: record F6 → ⌘⇧N, "Only in Finder" → F6 makes a new folder in
      Finder and does nothing in TextEdit.
- [ ] New Rule… with the result "Open app" set to Calculator → the trigger opens Calculator.
- [ ] A custom rule with the same trigger as a preset entry wins over the preset.
- [ ] Custom rule: switch it off, edit it, delete it (context menu) → each takes effect at once.
- [ ] Quit and relaunch → every change above is still there.

## 11. Mouse

- [ ] **[mouse]** Side buttons 4 / 5 → back / forward in Safari, Chrome and Finder.
- [ ] **[mouse]** Mouse page: switch "Side buttons" off → the buttons do nothing special.
- [ ] **[mouse]** Edit Back, click the recorder, press the other side button → the entry shows
      that button's number, and it now goes back.
- [ ] The left and right buttons work normally throughout.

## 12. Scroll

- [ ] **[mouse]** fn + wheel up / down → the page zooms in / out in Safari and Chrome, like
      ⌘+ / ⌘−.
- [ ] **[mouse]** Scroll page › "Hold while scrolling": choose Ctrl → Ctrl+wheel zooms, and
      the warning about macOS screen zoom appears. Choose Custom… and tick two modifiers →
      zoom needs both.
- [ ] **[mouse]** Windows scroll direction **on**, with natural scrolling on in System
      Settings → rolling the wheel towards you moves down the page. **Off** → back to the
      system direction.
- [ ] **Trackpad** scrolling and pinch-zoom are unchanged by every setting above.
- [ ] **[Magic Mouse]** Scrolling keeps the system behaviour and direction.

## 13. Clipboard history

- [ ] Clipboard page: switch the history on → copy text in TextEdit, an image (Preview) and a
      file (Finder) → all three appear in the history, newest first.
- [ ] ⌘⇧C (or the recorded shortcut) in any app → the panel opens at the pointer, in front
      of the app, **without** taking over the app's menu bar.
- [ ] Type to search → the list narrows. ↑ / ↓ move the selection; Enter pastes it into the
      app that was in front; Esc closes. Clicking outside also closes.
- [ ] Clicking an item pastes it. The pasted item stays on the clipboard, so ⌘V gives it again.
- [ ] Pin an item → it stays at the limit; unpin works. Remove one item; Clear History keeps
      pinned items.
- [ ] Record a different panel shortcut → the new one opens the panel and the old one does not.
      A shortcut already used by a KeyBridge rule shows a conflict warning.
- [ ] Copy a password from Passwords (or 1Password) → it is **not** recorded. Add TextEdit
      under "Never record from" → its copies stop appearing; Restore Default List resets it.
- [ ] Set "Keep" to 50 with more items copied → the oldest unpinned items drop.
- [ ] Quit and relaunch → the history is still there. Switch the history off → nothing more
      is recorded and the panel shortcut does nothing.

## 14. Secure Input, other remappers, multiple devices

- [ ] Click into a password field (Safari login page) → key remapping pauses while it has
      focus. Mouse buttons and scrolling still work. Leave the field → remapping resumes.
- [ ] Terminal › Secure Keyboard Entry on → after about 30 s the Overview names Terminal and
      how to switch it off; the menu bar icon fades. Switch it off → back to normal.
- [ ] Start Karabiner-Elements → within 5 s the Overview says it is running. Quit it → the
      notice goes away within 5 s.
- [ ] **[PC keyboard]** With the Mac's built-in keyboard and a PC keyboard both connected,
      every shortcut above works from either keyboard.
- [ ] **[mouse]** Unplug or switch off the mouse and reconnect it → the side buttons and zoom
      still work, without relaunching.
- [ ] Put the Mac to sleep and wake it → remapping still works. Lock the screen and unlock → the
      same.
- [ ] **[2nd Mac user]** Fast-switch to another user and back → remapping works in the first
      session again.

## 15. Languages and layout

For each of **English, 简体中文 and 日本語** (sidebar language menu, or System Settings ›
General › Language & Region › Applications):

- [ ] Switching applies at once; every page, the menu bar menu, the guide and the clipboard
      panel are in that language, with no English left over.
- [ ] At the smallest window size, no text is cut off or overlapping on any page. Rows wrap or
      stack instead.
- [ ] "Follow System" follows macOS's language after a relaunch.

## 16. About, diagnostics, legal

- [ ] About shows the right version and build.
- [ ] License and Third-Party Notices open in a sheet with the full text; Source Code opens the
      public GitHub repository (not a 404).
- [ ] Export Diagnostics… → the save panel starts in Downloads; saving shows the file in
      Finder. The file has the right version, the permissions, the settings and the log since
      launch, and **none** of the clipboard contents.

## 17. Resources and updates

- [ ] Idle for 5 minutes with the main window closed → KeyBridge uses about 0 % CPU (Activity
      Monitor) and a stable amount of memory.
- [ ] Type quickly in a long document for a minute → no lag, no dropped or doubled keys.
- [ ] (Once automatic updates ship) Check for Updates finds, installs and relaunches into a
      newer test build, keeping all settings and permissions.
- [ ] Delete KeyBridge from Applications (or `brew uninstall --cask keybridge`) → the keyboard
      and mouse behave as on a plain Mac.
