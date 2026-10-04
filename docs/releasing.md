# Releasing SameKeys

How a release is built and published.

## Making a release

1. **Version.** In `project.yml`, raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Sparkle
   compares the build number, so it must be higher than any build ever installed anywhere,
   test builds included. Run `xcodegen generate`.
2. **Release notes.** Write `release-notes/<version>/` in all three languages (see
   [its README](../release-notes/README.md)). Merge both changes to `main`.
3. **Hand test.** Run [release-checklist.md](release-checklist.md) on a release build and
   track it in an issue.
4. **Build**, on `main` with a clean tree:

   ```bash
   NOTARY_PROFILE=keybridge-notary scripts/release.sh
   ```

   This builds, signs and notarizes the app and then the DMG, staples both and writes
   `dist/SameKeys-<version>.dmg` with its `.sha256`.
5. **Publish:**

   ```bash
   scripts/publish-release.sh
   ```

   It asks before doing anything, then creates the GitHub release `v<version>` with the DMG,
   adds the version to `site/appcast.xml` and pushes. The website workflow deploys the feed in
   a minute or two, and installed copies find the update on their next daily check.
6. **Homebrew:**

   ```bash
   scripts/update-cask.sh
   ```

   It checks that the release serves the same DMG, then writes `Casks/keybridge.rb` in
   [lynnjeans/homebrew-tap](https://github.com/lynnjeans/homebrew-tap).
7. **Check.** The website's download button fetches the new DMG, and
   `brew install --cask lynnjeans/tap/keybridge` installs it. On a copy of the previous
   version, Check for Updates… offers the new one.

## Signing secrets

A release needs three secrets. All live in the maintainer's login keychain on the release Mac,
and none of them is in this repository. The table says where each one is kept and what happens if it is lost.

| Secret | In the keychain as | Backup | If it is lost |
|---|---|---|---|
| **Developer ID Application** certificate and its private key (team `JTCAH836NB`) | "Developer ID Application: Lei Sun (JTCAH836NB)" | A password-protected `.p12`, exported from Xcode › Settings › Accounts › Manage Certificates, kept offline by the maintainer | Issue a new one in the same team. Installed copies keep their permissions, because macOS ties them to the team, not the certificate (`codesign -d -r-` shows `certificate leaf[subject.OU] = JTCAH836NB`) |
| **Notarization credentials** | notarytool profile `keybridge-notary` | None needed | Create a new app-specific password at account.apple.com and run `xcrun notarytool store-credentials keybridge-notary --apple-id <Apple ID> --team-id JTCAH836NB` again |
| **Sparkle EdDSA private key** | Account `keybridge` (`generate_keys --account keybridge`) | Exported with `generate_keys --account keybridge -x <file>`, kept offline by the maintainer | **Installed copies can never be updated again.** They only accept updates signed with this key, whose public half (`SUPublicEDKey`) is built into every release. Guard it like a password |

Restoring on a new Mac:

- Certificate: double-click the `.p12` and enter its password.
- EdDSA key: `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account keybridge -f <file>`.
  Then check that `generate_keys --account keybridge -p` prints the `SUPublicEDKey` from `project.yml`.
- Notarization: store the profile again as above.

Never commit any of these, paste them into an issue or chat, or put them on the website. Anyone
holding the EdDSA key and able to change the appcast could push an update to every installed
copy.
