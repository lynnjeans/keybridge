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
`project.yml` and run `xcodegen generate`. Do the same after adding any file: entries added to
`project.pbxproj` by hand build fine but carry made-up object IDs, so the next `xcodegen generate`
rewrites them and shows up as an unrelated diff.

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
- The guide never shows a system permission alert. For Accessibility, the plain
  `AXIsProcessTrusted()` check made at launch is enough to list KeyBridge in the pane; the
  prompting variant was dropped because its alert opened on top of the deep-linked pane and then
  lingered behind System Settings with a Deny button. Input Monitoring is different: checking
  (`IOHIDCheckAccess`) leaves its list empty, so the guide calls `IOHIDRequestAccess` itself as
  soon as it reaches step 2 while the status is `notDetermined` (once per run), and again from
  the step's button. Expected log: `Onboarding requested inputMonitoring on reaching its step`
  right after `accessibility: denied → granted`, then `inputMonitoring: notDetermined → granted`
  in the same instant — step 2 passes without the user doing anything.
- **With Accessibility already granted, macOS may grant Input Monitoring silently.** Observed on
  macOS 26: `IOHIDRequestAccess` returned granted within about 1.5 s with no alert and no row in
  the Input Monitoring list, and the tap received ordinary key presses (`keyboard=` counts above
  zero). So "Granted" in KeyBridge with "No Items" in System Settings is not a detection bug, but
  the grant cannot be switched off there either — reset it with `tccutil reset ListenEvent`.
  The `tccd` log shows why: with Accessibility granted, the `kTCCServiceListenEvent` request is
  answered "allowed" within milliseconds, without asking anyone — and KeyBridge never gets a row
  of its own (a row seen in one run had been added by hand with "+"). Judge the grant by the
  `keyboard=` counter, not by the list.
- **Once Input Monitoring reads `denied`, step 2 is a dead end.** `IOHIDRequestAccess` then does
  nothing — no alert, no row — so the pane stays at "No Items" however often the button is
  pressed. Seen in a process that had read `denied` while Accessibility was still missing and
  kept that value after Accessibility was granted — likely the same in-process staleness as
  revocation below. After `tccutil reset ListenEvent io.github.lynnjeans.KeyBridge` and a
  relaunch, the fresh process read `granted` straight away, with no request, because
  Accessibility was granted — and the guide skipped itself. The launch log line
  `inputMonitoring: denied` rather than `notDetermined` gives the state away. Tracked in #125.
- **An explicit Input Monitoring "off" wins over Accessibility.** The silent grant above applies
  only while Input Monitoring is undecided. Add KeyBridge to the list with "+" and switch it off,
  and a fresh launch reads `inputMonitoring: denied` with Accessibility still on, so the engine
  does not start the tap.
- **Changing an Input Monitoring switch relaunches KeyBridge.** System Settings offers to quit
  and reopen the app; runningboard logs the relaunch with `com.apple.coreservices.uiagent` as the
  originator, and each change shows in the `tccd` log as
  `TCCDEvent: type=Modify, service=kTCCServiceListenEvent`. The new process reads the real
  state. Only if the user postpones that relaunch can the running process report a stale
  status — still to be checked (#126). Accessibility changes are picked up by the 2-second poll
  without a relaunch.
- **System Settings' privacy lists refresh late.** Right after a grant, or after a deep link,
  a pane can show "No Items" for a few seconds before KeyBridge's row appears. Wait, or reopen
  the pane, before concluding the row is missing.
- **KeyBridge is not frontmost at launch, even when started from Finder**, and
  `NSApplication.activate()` is refused while another app is frontmost. The guide therefore
  orders its own window front (`orderFrontRegardless`) when it appears and on every step change,
  so it is in view without being the active app. To check, list on-screen windows front to back
  with `CGWindowListCopyWindowInfo` and look for `Set Up KeyBridge` first; the frontmost
  *application* stays whatever the user had before.
- To confirm that grants survive a rebuild, build a bundle that genuinely differs. Swift builds
  are deterministic, so touching a source file can produce a byte-identical binary. Override the
  build number instead:

  ```bash
  xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -configuration Debug \
    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=99 build
  ```

## Configuration file

- The user's changes to the built-in rules live in
  `~/Library/Application Support/KeyBridge/config.json`: a `schemaVersion` and a list of
  `overrides`. No file means nothing has been changed. It is read once at launch, so after
  editing it by hand, relaunch KeyBridge. The launch logs one line in the `configuration`
  category: `No configuration file…`, `Configuration loaded: n override(s)`, or a migration or
  error message.
- An override holds a **complete** rule — the synthesized decoder does not fill in missing
  fields — so copy a rule's encoded form rather than writing one from memory. A `modified`
  rule replaces the built-in rule with the same `id` (`edit.copy`, `mouse.back`, …; see
  `BuiltInRules.swift`); `"isEnabled": false` switches it off. A `custom` rule is added.
- A file KeyBridge cannot use is renamed `config.unreadable-<date>.json` and the built-in rules
  are used; a file from an older version is upgraded in place with the original kept as
  `config.v<n>.json`; a file from a newer version is read but never overwritten. To start
  clean, quit KeyBridge and delete the folder.

## Shortcuts page and group switches

- The Shortcuts page shows the preset as group cards. Switching a group off writes
  `disabledGroups` into `config.json` **and** hands the engine the new rules in the same step, so
  the effect is immediate: switch off Editing and Ctrl+C stops being turned into ⌘C, while the
  group's entries stay listed but greyed out. Each change logs
  `Group <id> switched off` / `on` in the `configuration` category — check that, and the file,
  rather than the switch's colour: **in an inactive window macOS draws an "on" switch grey**, so a
  screenshot of a background window says nothing about switch state.
- Search filters to individual entries and hides groups with no match; a filtered group header
  reads "2 of 4 mappings".
- **The main window always reopens on Overview**: the selected page is `@SceneStorage`, which
  `open` does not restore for this app. Any screenshot of another page therefore needs the page
  clicked first — and Claude's shell cannot click (see "Posting test events").

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

## Layout in other languages

German and French run about 30% longer than English, so every page must wrap rather than cut
text off. Three more debug switches open a window without clicking, so each page can be
screenshotted in each language:

| Variable | Effect |
|---|---|
| `KB_DEBUG_SHOW` | `main`, `onboarding` or `clipboard` (the history panel) opens a second after launch |
| `KB_DEBUG_PAGE` | The main window shows this page: `overview`, `shortcuts`, `mouse`, `scroll`, `clipboard`, `customRules`, `about` |
| `KB_DEBUG_EXPAND_ALL` | Every group on the Shortcuts page starts expanded |

```bash
open build/Build/Products/Debug/KeyBridge.app --env KB_DEBUG_SHOW=main \
  --env KB_DEBUG_PAGE=shortcuts --env KB_DEBUG_EXPAND_ALL=1 \
  --args -AppleLanguages '(en)' -NSDoubleLocalizedStrings YES
```

- `-NSDoubleLocalizedStrings YES` repeats every localized string twice, a harsher test than any
  real language. Format specifiers come out mangled (`lld`, `@`); that is the pseudo-language, not
  a bug.
- Check at the smallest window, 780 pt wide, as well as the default 880. System Events can set the
  size and scroll the page:
  `osascript -e 'tell application "System Events" to tell process "KeyBridge" to set size of window 1 to {780, 860}'`,
  then `set value of scroll bar 1 of scroll area 1 of group 2 of splitter group 1 of group 1 of window 1 to 0.5`.
- Rows with a control beside text use `AdaptiveRow`: the text keeps a minimum width, and the
  control moves under it when it cannot. Groups of buttons use `WrappingControls`. A plain `HStack`
  with a `Spacer` squeezes the text to a word per line or truncates the button instead.
- Not reachable this way: the menu bar menu, the rule editor sheets and alerts. Check those by hand.

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

KeyBridge names other remappers it finds running in a notice on the Overview (KB-043). It reads
the user's own process list every 5 seconds — `NSWorkspace.runningApplications` does not list
agents that launchd starts, which is where most of these tools do their work — and logs each
change in the `permissions` category as `Other remappers running: …`. For Karabiner-Elements
only the user-level `Karabiner-Console-User-Server` counts: its root daemons
(`Karabiner-Core-Service`, `Karabiner-VirtualHIDDevice-Daemon`) keep running after the user quits
it from its menu. The list of tools is `OtherRemapperMonitor.Tool.known`.

To test without installing one of them, run any binary from a bundle whose `Info.plist` has a
listed identifier (for example `com.caldis.Mos`). Build the bundle in a folder not named `.app`
and rename it afterwards, since macOS refuses writes into an existing app bundle, and use a
binary you compiled: a copy of a system binary such as `/bin/sleep` is killed at launch.

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
