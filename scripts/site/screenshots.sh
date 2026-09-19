#!/bin/zsh
# Takes the website's screenshots: the Shortcuts page and the clipboard
# panel, in every language, light and dark, into site/screenshots/.
#
# Uses the Debug build (build it first) with a fresh settings folder and an
# example clipboard history (KB_DEBUG_SUPPORT_FOLDER), so neither your own
# settings nor your own copies appear. The Mac's appearance should be dark:
# light is forced per launch, dark is not. Keep the pointer away from the
# middle of the screen, or it leaves hover marks. Quits the KeyBridge that is
# running and relaunches it plainly at the end.
set -euo pipefail

root=${0:A:h:h:h}
app=$root/build/Build/Products/Debug/KeyBridge.app
out=$root/site/screenshots
work=$(mktemp -d)
trap 'rm -rf $work' EXIT

[[ -d $app ]] || { print -u2 "Build the Debug app first: $app"; exit 1 }
swiftc -O $root/scripts/site/windows.swift -o $work/windows

quit_keybridge() {
    osascript -e 'quit app "KeyBridge"' >/dev/null 2>&1 || true
    while pgrep -x KeyBridge >/dev/null; do sleep 0.5; done
    # Launch Services lags behind the process; opening at once fails (-600).
    sleep 2
}

# capture <language> <appearance> <what: main|clipboard> <file>
capture() {
    local language=$1 appearance=$2 what=$3 file=$4 support=$work/$1-$2-$3
    rm -rf $support && mkdir -p $support
    python3 $root/scripts/site/sample-clipboard.py $support/Clipboard $language

    local -a arguments=(-AppleLanguages "($language)")
    [[ $appearance == light ]] && arguments+=(-NSRequiresAquaSystemAppearance YES)

    quit_keybridge
    open $app --env KB_DEBUG_SHOW=$what --env KB_DEBUG_PAGE=shortcuts \
        --env KB_DEBUG_SUPPORT_FOLDER=$support --args $arguments
    sleep 3
    if [[ $what == main ]]; then
        # Active, so switches and the selection show their colour.
        osascript -e 'tell application "KeyBridge" to activate'
        osascript -e 'tell application "System Events" to tell process "KeyBridge" to set size of window 1 to {880, 700}'
        sleep 1
    fi

    local layer=0
    [[ $what == clipboard ]] && layer=3
    local id=$($work/windows | awk -v layer=$layer '$2 == layer { print $1; exit }')
    [[ -n $id ]] || { print -u2 "No $what window for $language $appearance"; exit 1 }
    mkdir -p ${file:h}
    screencapture -o -x -l$id $file
    print "$file"
}

for language in en zh-Hans ja; do
    for appearance in light dark; do
        capture $language $appearance main $out/$language/shortcuts-$appearance.png
        capture $language $appearance clipboard $out/$language/clipboard-$appearance.png
    done
done

quit_keybridge
open $app
