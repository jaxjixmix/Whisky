# Whisky P0/P1 stability, performance and bug-fix loop

Worktree: `/Users/mojics/orca/workspaces/whisky/Thigns-to-deliver` (clean upstream HEAD `fd5480a7`).
Full plan and acceptance criteria: `.ralph/p0-p1-fixes.md` (read it first each iteration).

## Goals
Fix the app-side P0/P1 findings from the upstream issue triage. No game/launcher compatibility work.

## Checklist
### P0
- [x] P0-1 Durable bottle creation (register/persist before Wine; keep visible; surface error) — #760 #798 #819 #1029 #1079 #1110 #1191 #1231 #1232 #1237 #1306 #1311 #1364 — done: settings/path saved before Wine, failures keep bottle + alert; verified build + typecheck
- [x] P0-2 Kill-on-quit (true default + synchronous wineserver -k wait) — #626 #680 #1134 — done: optional default true, `Wine.killBottleAndWait` waits 5s; verified build + typecheck
- [x] P0-3 Pipe EOF spin (buffered lines, disarm handler, join with \n) — #1010 #917 — done: PipeLineBuffer, handler nil on EOF, termination drains, runWine joins with newlines; self-tests pass
- [x] P0-4 Log cap (50 MB + marker, serialized writes, unique filenames) — #1115 #1005 #1261 — done: 50 MB cap with marker, shared write lock, UUID log suffix; self-test passes
- [x] P0-5 Downloader + atomic runtime install (errors, no NaN, retry, staging/validate/swap) — #293 #801 #995 #1020 #1070 #1271 #1275 — done: error/retry UI, guarded progress, stable temp file, staging + validate + swap; self-tests pass
- [x] P0-6 Off-main program/Start-Menu scan; fix pin loop; stop deleting .lnk — #688 #661 #941 — done: detached scan with a pins snapshot, async callers, `.lnk` kept and tracked in `importedShortcuts`, `continue` + duplicate guard; verified typecheck
- [x] P0-7 Settings/registry data loss (inverted guard, keep pins, quarantine/backup) — #359 #830 — done: missing file creates defaults, corrupt settings quarantined, pins kept (dedupe only), corrupt registry backed up, version mismatch preserves paths; self-tests pass
- [x] P0-8 Main-actor isolation for observed UI state — #1131 #1159 #1151 — done: Rosetta install state, process list fetch/kill, bottle creation settings and program scans all mutate on the main actor; verified typecheck
### P1
- [x] P1-9 ShellQuoting + launch/env quoting — #904 — done: single-quote helper, launch paths/env values quoted, AppleScript escaping for terminal commands; self-test + typecheck pass
- [x] P1-10 Winetricks via temp bash script — #470 #1011 — done: temp executable script with quoted PATH/WINEPREFIX/verb, Terminal runs `bash <script>`, script self-deletes; verbs read as a local file; typecheck passes
- [x] P1-11 Remove startup volume probes (#906) — done with P0-7: `Bottle.init` no longer touches pin volumes or files; only time a volume is probed is when creating a pin
- [x] P1-12 Edit-menu/Cmd-A bottle toggle — #1060 — done: Wine query/apply/revert of `HKCU\Software\Wine\Mac Driver\EditMenu`, bottle Config toggle, localized label; typecheck passes
- [x] P1-13 Blocklist dedupe — #431 — done: selected and single add both skip URLs already in the blocklist; typecheck passes
- [x] P1-14 Localization fallback audit — #853 — verified: all 124 dotted keys used by the app have an `en` catalog entry, `developmentRegion = en`, and `knownRegions` includes `en`/`Base`; current HEAD no longer has the raw-key gap (old 2.2.3 report)
- [x] P1-15 CrossOver HTML helper filter — #1215 — done: conservative noise-executable list filters Steam helpers, crash reporters, redistributables and the CrossOver HTML engine from the program list

## Verification (run after every item)
- `cd WhiskyKit && swift build`
- `cd WhiskyKit && swift run -Xswiftc -enable-testing WhiskyKitSelfTest` (XCTest is unavailable in CLT)
- `/tmp/typecheck-whisky.sh` (app Swift sources, Sparkle stub)
- Commit each verified item separately.

## Rules
- Smallest complete change, existing patterns, no new dependencies.
- Non-trivial logic gets a WhiskyKit test.
- Do not claim the app target was built (no Xcode).
- Update `.ralph/p0-p1-fixes.md` checklist and notes each iteration.