#!/bin/zsh
# Renders the image shown when a link to the website is shared, one per
# language, into site/assets/social/: the template social-preview.html with
# the app icon and that language's Shortcuts screenshot, at 2560×1280 by
# Google Chrome. The English image is also the repository's social preview
# on GitHub (Settings › Social preview), uploaded by hand.
set -euo pipefail

root=${0:A:h:h:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
out=$root/site/assets/social
icon=$root/scripts/site/icon.png
trap 'rm -f $icon' EXIT

[[ -x $chrome ]] || { print -u2 "Google Chrome is needed: $chrome"; exit 1 }
"$ictool" $root/SameKeys/Resources/AppIcon.icon --export-image --output-file $icon \
    --platform macOS --rendition Default --width 512 --height 512 --scale 1 >/dev/null

mkdir -p $out
for lang in en zh-Hans ja; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --force-device-scale-factor=2 --window-size=1280,640 \
        --screenshot=$out/$lang.png \
        "file://$root/scripts/site/social-preview.html?lang=$lang" 2>/dev/null
    print "$out/$lang.png $(( $(stat -f %z $out/$lang.png) / 1024 )) KB"
done
