# NVN-2 — Recon (Cici)

Recon for *Excise Carbon directory-persistence (Alias Manager + IconRef) → NSURL
bookmarks*. Leads in the ticket's `## Recon (Cici)` block were verified against
source, not trusted. Scope = directory **persistence / resolution / display**
only; the FSRef **file-I/O substrate** is NVN-3 (see §3).

## 1. Symptom — CAPTURED by R (contradicts the ticket premise)

R ran the known-good x86_64 build and exercised Preferences → Notes → "Other…".
**Result: the full path works end to end — there is NO live blocker on this
build.** Picking a folder (`nvNova`) closed the panel, persisted, and the "Read
notes from folder:" popup re-rendered with the new name *and* a folder icon.
Tracing that observed success back through the code, every Carbon API in scope
executed successfully on this machine/OS:

- `CFURLGetFSRef` (`Controllers/PrefsWindowController.m:365`) returned true — the
	pick was captured (no silent no-op).
- `+aliasDataForFSRef:` → `FSNewAlias` (`Categories/NSData_transformations.m:270`)
	produced alias data; `setAliasDataForDefaultDirectory:` persisted it.
- `displayNameForDefaultDirectoryWithFSRef:` → `LSCopyDisplayNameForRef`
	(`App/GlobalPrefs.m:945`) returned the display name (`nvNova`).
- `+smallIconForFSRef:` → `GetIconRefFromFileInfo` + `PlotIconRefInContext`
	(`Categories/NSBezierPath_NV.m:62,68`) rendered the folder icon (non-nil — it
	displays in the popup).

**Implication.** The ticket Background ("the Notes pane has a live blocker… the
visible tip of a latent launch-time failure") is **not** borne out on x86_64.
These subsystems are *doomed, not broken*: Alias Manager + IconRef are among the
hardest-deprecated Carbon APIs and disappear on **arm64** (NVN-6), yet still
function on the x86_64 build. NVN-2 is therefore best framed as **preventive
excision ahead of NVN-6**, performed on the known-good build precisely *because*
the old path still works there and can serve as a parity oracle for the bookmark
implementation. Flagged to R + Claude (premise / priority) per no-bleed — see §4.

## 2. Call-site inventory (verified, exact ranges)

### A. Alias persistence store (the saved location)
- `App/GlobalPrefs.m:41` — `static NSString *DirectoryAliasKey = @"DirectoryAlias";`
	(NSUserDefaults key the alias blob lives under). *Not in the ticket's leads —
	this is the persistence root.*
- `App/GlobalPrefs.m:925-933` — `setAliasDataForDefaultDirectory:sender:` /
	`aliasDataForDefaultDirectory` getter+setter. *Not in the ticket's leads.*

### B. Alias ⇄ FSRef conversion primitives
- `Categories/NSData_transformations.m:238-249` — `fsRefAsAlias:` →
	`FSResolveAliasWithMountFlags` (:244).
- `Categories/NSData_transformations.m:256-277` — `+aliasDataForFSRef:` →
	`FSFindFolder` + `FSNewAlias` (:270).
- `Categories/NSFileManager_NV.m:258-270` — `pathCopiedFromAliasData:` →
	`FSCopyAliasInfo`. *Not in the ticket's leads; consumed by `AppController.m:458`.*

### C. Display-name / icon rendering
- `App/GlobalPrefs.m:935-949` — `displayNameForDefaultDirectoryWithFSRef:`
	(`LSCopyDisplayNameForRef` :945).
- `App/GlobalPrefs.m:951-985` — `humanViewablePathForDefaultDirectory`
	(`FSGetCatalogInfo` + `LSCopyDisplayNameForRef` parent-walk, :954/:964/:967).
- `Categories/NSBezierPath_NV.m:55-78` — `+smallIconForFSRef:`
	(`GetIconRefFromFileInfo` :62, `PlotIconRefInContext` :68).

### D. Prefs UI (the picker surface)
`Controllers/PrefsWindowController.m`
- `:261-288` — `directorySelectionMenu` (`displayName…` :265, `fsRefAsAlias:`
	:270, `smallIconForFSRef:` :271).
- `:290-319` — `changeDefaultDirectory` (`fsRefAsAlias:` :300, `FSCompareFSRefs`
	:301, `+aliasDataForFSRef:` :303, `setAliasDataForDefaultDirectory:` :304).
- `:326-372` — `getNewNotesRefFromOpenPanel:returnedPath:` (`fsRefAsAlias:` :336,
	`CFURLGetFSRef` :365).

### E. Launch path — the real stakes
- `App/AppController.m:434-488` — startup DB init: `aliasDataForDefaultDirectory`
	:438, `initWithAliasData:` :448, `initWithDefaultDirectoryReturningError:` :451,
	`pathCopiedFromAliasData:` :458, `fsRefAsAlias:` + `LSCopyDisplayNameForRef`
	fallback :461, `setAliasNeedsUpdating:` :483.
- `Storage/NotationController.m:90-111` — `initWithAliasData:`
	(`FSResolveAliasWithMountFlags` :98) → `initWithDirectoryRef:` :99.
- `Storage/NotationController.m:710-738` — `aliasDataForNoteDirectory`
	(`FSFindFolder` :716, `FSNewAlias` :724); `setAliasNeedsUpdating:` :740.
- `App/AppController.m:581`, `:1012-1032` — **live DB-switch / reload** path
	round-trips alias data (`setAliasDataForDefaultDirectory:` :581/:1012,
	`initWithAliasData:` :1024, `aliasDataForNoteDirectory` :1031). *Not in the
	ticket's leads; a second consumer of the same persistence.*

### F. Other alias / icon consumers
- `Security/PassphraseRetriever.m:58-63` — `aliasDataForNoteDirectory` +
	`fsRefAsAlias:` to label the passphrase prompt with the notes dir.
- `ImportExport/ExternalEditorListController.m:105-112` — `smallIconForFSRef:`
	for editor-app icons (`CFURLGetFSRef` :108). `displayName` (:114-117) already
	uses `LSCopyDisplayNameForURL` — URL-based, **out of scope**.
- `Storage/NotationFileManager.m:333-390` — `relocateNotesDirectory` persists a
	new alias on a notes-folder *move* (`+aliasDataForFSRef:` :370,
	`setAliasDataForDefaultDirectory:` :371). *Not in the ticket's leads.*

## 3. The NVN-3 coupling seam (keep self-contained)

`NotationController` stores the resolved location as an **`FSRef` member**
(`noteDirectoryRef`, declared `NotationController.h:93`), and
`-initWithDirectoryRef:(FSRef*)` (`NotationController.m:130-162`) is the single
entry the whole file-I/O substrate hangs off. That FSRef substrate is **NVN-3's**
scope. NVN-2 changes only *persistence + resolution + display*: resolve a
bookmark to a URL/path and bridge to the existing `initWithDirectoryRef:` (via
`CFURLGetFSRef`, or a thin path/URL initializer) so NVN-3 can convert the
substrate independently, one variable at a time. This is what keeps NVN-2
landable on the known-good x86_64 build ahead of NVN-3.

## 4. Open questions for Solutioning (R + Claude)

1. **Premise / priority.** No live blocker on x86_64. Does NVN-2 keep priority 2
	and proceed as *preventive* excision ahead of NVN-6, and should the ticket
	Background be amended to "doomed, not broken"? (Claude owns the problem
	statement — flagged, not decided, by recon.)
2. **Migration.** One-time resolve-and-rewrite of the existing `DirectoryAlias`
	defaults blob → bookmark data, vs. reset + let the user re-pick. Capture
	update: the alias **does still resolve on this x86_64 build**, so
	resolve-and-rewrite is viable *now* — a strong argument to migrate on x86_64
	before arm64 removes the ability to read the old alias at all.
3. **Bridge shape.** Convert resolved bookmark → FSRef to feed the existing
	`initWithDirectoryRef:` (smallest diff, leaves the NVN-3 seam intact), vs. add
	a `-initWithDirectoryURL:` / path initializer now.
4. **Defaults key.** Reuse `DirectoryAlias` (mixed old/new payloads) vs. introduce
	`DirectoryBookmark` and migrate-then-delete the old key.
