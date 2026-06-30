# NVN-5 — Recon (Cici)

Recon for *Excise remaining Carbon surface (FSFindFolder, full UTCDateTime
excision, LSCopy…, residual IconRef, NVN-3 deferrals)*. Method: full grep sweep
across the tree (excluding `Vendor/`) per the ticket prompt, three parallel
deep-map passes (UTCDateTime, FSRef substrate, peripheral LaunchServices/Icon/
DiskUUID), and line-by-line re-verification of the headline archive path. Baseline
= post-NVN-3 `a2c046a`.

Scope-of-record note: this file **maps the whole remaining Carbon surface** and
presents its natural fault lines **neutrally** — it deliberately does **not**
recommend where the NVN-5 boundary falls. That cut is Solutioning's to lock
(R + Claude); see §7.

## 0. Two ticket premises are wrong — corrected here

The problem-statement was written pre-NVN-3 recon and two of its pointers no
longer hold. Recording the corrections so Solutioning doesn't chase ghosts:

- **`LSCopyDisplayNameForRef` at `App/AppController.m:461` — gone.** Line 461 is now
	`location = [location stringByAbbreviatingWithTildeInPath];`; NVN-3 already
	retired the display-name-from-FSRef call here. The only *live* LaunchServices
	call that still takes an `FSRef` is **`LSCopyItemAttribute`** in
	`Categories/NSString_NV.m:524` (inside `-UTIOfFileConformsToType:`), and that
	method has **zero callers** in-tree — dead code.
	`ImportExport/ExternalEditorListController.m:116` uses the URL-based
	`LSCopyDisplayNameForURL` (a `CFURLRef`) and is **not** a Carbon blocker.
- **`{UTCDateTime=SIS}` is not the live archive format.** It appears only in the
	dead non-keyed / `__LP64__` branch of `Models/NoteObject.m` (`:409` decode,
	`:495` encode). The real database uses **keyed** archiving (`NSKeyedArchiver`),
	where `fileModifiedDate` is written as
	`[coder encodeInt64:*(int64_t*)&fileModifiedDate forKey:@"fileModifiedDate"]`
	(`:453`) and read back via `decodeInt64ForKey:` + `memcpy` (`:338-339`). This
	reframes the DAT migration risk — see §3.

## 1. The load-bearing finding — "stragglers" undersells it

The ticket frames NVN-5 as Carbon *stragglers* cleaned up "around the spine." The
sweep says otherwise: a **load-bearing FSRef substrate is still linked**, because
NVN-2/NVN-3 deliberately left `noteDirectoryRef` as a bridge seam and ported only
the layers *around* it. In-code comments say so verbatim
(`NotationFileManager.m:226-227`: *"the live directory FSRef … stays NVN-2's bridge
seam"*; `NotationController.m:695`: *"FSRef substrate stays NVN-3's variable"*).

So the remaining Carbon File-Manager surface splits cleanly into two strata of
very different size and risk — **(A)** genuinely peripheral, self-contained items,
and **(B)** the directory-level FSRef substrate that threads through the storage
core. The full per-item map is §2; the fault line itself is §7. Both strata must
clear before the arm64 flip (NVN-6) can link, since `UCConvert*`, `FSFindFolder`,
`FSGetCatalogInfo`, `GetIconRefFromFileInfo` et al. are all absent on arm64.

## 2. Carbon inventory — by ticket recon item

Status legend: **live** (executes today) · **dead** (no caller) · **vestigial**
(executes but its product is no longer consumed — needs an audit to confirm).
NVN-10 (`FNNotify`/`FNSubscribe`) and NVN-12 (`statfs`) sites are flagged
out-of-scope, not mapped as NVN-5 work.

### 2.1 FSFindFolder — folder locators · live · **stratum A**
- `Storage/NotationFileManager.m:355` — `+getDefaultNotesDirectoryRef:` →
	`FSFindFolder(kUserDomain, kApplicationSupportFolderType, kCreateFolder, …)`,
	then `CreateDirectoryIfNotPresent(…, @"Notational Data", …)`. Callers:
	`NotationController.m` default-dir bootstrap; prefs "use default location".
	Modern: `-[NSFileManager URLsForDirectory:NSApplicationSupportDirectory
	inDomains:NSUserDomainMask]` + `createDirectoryAtURL:withIntermediateDirectories:`.
- `Storage/NotationFileManager.m:631` — `+trashFolderRef:forChild:` →
	`FSGetCatalogInfo(childRef, kFSCatInfoVolume, …)` then
	`FSFindFolder(volume, kTrashFolderType, kCreateFolder, …)`. **Only** caller is
	`notifyOfChangedTrash` (`:604`), which is itself an `FNNotify` path → **belongs
	to NVN-10's orbit**; flag, don't claim. Modern trash op is
	`-[NSFileManager trashItemAtURL:resultingItemURL:error:]` (already used at `:638`).

### 2.2 Full UTCDateTime excision — the big one · live · **stratum A**
Struct members (3):
- `Models/NoteObject.h:78` — `UTCDateTime fileModifiedDate, *attrsModifiedDate`.
- `Storage/NotationController.h:29-30` — `NoteCatalogEntry.{lastModified,
	lastAttrModified}`.
- `Categories/BufferUtils.h:36` — `PerDiskInfo.attrTime` (struct is 16 bytes,
	`COMPILE_ASSERT` at BufferUtils.h ~:361).

`UCConvert*` call sites (~15, **all arm64 blockers**):
- `Models/NoteObject.m` — `:536`, `:1148-1149`, `:1385`, `:1489`, `:1499`, `:1649`,
	`:1743-1744` (the last pair inside `exportToDirectoryRef:`, stratum B).
- `Controllers/EncodingsManager.m:255-256` — "in-memory newer than disk?" guard.
- NVN-3 bridge shims: `Storage/NotationFileManager.m:440` and
	`Storage/NotationDirectoryManager.m:257` (inside `UTCDateTimeFromNSDate`), and
	`NotationDirectoryManager.m:355` (inside `UTCDateTimesDifferBeyondTolerance`).

NVN-3 bridge shims to retire (introduced to keep UTCDateTime as the stored type
while re-sourcing dates from `NSURL` `NSDate`s):
- `UTCDateTimeFromNSDate` — **duplicated**, file-local, in `NotationFileManager.m:437`
	(callers `:465-467`) and `NotationDirectoryManager.m:254` (callers `:319-320`).
- `UTCDateTimesDifferBeyondTolerance` — `NotationDirectoryManager.m:353` (callers
	`:372-373`); 1-second tolerance compare that replaced NVN-3's removed bitwise
	struct compare. Once dates are native `NSDate`/`CFAbsoluteTime`, this becomes a
	direct `fabs(a-b) >= tol` (or `-[NSDate timeIntervalSinceDate:]`).

Macro + PerDiskInfo plumbing:
- `Categories/BufferUtils.h:24` — `UTCDateTimeIsEmpty` (bitwise 8-byte zero check);
	used at `NoteObject.m:141` and `BufferUtils.c:339`.
- `Categories/BufferUtils.c` — `SetPerDiskInfoWithTableIndex` (`:327`, direct struct
	assignment `:340`/`:354`) and the endian-swap in `CopyPerDiskInfoGroupsToOrder`
	(`:377-379`) that swaps `attrTime.{highSeconds,lowSeconds,fraction}` for the
	archive. `Models/NoteObject.m` accessors `fileModifiedDateOfNote` (header inline),
	`attrsModifiedDateOfNote` (`:133`), `setAttrModifiedDate` (`:122`, callers `:147`,
	`:556`, `:1330`, `:1440`, `:1465`).

### 2.3 LSCopyItemAttribute — UTI lookup · **dead** · stratum A
- `Categories/NSString_NV.m:519-533` — `-UTIOfFileConformsToType:` does
	`FSPathMakeRef` → `LSCopyItemAttribute(&fileRef, kLSRolesAll, kLSItemContentType,
	…)` → `UTTypeConformsTo`. **No callers in-tree.** Either delete outright, or (if
	kept) port to `-[NSURL getResourceValue:forKey:NSURLTypeIdentifierKey]` / `UTType`.

### 2.4 Residual IconRef — app-icon rendering · live · stratum A
- `Categories/NSBezierPath_NV.m:55-78` — `+smallIconForFSRef:` uses
	`GetIconRefFromFileInfo` (`:62`) + `PlotIconRefInContext` (`:68`); declared
	`NSBezierPath_NV.h:32`. **Confirmed sole caller** is
	`ImportExport/ExternalEditorListController.m:109` (`-iconImage`, which does
	`CFURLGetFSRef` on its `resolvedURL` first, `:108`). The caller only needs a
	16×16 `NSImage` of an app icon → `-[NSWorkspace iconForFile:[resolvedURL path]]`.
	Port the one caller, then delete the shared method.

### 2.5 exportToDirectoryRef: — save-panel export · live · **stratum B**
- `Models/NoteObject.m:1669-1748` — takes an `FSRef*` directory; internally:
	`FSCreateFileIfNotPresentInDirectory` (`:1721`), `FSRefWriteData` (`:1731`),
	`-writeCurrentFileEncodingToFSRef:` (`:1736`, itself `NoteObject.m:1337` →
	`FSRefMakePath` + `setTextEncodingAttribute:atFSPath:`), `pathWithFSRef:` (`:1739`),
	`FSGetCatalogInfo`/`FSSetCatalogInfo` for create/mod dates (`:1742-1745`). Caller
	`ImportExport/ExporterManager.m:91`/`:102` builds the `FSRef` from a save-panel
	`NSURL` via `CFURLGetFSRef` (`:79`). Modern: `exportToDirectoryURL:` writing via
	`-[NSData writeToURL:options:NSDataWritingAtomic error:]` + `-[NSFileManager
	setAttributes:ofItemAtPath:error:]` (`NSFileCreationDate`/`NSFileModificationDate`)
	+ existing path-based `-writeCurrentFileEncodingToPath:` (`NoteObject.m:1353`).

### 2.6 notesDirectoryIsTrashed — startup safety check · live · stratum A
- `Storage/NotationFileManager.m:240-245` — `FSDetermineIfRefIsEnclosedByFolder(0,
	kTrashFolderType, &noteDirectoryRef, &isInTrash)`. Caller
	`NotationController.m:711` (warn-and-offer-relocate on launch). Modern:
	`-[NSURL getResourceValue:forKey:NSURLIsInTrashKey error:]`.

### 2.7 DiskUUIDEntry + synthetic volume UUID · live · **possibly vestigial** · A
- `Storage/DiskUUIDEntry.{h,m}` — wraps a `CFUUIDRef` + `lastAccessed` `NSDate`,
	`NSCoding`-archivable. `CFUUIDRef` is CoreFoundation (not Carbon per se) — no
	arm64 issue by itself.
- `Storage/NotationFileManager.m:127-148` — `CopySyntheticUUIDForVolumeCreationDate`
	uses `FSGetCatalogInfo(kFSCatInfoVolume)` + `FSGetVolumeInfo(kFSVolInfoCreateDate)`
	+ `uuid_create_md5_from_name` over a `UTCDateTime` → **Carbon blocker**. It is the
	*last-resort fallback* in `initializeDiskUUIDIfNecessary` (after
	`CopyHFSVolumeUUIDForMount` and `FSEventsCopyUUIDForDevice`).
- `Storage/NotationPrefs.m:828` — `tableIndexOfDiskUUID:` maintains
	`seenDiskUUIDEntries`, indexing the per-note `PerDiskInfo.diskIDIndex`.
- **Audit needed (not assumed):** post-NVN-3 the per-note FSRef identity is gone;
	the disk-UUID / PerDiskInfo machinery is multi-disk-sync bookkeeping that *may*
	now be vestigial. But `PerDiskInfo` is **serialized into every note's keyed
	archive** (`NoteObject.m:450`), so it is archive-compat-sensitive and cannot be
	deleted on a hunch. Solutioning should confirm whether anything *reads*
	`seenDiskUUIDEntries`/`PerDiskInfo.diskIDIndex` for behavior (vs. just round-trips
	them) before deciding remove-vs-keep-and-de-Carbon.

### 2.8 FSRef substrate — the directory-level bridge · live · **stratum B**
- `Storage/NotationController.h:90` — `FSRef noteDirectoryRef`, the controller's
	resolved-location member. ~14 access points: init/bzero
	(`NotationController.m:73`, `:131`), `CFURLGetFSRef` from stored path (`:95`),
	`CFURLCreateFromFSRef` for the WAL path (`:359`), `pathWithFSRef:` derivations
	(`:696`, `:713`; `NotationDirectoryManager.m:124`), and in `NotationFileManager.m`:
	synthetic-UUID input (`:183`), `FSRefMakePath` for the `statfs` path (`:195`,
	**NVN-12 orbit**), trash check (`:242`), `relocateNotesDirectory`'s `FSMoveObject`/
	`FSCompareFSRefs` (`:312-329`). To de-Carbon stratum B this becomes an `NSURL*`/
	`NSString*`, and `pathWithFSRef:`/`CFURLGetFSRef` conversions collapse away.
- `Categories/NSFileManager_NV.m:263` — `-pathWithFSRef:` (`FSRefMakePath` wrapper),
	called from the sites above + `NoteObject.m:1739`.
- `Categories/BufferUtils.c` FSRef I/O primitives — `FSCreateFileIfNotPresentInDirectory`
	(`:415`, caller `NoteObject.m:1721`), `FSRefMakeInDirectoryWithString` (`:433`,
	callers `:421` + `NotationFileManager.m:42`), `FSRefWriteData` (`:498`, caller
	`NoteObject.m:1731`), and **`FSRefReadData` (`:447`) — no callers found → dead**,
	delete-on-sight. `CreateDirectoryIfNotPresent` (`NotationFileManager.m:38`)
	wraps `FSRefMakeInDirectoryWithString` + `FSCreateDirectoryUnicode`.
- `CFURLGetFSRef` sites that exist only to feed the above:
	`PrefsWindowController.m:361` (open-panel), `ExporterManager.m:79` (export),
	`ExternalEditorListController.m:108` (icon), `NotationFileManager.m:315`
	(relocate). All collapse once their consumers go URL-native.

## 3. UTCDateTime → NSDate migration — verified, and tractable

The DAT line "existing notes database still loads (NSCoding migration from
UTCDateTime → NSDate)" is the highest-risk item; the live archive code makes it
**manageable, not scary**:

- The live path is **keyed** and **key-addressable** — `fileModifiedDate` lives
	under its own string key (`NoteObject.m:453`/`:338`), so changing the type or
	neighboring fields does **not** shift any byte offsets (the positional
	`{UTCDateTime=SIS}` worry applies only to the dead non-keyed branch).
- Migration shape: on decode, if the new `double` key is absent, read the legacy
	`int64` key, reinterpret its 8 bytes as a `UTCDateTime`, and convert **once** to
	`CFAbsoluteTime`; thereafter persist forward as a `double`. The conversion that
	replaces the arm64-blocking `UCConvert*` is a **~10-line pure-C epoch helper**:
	UTCDateTime is seconds-since-1904-01-01 (`(highSeconds<<32)|lowSeconds`) plus a
	`fraction`/65536 sub-second; `CFAbsoluteTime` is seconds-since-2001-01-01, so
	`absTime = utcSeconds + fraction/65536.0 - kSecondsFrom1904To2001`. This one
	helper retires **all ~15 `UCConvert*` call sites** and powers the read-migration.
- `PerDiskInfo.attrTime` carries the same concern, localized to the endian-swap in
	`CopyPerDiskInfoGroupsToOrder` (`BufferUtils.c:377-379`): old archives hold the
	UTCDateTime byte layout, so its decode must run the same one-time conversion.
	Note `sizeof(double) == sizeof(UTCDateTime) == 8`, so `PerDiskInfo` stays 16
	bytes and the `COMPILE_ASSERT` need not change if `attrTime` becomes a `double`.

## 4. Cross-ticket boundaries (flag, don't claim)

- **NVN-10** owns directory watching: `FNNotify` (`NotationController.m:672`,
	`NotationFileManager.m:607`) and pre-Leopard `FNSubscribe`
	(`NotationDirectoryManager.m:155`, already `#if`-dead). The `kTrashFolderType`
	trash-notify path (`trashFolderRef:forChild:` → `notifyOfChangedTrash`) hangs off
	`FNNotify`, so it travels with NVN-10, not NVN-5.
- **NVN-12** owns the filesystem-acceptability gate: the `statfs`/`FSRefMakePath`
	path at `NotationFileManager.m:195`.
- **NVN-4** (DAT) already split out the `moveFileToTrash:` silent-success bug;
	untouched here.

## 5. The NVN-3 coupling seam (carried forward)

`NotationController` still hangs the whole storage substrate off
`-initWithDirectoryRef:(FSRef*)` and the `noteDirectoryRef` member
(`NotationController.h:90`). NVN-2 bridged *into* this seam (path→FSRef via
`CFURLGetFSRef`) and NVN-3 ported the I/O *below* it; stratum B (§2.8) is exactly
the act of finally dissolving this seam to an `NSURL`. That is why B is bigger than
a "straggler": touching `noteDirectoryRef` ripples through every storage file that
reads it.

## 6. Sweep coverage / dead-code ledger

Every non-`Vendor/` hit from the prompt's grep is accounted for above. Confirmed
**dead** (safe to delete regardless of the §7 cut): `FSRefReadData`
(`BufferUtils.c:447`), `-UTIOfFileConformsToType:` (`NSString_NV.m:519`),
`FNSubscribe` (`NotationDirectoryManager.m:155`, `#if`-gated). Confirmed
**already-modern, not blockers**: `LSCopyDisplayNameForURL`
(`ExternalEditorListController.m:116`), `LSCanURLAcceptURL`/`LSFindApplicationForInfo`
(same file). Confirmed **sole caller** relationships: `+smallIconForFSRef:` ←
`ExternalEditorListController.m:109` only.

## 7. The fault line — for Solutioning to lock (R + Claude)

Per R's call, recorded **neutrally**, no recommendation:

- **Stratum A — peripheral / self-contained.** FSFindFolder (§2.1), full
	UTCDateTime excision + the §3 epoch helper (§2.2), the dead `LSCopyItemAttribute`
	(§2.3), IconRef (§2.4), `notesDirectoryIsTrashed` (§2.6), DiskUUID de-Carbon /
	audit (§2.7). Each lands one-variable-at-a-time without touching the controller's
	location member.
- **Stratum B — load-bearing FSRef substrate.** `noteDirectoryRef` → `NSURL`
	(§2.8), the `BufferUtils.c` FSRef I/O primitives, the `exportToDirectoryRef:`
	rewrite (§2.5). Dissolving the NVN-3 seam (§5); broader blast radius across
	`Storage/`.

Open questions for Solutioning:
1. **Boundary.** Does NVN-5 own A only (and B spins out as a new sibling ticket —
	Claude is numbering authority), A+B as one arm64-gating push, or some seam in
	between? Both strata must clear before NVN-6 links regardless of how they're
	ticketed.
2. **UTCDateTime archive contract (§3).** Confirm the new-key-with-legacy-fallback
	migration and the pure-C epoch helper as the locked approach; decide whether to
	add an explicit format-version key while we're touching the archive.
3. **DiskUUID/PerDiskInfo disposition (§2.7).** Remove-vs-keep-and-de-Carbon, gated
	on the "is it ever *read* for behavior?" audit.
4. **`exportToDirectoryRef:` rewrite (§2.5).** Confirm `NSData writeToURL:` +
	`setAttributes:` preserves the export semantics (dates, encoding xattr, tags)
	the current FSRef path sets.

DAT acceptance lives in the ticket's `## DAT (R)`: zero Carbon File Manager / Alias
/ Icon / UTCUtils symbols in the link; existing DB still loads (the §3 migration);
date ordering + change-detection still correct.
