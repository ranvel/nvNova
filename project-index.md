# nvNova (nvALT) — Project Index

> Auto-maintained by Claude. Last updated: 2026-06-27

nvNova is a macOS note-taking app (Cocoa, Objective-C, **MRC — not ARC**), forked
from Notational Velocity. A single search/title field drives everything: typing
filters notes live, and non-matching text becomes a new note's title. Xcode target
`Notation`, product `nvNova`, license GPL-3.0. See `CLAUDE.md` for architecture.

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

### /nvNova/App/
Monolithic app delegate, global prefs, and entry point.

- `nvNova/App/AppController.m` — Primary app delegate / main UI controller (~130 KB)
- `nvNova/App/AppController_Importing.m` — Note importing from pasteboard and nv:// URLs
- `nvNova/App/AppController_Preview.m` — Note content access and preview-mode state
- `nvNova/App/GlobalPrefs.m` — App-wide UI preferences and persistent settings
- `nvNova/App/main.m` — Application entry point
- `nvNova/App/SearchCommand.m` — AppleScript search command for note queries
- `nvNova/App/nvaDevConfig.h` — Development configuration flags for experimental features
- `nvNova/App/SimperiumConfig.h` — Local Simperium API key config (git-ignored)
- `nvNova/App/SimperiumConfig-example.h` — Template for Simperium configuration

### /nvNova/Models/
Core note data models and sync protocols.

- `nvNova/Models/NoteObject.m` — Core note model; cached C strings power fast search
- `nvNova/Models/DeletedNoteObject.m` — Note wrapper with deletion metadata (syncs deletions)
- `nvNova/Models/DeletionManager.m` — Notifications for externally deleted note files
- `nvNova/Models/LabelObject.m` — Records relationships between labels and notes
- `nvNova/Models/WordCountToken.m` — Custom UI token displaying word counts
- `nvNova/Models/SynchronizedNoteProtocol.h` — Protocol defining the synchronized-note interface
- `nvNova/Models/SynchronizedNoteMixIns.h` — Mixin methods for sync-service metadata

### /nvNova/Storage/
The heart of the app: in-memory database, WAL journal, and file mirroring.

- `nvNova/Storage/NotationController.m` — Main notes database controller and orchestrator
- `nvNova/Storage/NotationPrefs.m` — Per-database prefs: encryption, storage format, sync accounts
- `nvNova/Storage/NotationFileManager.m` — Reads/writes notes to disk with encoding
- `nvNova/Storage/NotationDirectoryManager.m` — Manages note directory structure and enumeration
- `nvNova/Storage/WALController.m` — Write-ahead journal for crash recovery / incremental writes
- `nvNova/Storage/FrozenNotation.m` — Serializes the whole database blob (optionally encrypted)
- `nvNova/Storage/DiskUUIDEntry.m` — Caches disk UUID references with timestamps
- `nvNova/Storage/FSExchangeObjectsCompat.c` — Atomic file-swap compatibility shim for macOS

### /nvNova/Sync/
Pluggable sync, keyed by service name (only Simplenote registered).

- `nvNova/Sync/SyncSessionController.m` — Sync session lifecycle and power-event handling
- `nvNova/Sync/NotationSyncServiceManager.m` — Bridges sync sessions to NotationController
- `nvNova/Sync/SimplenoteSession.m` — Simperium API session and sync operations
- `nvNova/Sync/SimplenoteEntryCollector.m` — Collects and parses Simperium sync entries
- `nvNova/Sync/SyncResponseFetcher.m` — HTTP request and response parsing for sync
- `nvNova/Sync/SyncServiceSessionProtocol.h` — Protocol every sync backend implements

### /nvNova/Security/
Encryption primitives, key derivation, and passphrase UI.

- `nvNova/Security/KeyDerivationManager.m` — Password hashing iterations and key derivation
- `nvNova/Security/KeyDerivationDelaySlider.m` — UI slider for key-derivation timing
- `nvNova/Security/pbkdf2.c` — PBKDF2 (SHA1-based) key-derivation function
- `nvNova/Security/hmacsha1.c` — HMAC-SHA1 message authentication code
- `nvNova/Security/broken_md5.c` — MD5 digest implementation (public domain)
- `nvNova/Security/idea_ossl.c` — IDEA block-cipher implementation
- `nvNova/Security/PassphrasePicker.m` — Passphrase selection interface
- `nvNova/Security/PassphraseChanger.m` — UI for changing the security passphrase
- `nvNova/Security/PassphraseRetriever.m` — Retrieves and validates stored passphrases
- `nvNova/Security/BlorPasswordRetriever.m` — Imports encrypted Blor-format note archives
- `nvNova/Security/NVPasswordGenerator.m` — Random password generation with charset options
- `nvNova/Security/SecureTextEntryManager.m` — Manages secure text input and visibility
- `nvNova/Security/SFPasswordAssistantInspectorController.h` — Apple PasswordAssistant integration

### /nvNova/Controllers/
UI controllers for prefs, previews, labels, bookmarks, and searches.

- `nvNova/Controllers/PreviewController.m` — Renders Markdown/Textile preview in a WebView
- `nvNova/Controllers/PrefsWindowController.m` — App-wide preferences window
- `nvNova/Controllers/NotationPrefsViewController.m` — Storage and sync preferences view controller
- `nvNova/Controllers/LabelsListController.m` — Label/tag display and editing UI
- `nvNova/Controllers/TagEditingManager.m` — Inline tag-editing panel
- `nvNova/Controllers/BookmarksController.m` — Note bookmarks with search and selection state
- `nvNova/Controllers/SavedSearchesController.m` — Saved search queries for quick access
- `nvNova/Controllers/EncodingsManager.m` — Detects and converts text encoding for imports

### /nvNova/ImportExport/
Importing alien formats and exporting notes.

- `nvNova/ImportExport/AlienNoteImporter.m` — Imports notes from Stickies and external formats
- `nvNova/ImportExport/ExporterManager.m` — Exports notes to various storage formats
- `nvNova/ImportExport/ExternalEditorListController.m` — Manages external text editors for notes
- `nvNova/ImportExport/StickiesDocument.m` — Imported Apple Stickies note data structure
- `nvNova/ImportExport/URLGetter.m` — Downloads HTTP URL content for note import

### /nvNova/Text/
Markup conversion (Markdown/MultiMarkdown/Textile) and text finding.

- `nvNova/Text/NSString_Markdown.m` — Converts text to HTML via Markdown 1.0.1
- `nvNova/Text/NSString_MultiMarkdown.m` — MultiMarkdown format processing
- `nvNova/Text/NSString_Textile.m` — Converts text to HTML via Textile 2.12
- `nvNova/Text/NSString-Markdown.m` — Alternate Markdown-to-HTML implementation
- `nvNova/Text/AttributedPlainText.m` — Attributed text with formatting and link detection
- `nvNova/Text/GGReadabilityParser.m` — Extracts readable content from web-page HTML
- `nvNova/Text/MultiTextFinder.m` — Text search for pre-10.7 macOS
- `nvNova/Text/NSTextFinder_LastFind.m` — Adds last-find-success tracking to NSTextFinder
- `nvNova/Text/NSTextFinder.h` — Text finder interface declarations

### /nvNova/Categories/
C utilities and Foundation category extensions.

- `nvNova/Categories/BufferUtils.c` — Buffer/character manipulation utilities for search
- `nvNova/Categories/CRC32.c` — CRC32 checksum with lookup tables
- `nvNova/Categories/Spaces.c` — macOS Spaces API for window-space context tracking
- `nvNova/Categories/InvocationRecorder.m` — Records/replays method invocations for undo
- `nvNova/Categories/NSBezierPath_NV.m` — Rounded-rectangle drawing extensions
- `nvNova/Categories/NSCollection_utils.m` — Dictionary/collection utilities for font traits
- `nvNova/Categories/NSData_transformations.m` — Data compression and crypto transforms
- `nvNova/Categories/NSFileManager_NV.m` — Finder tags and file-attribute extensions
- `nvNova/Categories/NSFileManager+DirectoryLocations.m` — Locates standard macOS directories
- `nvNova/Categories/NSString_CustomTruncation.m` — Text truncation with custom UI formatting
- `nvNova/Categories/NSString_NV.m` — String utilities for date formatting and searching
- `nvNova/Categories/TemporaryFileCache.m` — Cache for temporary note-editing files
- `nvNova/Categories/TemporaryFileCachePreparer.m` — Creates/mounts RAM disks for temp files

### /nvNova/Views/
Top-level custom views.

- `nvNova/Views/DFView.m` — Base view with background-color initialization
- `nvNova/Views/EmptyView.m` — Placeholder shown when no notes available
- `nvNova/Views/LinearDividerShader.m` — Linear gradient shader for dividers
- `nvNova/Views/StatusItemView.m` — Status-bar menu item icon view

### /nvNova/Views/Editors/
The combined search/title field and the rich-text note editor.

- `nvNova/Views/Editors/DualField.m` — The combined search/title field (DualField)
- `nvNova/Views/Editors/LinkingEditor.m` — Rich-text editor with note-linking support
- `nvNova/Views/Editors/LinkingEditor_Indentation.m` — Text indentation handling for the editor
- `nvNova/Views/Editors/LabelEditor.m` — Label text editor with character validation
- `nvNova/Views/Editors/MultiplePageView.m` — Apple multi-page text-layout container

### /nvNova/Views/Tables/
The notes list table and its data source.

- `nvNova/Views/Tables/NotesTableView.m` — Main notes-list table view
- `nvNova/Views/Tables/FastListDataSource.m` — Efficient data source for fast rendering
- `nvNova/Views/Tables/QuickSearchTable.m` — Search-results table with inline editing
- `nvNova/Views/Tables/BookmarksTable.m` — Bookmarks table with keyboard handling
- `nvNova/Views/Tables/NoteAttributeColumn.m` — Custom column for note attributes
- `nvNova/Views/Tables/HeaderViewWIthMenu.m` — Table header view with menu support
- `nvNova/Views/Tables/NotesTableCornerView.m` — Corner view with gradient decoration

### /nvNova/Views/Cells/
Custom table/text cells.

- `nvNova/Views/Cells/UnifiedCell.m` — Unified cell for combined note display
- `nvNova/Views/Cells/CustomTextFieldCell.m` — Text-field cell with highlight drawing
- `nvNova/Views/Cells/LabelColumnCell.m` — Editable table cell for label display
- `nvNova/Views/Cells/NotesTableHeaderCell.m` — Notes-table header with gradient/borders
- `nvNova/Views/Cells/BTTableHeaderCell.m` — Table header cell with metallic background

### /nvNova/Views/Scrollers/
Custom scrollers and scroll/clip views (NV's transparent-scroller family).

- `nvNova/Views/Scrollers/ETScrollView.m` — Scroll view selecting appropriate scroller classes
- `nvNova/Views/Scrollers/ETNoteScrollView.m` — Note scroll view with custom hit testing
- `nvNova/Views/Scrollers/ETOverlayScroller.m` — Lion-compatible overlay scrollbar
- `nvNova/Views/Scrollers/ETTransparentScroller.m` — Transparent scroller with image assets
- `nvNova/Views/Scrollers/ETClipView.m` — Clip view managing text-width constraints
- `nvNova/Views/Scrollers/ETContentView.m` — Content view with background rendering
- `nvNova/Views/Scrollers/BodyScroller.m` — Note-body scroller with delayed layout
- `nvNova/Views/Scrollers/BlueTransparentScroller.m` — Transparent scroller, blue knob
- `nvNova/Views/Scrollers/WhiteTransparentScroller.m` — Transparent scroller, white knob
- `nvNova/Views/Scrollers/BTTransparentScroller.m` — Transparent scrollbar with custom images
- `nvNova/Views/Scrollers/FocusRingScrollView.m` — Scroll view with focus-ring rendering

### /nvNova/Views/Buttons/
Custom buttons.

- `nvNova/Views/Buttons/ETTransparentButton.m` — Transparent button using a custom cell
- `nvNova/Views/Buttons/ETTransparentButtonCell.m` — Transparent button cell with image assets
- `nvNova/Views/Buttons/TitlebarButton.m` — Titlebar button with divider-shader styling

### /nvNova/Views/Windows/
Custom window subclasses.

- `nvNova/Views/Windows/FullscreenWindow.m` — Fullscreen window accepting keyboard input
- `nvNova/Views/Windows/MAAttachedWindow.m` — Attached popup window with arrow positioning

### /nvNova/Resources/
Web preview templates, supporting build files, and interface/localization assets.

- `nvNova/Resources/Web/template.html` — HTML template for Markdown/Textile preview
- `nvNova/Resources/Web/templateclean.html` — Minimal "clean" preview template
- `nvNova/Resources/Web/custom.css` — User-customizable preview stylesheet
- `nvNova/Resources/Web/customclean.css` — Stylesheet for the clean template
- `nvNova/Resources/Web/Credits.html` — Credits page shown in-app
- `nvNova/Resources/Supporting/Info.plist` — App bundle Info.plist
- `nvNova/Resources/Supporting/Notation_Prefix.pch` — Precompiled-header prefix
- `nvNova/Resources/Supporting/dsa_pub.pem` — Sparkle update-feed signing public key
- `nvNova/Resources/Supporting/Markdownify.nvhelp` — In-app Markdown help content
- `nvNova/Resources/Supporting/tp2md.rb` — TaskPaper-to-Markdown conversion script
- `nvNova/Resources/Supporting/gen_sectorderfiles` — Build helper for section-order files
- `nvNova/Resources/Supporting/Notation.freqorder` — Symbol frequency-order optimization data
- `nvNova/Resources/Supporting/Notation.launchorder` — Launch-order optimization data
- `nvNova/Resources/Interface/MarkupPreview.xib` — Markup preview interface
- `nvNova/Resources/Interface/Notation.sdef` — AppleScript scripting-definition file
- `nvNova/Resources/Localizations/` — `.lproj` nib localizations (de, en, fr, it, pt-PT, zh)

### /nvNova/Vendor/
Vendored dependencies — frameworks, static OpenSSL, Perl Markdown/Textile, and a
`multimarkdown` binary. Raw vendored source; not individually indexed.
