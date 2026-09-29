# Releasing KeyBridge

How a release is built and published. The hand test before each release is in
[release-checklist.md](release-checklist.md).

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
