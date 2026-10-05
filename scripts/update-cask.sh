#!/bin/zsh
# Points the Homebrew cask at the release publish-release.sh just made (KB-102):
# writes Casks/samekeys.rb in github.com/lynnjeans/homebrew-tap, so that
#
#   brew install --cask lynnjeans/tap/samekeys
#
# installs it. The whole file is written from here on every release, so this
# script is the one place the cask is defined.
#
#   scripts/update-cask.sh
#
# Reads the version from project.yml and the checksum from
# dist/SameKeys-<version>.dmg.sha256 (both from scripts/release.sh), and checks
# that the GitHub release really serves that file. Writes through the GitHub
# API, so nothing is cloned.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { print -P "%B==> $1%b" }
fail() { print -u2 "error: $1"; exit 1 }

tap=lynnjeans/homebrew-tap
cask_file=Casks/samekeys.rb
version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
[[ -n $version ]] || fail "could not read the version from project.yml"
checksum=dist/SameKeys-$version.dmg.sha256
[[ -s $checksum ]] || fail "$checksum is missing; run scripts/release.sh first"
sha256=$(<$checksum)
url=https://github.com/lynnjeans/samekeys/releases/download/v$version/SameKeys-$version.dmg

step "Checking the release download"
served=$(curl -fsSL $url | shasum -a 256 | awk '{ print $1 }') || fail "$url cannot be downloaded; publish the release first"
[[ $served == $sha256 ]] || fail "the release's DMG ($served) is not the one in dist/ ($sha256)"
gh repo view $tap >/dev/null 2>&1 || fail "github.com/$tap does not exist yet"

# Sparkle updates SameKeys in place, so `auto_updates` keeps `brew upgrade`
# from fighting it. The minimum macOS matches the appcast's (scripts/appcast.py):
# `:sonoma` means Sonoma or later.
cask=$(cat <<EOF
cask "samekeys" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/lynnjeans/samekeys/releases/download/v#{version}/SameKeys-#{version}.dmg"
  name "SameKeys"
  desc "Windows keyboard shortcuts and mouse habits"
  homepage "https://samekeys.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "SameKeys.app"

  uninstall quit: "com.samekeys.SameKeys"

  zap trash: [
    "~/Library/Application Support/SameKeys",
    "~/Library/Caches/com.samekeys.SameKeys",
    "~/Library/HTTPStorages/com.samekeys.SameKeys",
    "~/Library/Preferences/com.samekeys.SameKeys.plist",
  ]
end
EOF
)

step "Writing $cask_file in $tap"
existing=$(gh api repos/$tap/contents/$cask_file --jq .sha 2>/dev/null || true)
args=(-X PUT repos/$tap/contents/$cask_file -f message="samekeys $version" -f content=$(print -rn -- "$cask"$'\n' | base64))
[[ -n $existing ]] && args+=(-f sha=$existing)
gh api $args --jq .commit.html_url

step "Done"
print "  Try it: brew update && brew install --cask lynnjeans/tap/samekeys"
