# Whisky P0/P1 stability, performance and bug-fix loop

Worktree: `/Users/mojics/orca/workspaces/whisky/Thigns-to-deliver` (clean upstream HEAD `fd5480a7`).
Full plan and acceptance criteria: `.ralph/p0-p1-fixes.md` (read it first each iteration).

## Goals
Fix the app-side P0/P1 findings from the upstream issue triage. No game/launcher compatibility work.

## Checklist
### P0
- [x] P0-1 Durable bottle creation (register/persist before Wine; keep visible; surface error) — #760 #798 #819 #1029 #1079 #1110 #1191 #1231 #1232 #1237 #1306 #1311 #1364 — done: settings/path saved before Wine, failures keep bottle + alert; verified build + typecheck
- [x] P0-2 Kill-on-quit (true default + synchronous wineserver -k wait) — #626 #680 #1134 — done: optional default true, `Wine.killBottleAndWait` waits 5s; verified build + typecheck
- [ ] P0-3 Pipe EOF spin (buffered lines, disarm handler, join with \n) — #1010 #917
- [ ] P0-4 Log cap (50 MB + marker, serialized writes, unique filenames) — #1115 #1005 #1261
- [ ] P0-5 Downloader + atomic runtime install (errors, no NaN, retry, staging/validate/swap) — #293 #801 #995 #1020 #1070 #1271 #1275
- [ ] P0-6 Off-main program/Start-Menu scan; fix pin loop; stop deleting .lnk — #688 #661 #941
- [ ] P0-7 Settings/registry data loss (inverted guard, keep pins, quarantine/backup) — #359 #830
- [ ] P0-8 Main-actor isolation for observed UI state — #1131 #1159 #1151
### P1
- [ ] P1-9 ShellQuoting + launch/env quoting — #904
- [ ] P1-10 Winetricks via temp bash script — #470 #1011
- [ ] P1-11 Remove startup volume probes (#906)
- [ ] P1-12 Edit-menu/Cmd-A bottle toggle — #1060
- [ ] P1-13 Blocklist dedupe — #431
- [ ] P1-14 Localization fallback audit — #853
- [ ] P1-15 CrossOver HTML helper filter — #1215

## Verification (run after every item)
- `cd WhiskyKit && swift build`
- `cd WhiskyKit && swift test` (once the test target exists)
- `/tmp/typecheck-whisky.sh` (app Swift sources, Sparkle stub)
- Commit each verified item separately.

## Rules
- Smallest complete change, existing patterns, no new dependencies.
- Non-trivial logic gets a WhiskyKit test.
- Do not claim the app target was built (no Xcode).
- Update `.ralph/p0-p1-fixes.md` checklist and notes each iteration.