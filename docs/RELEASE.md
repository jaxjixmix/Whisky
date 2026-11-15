# Release Guide

This fork publishes two artifact streams from `jaxjixmix/Whisky`:

- **App releases** — tag `app-vX.Y.Z`, DMG in the GitHub release.
- **Wine Libraries releases** — tag `vX.Y.Z`, `Libraries.tar.gz` in the GitHub release.

Static metadata is served from GitHub Pages:

- `https://jaxjixmix.github.io/Whisky/WhiskyWineVersion.plist`
- `https://jaxjixmix.github.io/Whisky/appcast.xml`

The app reads the same values from `Whisky/Info.plist`
(`WhiskyDistributionBaseURL`, `WhiskyReleasesBaseURL`, `SUFeedURL`). Change
those two base URLs if the release host moves; no code change is needed.

> The old `data.getwhisky.app` endpoints are dead (404). Do not release until
> the Pages and GitHub Releases artifacts below exist.

## One-time setup

1. **Developer ID Application certificate** in the login keychain.
2. **notarytool profile**:
   ```sh
   xcrun notarytool store-credentials AC_PASSWORD \
     --apple-id <email> --team-id <TEAM_ID> --password <app-specific-password>
   ```
3. **Sparkle Ed25519 key**: run Sparkle's `generate_keys` once. The public key
   is `SUPublicEDKey` in `Whisky/Info.plist`; the private key stays in the
   login keychain. Back it up — losing it strands existing installs.
4. **GitHub Pages** for this repository, serving `dist/pages/` (or the branch
   configured in the Pages workflow). The appcast and version plist must be
   reachable at the two URLs above.

## Wine Libraries release

1. Assemble `Libraries.tar.gz` with `Libraries/Wine/bin/wine64` and the version
   plist. Record the component versions.
2. Publish it:
   ```sh
   gh release create vX.Y.Z --repo jaxjixmix/Whisky \
     --title "Wine Libraries vX.Y.Z" Libraries.tar.gz
   ```
3. Export the Sparkle private key for this one command (never commit it):
   ```sh
   SPARKLE_BIN=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Whisky-*/SourcePackages/artifacts/sparkle/Sparkle/bin | head -1)
   "$SPARKLE_BIN/generate_keys" -x /tmp/whisky-runtime-private-key
   ```
4. Generate the signed version plist:
   ```sh
   swift scripts/generate-runtime-manifest.swift \
     Libraries.tar.gz X.Y.Z /tmp/whisky-runtime-private-key \
     dist/pages/WhiskyWineVersion.plist
   ```
   `WHISKY_RELEASES_BASE_URL` can override the default release host.
5. Delete the exported key from `/tmp`, commit the plist, and let Pages
   publish. Verify the URL returns the plist.
6. Test a **Release** build on a clean account: it must download the archive,
   verify the SHA-256/signature, and install. A Release build refuses an
   unsigned manifest by design; Debug builds warn and continue.

The signed payload is:

```
WhiskyWine|<version>|<sha256>|<downloadURL>
```

`sha256` is lowercase hex. `signature` is base64 Ed25519. The app verifies with
`WhiskyRuntimePublicKey` if present, otherwise `SUPublicEDKey`.

## App release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `Whisky.xcodeproj/project.pbxproj`.
2. Add release notes.
3. Archive, export with Developer ID, sign the DMG, submit with
   `xcrun notarytool submit --wait`, staple, and verify with `spctl --assess`.
4. Sign the DMG with Sparkle's `sign_update` and add an `<item>` to
   `dist/pages/appcast.xml` with the signature and length.
5. Publish the app:
   ```sh
   gh release create app-vX.Y.Z --repo jaxjixmix/Whisky \
     --title "Whisky X.Y.Z" --notes "..." build/Whisky-X.Y.Z.dmg
   ```
6. Publish Pages so Sparkle sees the new appcast.
7. The current `.github/workflows/Release.yml` still contains upstream
   (`Whisky-App`) Discord/Homebrew references. Update or remove those steps
   before publishing from this fork.

## Smoke tests

- Fresh account: setup downloads the runtime, verifies it, and finishes.
- Create a bottle; install/run a simple program; quit Whisky and confirm no
  `wine64-preloader` remains.
- Create a shortcut for a path with spaces and arguments containing `;`; the
  shortcut must not execute shell metacharacters.
- Launch a program that writes a long line with no newline; Whisky must stay
  responsive and its log must be capped.
- Confirm logs under `~/Library/Logs/com.isaacmarovitz.Whisky` are mode 0600.
- Run the self-tests:
  ```sh
  cd WhiskyKit
  swift run -Xswiftc -enable-testing WhiskyKitSelfTest
  swift run -Xswiftc -enable-testing WhiskyKitSecuritySelfTest
  ```

## Current blockers

- GitHub Pages and the Wine Libraries release do not exist yet for this fork.
- The runtime must be signed; without it a Release build cannot install.
- The app target was typechecked but not built or run in the development
  environment that produced this guide (no Xcode available).
