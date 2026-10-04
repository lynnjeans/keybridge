#!/bin/zsh
# Updates SameKeys/Resources/Localizable.xcstrings from the strings the last
# build found in the source. Xcode does this by itself when building in the
# IDE; command-line builds (xcodebuild) only extract, so run this after one.
#
#   xcodebuild -project SameKeys.xcodeproj -scheme SameKeys -derivedDataPath build build
#   scripts/sync-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."
data=(build/Build/Intermediates.noindex/SameKeys.build/Debug/SameKeys.build/Objects-normal/*/*.stringsdata)
xcrun xcstringstool sync SameKeys/Resources/Localizable.xcstrings --stringsdata "${data[@]}"
python3 - <<'PY'
import json
path = "SameKeys/Resources/Localizable.xcstrings"
catalog = json.load(open(path))
strings = catalog["strings"]
# Keys made only of symbols (⌘, +, an empty label) read the same in every
# language; marking them keeps them out of the missing-translation count.
for key, entry in strings.items():
    if not any(c.isalpha() for c in key.replace("%lld", "").replace("%@", "")):
        entry["shouldTranslate"] = False
with open(path, "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    f.write("\n")
stale = [k for k, v in strings.items() if v.get("extractionState") == "stale"]
print(f"{len(strings)} strings, {len(stale)} stale")
PY
