#!/usr/bin/env bash
#
# bootstrap-github.sh — create the KeyBridge GitHub project: repository,
# labels, milestones and the full v1.0 backlog as issues.
#
# Prerequisites:
#   brew install gh && gh auth login
#
# Usage:
#   ./scripts/bootstrap-github.sh                   # create everything
#   REPO=owner/name ./scripts/bootstrap-github.sh   # target an existing repo
#
# Re-running is safe for labels and milestones (existing ones are skipped).
# Issues are NOT deduplicated — a second run creates duplicates.

set -euo pipefail

REPO_NAME="keybridge"
VISIBILITY="private"   # switch to "public" when the project opens up

# ---------------------------------------------------------------- preflight --

command -v gh >/dev/null 2>&1 || {
  echo "error: gh is not installed.  Run: brew install gh" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || {
  echo "error: gh is not authenticated.  Run: gh auth login" >&2; exit 1; }

if [[ -z "${REPO:-}" ]]; then
  OWNER="$(gh api user --jq .login)"
  REPO="${OWNER}/${REPO_NAME}"
fi

echo "==> Target repository: ${REPO}"

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "    repository already exists — reusing it"
else
  echo "    creating ${VISIBILITY} repository…"
  gh repo create "$REPO" --"$VISIBILITY" \
    --description "A Mac shortcut bridge for Windows users — keep your muscle memory on macOS." \
    --source=. --remote=origin
fi

# ------------------------------------------------------------------- labels --

echo "==> Creating labels…"
label() {
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
  echo "    · $1"
}

label "P0"                 "B60205" "Blocking or foundational — must come first"
label "P1"                 "1D76DB" "Core functionality — required for v1.0"
label "P2"                 "C5DEF5" "Enhancement — can be deferred"

label "module:foundation"  "5319E7" "Project scaffolding and system permissions"
label "module:engine"      "5319E7" "CGEventTap event engine"
label "module:device"      "5319E7" "Device identification (IOHIDManager)"
label "module:rules"       "5319E7" "Rule model and storage"
label "module:keyboard"    "5319E7" "Keyboard remapping"
label "module:mouse"       "5319E7" "Mouse and scroll wheel"
label "module:presets"     "5319E7" "Windows preset packs"
label "module:ui"          "5319E7" "User interface"
label "module:clipboard"   "5319E7" "Clipboard manager"
label "module:i18n"        "5319E7" "Localization"
label "module:release"     "5319E7" "Distribution and license compliance"
label "module:qa"          "5319E7" "Quality assurance"
label "module:window"      "5319E7" "Window management (v1.1)"

# --------------------------------------------------------------- milestones --

echo "==> Creating milestones…"
milestone() {
  if gh api "repos/${REPO}/milestones" --jq '.[].title' 2>/dev/null | grep -qxF "$1"; then
    echo "    · $1 (exists)"
  else
    gh api "repos/${REPO}/milestones" -f title="$1" -f description="$2" >/dev/null
    echo "    · $1"
  fi
}

milestone "M0 Foundation & Permissions" "App launches, guides the user through authorization, and shows permission state"
milestone "M1 Event Engine"             "Reliably intercept keyboard, mouse and scroll events, with the robustness groundwork in place"
milestone "M2 Device Identification"    "Per-device configuration, and scroll features that apply to mice only"
milestone "M3 Rule Model & Storage"     "Preset layer + user override layer; re-applying a preset never loses customizations"
milestone "M4 Keyboard Remapping"       "Any combo-to-combo mapping works reliably"
milestone "M5 Mouse & Scroll"           "Side-button navigation and modifier+scroll page zoom — the differentiator"
milestone "M6 Windows Presets"          "One click to a Windows feel, every entry still individually editable"
milestone "M7 UI Shell"                 "Native macOS look; usable by a newcomer with no learning curve"
milestone "M8 Clipboard"                "Win+V style history — an independent subsystem that can be built in parallel"
milestone "M9 Localization"             "English as the root language, Chinese and Japanese switchable, follows the system"
milestone "M10 Distribution & Compliance" "A signed, notarized build ready to ship, with GPL compliance"
milestone "M11 Quality"                 "Regressions catchable, problems diagnosable"
milestone "v1.1 Window Snapping"        "Flagship increment: Win+←/→/↑ half-screen and maximize"
milestone "v2 Deep Keyboard Remapping"  "DriverKit, tap/hold and layers — needs its own feasibility review"

# ------------------------------------------------------------------- issues --

echo "==> Creating issues…"
issue() {
  local id="$1" title="$2" prio="$3" mod="$4" ms="$5" est="$6" deps="$7" desc="$8"
  shift 8
  local ac=""
  for a in "$@"; do ac+="- [ ] ${a}"$'\n'; done

  gh issue create --repo "$REPO" \
    --title "${id} ${title}" \
    --label "$prio" --label "$mod" \
    --milestone "$ms" \
    --body "$(cat <<EOF
**Estimate** ${est}　·　**Depends on** ${deps}

## Description
${desc}

## Acceptance criteria
${ac}
---
<sub>From the KeyBridge v1.0 development plan · ${ms}</sub>
EOF
)" >/dev/null
  echo "    · ${id} ${title}"
}

# ---- M0 Foundation & Permissions -------------------------------------------
issue "KB-001" "Set up Xcode project and menu bar shell" "P0" "module:foundation" "M0 Foundation & Permissions" "1d" "—" \
"Create the Swift/SwiftUI project with a \`MenuBarExtra\` that stays resident plus an empty main window. Put the GPL-3.0 LICENSE in place." \
"Menu bar icon stays resident and opens the main window" "Builds and runs natively on Apple Silicon"

issue "KB-002" "Configure stable development signing" "P0" "module:foundation" "M0 Foundation & Permissions" "0.5d" "KB-001" \
"Set up a Developer ID / stable signing identity so granted system permissions survive rebuilds instead of being revoked on every compile." \
"Permissions stay granted across repeated build-and-run cycles"

issue "KB-003" "Permission detection service" "P0" "module:foundation" "M0 Foundation & Permissions" "1d" "KB-001" \
"Wrap Accessibility (\`AXIsProcessTrusted()\`) and Input Monitoring (\`IOHIDCheckAccess()\`) state queries behind one service." \
"Each permission's state can be read independently and accurately" "A single \"all required permissions granted\" check is exposed"

issue "KB-004" "Live permission refresh and revocation handling" "P0" "module:foundation" "M0 Foundation & Permissions" "1d" "KB-003" \
"Re-check on \`didBecomeActive\` and on a light poll. If a permission is revoked while running, degrade to the unauthorized state cleanly." \
"Granting a permission turns the UI green without restarting the app" "Revoking a permission mid-session does not crash and the state rolls back correctly"

issue "KB-005" "First-run permission onboarding (3 steps)" "P0" "module:foundation" "M0 Foundation & Permissions" "2d" "KB-003" \
"Explain why each permission is needed, deep-link to the right System Settings pane, then detect the grant and advance automatically. The master toggle stays disabled until both are granted." \
"Deep links open the correct authorization pane" "The flow advances on its own once a permission is granted"

issue "KB-006" "Permission status display and master toggle gating" "P0" "module:foundation" "M0 Foundation & Permissions" "1d" "KB-004" \
"Overview permission card: green \"Ready\" when both are granted, amber \"Action needed\" with a jump-to-settings button otherwise. Menu bar icon shows a muted state when unauthorized." \
"The user can tell at any time whether all required permissions are granted" "When a permission is missing the master toggle is disabled and the reason is stated"

# ---- M1 Event Engine --------------------------------------------------------
issue "KB-010" "CGEventTap lifecycle management" "P0" "module:engine" "M1 Event Engine" "2d" "KB-003" \
"Create, enable, and tear down the event tap; attach it to a run loop; subscribe to keyboard, mouse button and scroll wheel event types." \
"All three event categories are received and passed through reliably" "Everything is released cleanly on quit with nothing left behind"

issue "KB-011" "Auto-recover from EventTap disable" "P0" "module:engine" "M1 Event Engine" "1d" "KB-010" \
"Watch for \`kCGEventTapDisabledByTimeout\` and \`ByUserInput\` and re-enable the tap automatically. Without this the app silently stops working under load." \
"Functionality recovers on its own after a deliberately induced timeout" "Each recovery is written to the diagnostic log"

issue "KB-012" "Tag injected events to prevent feedback loops" "P0" "module:engine" "M1 Event Engine" "1d" "KB-010" \
"Stamp synthesized events via \`eventSourceUserData\` and pass our own events straight through when they re-enter the tap." \
"Remapping never produces an infinite loop" "Self-generated events are not rewritten a second time"

issue "KB-013" "Rule matching and dispatch pipeline" "P0" "module:engine" "M1 Event Engine" "3d" "KB-010, KB-030" \
"The core path: event → scope filter (device / app) → rule match → action. Must stay low-latency." \
"Matching rules fire correctly and unmatched events pass through untouched" "Per-event processing time is measurable and adds no perceptible latency"

issue "KB-014" "Frontmost application detection" "P1" "module:engine" "M1 Event Engine" "0.5d" "KB-001" \
"Read the frontmost app's bundle identifier via \`NSWorkspace\` to drive per-app scoping." \
"The bundle identifier updates immediately when the user switches apps"

# ---- M2 Device Identification -----------------------------------------------
issue "KB-020" "Enumerate HID devices with IOHIDManager" "P1" "module:device" "M2 Device Identification" "1.5d" "KB-001" \
"List connected keyboards and mice with vendor ID, product ID and name, and observe connect/disconnect changes." \
"The Razer ProClick (0x1532/0x0076) is identified correctly" "The device list updates live on plug and unplug"

issue "KB-021" "Associate events with source device" "P1" "module:device" "M2 Device Identification" "2d" "KB-020, KB-010" \
"Tie the event stream back to a specific device so different mice can carry different configurations." \
"Two mice can have different rule sets applied simultaneously"

issue "KB-022" "Distinguish trackpad from mouse scrolling" "P0" "module:device" "M2 Device Identification" "2d" "KB-010" \
"Use \`continuous\`, \`phase\` and \`momentumPhase\` to tell where a scroll came from. Prerequisite for every scroll feature." \
"Trackpad scrolling is unaffected by reversal and zoom rules" "Mouse wheel detection is accurate enough for everyday use"

# ---- M3 Rule Model & Storage ------------------------------------------------
issue "KB-030" "Rule data model" "P0" "module:rules" "M3 Rule Model & Storage" "1.5d" "—" \
"Codable definitions for \`Rule\` (from/to), \`Preset\`, \`Override\` and \`Scope\` (device / app)." \
"The model can express every entry in the Windows preset packs" "Encoding and decoding round-trips without loss"

issue "KB-031" "Preset + override merge logic" "P0" "module:rules" "M3 Rule Model & Storage" "2d" "KB-030" \
"Effective rules = preset layer merged with the user override layer, override winning. Re-applying a preset must preserve entries the user has edited." \
"Re-applying a preset leaves customized entries untouched" "Entries the user never touched pick up the new preset values"

issue "KB-032" "Config persistence and schema migration" "P1" "module:rules" "M3 Rule Model & Storage" "1d" "KB-030" \
"Persist configuration locally with a schema version and a migration path." \
"Configuration is fully restored after a restart" "Older configuration files migrate without user intervention"

issue "KB-033" "Per-app scoping and exception list" "P1" "module:rules" "M3 Rule Model & Storage" "1.5d" "KB-030, KB-014" \
"Let rules target a bundle identifier — the Finder suite applies only to \`com.apple.finder\`. Ship a built-in exception so Ctrl+C stays an interrupt in terminals." \
"Finder rules do not fire in other applications" "Ctrl+C keeps its interrupt behaviour in Terminal and iTerm"

# ---- M4 Keyboard Remapping --------------------------------------------------
issue "KB-040" "Combo-to-combo remap executor" "P0" "module:keyboard" "M4 Keyboard Remapping" "3d" "KB-013, KB-012" \
"Parse modifier flags and key codes, swallow the original event, and synthesize the target combination (e.g. Ctrl+C to ⌘C)." \
"Ctrl+C/V/Z and Home/End behave correctly across common apps" "Key repeat and modifier release ordering behave correctly"

issue "KB-041" "Secure Input detection and user notice" "P1" "module:keyboard" "M4 Keyboard Remapping" "1d" "KB-040" \
"Detect \`IsSecureEventInputEnabled()\` and tell the user plainly that remapping is suspended in password fields — a system limitation, not a bug." \
"Focusing a password field surfaces an understandable notice instead of silently failing"

issue "KB-042" "fn modifier support" "P1" "module:keyboard" "M4 Keyboard Remapping" "1d" "KB-040" \
"Recognize the \`secondaryFn\` flag so combinations like fn+C can be used as triggers." \
"Combinations such as fn+C can be mapped" "Pressing fn on its own keeps its native behaviour"

# ---- M5 Mouse & Scroll ------------------------------------------------------
issue "KB-050" "Side button mapping" "P0" "module:mouse" "M5 Mouse & Scroll" "1.5d" "KB-013" \
"Intercept buttons 4 and 5 and map them to any shortcut, defaulting to ⌘[ and ⌘] for browser back and forward." \
"Side buttons navigate back and forward in browsers" "The detected button number is visible and remappable in the UI"

issue "KB-051" "Mouse buttons to system actions" "P2" "module:mouse" "M5 Mouse & Scroll" "1d" "KB-050" \
"Map buttons to Mission Control, space switching, Launchpad and similar system actions." \
"At least three common system actions are supported"

issue "KB-052" "Modifier + scroll to page zoom" "P0" "module:mouse" "M5 Mouse & Scroll" "2d" "KB-013, KB-022" \
"Intercept scroll events and synthesize ⌘+ / ⌘− while the configured modifier is held. The modifier is selectable: fn, Ctrl, or custom. This is the capability no free tool offers." \
"Modifier+scroll zooms page content in browsers and documents" "The modifier is switchable in the UI, and choosing Ctrl warns about the system screen-zoom conflict"

issue "KB-053" "Reverse scroll direction (mouse only)" "P1" "module:mouse" "M5 Mouse & Scroll" "1d" "KB-022" \
"Reverse mouse wheel direction while leaving the trackpad on the system setting." \
"Mouse direction is reversed and the trackpad is unaffected"

issue "KB-054" "Pointer speed and acceleration curve" "P2" "module:mouse" "M5 Mouse & Scroll" "2d" "KB-021" \
"Allow disabling the system acceleration curve for a linear feel. LinearMouse (GPL-compatible) can be reused here." \
"Acceleration can be toggled and speed adjusted"

# ---- M6 Windows Presets -----------------------------------------------------
issue "KB-060" "Built-in Windows preset packs (6 groups)" "P1" "module:presets" "M6 Windows Presets" "2.5d" "KB-030, KB-033" \
"Editing, text navigation, file management (Finder), windows and apps, browser, and system extras (F1–F12, Win+., Win+Shift+S, Win key to Spotlight)." \
"Every \"bulk\" and \"dedicated\" entry from the coverage list is implemented" "The Finder group is correctly scoped to Finder only"

issue "KB-061" "One-click apply without overwriting customizations" "P1" "module:presets" "M6 Windows Presets" "2d" "KB-031, KB-060" \
"The Apply / Re-apply action on the Overview and Shortcuts pages, built on the merge semantics from KB-031." \
"Applying a preset activates all its groups immediately" "Entries the user customized are preserved and stay marked as such"

issue "KB-062" "Smart exception prompt" "P2" "module:presets" "M6 Windows Presets" "1d" "KB-033" \
"When the user is a frequent terminal user, keep Ctrl+C reserved automatically and explain it once." \
"The notice appears only once and can be revisited in settings"

# ---- M7 UI Shell ------------------------------------------------------------
issue "KB-070" "Main window frame and sidebar navigation" "P1" "module:ui" "M7 UI Shell" "1.5d" "KB-001" \
"\`NavigationSplitView\` with a sidebar and detail pane, seven navigation items, light and dark appearance." \
"Navigation is smooth and both appearances render correctly"

issue "KB-071" "Overview page" "P1" "module:ui" "M7 UI Shell" "2d" "KB-006, KB-061" \
"Master toggle, one-click apply bar, summary counts, permission card, device card and contextual notices." \
"Matches the approved design mockup" "Every state (unauthorized / ready) renders correctly"

issue "KB-072" "Shortcuts page" "P1" "module:ui" "M7 UI Shell" "3d" "KB-060" \
"Preset bar (switch / re-apply), search, group cards with a group-level toggle and expansion, and per-entry mapping rows." \
"All six groups can be toggled and expanded" "Search filters down to individual entries"

issue "KB-073" "Keycap component" "P1" "module:ui" "M7 UI Shell" "1d" "KB-070" \
"A reusable keycap view rendering modifier symbols and \"before → after\" mappings." \
"Any key combination renders correctly" "Legible in both light and dark appearance"

issue "KB-074" "Per-entry editor with customization marker" "P1" "module:ui" "M7 UI Shell" "2.5d" "KB-073, KB-031" \
"Edit a single mapping with shortcut recording; a changed entry is marked Customized and written to the override layer." \
"Recording captures combinations including modifiers" "Changes land in the override layer and the UI marks them correctly"

issue "KB-075" "Mouse and Scroll pages" "P1" "module:ui" "M7 UI Shell" "1.5d" "KB-070" \
"Side button configuration, zoom toggle with modifier selection, and scroll direction reversal." \
"Every control drives the engine in real time"

issue "KB-076" "Devices page" "P2" "module:ui" "M7 UI Shell" "1d" "KB-020" \
"List connected devices and provide an entry point to their individual configuration." \
"The list refreshes live as devices connect and disconnect"

issue "KB-077" "Custom rule editor (advanced)" "P2" "module:ui" "M7 UI Shell" "2.5d" "KB-074" \
"Create arbitrary combo-to-combo rules with device and app scope." \
"Rules can be created, edited and deleted, taking effect immediately"

issue "KB-078" "Menu bar menu and quick pause" "P1" "module:ui" "M7 UI Shell" "1.5d" "KB-070" \
"Menu bar dropdown with the master toggle, a temporary pause, open main window, and quit." \
"The app can be paused and resumed without opening the main window"

# ---- M8 Clipboard -----------------------------------------------------------
issue "KB-080" "NSPasteboard monitoring and capture" "P1" "module:clipboard" "M8 Clipboard" "1.5d" "KB-001" \
"Poll \`changeCount\` to capture clipboard changes, preserving the original data types." \
"Text, image and file copies are all captured" "Polling overhead is negligible"

issue "KB-081" "History storage and retention limits" "P1" "module:clipboard" "M8 Clipboard" "2d" "KB-080" \
"Persist history locally with a configurable item cap; evict oldest entries when full, except pinned ones." \
"History survives a restart" "Eviction follows the configured policy once the cap is reached"

issue "KB-082" "Privacy filtering (security-critical)" "P0" "module:clipboard" "M8 Clipboard" "1.5d" "KB-080" \
"Skip sensitive and transient types such as \`org.nspasteboard.ConcealedType\`, and support excluding specific apps. Getting this wrong leaks passwords." \
"Content copied from password managers is never recorded" "The exclusion list works and is editable"

issue "KB-083" "Global hotkey and popup panel" "P1" "module:clipboard" "M8 Clipboard" "2.5d" "KB-081" \
"⌘⇧V by default brings up the history panel — native UI, fully keyboard-operable." \
"The panel opens from any application" "The hotkey is customizable and conflicts are reported"

issue "KB-084" "Search and pinned favorites" "P1" "module:clipboard" "M8 Clipboard" "1.5d" "KB-083" \
"Fuzzy search across history; pinned entries stay on top and are never evicted." \
"Search responds instantly" "Pinned entries survive a restart"

issue "KB-085" "Select to paste" "P1" "module:clipboard" "M8 Clipboard" "1d" "KB-083" \
"Selecting an entry writes it back to the pasteboard and pastes it into the frontmost app." \
"The selected entry pastes correctly in its original data type"

# ---- M9 Localization --------------------------------------------------------
issue "KB-090" "Adopt String Catalog and extract strings" "P1" "module:i18n" "M9 Localization" "1.5d" "KB-072" \
"Introduce \`.xcstrings\` and move every hard-coded UI string to a semantic key." \
"No hard-coded strings remain in the UI" "Missing keys are surfaced by Xcode"

issue "KB-091" "Three-language support and switching" "P1" "module:i18n" "M9 Localization" "2d" "KB-090" \
"English, Simplified Chinese and Japanese. Follow the system language by default, allow a manual override, and fall back to English for missing keys." \
"All three languages are complete with no gaps" "Switching takes effect immediately and persists"

issue "KB-092" "Layout resilience for long translations" "P2" "module:i18n" "M9 Localization" "1d" "KB-091" \
"German and French run roughly 30% longer than English; layouts must flex rather than truncate." \
"Layouts hold with simulated over-long strings"

# ---- M10 Distribution & Compliance ------------------------------------------
issue "KB-100" "Signing, notarization and DMG packaging" "P0" "module:release" "M10 Distribution & Compliance" "2d" "KB-002" \
"Developer ID signing plus notarization and a DMG packaging script, so Gatekeeper opens the app without warnings." \
"A fresh machine can download and open the app with no warning" "The packaging process is scripted and repeatable"

issue "KB-101" "Automatic updates via Sparkle" "P1" "module:release" "M10 Distribution & Compliance" "1.5d" "KB-100" \
"Integrate Sparkle with an update feed and signature verification." \
"An older build updates itself to a newer one"

issue "KB-102" "GitHub Release and Homebrew Cask" "P1" "module:release" "M10 Distribution & Compliance" "1d" "KB-100" \
"A release process and a Cask formula supporting \`brew install --cask\`." \
"Release artifacts download and install" "Cask installation succeeds"

issue "KB-103" "GPL-3.0 compliance and third-party notices" "P0" "module:release" "M10 Distribution & Compliance" "0.5d" "—" \
"LICENSE plus \`THIRD_PARTY_NOTICES\` listing every dependency's license and copyright. Confirm no NC-licensed code was pulled in." \
"Every dependency's license notice is present" "No code from Mos or Mac Mouse Fix has been incorporated"

issue "KB-104" "Donation links" "P2" "module:release" "M10 Distribution & Compliance" "0.5d" "KB-078" \
"GitHub Sponsors / Open Collective links shown on the About page and in the repository." \
"The About page links out to the donation page"

# ---- M11 Quality ------------------------------------------------------------
issue "KB-110" "Unit tests for core logic" "P1" "module:qa" "M11 Quality" "2d" "KB-031, KB-040" \
"Cover rule merging (preset + override), scope filtering and event matching." \
"Key branches of merging and matching have test cases" "Tests run in CI"

issue "KB-111" "Manual test checklist and regression pass" "P1" "module:qa" "M11 Quality" "1.5d" "all feature issues" \
"Cover common apps (browsers, Finder, terminals, Office), permission revocation, Secure Input and multi-device setups." \
"The checklist is reusable for every release regression pass"

issue "KB-112" "Diagnostic logging and issue reporting" "P2" "module:qa" "M11 Quality" "1.5d" "KB-010" \
"Record key events such as event tap restarts and permission changes, and offer a way to export diagnostics." \
"Diagnostics can be exported to accompany a user report"

# ---- v1.1 Window Snapping ---------------------------------------------------
issue "KB-200" "Window manipulation foundation" "P1" "module:window" "v1.1 Window Snapping" "2.5d" "KB-003" \
"Read and write the frontmost window's frame via \`AXUIElement\`; the Accessibility permission is already in place." \
"Any frontmost window can be moved and resized"

issue "KB-201" "Snap shortcuts for half-screen and maximize" "P1" "module:window" "v1.1 Window Snapping" "2d" "KB-200" \
"Left and right half-screen plus maximize-in-place, distinct from the macOS green-button fullscreen space." \
"Positions are computed correctly across multiple displays"

issue "KB-202" "Drag-to-edge auto snapping" "P2" "module:window" "v1.1 Window Snapping" "3d" "KB-200" \
"Detect a drag to a screen edge, show a snap preview and settle the window on release." \
"Drag preview and release snapping feel smooth"

issue "KB-203" "Window page UI" "P1" "module:window" "v1.1 Window Snapping" "1.5d" "KB-201" \
"Add a Window navigation item with its configuration toggles." \
"Consistent with the existing design language"

# ---- v2 Deep Keyboard Remapping ---------------------------------------------
issue "KB-300" "DriverKit virtual HID engine" "P2" "module:keyboard" "v2 Deep Keyboard Remapping" "5d+" "stable v1.0" \
"Introduce a second engine as a system extension, coexisting with the CGEventTap engine." \
"The system extension installs and runs reliably"

issue "KB-301" "Tap/hold dual-role keys" "P2" "module:keyboard" "v2 Deep Keyboard Remapping" "4d" "KB-300" \
"A timeout state machine for keys that behave differently on tap versus hold (Caps as Esc on tap, Control on hold)." \
"Detection is accurate with no spurious triggers"

issue "KB-302" "Layers and simultaneous keys" "P2" "module:keyboard" "v2 Deep Keyboard Remapping" "4d" "KB-301" \
"Support layers and simultaneous key chords." \
"Layer switching and chord triggering are stable"

echo
echo "==> Done."
echo "    Issues:     https://github.com/${REPO}/issues"
echo "    Milestones: https://github.com/${REPO}/milestones"
echo
echo "Next: create a Project board and add the issues —"
echo "    gh project create --owner @me --title 'KeyBridge v1.0'"
