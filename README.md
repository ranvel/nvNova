# nvNova

> A community revival of **nvALT** — the keyboard-driven, plain-text, search-first
> note app for macOS — nursed back to health and running on modern macOS.
> Free and open source (GPLv3), and yours to keep. No accounts. No subscription.



## Contents
- [About](#about)
- [Heritage](#heritage)
- [What it is](#what-it-is)
- [Features](#features)
- [Project status](#project-status)
- [Building from source](#building-from-source)
- [Customization](#customization)
- [License](#license)
- [Credits](#credits)

## About
nvNova continues the open-source line of Notational Velocity and nvALT. nvALT — the
much-loved fork by Brett Terpstra and David Halter — saw its last release back in
2017, and the codebase had gone dormant. nvNova picks it back up with a simple
promise: **recuperation, not rewrite.** The app was already nearly perfect; the job
is to nurse it back to health on current macOS, fix what's genuinely broken, and
keep it free and open for everyone who just wants a fast, local, plain-text
scratchpad — with no account and no subscription.

Guiding principle: **never lose a note.** Data integrity comes before polish, and
polish comes before performance.

## Heritage
nvNova stands on a long line of keyboard-first note apps:

**[Notational Velocity][notational]** (Zachary Schneirov) → **[nvALT][nvalt]**
(Brett Terpstra & David Halter / Elastic Threads) → **[DivineDominion's
MultiMarkdown fork][divinedominion]** → **nvNova**.

Notes are stored as plain text files on disk — no proprietary database, no lock-in.
Your notes outlive any one app, including this one.

## What it is
Notational Velocity is a way to take notes quickly and effortlessly using just your
keyboard. Press a shortcut to bring up the window and start typing — it searches
your existing notes as you type, filtering the list live. Use ⌘-J and ⌘-K to move
through the results. Enter selects and begins editing; if nothing matches, just type
a unique title and press Enter to start a fresh note. See
[notational.net][notational] for the original, more eloquent synopsis.

## Features
On top of the core Notational Velocity workflow, nvNova carries forward nvALT's
additions:

- Widescreen (horizontal) layout option
- Shortcut (⌘-⌥-N) to collapse the notes panel
- Markdown, Textile, and MultiMarkdown support with a Preview window
- HTML source tab in the Preview window for fast copy/paste to blogs, etc.
- Customizable HTML and CSS templates for the Preview window (JavaScript supported)
- Interface refinements and assorted bug fixes

## Project status
nvNova is an active revival, developed in the open.

- **It builds and runs again** on modern macOS — the first time the project has
  compiled since the macOS 10.9 era.
- Current builds are **x86_64 (Rosetta on Apple Silicon)** by deliberate choice: the
  vendored crypto and MultiMarkdown libraries are Intel-only for now. A native arm64
  pass is planned.
- It remains **pure Objective-C / AppKit** — faithful to the original. No rewrite.

Work in progress, roughly in priority order: making accidental note deletion harder
(the #1 reason for the revival), verifying the legacy file-I/O path behaves
correctly on current macOS, Retina/asset cleanup, and native arm64. See
[`docs/revival-status.md`](docs/revival-status.md) for the live roadmap.

## Building from source
No pre-built release is available yet — for now, build it yourself:

```bash
git clone <your-fork-url> nvNova
cd nvNova
cp nvAlt/App/SimperiumConfig-example.h nvAlt/App/SimperiumConfig.h
xcodebuild -project Notation.xcodeproj -scheme "Notation Develop" -configuration Development build
```

`SimperiumConfig.h` is git-ignored; an empty `kSimperiumAPIKeyString` builds fine and
simply disables Simplenote/Simperium sync. Provide a real key to enable it. The built
app (still named `nvALT.app` until the rename lands) appears under
`~/Library/Developer/Xcode/DerivedData/`. Opening the project in Xcode and pressing
⌘R works too (ad-hoc "Sign to Run Locally").

## Customization
Choose "Open Custom CSS Folder" in the Preview menu and the app's support folder
opens, containing `template.html` and `custom.css`. If you're handy with HTML and
CSS, customize these however you like. You can add JavaScript too, but external
scripts must load from a URL or a full `file://` path. If anything breaks, delete or
rename your customizations and the defaults are restored automatically the next time
you open the menu item.

## License
nvNova is distributed under the **GNU General Public License v3.0** (see
[`COPYING.txt`](COPYING.txt)) — chosen deliberately so the project stays free and
open for good. No one can take it closed.

Portions of the original Notational Velocity source carry a BSD-3-Clause notice,
preserved in [`License.txt`](License.txt). New files should carry GPLv3 headers.

## Credits
nvNova exists only because of the people who built and maintained what came before:

- **Notational Velocity** — original [source][original source] by Zachary Schneirov
  ([scrod][original source])
- **nvALT** — Brett Terpstra ([ttscoff][nvalt]) and David Halter / Elastic Threads
  ([elasticthreads][elasticthreads])
- **MultiMarkdown fork** — [DivineDominion][divinedominion]
- **nvNova** — maintained by <!-- TODO: your handle / the community -->

[notational]: http://notational.net/
[original source]: https://github.com/scrod/nv
[divinedominion]: https://github.com/DivineDominion/nv
[nvalt]: https://brettterpstra.com/projects/nvalt/
[elasticthreads]: https://github.com/elasticthreads/nv