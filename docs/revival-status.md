# nvNova Revival — Status & Roadmap

_Last updated: 2026-06-27_

This document tracks the health of the nvNova revival: what's been restored, what's
still broken, and the order we intend to fix things. The guiding frame is
**recuperation, not rewrite** — the previous maintainers were in survival mode;
we're nursing a near-perfect app back to health. No urgency, quality over speed.

See also: `CLAUDE.md` (architecture & build notes), `COPYING.txt` (GPL-3.0).

---

## TL;DR

- **It builds and runs again** (as of 2026-06-26) for the first time since the
  macOS-10.9 era. `xcodebuild -scheme "Notation Develop" -configuration Development build`
  succeeds with no overrides, and the app launches.
- It's an **x86_64 / Rosetta** build by deliberate choice (vendored libs are
  Intel-only). Native arm64 is a later pass.
- The product remains **pure Objective-C / AppKit / MRC** — no Swift, ever.
- Four known issues are open (UI scale, assets, Carbon/FSRef runtime risk,
  native arm64), plus the long-standing **#1 product goal: make accidental note
  deletion harder**.

---

## Progress — what's been restored

### Build restoration (commit `8bb2994`, branch `revive/make-it-build`)

The project hadn't compiled in years. Getting it green turned out to be smaller
than feared — the bulk of the dreaded "deprecation blockers" are only *warnings*
(`GCC_TREAT_WARNINGS_AS_ERRORS = NO`), and there were no linker or architecture
walls once we built x86_64.

**Project settings baked into `Notation.xcodeproj/project.pbxproj`:**

- Replaced stale search paths (`ICU/icu`, the Homebrew OpenSSL Cellar path, the
  pre-reorg `library/**`) with `$(SRCROOT)/nvNova/Vendor`, and added a recursive
  `$(SRCROOT)/nvNova/**` header path for the post-reorg path-less `#import`s;
  `ALWAYS_SEARCH_USER_PATHS = YES`.
- `MACOSX_DEPLOYMENT_TARGET` 10.9 → 10.13.
- Pinned `ARCHS = x86_64` (see "native arm64" below).
- Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`, manual, no team) so it runs
  locally without an Apple developer account.

**Source fixes** — almost all one root cause: modern clang treats an *implicit
function declaration* as a hard error, and the directory reorg left some files no
longer seeing declarations they relied on. Fixes were adding the correct
`#import`/`#include` or a small forward declaration:

| File | Fix |
|------|-----|
| `App/GlobalPrefs.m`, `Controllers/PrefsWindowController.m`, `Categories/NSString_CustomTruncation.m` | import `BufferUtils.h` (`IsZeros`, `replace_breaks*`) |
| `App/AppController.m` | import `NSString_CustomTruncation.h` (`ResetFontRelatedTableAttributes`) |
| `Categories/NSFileManager_NV.m` | include `<sys/xattr.h>` (`getxattr`/`setxattr`/`removexattr`) |
| `Categories/NSData_transformations.m` | include `<openssl/err.h>` |
| `Storage/NotationFileManager.m` + `Storage/FSExchangeObjectsCompat.h` | declare & import `volumeCapabilities()` |
| `Sync/SyncSessionController.m` | restore IOKit imports (`<IOKit/IOMessage.h>`, `<IOKit/pwr_mgt/IOPMLib.h>`) |
| `Vendor/RBSplitView/RBSplitView.m`, `Views/EmptyView.m` | forward-declare `outletObjectAwoke()` instead of importing the AppController monolith |
| `Storage/WALController.m` | replace semi-private `CFHashBytes` with an inline FNV-1a hash (public-API, future-proof; values are irrelevant to a CF collection callback) |
| `Categories/NSData_transformations.m` | **real bug fix:** `ERR_error_string(…, 3 args)` → `ERR_error_string_n` (bounded variant the code clearly intended; the old implicit declaration had masked the arg-count mismatch) |

**Local config:** `nvNova/App/SimperiumConfig.h` is git-ignored and must be copied
from `SimperiumConfig-example.h`. An empty `kSimperiumAPIKeyString` disables
Simplenote/Simperium sync while still building. (A placeholder with an empty key
is created locally; provide a real key to enable sync.)

### HiDPI fix (uncommitted as of writing — pending visual confirmation)

`NSHighResolutionCapable` was absent from `Info.plist`, so on Retina displays the
app rendered at 1× and was upscaled — making the whole UI oversized *and* every
bitmap blurry, while the `.icns` icon (separate render path) stayed crisp. Added
`NSHighResolutionCapable = true`. This is expected to resolve most of issues
**#1 (scale)** and **#2 (blurry assets)**; any remaining softness is missing
`@2x` asset variants.

---

## How to build & run

```bash
xcodebuild -project Notation.xcodeproj \
  -scheme "Notation Develop" -configuration Development build
```

The product is `nvNova.app` under `~/Library/Developer/Xcode/DerivedData/Notation-*/Build/Products/Development/`.
On Apple Silicon it runs under Rosetta (x86_64). Opening the project in Xcode and
pressing ⌘R works too (ad-hoc "Sign to Run Locally").

---

## Outstanding issues (prioritized)

Priority reflects the project's purpose: **never lose a note.** Data integrity
outranks polish; polish outranks performance.

### P0 — The fatal product flaw: accidental note deletion is too easy

The #1 reason for the revival. Today a single `Delete` keypress in the notes list,
followed by Return, deletes a note — because the confirmation alert's **default
(Return) button is "Delete"**. There is a confirmation pref (`confirmNoteDeletion`,
default on) and undo + Trash exist as a safety net, but the defaults make a stray
keypress dangerous.

- Core path: `AppController deleteNote:` (`App/AppController.m`) →
  `NotationController removeNotesAtIndexes:` → `removeNote:` (`Storage/NotationController.m`).
- Confirmation alert: `App/AppController.m` (default button is the destructive one).
- Delete key binding: `Views/Tables/NotesTableView.m`.
- Undo: `NotationController _registerDeletionUndoForNote:`. Trash: `NoteObject moveFileToTrash`.

**Likely fix:** make "Cancel" the default button, wire up the suppression
checkbox, and/or require a more deliberate gesture than a single keypress.
_Deliberately not started yet — r wants to re-familiarize with the live behavior
first to define exactly what "right" feels like._

### P1 — Carbon / FSRef runtime correctness (data integrity)

The code compiles ~220 deprecated Carbon `FSRef` / `UTCDateTime` calls (warnings,
not errors), concentrated in `Storage/`. They compile but **may misbehave at
runtime** on modern macOS — and they sit squarely in the file/note-directory
read/write path, so silent failure here means lost or unsaved notes.

**Next step is a _triage_, not the full rewrite:** confirm whether disk and
note-directory operations actually work correctly at runtime on macOS 26, or are
silently failing. That result decides whether this is a five-alarm fire or a slow
background modernization. Hotspots: `Storage/NotationDirectoryManager.m`,
`Storage/NotationFileManager.m`, `Storage/NotationController.m`, `Models/NoteObject.m`.

**Triage started — see `docs/p1-fsref-triage.md`.** Key early finding: APFS
doesn't implement `exchangedata(2)`, so on every modern Mac the native
`FSExchangeObjects` branch is dead code and **100% of atomic saves run through the
emulated swap** (`FSExchangeObjectsCompat.c`) — which is itself FSRef-based. With
the default `SingleDatabaseFormat`, that swap rewrites the entire DB blob on every
save, so the emulation is now load-bearing for all data integrity. The triage doc
has the risk-tiered call inventory, a confirmed safety-net bug in `moveFileToTrash:`
(reports success when it can't resolve the Trash — ties into P0), and a
cheapest-signal-first test method (listen for the existing error logs before
writing any instrumentation).

### P2 — UI scale ("huge UI")

Believed to be the HiDPI key (now added — pending confirmation). If the scale is
correct after that, this is **done** and the old-VM reference exercise is
unnecessary. If it's still wrong, it's a genuine nib/layout problem and a
released-version reference (run in an old macOS VM) is worth gathering.

### P2 — Assets are low quality

The app icon is good, but other bundled image assets look poor. Part of this is
the HiDPI blur (above). What remains is **missing `@2x` Retina variants** /
outdated artwork in `nvNova/Resources/` that need regenerating. Medium effort,
do after the scale question is settled.

### P3 — Native arm64

Currently x86_64/Rosetta because the vendored static libs `libcrypto.a` /
`libssl.a` (i386+x86_64) and the `multimarkdown` binary (x86_64) have **no arm64
slice**. Going native means re-vendoring arm64 OpenSSL and an arm64 (or universal)
`multimarkdown`, then flipping `ARCHS`. Self-contained and satisfying, but it's
performance/cleanliness — not correctness — so it's last.

---

## Deferred / notes

- The ~220 Carbon deprecation **warnings** are expected and intentionally not
  silenced — they're the visible to-do list for the P1 modernization pass.
- `License.txt` (BSD-3-Clause) is a pre-2010 NV leftover; the project is governed
  by `COPYING.txt` (GPL-3.0). Preserve the GPLv3 per-file headers on new files.
