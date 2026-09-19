#!/bin/zsh
# Builds a KeyBridge release: a Release build, signed, packed into a DMG,
# and notarized and stapled when the credentials are there.
#
#   scripts/release.sh
#
# The version and build number come from project.yml (MARKETING_VERSION,
# CURRENT_PROJECT_VERSION); raise them there, commit, then run this.
#
# Signing, first found wins:
#   1. $SIGN_IDENTITY, e.g. "Developer ID Application: Lei Sun (TEAMID)"
#   2. the first "Developer ID Application" identity in the keychain
#   3. ad-hoc ("-"): the app runs on this Mac, but Gatekeeper blocks it on
#      any other until the user allows it in System Settings
# An "Apple Development" certificate is never used: Gatekeeper rejects it on
# other Macs just the same, and it would hide that the release is not ready.
#
# Notarization needs a Developer ID signature and a notarytool keychain
# profile, stored once with
#   xcrun notarytool store-credentials keybridge-notary \
#     --apple-id <Apple ID> --team-id <TEAMID> --password <app-specific password>
# and named here as NOTARY_PROFILE=keybridge-notary. Without it the DMG is
# signed but not notarized.
#
# Output in dist/: KeyBridge-<version>.dmg and KeyBridge-<version>.dmg.sha256
# (the checksum the Homebrew cask needs).
set -euo pipefail
cd "$(dirname "$0")/.."

step() { print -P "%B==> $1%b" }
fail() { print -u2 "error: $1"; exit 1 }

version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
build=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)
[[ -n $version && -n $build ]] || fail "could not read the version from project.yml"

# A release must be reproducible from a commit.
if [[ -n $(git status --porcelain) && -z ${ALLOW_DIRTY:-} ]]; then
  fail "the working tree has uncommitted changes; commit them, or set ALLOW_DIRTY=1 for a test build"
fi

identity=${SIGN_IDENTITY:-}
if [[ -z $identity ]]; then
  identity=$(security find-identity -v -p codesigning | awk -F'"' '/"Developer ID Application/ { print $2; exit }')
fi
identity=${identity:--}
team=""
if [[ $identity != - ]]; then
  [[ $identity == "Developer ID Application"* ]] || fail "SIGN_IDENTITY must be a Developer ID Application identity: $identity"
  team=${${identity##*\(}%\)}
fi

work=build/release
dmg=dist/KeyBridge-$version.dmg
rm -rf $work
mkdir -p $work dist

step "Building KeyBridge $version ($build), signed with: ${identity/#-/ad-hoc}"
sign_flags=()
# A secure timestamp is required for notarization; ad-hoc signatures cannot have one.
[[ $identity != - ]] && sign_flags=(OTHER_CODE_SIGN_FLAGS=--timestamp)
xcodebuild -project KeyBridge.xcodeproj -scheme KeyBridge -configuration Release \
  -derivedDataPath $work/DerivedData -archivePath $work/KeyBridge.xcarchive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
  $sign_flags -quiet archive

app=$work/KeyBridge.xcarchive/Products/Applications/KeyBridge.app
[[ -d $app ]] || fail "the archive has no KeyBridge.app"

step "Checking the app"
built=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $app/Contents/Info.plist)
[[ $built == $version ]] || fail "the app says version $built, project.yml says $version"
codesign --verify --strict --deep $app
if [[ $identity != - ]]; then
  # Notarization rejects apps without the hardened runtime.
  codesign -dvv $app 2>&1 | grep -q "flags=.*runtime" || fail "the app is not signed with the hardened runtime"
fi
[[ -f $app/Contents/Resources/LICENSE ]] || fail "LICENSE is missing from the app (GPL-3.0 requires it)"

step "Packing $dmg"
root=$work/dmg
mkdir -p $root
ditto $app $root/KeyBridge.app
ln -s /Applications $root/Applications
rm -f $dmg
hdiutil create -quiet -volname "KeyBridge $version" -srcfolder $root -fs HFS+ -format UDZO $dmg
[[ $identity != - ]] && codesign --sign "$identity" --timestamp $dmg

notarized=no
if [[ $identity != - && -n ${NOTARY_PROFILE:-} ]]; then
  step "Notarizing (this usually takes a few minutes)"
  result=$(xcrun notarytool submit $dmg --keychain-profile $NOTARY_PROFILE --wait 2>&1) || true
  print -- $result
  if [[ $result != *"status: Accepted"* ]]; then
    id=$(print -- $result | awk '/^ *id:/ { print $2; exit }')
    fail "notarization was not accepted; see: xcrun notarytool log ${id:-<submission id>} --keychain-profile $NOTARY_PROFILE"
  fi
  xcrun stapler staple -q $dmg
  xcrun stapler validate -q $dmg
  spctl --assess --type open --context context:primary-signature $dmg
  notarized=yes
fi

shasum -a 256 $dmg | awk '{ print $1 }' > $dmg.sha256

step "Done"
print "  DMG:        $dmg ($(du -h $dmg | cut -f1 | tr -d ' '))"
print "  SHA-256:    $(cat $dmg.sha256)"
print "  Signed:     ${identity/#-/ad-hoc}"
print "  Notarized:  $notarized"
if [[ $notarized == no ]]; then
  print "  Not ready to publish: Gatekeeper will block this build on other Macs."
  [[ $identity == - ]] && print "  Needs a Developer ID Application certificate (paid Apple Developer Program)."
  [[ $identity != - ]] && print "  Set NOTARY_PROFILE to notarize (see the top of this script)."
fi
