---
key: NVN-2
summary: Excise Carbon directory-persistence (Alias Manager + IconRef) → plain path/URL persistence
status: Done
resolution: Fixed
priority: 1
fixVersion:
created: 2026-06-28
updated: 2026-06-28
session: fc281ebf-2f3d-4ea5-b411-8117aa0c15f4
tags: [carbon, prefs, launch, alias-manager, base-layer, excision]
---

## Background
The saved notes-directory location is persisted as a Carbon **Alias Manager**
record and rendered with **IconRef** — two of the hardest-deprecated Carbon
subsystems, both gone on arm64. The same persistence sits on the launch path
(`AppController.m:434-488`), so it is not prefs-local.

Reframed by recon (`attach/NVN-2/recon.md` §1): there is **no live blocker on
x86_64** — the full Carbon path resolves end to end on the known-good build.
These subsystems are **doomed, not broken**: they work under Rosetta and vanish
on arm64. NVN-2 is therefore base-layer excision on the known-good build,
**P1 because it gates the Rosetta → arm64 exit (NVN-6)**, with the still-working
x86_64 path available as a parity oracle for the replacement.

Excision **Slice 1** — the bounded first cut. Lands before NVN-3 (one variable at
a time) and on the known-good x86_64 build (before the arm64 flip, NVN-6).

## Recon (Cici)
Done → `attach/NVN-2/recon.md`. **Headline: no live blocker on x86_64** — the
full Carbon directory-persistence path (CFURLGetFSRef, Alias Manager, IconRef,
LSCopyDisplayNameForRef) works end to end on the known-good build, captured by R.
This contradicts the Background below; reframe as *preventive excision ahead of
NVN-6 (arm64)*. Full call-site inventory (incl. consumers missed by the original
leads: `GlobalPrefs` alias store, `AppController` DB-switch path,
`relocateNotesDirectory`, `pathCopiedFromAliasData:`), the NVN-3 FSRef seam, and
open questions for Solutioning are in the recon file.

## Solution (locked)
nvNova is **not** sandboxed and has **no users** (GitHub stars are the user
signal — none yet), so there is no on-disk format to preserve and no reason to
carry the bookmark apparatus. Persist the notes-directory location as a **plain
path/URL string in `NSUserDefaults`** — no Alias Manager, and no `NSURL` bookmark
data (plain or security-scoped). A plain bookmark would buy back auto-resolution
when the folder is moved/renamed *while the app is closed*; that lone edge case is
deliberately traded for deleting the serialization + stale-resolution code, since
live moves are NVN-10's `WatchRoot` job and a missing path just re-prompts.

- **Persistence.** New defaults key `NotesDirectoryPath` (plain string). Retire
	`DirectoryAliasKey` (`GlobalPrefs.m:41`) and its getter/setter (`:925-933`); do
	not read or write the old `DirectoryAlias` blob at all. No migration —
	greenfield, no old key in the wild.
- **Resolution → NVN-3 seam (intact).** Resolve the stored path → `NSURL` →
	`CFURLGetFSRef`, and feed the existing `-initWithDirectoryRef:(FSRef*)`
	(`NotationController.m:130-162`). Smallest diff; leaves the FSRef substrate as
	NVN-3's independent variable. No new `-initWithDirectoryURL:` in this slice
	(recon §4 Q3 → bridge-via-FSRef).
- **Missing/unresolvable path.** No silent fallback masking a bad pick: if the
	stored path does not resolve, prompt the user to re-pick (zero users makes this
	free). Live moves are NVN-10's FSEvents `WatchRoot`/`RootChanged` job.
- **Display + icon.** Display name via `-[NSFileManager displayNameAtPath:]`;
	folder icon via `-[NSWorkspace iconForFile:]`. Replaces `LSCopyDisplayNameForRef`
	(`GlobalPrefs.m:945`) and the IconRef render (`NSBezierPath_NV.m:62,68`) at the
	notes-dir call sites.
- **Shared IconRef chokepoint.** `+smallIconForFSRef:` (`NSBezierPath_NV.m:55-78`)
	has a second caller — editor-app icons in
	`ExternalEditorListController.m:105-112` — out of scope here. Swap the notes-dir
	icon but **do not delete** `+smallIconForFSRef:`; the leftover editor-list caller
	moves to NVN-5.

## Implementation
Done (session `fc281ebf…`). Notes-directory location now persists as a plain
string under `NSUserDefaults` key `NotesDirectoryPath`; all Alias Manager + IconRef
+ `LSCopyDisplayNameForRef` use on the notes-dir path is gone. Static sweep for
`DirectoryAlias|fsRefAsAlias|aliasDataFor|pathCopiedFromAliasData|aliasNeedsUpdating|initWithAliasData|FSResolveAliasWithMountFlags|FSNewAlias|FSCopyAliasInfo|LSCopyDisplayNameForRef`
returns clean.

**Files touched (7):**
- `App/GlobalPrefs.{h,m}` — `DirectoryAliasKey`→`NotesDirectoryPathKey`; accessors
	retyped to `setNotesDirectoryPath:sender:` / `notesDirectoryPath` (NSString);
	deleted `displayNameForDefaultDirectoryWithFSRef:` and the dead
	`humanViewablePathForDefaultDirectory`.
- `Storage/NotationController.{h,m}` — `initWithAliasData:` → `initWithDirectoryPath:error:`
	(path→URL→`CFURLGetFSRef`→existing `initWithDirectoryRef:`); `aliasDataForNoteDirectory`
	→ `notesDirectoryPath` (via `pathWithFSRef:`); removed `aliasHandle`/`aliasNeedsUpdating`
	ivars + accessors.
- `Controllers/PrefsWindowController.m` — picker menu uses `displayNameAtPath:` +
	`[NSWorkspace iconForFile:]`; `changeDefaultDirectory` compares/stores paths;
	open-panel start dir reads the stored path. `getNewNotesRefFromOpenPanel:` keeps
	`CFURLGetFSRef` (the NVN-3 bridge).
- `App/AppController.m` — launch + DB-switch read/store the path and init via
	`initWithDirectoryPath:`; KVO selector key + handler renamed in lockstep
	(`:504`/`:1004`); error strings use the path directly.
- `Categories/NSData_transformations.{h,m}` — deleted `fsRefAsAlias:` +
	`+aliasDataForFSRef:` (orphaned).
- `Categories/NSFileManager_NV.{h,m}` — deleted `pathCopiedFromAliasData:` (orphaned).
- `Storage/NotationFileManager.m` (relocate) + `Security/PassphraseRetriever.m` —
	persist/read the path instead of alias.

**Design note — flag-free persistence.** The `aliasNeedsUpdating` machinery
collapsed into one unconditional persist in `-setNotationController:`
(`[prefsController setNotesDirectoryPath:[notationController notesDirectoryPath]
sender:self]`). `sendCallbacksForGlobalPrefs` excludes the original sender, so
`sender:self` (AppController, the only registered observer) writes defaults
**without** re-triggering a DB reload; a pick from PrefsWindowController
(`sender:self`, a non-observer) **does** fire the reload — same mechanism as
before, no loop.

**Scope guards held:** `+smallIconForFSRef:` kept (editor-list caller → NVN-5);
FSRef substrate (`noteDirectoryRef`, `initWithDirectoryRef:`, `pathWithFSRef:`)
untouched (NVN-3); no migration (greenfield).

## DAT (R)
Parity oracle on the known-good x86_64 build:
1. Preferences → Notes → "Other…" → pick a folder → Select → folder switches,
	popup shows new name **and** icon (identical to the captured baseline).
2. `defaults read <bundleID> NotesDirectoryPath` holds the plain path; no
	`DirectoryAlias` key present.
3. Relaunch → opens the same folder (path resolves at launch).
4. Point the default at a non-existent/moved path → re-prompts (no silent
	fallback).

**Verified (R).** Rebuilt x86_64; picked a folder via "Other…" → switched;
relaunched the built product (cold start, no Xcode Run) → reopened the same
folder. `defaults read com.ranvel.nvNova NotesDirectoryPath` →
`/Users/martindales/Documents/nvNova` (plain path, no alias blob). Steps 1–3
pass; storage confirmed flipped off Alias Manager. → Done.
