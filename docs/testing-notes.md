# Testing Notes

How to verify KeyBridge's behaviour on a real Mac, and the traps that produce confidently
wrong results. Every item here cost at least one round of misdiagnosis during development.
This is the seed of the manual test checklist (KB-111).

**Rule of thumb:** when a check reports zero events, no log lines, or "no change", suspect the
check before the code.

---

## Unit tests

Logic that needs no running app (the rule model so far) is covered by the `KeyBridgeTests`
bundle, written with Swift Testing. The bundle compiles the sources it tests itself rather than
loading them from the app, so a test run never launches KeyBridge or starts its event tap.

```bash
xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -configuration Debug \
  -derivedDataPath build/DerivedData test
```

When adding a folder whose code is tested, add it to the `KeyBridgeTests` sources in
`project.yml` and run `xcodegen generate`.

## Launching the app

- **Launch with `open`**, never by running the binary from a terminal. macOS attributes
  permission checks to the responsible process; run from a terminal, that is the terminal, so
  you end up testing the terminal's permissions instead of KeyBridge's.

  ```bash
  open build/DerivedData/Build/Products/Debug/KeyBridge.app
  ```

- KeyBridge is a menu bar app (`LSUIElement`): no Dock icon, and no window opens at launch —
  except on a first run that still needs a permission, which opens the guide below. Its only
  permanent visible presence is the ⌘ icon in the menu bar.

## Permissions

- KeyBridge needs **both** Accessibility and Input Monitoring. With Accessibility alone the
  event tap is still created, and modifier changes, mouse buttons and scrolling still arrive —
  but **ordinary key presses are silently withheld**. A run of Shift presses therefore looks
  like working keyboard input. That is why the debug counters report `keyboard` (key down/up)
  and `modifier` (flag changes) separately. Details in #69.
- Permission changes are picked up while the app runs, by a check every 2 seconds and whenever
  KeyBridge becomes active; each change is logged in the `permissions` category as
  `accessibility: granted → denied`. To test, toggle KeyBridge in System Settings › Privacy &
  Security while it runs. Revoking Accessibility should log `Event tap stopped` with the keyboard
  and mouse still working normally; granting it again should log `Event tap started`, and
  remapping works again without a restart. The menu bar dropdown shows the live state of both
  permissions.
- The engine runs only while the master switch (Overview › Windows Shortcut Mode) is on **and**
  both permissions are granted. With a permission missing, the Overview shows "Action needed",
  the switch is greyed out with the reason below it, and the menu bar icon is faded. The switch
  is remembered across launches (`engineEnabled` in the app's user defaults); to reset it:

  ```bash
  defaults delete io.github.lynnjeans.KeyBridge engineEnabled
  ```

- Opening KeyBridge again while it runs (double-click in Finder, or Spotlight) opens the main
  window — the way in when the notch hides the menu bar icon.
- The first-run guide (Set Up KeyBridge) opens by itself on a first launch that is still missing
  a permission, and walks Accessibility → Input Monitoring → Ready. Its step follows the live
  permission state, so granting one in System Settings moves the window on within the 2-second
  poll, with nothing to click. Once finished it does not return; the menu bar item and the
  Overview both lead back to it while a permission is missing. To replay it, forget both the
  grants and the fact that the guide has been seen, then relaunch:

  ```bash
  tccutil reset Accessibility io.github.lynnjeans.KeyBridge
  tccutil reset ListenEvent io.github.lynnjeans.KeyBridge
  defaults delete io.github.lynnjeans.KeyBridge onboardingCompleted
  ```

  `tccutil reset` kills the running app, and `defaults` writes are cached per process, so quit
  KeyBridge before running these or the old value is written back on quit.
- Each step asks the system for its permission before opening the pane. That request is what
  puts KeyBridge in the System Settings list at all — an app that has never asked has no row to
  switch on — but it prompts only once per app, so from the second time on only the deep link
  does anything visible.
- To confirm that grants survive a rebuild, build a bundle that genuinely differs. Swift builds
  are deterministic, so touching a source file can produce a byte-identical binary. Override the
  build number instead:

  ```bash
  xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -configuration Debug \
    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=99 build
  ```

## Reading the log

- **In zsh, `log` is a shell builtin** that shadows `/usr/bin/log`. `log show …` returns
  nothing and reports no error. Always use the full path:

  ```bash
  /usr/bin/log show --predicate 'subsystem == "io.github.lynnjeans.KeyBridge"' --last 10m --style compact
  ```

- Filter by `processID == <pid>` to separate one launch from the previous one, or pass
  `--start "YYYY-MM-DD HH:MM:SS"`. `--start` takes whole seconds only; a fractional value fails
  with a date conversion error instead of showing anything.
- Log categories: `permissions` (state at launch) and `eventtap` (lifecycle, recoveries, and in
  Debug builds per-category event counts every 3 seconds).
- The counters record **counts only, never event contents** — logging keystrokes would turn
  the system log into a keylogger. Keep it that way.
- Values interpolated into log messages are private by default and show as `<private>`; mark
  them `privacy: .public` only when they carry no personal data.

## Debug switches

Debug builds read these environment variables at launch. Pass them with `open --env`:

| Variable | Effect |
|---|---|
| `KB_DEBUG_SELFTEST` | KeyBridge posts zero-delta scroll events itself: five stamped as its own, then plain ones |
| `KB_DEBUG_STALL_ONCE` | The next event blocks the tap callback for 2 s, so macOS disables the tap and recovery can be observed |
| `KB_DEBUG_MATCHTEST` | Installs two test rules on F19 (one everywhere, one Finder-only), brings Finder to the front and presses F19, switches back to the previous app and presses F19 again, then presses F20, which has no rule |

Expected log for `KB_DEBUG_MATCHTEST` (category `engine`): `Matched rules: selftest.finder=3`,
then `selftest.any=3`, and no match for F20. The `eventtap` category reports per-event
processing time as `Processing: n=… avg=…µs max=…µs`; each call is also a signpost interval
named `process`, so Instruments can chart it in any build. The self-test rules replace the
built-in ones for that launch.

`KB_DEBUG_REMAPTEST` checks what applications actually receive. It starts a debug-only
listen-only tap placed after every other tap (the *downstream probe*), which logs only F17–F20,
and remaps ⌃F19 → ⌥F18. Expected `Downstream:` lines (KeyBridge adds fn to the F18 it
creates, as the hardware does for F-keys; the self-test's own F20 is posted without it):

1. ⌃F19 with two repeats, Ctrl released before F19: `F18 down`, `repeat`, `repeat`, `up`, each
   `[option+fn]`, and no F19.
2. Ctrl released while F19 repeats: `F18 down`, `F18 up` — the repeat without Ctrl is swallowed.
3. F20, which has no rule: `F20 down []`, `F20 up []`, unchanged.
4. Mouse button 4, mapped to ⌥F17: `F17 down`, `F17 up`, and no `button 4` line — the click
   never reaches an application.
5. Mouse button 6, which has no rule: `button 6 down`, `button 6 up`.

The F17, F18 and F20 presses reach the frontmost app, and button 6 clicks at the pointer; nothing
uses those by default.

`KB_DEBUG_SCROLLTEST` installs match-only rules for plain scrolling up and down, which change
nothing on screen because scroll actions are not carried out yet. Scroll with a mouse, then on a
trackpad, and read the log. Each 3-second report then includes `Scroll sources:
notchedWheel=… smoothWheel=… gesture=…`, and only the mouse should produce `Matched rules:
selftest.scrollUp=…` / `selftest.scrollDown=…`. A trackpad flick keeps producing `gesture`
events for a while after the fingers lift; that is momentum, and it must not match either.

## Karabiner-Elements and other HID-level remappers

Tools that remap at the HID level, such as Karabiner-Elements, act before KeyBridge's event tap,
so KeyBridge only ever sees their output. When checking a KeyBridge mapping by hand, make sure no
such tool maps the same input — a Karabiner rule for the side buttons, for example, means
KeyBridge never receives them, and a passing test would be Karabiner's. Events posted by the
self-tests bypass these tools.

```bash
open --env KB_DEBUG_SELFTEST=1 --env KB_DEBUG_STALL_ONCE=1 build/DerivedData/Build/Products/Debug/KeyBridge.app
```

Expected log: `own=5`, then `Event tap was disabled by the system (timeout); re-enabled,
recovery #1`, then the later plain events still counted.

## Posting test events

- A process can post events only if it holds the permission to. **Shells launched by AI coding
  tools and some terminal wrappers often don't**: a helper process in between can break
  permission inheritance, and macOS then drops posted events without any error. Check first:

  ```swift
  import CoreGraphics
  print(CGPreflightPostEventAccess())   // false means posted events will vanish
  ```

- Prefer posting from inside KeyBridge, which does hold the permission — that is what
  `KB_DEBUG_SELFTEST` does.

## Code signing

- **`codesign -dv` does not print the `CDHash`.** Comparing it between builds compares two empty
  strings. Use `codesign -dvvv`.
- What macOS stores when a permission is granted is the app's designated requirement:

  ```bash
  codesign -d -r- KeyBridge.app
  ```

  With a real certificate it names the bundle identifier and the certificate. With ad-hoc
  signing it pins the `cdhash`, which changes on every build — that is why grants are lost.
- To check that a new build would still satisfy a previously granted permission:

  ```bash
  codesign --verify -R="=<requirement from the old build>" KeyBridge.app
  ```

- Hardened runtime shows as `flags=0x10000(runtime)`. Xcode applies it only when signing with a
  real identity; ad-hoc builds run without it.

## Menu bar on macOS 26

- Third-party status items are hosted by **Control Center**, not by the app's own process.
  Listing windows by KeyBridge's PID shows none even when the icon is plainly visible.
- After the app quits, Control Center keeps an off-screen placeholder in its slot and swaps it
  for a live window on relaunch. Counting Control Center's status-level windows therefore gives
  the same number whether KeyBridge is running or not, with a brief extra one during the swap.
- To check for the icon programmatically, list windows at layer 25 owned by Control Center and
  look for an on-screen one at KeyBridge's position. The reliable check is still to look.
- **On a MacBook with a notch, a full menu bar silently hides the items that do not fit.** The
  newest item is the leftmost, so a freshly launched KeyBridge is the first to vanish behind the
  notch while running normally. Listing the layer-25 windows shows it with `onscreen=no` at an
  x position inside the notch (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` give
  its edges). Quit an app or turn off an item in System Settings › Menu Bar to make room.

## Shell scripting

- **zsh does not word-split unquoted variables.** A command stored in a variable
  (`XB="xcodebuild -project …"; $XB build`) runs as a single, nonexistent command name. Use a
  shell function instead.
- **zsh expands a word starting with `=`** into the path of the command it names.
  `echo =====` fails with `==== not found`, and the failed expansion aborts the whole command
  line, so none of the commands chained with `;` run at all. Quote such words: `echo '====='`.
