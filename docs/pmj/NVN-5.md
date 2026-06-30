---
key: NVN-5
summary: Excise remaining Carbon surface — full UTCDateTime excision, FSFindFolder, IconRef, noteDirectoryRef substrate, NVN-3 deferrals
status: DAT
resolution:
priority: 3
fixVersion:
created: 2026-06-28
updated: 2026-06-30
session: f1e817e0-6eb0-4c3f-9611-6eb78cfbf2f5
tags: [carbon, cleanup, excision]
---

## Background
Everything Carbon that remains after Slices 1–3 (NVN-2, NVN-3, NVN-4). This is
the cleanup pass that should leave zero Carbon File Manager / Alias / Icon /
UTCUtils symbols in the link — gating the arm64 flip (NVN-6).

Recon (§1 of `attach/NVN-5/recon.md`) revealed the remaining surface splits into
two strata: **(A)** genuinely peripheral, self-contained items (FSFindFolder,
UTCDateTime, IconRef, trash check, DiskUUID) and **(B)** a load-bearing FSRef
substrate (`noteDirectoryRef`, BufferUtils.c I/O primitives,
`exportToDirectoryRef:`) that NVN-2/NVN-3 deliberately left as a bridge seam. Both
strata are in scope — see Solution.

Recon also corrected two ticket premises: `LSCopyDisplayNameForRef` at
`AppController.m:461` is already gone (NVN-3 retired it); the `{UTCDateTime=SIS}`
archive worry applies only to the dead non-keyed branch — the live database uses
keyed archiving with key-addressable fields.

(Directory watching — `FNNotify`/`FNSubscribe` — is NVN-10, not this ticket.)

## Recon (Cici)
DONE → `attach/NVN-5/recon.md` (full Carbon surface mapped; two ticket premises
corrected; UTCDateTime→NSDate migration verified tractable; A/B fault line recorded
neutrally for Solutioning to lock).

## Solution (locked)
LOCKED (R + Claude, 2026-06-30). Excise the **full remaining Carbon surface** —
both stratum A (peripheral) and stratum B (load-bearing FSRef substrate) — in one
ticket. Sequence A first (lower risk, independent), then B. Both must clear before
NVN-6 can link.

**Dead code sweep.** Delete on sight, no port needed:
- `FSRefReadData` (`BufferUtils.c:447`) — no callers
- `-UTIOfFileConformsToType:` (`NSString_NV.m:519`) — no callers
- `FNSubscribe` block (`NotationDirectoryManager.m:155`) — `#if`-gated dead

### Stratum A — peripheral / self-contained

**Full UTCDateTime excision (the headline).** Replace the `UTCDateTime` struct
with `CFAbsoluteTime` (`double`) everywhere. The single lever: a **~10-line pure-C
epoch helper** that converts UTCDateTime's 1904 epoch + 1/65536-sec fraction to
CFAbsoluteTime's 2001 epoch:
`absTime = ((highSeconds << 32) | lowSeconds) + fraction/65536.0 - kSecondsFrom1904To2001`.
This one helper retires all ~15 `UCConvert*` call sites (all arm64 blockers) and
powers the archive read-migration.

Archive migration (keyed path only — the non-keyed `{UTCDateTime=SIS}` branch is
dead): on decode, check for a new `double` key; if absent, read the legacy `int64`
key, reinterpret as `UTCDateTime`, run the epoch helper, done. On encode, always
write the new `double` key. No explicit format-version key — key presence IS the
versioning (zero users, no third-party compat concern). Same pattern for
`PerDiskInfo.attrTime`: `sizeof(double) == sizeof(UTCDateTime) == 8`, so
`PerDiskInfo` stays 16 bytes and the `COMPILE_ASSERT` holds.

Struct members to convert (`UTCDateTime` → `CFAbsoluteTime`/`double`):
- `NoteObject.h:78` — `fileModifiedDate`, `*attrsModifiedDate`
- `NotationController.h:29-30` — `NoteCatalogEntry.{lastModified, lastAttrModified}`
- `BufferUtils.h:36` — `PerDiskInfo.attrTime`

NVN-3 bridge shims to retire (become direct `NSDate`/`CFAbsoluteTime` ops):
- `UTCDateTimeFromNSDate` (duplicated in `NotationFileManager.m:437` and
	`NotationDirectoryManager.m:254`)
- `UTCDateTimesDifferBeyondTolerance` (`NotationDirectoryManager.m:353`) → direct
	`fabs(a - b) >= tolerance`
- `UTCDateTimeIsEmpty` macro (`BufferUtils.h:24`) → `absTime == 0.0` or similar

Endian-swap in `CopyPerDiskInfoGroupsToOrder` (`BufferUtils.c:377-379`): the
three-field `{highSeconds, lowSeconds, fraction}` swap becomes a single `double`
byte-swap. Old archives hold the UTCDateTime byte layout, so decode must run the
epoch helper on the raw bytes before storing as `double`.

**FSFindFolder → NSFileManager.** `+getDefaultNotesDirectoryRef:` →
`-[NSFileManager URLsForDirectory:NSApplicationSupportDirectory
inDomains:NSUserDomainMask]` + `createDirectoryAtURL:withIntermediateDirectories:`.
The `trashFolderRef:forChild:` call at `:631` is NVN-10 orbit (hangs off
`FNNotify`/`notifyOfChangedTrash`) — flag, don't touch.

**IconRef → NSWorkspace.** Port the sole caller
(`ExternalEditorListController.m:109`) to
`-[NSWorkspace iconForFile:[resolvedURL path]]`, then delete
`+smallIconForFSRef:` (`NSBezierPath_NV.m:55-78`).

**notesDirectoryIsTrashed → NSURL.** Replace
`FSDetermineIfRefIsEnclosedByFolder(… kTrashFolderType …)` with
`-[NSURL getResourceValue:forKey:NSURLIsInTrashKey error:]`.

**DiskUUID/PerDiskInfo — de-Carbon the blocker, audit disposition.**
The arm64 blocker is `CopySyntheticUUIDForVolumeCreationDate`
(`NotationFileManager.m:127-148`) — uses `FSGetCatalogInfo` + `FSGetVolumeInfo` +
`UTCDateTime`. De-Carbon this site (non-Carbon volume-creation-date query, or
remove the fallback entirely if the audit shows `diskIDIndex` is never read for
behavior). `CFUUIDRef` in `DiskUUIDEntry` is CoreFoundation — not a blocker.
`PerDiskInfo` stays in the archive for compat until proven vestigial; the
`attrTime` field migrates per the UTCDateTime plan above.

**Dead LaunchServices call.** `-UTIOfFileConformsToType:` (`NSString_NV.m:519`) is
dead code (zero callers) — delete, don't port.

### Stratum B — load-bearing FSRef substrate

**noteDirectoryRef → NSURL.** Dissolve the NVN-2/NVN-3 bridge seam:
`NotationController.h:90`'s `FSRef noteDirectoryRef` becomes an `NSURL*` (or
`NSString*` path). The ~14 access points across `NotationController.m`,
`NotationDirectoryManager.m`, and `NotationFileManager.m` — `pathWithFSRef:`
derivations, `CFURLGetFSRef` conversions, `FSRefMakePath` calls — collapse into
direct NSURL/path operations. The `statfs` path at `NotationFileManager.m:195` is
NVN-12 orbit — port the derivation but don't touch the `statfs` logic.

**exportToDirectoryRef: → exportToDirectoryURL:.** Takes an `NSURL*` directory
instead of `FSRef*`. Port path per recon §2.5:
- `FSCreateFileIfNotPresentInDirectory` → `NSFileManager fileExistsAtPath:` /
	`NSData writeToURL:options:NSDataWritingAtomic error:`
- `FSRefWriteData` → same `NSData writeToURL:`
- Date writeback (`FSGetCatalogInfo`/`FSSetCatalogInfo`) →
	`NSFileManager setAttributes:ofItemAtPath:error:`
	(`NSFileCreationDate`/`NSFileModificationDate`)
- Encoding xattr → existing path-based `writeCurrentFileEncodingToPath:`
	(already ported in NVN-3)
- Caller `ExporterManager.m:79`'s `CFURLGetFSRef` collapses — it already has the
	NSURL from the save panel

**BufferUtils.c FSRef primitives — delete.** Once their consumers are ported:
- `FSCreateFileIfNotPresentInDirectory` (`:415`) — consumed by exportToDirectoryRef:
- `FSRefMakeInDirectoryWithString` (`:433`) — consumed by above +
	`NotationFileManager.m:42`
- `FSRefWriteData` (`:498`) — consumed by exportToDirectoryRef:
- `FSRefReadData` (`:447`) — already dead, delete immediately
- `CreateDirectoryIfNotPresent` (`NotationFileManager.m:38`) — wraps the above +
	`FSCreateDirectoryUnicode`
- `pathWithFSRef:` (`NSFileManager_NV.m:263`) — consumed by the noteDirectoryRef
	access points

**CFURLGetFSRef collapse.** These exist only to feed the FSRef substrate:
`PrefsWindowController.m:361`, `ExporterManager.m:79`,
`ExternalEditorListController.m:108`, `NotationFileManager.m:315`. All go away
once their consumers are URL-native.

### Scope fences

- **NVN-10** owns `FNNotify`/`FNSubscribe`, `notifyOfChangedTrash`, and
	`trashFolderRef:forChild:`.
- **NVN-12** owns the `statfs` filesystem-acceptability gate.
- The dead non-keyed NSCoding branch (`__LP64__` / non-keyed) is not ported — it's
	dead code. If it clutters, delete it; don't invest in migrating it.

Acceptance = the `## DAT (R)` checklist.

## Implementation
Done (Cici). Branch `nvn-5-excise-carbon`, four commits off `a2c046a`:

- `676481b` — **UTCDateTime → CFAbsoluteTime + archive migration.** Struct members
	(`NoteObject.fileModifiedDate`/`attrsModifiedDate`, `NoteCatalogEntry.{lastModified,
	lastAttrModified}`, `PerDiskInfo.attrTime`) and all ~15 `UCConvert*` sites become
	plain `CFAbsoluteTime`. Keyed archive writes new keys `fileModifiedDateAbsolute`
	(double) + `perDiskInfoGroups2`; decode falls back to the legacy keys and converts
	once via a pure-C epoch helper (`NVAbsTimeFromLegacyBits` / `CopyLegacyPerDiskInfoGroups`,
	`kCFAbsoluteTimeIntervalSince1904` — CoreFoundation, not Carbon). `FSCatalogInfo`
	date-carrier → `NoteFileInfo` (CFAbsoluteTime). NVN-3 shims retired. Dead non-keyed
	NSCoding branch removed. `sizeof(PerDiskInfo)` stays 16; `COMPILE_ASSERT` holds.
- `6fac22a` — **peripherals.** IconRef → `-[NSWorkspace iconForFile:]` (deleted
	`+smallIconForFSRef:`); `-UTIOfFileConformsToType:` → `NSURLTypeIdentifierKey`;
	`-notesDirectoryIsTrashed` → `NSURLIsInTrashKey`.
- `1e8a091` — **FSRef substrate.** `FSRef noteDirectoryRef` → `NSString
	*notesDirectoryPath`; `initWithDirectoryPath:` is the sole initializer;
	`getDefaultNotesDirectoryRef:` → `+getDefaultNotesDirectoryPath:` (NSFileManager);
	`exportToDirectoryRef:` → `exportToDirectoryURL:` (NSData/NSFileManager);
	`relocateNotesDirectory` → `moveItemAtURL:`; synthetic disk UUID via
	`NSURLVolumeCreationDateKey`. Deleted the callerless BufferUtils FSRef primitives,
	`CreateDirectoryIfNotPresent`, `pathWithFSRef:`, `writeCurrentFileEncodingToFSRef:`,
	the `orWithFSRef:` param, and `trashFolderRef:forChild:`.

**Verification (static; project doesn't build by design):** the live tree links zero
Carbon File Manager / Alias / Icon / UTCUtils symbols (grep sweep clean — only comments
and one log-string literal remain).

**Recon corrections found during implementation:**
- `-UTIOfFileConformsToType:` was **not** dead — `AlienNoteImporter.m:422` calls it. It
	was a live `FSPathMakeRef`+`LSCopyItemAttribute` blocker, so it was **ported**, not deleted.
- DiskUUID audit (recon §2.7): `diskIDIndex` **is** read for behavior — it indexes
	`PerDiskInfo` for the per-disk attr-mod time used in change-detection (non-SingleDatabase
	format). So the synthetic-UUID fallback was **de-Carboned**, not removed. Its UUID value
	now differs from the pre-NVN-5 Carbon one, so a synthetic-fallback disk re-reads its
	per-disk attr times once after upgrade (rare path; HFS/FSEvents UUIDs are used first).

**Deviations (flagged for R / NVN-10):**
- `notifyOfChangedTrash` + `trashFolderRef:forChild:` were recon-fenced to NVN-10, but
	they consumed `noteDirectoryRef` and linked `FSFindFolder`/`FSGetCatalogInfo`/`FNNotify`
	— which NVN-5's DAT#1 requires gone. De-Carboned `notifyOfChangedTrash` (kept its
	NSWorkspace Finder refresh, dropped the Carbon half) and deleted `trashFolderRef:`. The
	`FNNotify` post-write nudges in `synchronizeNoteChanges`/`ExporterManager` were dropped
	too. The genuine NVN-10 work (FSEvents directory *watching*) is untouched.
- One dead reference to the removed ivar survives at `NotationDirectoryManager.m:155`
	inside the `#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5` (pre-Leopard
	`FNSubscribe`) block — preprocessed out on the 10.9 target; left for NVN-10 to excise.

## DAT (R)
- [ ] No remaining Carbon File Manager / Alias / Icon / UTCUtils symbols link in the build
- [ ] Existing notes database still loads (keyed archive migration UTCDateTime → CFAbsoluteTime)
- [ ] Date ordering and change-detection behave correctly
- [ ] Export to directory produces correct files with correct dates and encoding xattr
