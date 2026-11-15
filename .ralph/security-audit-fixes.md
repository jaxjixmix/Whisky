# Security audit fixes — release branch

Branch: `fix/security-audit` (from `fork/main` @ `6d8289ff`).
Full details: `.ralph/security-audit-fixes.md` (read first).

## Checklist
- [x] S1 Root shell injection in CLI install — done: `quoted form of` + `appleScriptQuoted`; typecheck OK.
- [x] S2 Program args shell injection — done: args split + ShellQuoting; regression test passes.
- [x] S3 Runtime integrity — done: sha256/signature manifest, Ed25519 verifier, release-strict/debug-warn, symlink rejection, tests pass.
- [x] S4 Shortcut script — done: 0755 and atomic writes (replaces a symlink); typecheck OK.
- [x] S5 Pipe buffer cap — done: 1 MB cap, 2 MB no-newline test passes.
- [x] S6 Parser caps — done: icon size/file bounds, bitmap dimension/colour-table caps, `.lnk` 1 MB cap; tests pass.
- [x] S7 Download caps — done: 2 GB runtime cap with error/retry, 1 MB manifest cap, localized key; typecheck OK.
- [x] S8 Log permissions — done: files 0600, folder 0700, logging split to Wine+Logging; test passes.

## Verification after each item
- `cd WhiskyKit && swift build`
- `swift run -Xswiftc -enable-testing WhiskyKitSelfTest`
- `swift run -Xswiftc -enable-testing WhiskyKitSecuritySelfTest` (new target)
- `./scripts/typecheck-app.sh`
- `git diff --check`
- Commit each item separately.

## Rules
- Smallest complete fix; tests for non-trivial logic.
- No app build possible (no Xcode); typecheck is the gate.
- Keep SwiftLint limits (line 120, function 50 code lines, file 400, headers).
- Do not claim the app target was built.
## Final Verification

- Command: `cd WhiskyKit && swift build && swift run -Xswiftc -enable-testing WhiskyKitSelfTest && swift run -Xswiftc -enable-testing WhiskyKitSecuritySelfTest && cd .. && ./scripts/typecheck-app.sh`
- Result: WhiskyKit builds; 12/12 stability tests pass; 10/10 security tests pass; app sources typecheck; `git diff --check` clean; SwiftLint passes on PR #10.
- App target was not built or run (no Xcode); no real Wine runtime/server test.
- Release prerequisite: publish a signed `WhiskyWineVersion.plist` with `sha256` and a base64 Ed25519 `signature` over `WhiskyWine|<version>|<sha256>|<downloadURL>`; release builds refuse unsigned runtimes.
