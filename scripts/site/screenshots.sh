#!/bin/zsh
# Takes the website's screenshots: the Shortcuts page and the clipboard
# panel, in every language, light and dark, into site/screenshots/.
#
# Uses the Debug build (build it first) with a fresh settings folder and an
# example clipboard history (KB_DEBUG_SUPPORT_FOLDER), so neither your own
# settings nor your own copies appear. Light and dark are set per launch
# (KB_DEBUG_APPEARANCE), whatever the Mac's own appearance. Keep the pointer
# away from the middle of the screen, or it leaves hover marks. Quits the
# KeyBridge that is running, and at the end opens the one in Applications
# again with its Finder extension.
set -euo pipefail

root=${0:A:h:h:h}
app=$root/build/Build/Products/Debug/KeyBridge.app
out=$root/site/screenshots
work=$(mktemp -d)
trap 'rm -rf $work' EXIT

[[ -d $app ]] || { print -u2 "Build the Debug app first: $app"; exit 1 }
swiftc -O $root/scripts/site/windows.swift -o $work/windows

quit_keybridge() {
    # Not `quit app`: that Apple event can wait on an Automation prompt.
    pkill -x KeyBridge || true
    while pgrep -x KeyBridge >/dev/null; do sleep 0.5; done
    # Launch Services lags behind the process; opening at once fails (-600).
    sleep 2
}

# capture <language> <appearance> <what: main|clipboard> <file>
capture() {
    local language=$1 appearance=$2 what=$3 file=$4 support=$work/$1-$2-$3
    rm -rf $support && mkdir -p $support
    python3 $root/scripts/site/sample-clipboard.py $support/Clipboard $language

    quit_keybridge
    open $app --env KB_DEBUG_SHOW=$what --env KB_DEBUG_PAGE=shortcuts \
        --env KB_DEBUG_APPEARANCE=$appearance --env KB_DEBUG_SUPPORT_FOLDER=$support \
        --args -AppleLanguages "($language)"
    sleep 3
    if [[ $what == main ]]; then
        # Active, so switches and the selection show their colour.
        osascript -e 'tell application "System Events" to set frontmost of process "KeyBridge" to true'
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
# The Debug build registered its own Finder extension; hand it back.
installed=/Applications/KeyBridge.app
if [[ -d $installed ]]; then
    pluginkit -a $installed/Contents/PlugIns/KeyBridgeFinder.appex 2>/dev/null || true
    pluginkit -r $app/Contents/PlugIns/KeyBridgeFinder.appex 2>/dev/null || true
    pkill -x KeyBridgeFinder || true
    open $installed
fi
