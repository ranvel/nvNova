# P1 — Carbon / FSRef Runtime Triage

_Last updated: 2026-06-27_

Working doc for the P1 item in `revival-status.md`: **does the Carbon File Manager
I/O substrate actually move bytes correctly at runtime on modern macOS (APFS,
macOS 26), or is it silently failing?** Same guiding frame as the rest of the
revival — recuperation, not rewrite. This triage decides whether P1 is a
five-alarm fire (notes silently lost) or a slow background modernization. We do
**not** rewrite anything until we know which.

See also: `revival-status.md` (roadmap), `Storage/NotationFileManager.m` (the
substrate), `Storage/FSExchangeObjectsCompat.c` (the swap shim).

---

## The reframing: the emulated swap is now load-bearing

The original triage worry was "~220 deprecated Carbon calls, do they work?" Static
reading narrows that down to a sharper question.

`storeDataAtomicallyInNotesDirectory:` chooses between two atomic-save strategies
based on `VolumeSupportsExchangeObjects()`, which keys off the volume capability
bit `VOL_CAP_INT_EXCHANGEDATA`:

- **`FSExchangeObjects`** (native, kernel-atomic) — taken only when the volume
  advertises `exchangedata(2)` support.
- **`FSExchangeObjectsEmulate`** (hand-rolled rename/move dance in
  `FSExchangeObjectsCompat.c`) — the fallback.

**APFS does not implement `exchangedata(2)`.** It has been the default filesystem
since High Sierra (10.13) and is mandatory on SSDs. So on every modern Mac the
native branch is **dead code**, and **100% of atomic saves run through the
emulation.** That emulation is itself built on FSRef primitives
(`FSGetCatalogInfo`, `FSRenameUnicode`, `FSMoveObject`), so it is exactly as
exposed to any FSRef runtime degradation as everything else — except it is now the
*only* path, and it has a multi-step partial-failure window with hand-rolled
rollback.

This matters because the default storage format is `SingleDatabaseFormat`
(`NotationPrefs.m:69`): the entire note database is one serialized blob
(`Notes & Settings`) rewritten via this atomic-swap path on **every save**. If the
emulated swap truncates or half-completes, that is not one lost note — it is the
whole database. The separate-file formats (`PlainText`/`RTF`/`HTML`, the
"notes-as-files" use case) spread the risk across per-note
create/write/rename/delete, but route through the same primitives.

So the real triage question is narrower and scarier than "220 warnings":
**does the emulated atomic swap reliably preserve data on APFS/macOS 26, and if any
FSRef call in that chain is degraded, where exactly does the byte loss happen?**

---

## Surface inventory, ranked by note-loss risk

All of this lives in `Storage/NotationFileManager.m` unless noted. Risk is about
*data integrity*, per the project's ordering (integrity > polish > performance).

### Tier 1 — Write/save path (runs on every save; direct note-loss risk)

| Call | Site | Why it's Tier 1 |
|------|------|-----------------|
| `FSRefWriteData` | `storeDataAtomicallyInNotesDirectory:` | The actual byte commit to the temp file. Silent truncation or no-op here = lost data with no error surfaced to the user. |
| `FSExchangeObjectsEmulate` | same | Always taken on APFS. Multi-step swap; a failure between the rename steps can leave dest truncated/missing with only the temp holding good bytes. Has rollback, but rollback also uses FSRef calls. |
| `CreateTemporaryFile` / `FSCreateFileUnicode` | helper | If temp creation fails or lands outside the notes dir, the swap target is wrong. |
| `FSDeleteObject` | temp cleanup + `deleteFileInNotesDirectory:` | Temp-cleanup failure leaks files (cosmetic); per-file note delete failure is a correctness issue in file formats. |
| `FSCreateFileIfNotPresentInDirectory` | `createFileIfNotPresentInNotesDirectory:` | Resolves/creates the destination ref the swap writes into. |

### Tier 2 — Read/load path (load-time correctness)

| Call | Site | Why it matters |
|------|------|----------------|
| `FSRefReadData` | `dataFromFileInNotesDirectory:…` | Reads note/blob bytes back. Truncated or stale reads = apparent data loss / corruption on load. |
| `FSGetCatalogInfo` | `fileInNotesDirectory:…`, ownership/size checks | Wrong sizes/dates feed the read length and change-detection. |
| `FSRefMakeInDirectoryWithString` / `FSRefMakePath` | path↔ref resolution throughout | If ref resolution is off, every downstream op targets the wrong (or no) file. |

### Tier 3 — Safety nets & locators (degrade quietly, but tie to P0)

| Call | Site | Why it matters |
|------|------|----------------|
| `FSFindFolder(kApplicationSupportFolderType)` | `getDefaultNotesDirectoryRef:` | Resolves the default notes directory. Wrong answer = notes created somewhere unexpected. |
| `FSFindFolder(kTrashFolderType)` + `FSMoveObject` | `moveFileToTrash:`, `trashFolderRef:forChild:` | This is the deletion **safety net**. If trash-move fails, deletes bypass the recoverable Trash — which feeds directly back into **P0** (accidental deletion). |
| `FSDetermineIfRefIsEnclosedByFolder(kTrashFolderType)` | `notesDirectoryIsTrashed` | Long-suspect on modern macOS; verify it doesn't false-negative. |

### Tier 4 — Low-stakes / cosmetic

| Call | Site | Note |
|------|------|------|
| `CopySyntheticUUIDForVolumeCreationDate` (`UTCDateTime`, `kFSVolInfoCreateDate`) | disk-UUID init | Only used in non-`SingleDatabase` formats to tag per-disk attr mod dates. APFS create-date semantics differ from HFS+; worst case is a stable-but-meaningless UUID. Low priority. |
| `FNNotify(kFNDirectoryModifiedMessage)` | `notifyOfChangedTrash` | Finder refresh nudge. Cosmetic. |

---

## Findings from reading the source (independent of runtime status)

Re-verified line-by-line against `Storage/NotationFileManager.m` (2026-06-27):
**one real bug, one false alarm.**

### Confirmed — `moveFileToTrash:` reports success on a trash-resolution failure

```objc
OSStatus err = [self refreshFileRefIfNecessary:childRef …];   // :648
if (noErr != err) return err;                                 // :649  err is now provably noErr
FSRef folder;
if ([NotationController trashFolderRef:&folder forChild:childRef] != noErr)
    return err;                                               // :653  returns noErr — "success", moved nothing
```

Past `:649` `err` can only be `noErr`, so the `return err` at `:653` hands back
success when the Trash can't be resolved. The caller treats that as a completed
trash:

```objc
if ((err = [self moveFileToTrash:&tempFileRef forFilename:nil]) != noErr)   // :604
```

Real silent safety-net hole, and it ties straight into **P0** — the recoverability
story the deletion UI implies isn't guaranteed underneath. **Fix:** capture and
return the actual status from `trashFolderRef:forChild:` (or a concrete error) at
`:653` instead of the stale `err`.

### Not a bug — `CreateTemporaryFile` is the correctly defensive one

An earlier draft of this doc flagged this function as fragile, claiming a
non-`fnfErr`/`noErr` error "falls straight through to `FSCreateFileUnicode` with a
stale ref." **That was wrong** — the guard at `:68` gates creation on `fnfErr`
specifically:

```objc
do {
    …
    result = FSRefMakeInDirectoryWithString(parentRef, childTempRef, filename, chars);
} while (result == noErr);              // :66  loops only while the name already exists
if (result == fnfErr) {                 // :68  ONLY fnfErr reaches creation
    result = FSCreateFileUnicode(parentRef, nameLength, chars, …);
}
return result;                          // :72  any other error returned verbatim, no file created
```

On any unexpected error the loop exits, the `fnfErr` guard is false,
`FSCreateFileUnicode` is skipped, and the raw error returns to the caller. That's
the safe behaviour. The only true residual is an **observability** nit: unexpected
`OSStatus` codes bubble up verbatim with no `[TRIAGE]`-style breadcrumb, so a weird
volume error here would surface as an opaque code. Worth a log line during the
Step 1 instrumentation pass — nothing more.

---

## Triage method — cheapest signal first

The point is to answer "fire or not?" with minimal effort before touching code.
The substrate already `NSLog`s most FSRef errors — it just returns early, and
callers don't always surface those to the UI. So:

### Step 0 — Listen before instrumenting (zero code)

Run the existing Development build from a terminal (or watch `Console.app`),
filtered to the strings already in the source, and just *use the app normally*
against a scratch notes directory for a session:

```
"error writing to temporary file"
"error exchanging contents of temporary file"
"error creating temporary file"
"FSRefMakePath: error"
"Error deleting"
NSStringFromSelector + ": error"   // dataFromFileInNotesDirectory read errors
```

Then quit and relaunch. **If those are silent and every note survives the
relaunch, the substrate is probably fine** and P1 drops to slow-background
modernization. **If any fire, we've found the fire** and Tier 1/2 get promoted.

### Step 1 — Targeted instrumentation (small pass, only if Step 0 is ambiguous)

Add a `[TRIAGE]`-prefixed log at the error branch of every Tier 1/2 FSRef call,
logging the call name, `OSStatus`, and the filename/ref. Decode the status codes
that actually indicate trouble:

- `-35 nsvErr` (no such volume) / `-43 fnfErr` (file not found) on a path we expect to exist
- `-1413 errFSBadFSRef` / `-1414 errFSBadBuffer` — ref/buffer no longer valid
- `paramErr (-50)` — API rejecting arguments outright

Then exercise, deterministically, on a scratch dir:

1. **Create** a note → `cat` the on-disk blob/file, confirm bytes match.
2. **Edit + save ~20×** → confirm no truncation and no zero-byte window mid-save;
   confirm temp files are cleaned up (no leak).
3. **Crash-during-save** (or force an emulation step to fail) → confirm rollback
   leaves *either* old-good *or* new-good content, **never empty**. This is the
   integrity assertion that matters most.
4. **Delete** a note → confirm it lands in the volume Trash, not the void
   (exercises Tier 3 + the latent bug above).
5. **Switch to `PlainTextFormat`**, repeat 1–4 → exercises the per-file
   create/rename/delete paths the blob path skips.
6. **Relocate notes dir** APFS→external volume → exercises `FSMoveObject` across
   volumes and the alias round-trip.

A few hours with this either produces a clean bill of health or a precise list of
which primitive fails and on what operation — which is exactly the input the P1
fix pass (or its deferral) needs.

---

## Outcome → decision

- **All quiet, data survives** → mark P1 "verified working on macOS 26 / APFS,"
  leave the deprecation warnings as the standing modernization backlog, move on.
- **Failures isolated to safety nets (Tier 3)** → small surgical fix (trash
  resolution + the `moveFileToTrash:` bug), ties into the P0 work anyway.
- **Failures in Tier 1/2** → this becomes the top priority above everything except
  P0's design question, and the modernization target is well-scoped: port the
  save/read path off FSRef to URL/`NSFileManager`/`-[NSData writeToURL:options:]`
  (atomic) primitives, starting with `storeDataAtomicallyInNotesDirectory:`.

No code changes until Step 0/1 give us the verdict.
