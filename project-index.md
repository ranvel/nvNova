# nvNova (nvALT) — Project Index

> Auto-maintained by Claude. Last updated: 2026-06-27

nvALT is a macOS note-taking app (Cocoa, Objective-C, **MRC — not ARC**), forked
from Notational Velocity. A single search/title field drives everything: typing
filters notes live, and non-matching text becomes a new note's title. Xcode target
`Notation`, product `nvALT`, license GPL-3.0. See `CLAUDE.md` for architecture.

## Project Structure

### / (Root)
- `project-index.md` — This file; master map of the codebase
- `CLAUDE.md` — Root-level AI onboarding context and architecture notes
- `README.md` — Project readme
- `revival-status.md` — Status notes on the modernization/revival effort
- `COPYING.txt` — GPL-3.0 license (the governing license)
- `License.txt` — Leftover BSD-3-Clause from NV's pre-2010 days
- `Acknowledgments.txt` — Third-party acknowledgments
- `Notation.xcodeproj` — Xcode project (edit `project.pbxproj` via the `xcodeproj` gem)

### /docs/
- `docs/revival-status.md` — Detailed revival/build-status writeup

### /nvAlt/App/
Monolithic app delegate, global prefs, and entry point.

- `nvAlt/App/AppController.m` — Primary app delegate / main UI controller (~130 KB)
- `nvAlt/App/AppController_Importing.m` — Note importing from pasteboard and nv:// URLs
- `nvAlt/App/AppController_Preview.m` — Note content access and preview-mode state
- `nvAlt/App/GlobalPrefs.m` — App-wide UI preferences and persistent settings
- `nvAlt/App/main.m` — Application entry point
- `nvAlt/App/SearchCommand.m` — AppleScript search command for note queries
- `nvAlt/App/nvaDevConfig.h` — Development configuration flags for experimental features
- `nvAlt/App/SimperiumConfig.h` — Local Simperium API key config (git-ignored)
- `nvAlt/App/SimperiumConfig-example.h` — Template for Simperium configuration

### /nvAlt/Models/
Core note data models and sync protocols.

- `nvAlt/Models/NoteObject.m` — Core note model; cached C strings power fast search
- `nvAlt/Models/DeletedNoteObject.m` — Note wrapper with deletion metadata (syncs deletions)
- `nvAlt/Models/DeletionManager.m` — Notifications for externally deleted note files
- `nvAlt/Models/LabelObject.m` — Records relationships between labels and notes
- `nvAlt/Models/WordCountToken.m` — Custom UI token displaying word counts
- `nvAlt/Models/SynchronizedNoteProtocol.h` — Protocol defining the synchronized-note interface
- `nvAlt/Models/SynchronizedNoteMixIns.h` — Mixin methods for sync-service metadata

### /nvAlt/Storage/
The heart of the app: in-memory database, WAL journal, and file mirroring.

- `nvAlt/Storage/NotationController.m` — Main notes database controller and orchestrator
- `nvAlt/Storage/NotationPrefs.m` — Per-database prefs: encryption, storage format, sync accounts
- `nvAlt/Storage/NotationFileManager.m` — Reads/writes notes to disk with encoding
- `nvAlt/Storage/NotationDirectoryManager.m` — Manages note directory structure and enumeration
- `nvAlt/Storage/WALController.m` — Write-ahead journal for crash recovery / incremental writes
- `nvAlt/Storage/FrozenNotation.m` — Serializes the whole database blob (optionally encrypted)
- `nvAlt/Storage/DiskUUIDEntry.m` — Caches disk UUID references with timestamps
- `nvAlt/Storage/FSExchangeObjectsCompat.c` — Atomic file-swap compatibility shim for macOS

### /nvAlt/Sync/
Pluggable sync, keyed by service name (only Simplenote registered).

- `nvAlt/Sync/SyncSessionController.m` — Sync session lifecycle and power-event handling
- `nvAlt/Sync/NotationSyncServiceManager.m` — Bridges sync sessions to NotationController
- `nvAlt/Sync/SimplenoteSession.m` — Simperium API session and sync operations
- `nvAlt/Sync/SimplenoteEntryCollector.m` — Collects and parses Simperium sync entries
- `nvAlt/Sync/SyncResponseFetcher.m` — HTTP request and response parsing for sync
- `nvAlt/Sync/SyncServiceSessionProtocol.h` — Protocol every sync backend implements

### /nvAlt/Security/
Encryption primitives, key derivation, and passphrase UI.

- `nvAlt/Security/KeyDerivationManager.m` — Password hashing iterations and key derivation
- `nvAlt/Security/KeyDerivationDelaySlider.m` — UI slider for key-derivation timing
- `nvAlt/Security/pbkdf2.c` — PBKDF2 (SHA1-based) key-derivation function
- `nvAlt/Security/hmacsha1.c` — HMAC-SHA1 message authentication code
- `nvAlt/Security/broken_md5.c` — MD5 digest implementation (public domain)
- `nvAlt/Security/idea_ossl.c` — IDEA block-cipher implementation
- `nvAlt/Security/PassphrasePicker.m` — Passphrase selection interface
- `nvAlt/Security/PassphraseChanger.m` — UI for changing the security passphrase
- `nvAlt/Security/PassphraseRetriever.m` — Retrieves and validates stored passphrases
- `nvAlt/Security/BlorPasswordRetriever.m` — Imports encrypted Blor-format note archives
- `nvAlt/Security/NVPasswordGenerator.m` — Random password generation with charset options
- `nvAlt/Security/SecureTextEntryManager.m` — Manages secure text input and visibility
- `nvAlt/Security/SFPasswordAssistantInspectorController.h` — Apple PasswordAssistant integration

### /nvAlt/Controllers/
UI controllers for prefs, previews, labels, bookmarks, and searches.

- `nvAlt/Controllers/PreviewController.m` — Renders Markdown/Textile preview in a WebView
- `nvAlt/Controllers/PrefsWindowController.m` — App-wide preferences window
- `nvAlt/Controllers/NotationPrefsViewController.m` — Storage and sync preferences view controller
- `nvAlt/Controllers/LabelsListController.m` — Label/tag display and editing UI
- `nvAlt/Controllers/TagEditingManager.m` — Inline tag-editing panel
- `nvAlt/Controllers/BookmarksController.m` — Note bookmarks with search and selection state
- `nvAlt/Controllers/SavedSearchesController.m` — Saved search queries for quick access
- `nvAlt/Controllers/EncodingsManager.m` — Detects and converts text encoding for imports

### /nvAlt/ImportExport/
Importing alien formats and exporting notes.

- `nvAlt/ImportExport/AlienNoteImporter.m` — Imports notes from Stickies and external formats
- `nvAlt/ImportExport/ExporterManager.m` — Exports notes to various storage formats
- `nvAlt/ImportExport/ExternalEditorListController.m` — Manages external text editors for notes
- `nvAlt/ImportExport/StickiesDocument.m` — Imported Apple Stickies note data structure
- `nvAlt/ImportExport/URLGetter.m` — Downloads HTTP URL content for note import

### /nvAlt/Text/
Markup conversion (Markdown/MultiMarkdown/Textile) and text finding.

- `nvAlt/Text/NSString_Markdown.m` — Converts text to HTML via Markdown 1.0.1
- `nvAlt/Text/NSString_MultiMarkdown.m` — MultiMarkdown format processing
- `nvAlt/Text/NSString_Textile.m` — Converts text to HTML via Textile 2.12
- `nvAlt/Text/NSString-Markdown.m` — Alternate Markdown-to-HTML implementation
- `nvAlt/Text/AttributedPlainText.m` — Attributed text with formatting and link detection
- `nvAlt/Text/GGReadabilityParser.m` — Extracts readable content from web-page HTML
- `nvAlt/Text/MultiTextFinder.m` — Text search for pre-10.7 macOS
- `nvAlt/Text/NSTextFinder_LastFind.m` — Adds last-find-success tracking to NSTextFinder
- `nvAlt/Text/NSTextFinder.h` — Text finder interface declarations

### /nvAlt/Categories/
C utilities and Foundation category extensions.

- `nvAlt/Categories/BufferUtils.c` — Buffer/character manipulation utilities for search
- `nvAlt/Categories/CRC32.c` — CRC32 checksum with lookup tables
- `nvAlt/Categories/Spaces.c` — macOS Spaces API for window-space context tracking
- `nvAlt/Categories/InvocationRecorder.m` — Records/replays method invocations for undo
- `nvAlt/Categories/NSBezierPath_NV.m` — Rounded-rectangle drawing extensions
- `nvAlt/Categories/NSCollection_utils.m` — Dictionary/collection utilities for font traits
- `nvAlt/Categories/NSData_transformations.m` — Data compression and crypto transforms
- `nvAlt/Categories/NSFileManager_NV.m` — Finder tags and file-attribute extensions
- `nvAlt/Categories/NSFileManager+DirectoryLocations.m` — Locates standard macOS directories
- `nvAlt/Categories/NSString_CustomTruncation.m` — Text truncation with custom UI formatting
- `nvAlt/Categories/NSString_NV.m` — String utilities for date formatting and searching
- `nvAlt/Categories/TemporaryFileCache.m` — Cache for temporary note-editing files
- `nvAlt/Categories/TemporaryFileCachePreparer.m` — Creates/mounts RAM disks for temp files

### /nvAlt/Views/
Top-level custom views.

- `nvAlt/Views/DFView.m` — Base view with background-color initialization
- `nvAlt/Views/EmptyView.m` — Placeholder shown when no notes available
- `nvAlt/Views/LinearDividerShader.m` — Linear gradient shader for dividers
- `nvAlt/Views/StatusItemView.m` — Status-bar menu item icon view

### /nvAlt/Views/Editors/
The combined search/title field and the rich-text note editor.

- `nvAlt/Views/Editors/DualField.m` — The combined search/title field (DualField)
- `nvAlt/Views/Editors/LinkingEditor.m` — Rich-text editor with note-linking support
- `nvAlt/Views/Editors/LinkingEditor_Indentation.m` — Text indentation handling for the editor
- `nvAlt/Views/Editors/LabelEditor.m` — Label text editor with character validation
- `nvAlt/Views/Editors/MultiplePageView.m` — Apple multi-page text-layout container

### /nvAlt/Views/Tables/
The notes list table and its data source.

- `nvAlt/Views/Tables/NotesTableView.m` — Main notes-list table view
- `nvAlt/Views/Tables/FastListDataSource.m` — Efficient data source for fast rendering
- `nvAlt/Views/Tables/QuickSearchTable.m` — Search-results table with inline editing
- `nvAlt/Views/Tables/BookmarksTable.m` — Bookmarks table with keyboard handling
- `nvAlt/Views/Tables/NoteAttributeColumn.m` — Custom column for note attributes
- `nvAlt/Views/Tables/HeaderViewWIthMenu.m` — Table header view with menu support
- `nvAlt/Views/Tables/NotesTableCornerView.m` — Corner view with gradient decoration

### /nvAlt/Views/Cells/
Custom table/text cells.

- `nvAlt/Views/Cells/UnifiedCell.m` — Unified cell for combined note display
- `nvAlt/Views/Cells/CustomTextFieldCell.m` — Text-field cell with highlight drawing
- `nvAlt/Views/Cells/LabelColumnCell.m` — Editable table cell for label display
- `nvAlt/Views/Cells/NotesTableHeaderCell.m` — Notes-table header with gradient/borders
- `nvAlt/Views/Cells/BTTableHeaderCell.m` — Table header cell with metallic background

### /nvAlt/Views/Scrollers/
Custom scrollers and scroll/clip views (NV's transparent-scroller family).

- `nvAlt/Views/Scrollers/ETScrollView.m` — Scroll view selecting appropriate scroller classes
- `nvAlt/Views/Scrollers/ETNoteScrollView.m` — Note scroll view with custom hit testing
- `nvAlt/Views/Scrollers/ETOverlayScroller.m` — Lion-compatible overlay scrollbar
- `nvAlt/Views/Scrollers/ETTransparentScroller.m` — Transparent scroller with image assets
- `nvAlt/Views/Scrollers/ETClipView.m` — Clip view managing text-width constraints
- `nvAlt/Views/Scrollers/ETContentView.m` — Content view with background rendering
- `nvAlt/Views/Scrollers/BodyScroller.m` — Note-body scroller with delayed layout
- `nvAlt/Views/Scrollers/BlueTransparentScroller.m` — Transparent scroller, blue knob
- `nvAlt/Views/Scrollers/WhiteTransparentScroller.m` — Transparent scroller, white knob
- `nvAlt/Views/Scrollers/BTTransparentScroller.m` — Transparent scrollbar with custom images
- `nvAlt/Views/Scrollers/FocusRingScrollView.m` — Scroll view with focus-ring rendering

### /nvAlt/Views/Buttons/
Custom buttons.

- `nvAlt/Views/Buttons/ETTransparentButton.m` — Transparent button using a custom cell
- `nvAlt/Views/Buttons/ETTransparentButtonCell.m` — Transparent button cell with image assets
- `nvAlt/Views/Buttons/TitlebarButton.m` — Titlebar button with divider-shader styling

### /nvAlt/Views/Windows/
Custom window subclasses.

- `nvAlt/Views/Windows/FullscreenWindow.m` — Fullscreen window accepting keyboard input
- `nvAlt/Views/Windows/MAAttachedWindow.m` — Attached popup window with arrow positioning

### /nvAlt/Resources/
Web preview templates, supporting build files, and interface/localization assets.

- `nvAlt/Resources/Web/template.html` — HTML template for Markdown/Textile preview
- `nvAlt/Resources/Web/templateclean.html` — Minimal "clean" preview template
- `nvAlt/Resources/Web/custom.css` — User-customizable preview stylesheet
- `nvAlt/Resources/Web/customclean.css` — Stylesheet for the clean template
- `nvAlt/Resources/Web/Credits.html` — Credits page shown in-app
- `nvAlt/Resources/Supporting/Info.plist` — App bundle Info.plist
- `nvAlt/Resources/Supporting/Notation_Prefix.pch` — Precompiled-header prefix
- `nvAlt/Resources/Supporting/dsa_pub.pem` — Sparkle update-feed signing public key
- `nvAlt/Resources/Supporting/Markdownify.nvhelp` — In-app Markdown help content
- `nvAlt/Resources/Supporting/tp2md.rb` — TaskPaper-to-Markdown conversion script
- `nvAlt/Resources/Supporting/gen_sectorderfiles` — Build helper for section-order files
- `nvAlt/Resources/Supporting/Notation.freqorder` — Symbol frequency-order optimization data
- `nvAlt/Resources/Supporting/Notation.launchorder` — Launch-order optimization data
- `nvAlt/Resources/Interface/MarkupPreview.xib` — Markup preview interface
- `nvAlt/Resources/Interface/Notation.sdef` — AppleScript scripting-definition file
- `nvAlt/Resources/Localizations/` — `.lproj` nib localizations (de, en, fr, it, pt-PT, zh)

### /nvAlt/Vendor/
Vendored dependencies — frameworks, static OpenSSL, Perl Markdown/Textile, and a
`multimarkdown` binary. Raw vendored source; not individually indexed.
