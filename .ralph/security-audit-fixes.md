# Security audit fixes — release branch

Branch: `fix/security-audit` (from `fork/main` @ `6d8289ff`).
Full details: `.ralph/security-audit-fixes.md` (read first).

## Checklist
- [x] S1 Root shell injection in CLI install — done: `quoted form of` + `appleScriptQuoted`; typecheck OK.
- [ ] S2 Program args shell injection — split/quote args in `Wine.generateRunCommand`; regression test.
- [ ] S3 Runtime integrity — optional sha256/signature in `WhiskyWineVersion`; verify SHA-256 + Ed25519 (pinned key); strict release / warn debug; reject symlinked runtime; tests.
- [ ] S4 Shortcut script — 0755, atomic write, remove existing symlink.
- [ ] S5 Pipe buffer cap — 1 MB cap in `PipeLineBuffer`; 2 MB no-newline test.
- [ ] S6 Parser caps — PE icon bounds, bitmap dimensions/colour table, `.lnk` cap; tests.
- [ ] S7 Download caps — 2 GB runtime, 1 MB version plist, localized error.
- [ ] S8 Log permissions — 0600 files, 0700 folder; test.

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