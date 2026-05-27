# Release Signing and Notarization

Tagged releases are built by `.github/workflows/release.yml`. The workflow signs
the `pnt-bpm` command-line binary, signs the installer package, submits the
package to Apple's notary service, staples the notarization ticket, verifies the
result, and then uploads the package to the GitHub release.

This requires an active Apple Developer Program membership and these
certificates:

- Developer ID Application: signs the `pnt-bpm` executable.
- Developer ID Installer: signs the `.pkg` installer.

## GitHub Secrets

Add these repository secrets before pushing the next release tag:

```sh
base64 -i DeveloperIDApplication.p12 | gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --repo keithchambers/pnt-bpm
gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --repo keithchambers/pnt-bpm

base64 -i DeveloperIDInstaller.p12 | gh secret set DEVELOPER_ID_INSTALLER_P12_BASE64 --repo keithchambers/pnt-bpm
gh secret set DEVELOPER_ID_INSTALLER_P12_PASSWORD --repo keithchambers/pnt-bpm

base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_API_KEY_P8_BASE64 --repo keithchambers/pnt-bpm
gh secret set APPLE_API_KEY_ID --repo keithchambers/pnt-bpm
gh secret set APPLE_API_ISSUER_ID --repo keithchambers/pnt-bpm
```

The `.p12` files must include the private keys. Export them from Keychain Access
after creating the Developer ID certificates in the Apple Developer account.
Create the `.p8` key in App Store Connect as an API key that can use the Apple
notary service.

Instead of the App Store Connect API key, the workflow can also notarize with an
Apple ID and app-specific password:

```sh
gh secret set APPLE_ID --repo keithchambers/pnt-bpm --body "djkeithchambers@gmail.com"
gh secret set APPLE_TEAM_ID --repo keithchambers/pnt-bpm --body "6L4C5M8K2S"
gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo keithchambers/pnt-bpm
```

Do not commit `.p12`, `.p8`, passwords, or app-specific passwords to this repo.

The binary is signed with the hardened runtime and the
`com.apple.security.cs.disable-library-validation` entitlement because
`pnt-bpm` loads the locally installed Serato Pitch n' Time Audio Unit.

## Local Signing

Unsigned local package:

```sh
scripts/package-release.sh
scripts/verify-package.sh
```

Signed and notarized local package with identities already installed in the
login keychain:

```sh
PNT_BPM_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PNT_BPM_PKG_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
PNT_BPM_REQUIRE_SIGNING=1 \
  scripts/package-release.sh

PNT_BPM_NOTARY_KEYCHAIN_PROFILE="pnt-bpm-notary" \
  scripts/notarize-package.sh

PNT_BPM_REQUIRE_SIGNED_BINARY=1 \
PNT_BPM_REQUIRE_SIGNED_PKG=1 \
PNT_BPM_REQUIRE_NOTARIZED_PKG=1 \
  scripts/verify-package.sh
```

Create the local notary profile once with:

```sh
xcrun notarytool store-credentials pnt-bpm-notary \
  --key /path/to/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

## Release

After the secrets are set, push a version commit and matching `vX.Y.Z` tag. The
release workflow fails if signing identities or notarization credentials are
missing, so the GitHub release asset cannot silently fall back to an unsigned
package.
