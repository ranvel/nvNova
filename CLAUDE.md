# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**nvALT** — a macOS note-taking app (Cocoa, Objective-C), forked from Zachary Schneirov's **Notational Velocity**. The Xcode target is named `Notation`; the product is `nvALT`. The core idea: a single search/title field drives everything — typing incrementally filters notes in real time, and if nothing matches, that same text becomes the title of a new note (⌘J/⌘K navigate the list).

License is **GPL-3.0** (`COPYING.txt`); `License.txt` (BSD-3-Clause) is a leftover from NV's pre-2010 days. Per-file source headers carry the GPLv3 grant — preserve it on files you add.

## Build

```bash
# Schemes: "Notation Develop" and "Notation Release". Configs: Development, ForBuilding.
xcodebuild -project Notation.xcodeproj -scheme "Notation Develop" -configuration Development build
```

There is no test target, no package manager, and no lint config — it's a plain Xcode project. Dependencies are vendored under `nvAlt/Vendor/` (frameworks, static OpenSSL, Perl Markdown/Textile, a `multimarkdown` binary).

### It does not currently compile, by design
The codebase targets macOS 10.9 and is being modernized incrementally. Do **not** spend effort making it build unless explicitly asked. Known blockers, in order:
1. **Header search paths.** Every `#import` is a bare `"Foo.h"` with no path (the project was historically flat). After the directory reorg (see below), cross-folder imports need a recursive path — add `$(SRCROOT)/nvAlt/**` to `HEADER_SEARCH_PATHS` with `ALWAYS_SEARCH_USER_PATHS = YES`. The existing `HEADER_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` still point at pre-reorg / Homebrew-era locations and are stale.
2. **10.9-era API deprecations** — Carbon `UTCDateTime`/`FSRef`, `CFHashBytes`, deprecated AppKit, etc.

## Memory management

**Manual Reference Counting (MRC), not ARC.** ARC and ObjC GC are both off. Honor `retain`/`release`/`autorelease`/`dealloc` manually, and note the heavy use of raw C buffers (`malloc`/`free`) for search — get the ownership right.

## Architecture (the parts that span many files)

**`NotationController` (`nvAlt/Storage/`) is the heart.** It owns the in-memory note database — `allNotes` plus a parallel C array (`allNotesBuffer`) for fast filtering — and coordinates the list data source, labels, deletion, and sync. Most subsystems hang off it.

**`NoteObject` (`nvAlt/Models/`)** is the note model (`<NSCoding, SynchronizedNote>`). The "Velocity" speed comes from cached C strings (`cTitle`, `cContents`, `cLabels`) that incremental search scans directly rather than walking `NSString`s. Notes carry `nodeID` + per-disk info for file syncing and WAL storage.

**Persistence is layered:**
- **`WALController` / `WALStorageController` (`Storage/`)** — a write-ahead journal. Each note change is appended as a per-record-encrypted (per-record salt + master key), zlib-compressed record. This is the crash-safety / incremental-write layer.
- **`NotationFileManager` / `NotationDirectoryManager` (`Storage/`)** — mirror notes to/from individual files in the user's notes directory (tracked via `NoteCatalogEntry`). `NotationPrefs.notesStorageFormat` picks the on-disk format (single encrypted database vs. plain text / RTF / HTML).
- **`FrozenNotation`** — the serialized (optionally encrypted) whole-database blob.

**`NotationPrefs` (`Storage/`) is per-database, distinct from `GlobalPrefs` (`App/`, app-wide UI prefs).** It holds the encryption state (master key/salt/verifier, PBKDF2 iteration count), storage format, allowed file types, and sync-service account credentials (kept in the keychain). Encryption primitives live in `nvAlt/Security/` (PBKDF2, the WAL/database master key, passphrase UI).

**Sync (`nvAlt/Sync/`) is pluggable by service name.** `SyncSessionController` holds a session per service, each conforming to `<SyncServiceSession>`; `NotationSyncServiceManager` bridges it to `NotationController`. The only registered service is Simplenote — `+[SyncSessionController allServiceClasses]` returns `[SimplenoteSession]`, so that array is the extension point for adding a backend. Both `NoteObject` and `DeletedNoteObject` conform to `<SynchronizedNote>` so deletions sync too. Sync uses IOKit power notifications to delay system sleep mid-operation.

**`AppController` (`nvAlt/App/`, ~130 KB) is the monolithic app delegate / main UI controller.** It wires the `DualField` (the combined search/title field), the notes table, the `RBSplitView` (horizontal/vertical layouts), the `LinkingEditor`, and the Markdown/MultiMarkdown/Textile `PreviewController`. Preview rendering runs note text through the vendored markup tools (`nvAlt/Text/` + `nvAlt/Vendor/`) into the HTML templates in `nvAlt/Resources/Web/` (`template.html` + `custom.css`, user-customizable).

## Repository layout & editing the project file

Source is organized under `nvAlt/` by subsystem: `App`, `Models`, `Storage`, `Sync`, `Security`, `ImportExport`, `Text`, `Controllers`, `Categories`, `Views/{Scrollers,Cells,Tables,Editors,Buttons,Windows}`, `Vendor`, `Resources`. Only `Notation.xcodeproj` and docs sit at the repo root. The Xcode group tree mirrors these folders.

Because imports are path-less, **moving or adding files means updating `Notation.xcodeproj/project.pbxproj`**. Do this with the `xcodeproj` Ruby gem (already installed) rather than hand-editing the pbxproj — a small script that finds the file reference, sets its group/path, and saves is the reliable approach.
