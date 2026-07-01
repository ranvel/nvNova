# PMJ — Poor Man's Jira 📋
### Implementation spec — plaintext markdown ticketing under version control

This document is a complete, project-agnostic spec for standing up a PMJ tracker
in any project. It is written to be handed to **Cici** (Claude Code) and the
**Claude** PM/architecture role cold, with no prior context. Fill in the
[Project Parameters](#1-project-parameters-fill-these-in) block first; every
other section reads off it.

PMJ replaces a hosted issue tracker (Jira, Linear, etc.) with plaintext `.md`
tickets living in the repo. The wins it is buying:

- **One MCP, no context bleed.** A hosted tracker means a second MCP in the
  loop alongside the project's file bridge. Two MCPs bleed context into each
  other. PMJ collapses to a single local file MCP — the bridge — and the
  tracker becomes ordinary files that bridge already reads.
- **The ticket IS the brief.** No separate handoff doc. The ticket carries the
  recon prompt, the locked solution, and the implementation handoff in one
  versioned file.
- **No tracker-API taxes.** Whole-description-replace stomping edits, no inline
  backticks, identifier-escaping quirks, title-juggling for status — all of
  that is an artifact of poking a tracker through an API. Plaintext under git
  has none of it. Edits are surgical; history is `git log`.
- **Deterministic Claude ↔ Cici interface.** The file on disk is the single
  source of truth both roles read and write. No sync lag, no stale-status
  window.

---

## 1. Project parameters (fill these in)

The implementing Claude/Cici fills this in once, per project, before anything
else. Everything downstream references these names.

| Parameter        | Example          | Meaning                                                      |
|------------------|------------------|-------------------------------------------------------------|
| `KEY_PREFIX`     | `PROJ`           | Ticket key prefix. Keys look like `PROJ-1`, `PROJ-2`, …      |
| `TICKETS_DIR`    | `docs/pmj/`      | Where live tickets live. (Name it `pmj/`, `fakear/`, etc.)   |
| `ARCHIVE_DIR`    | `docs/pmj/_archive/` | Dead tickets (Done/Canceled/Duplicate).                 |
| `ATTACH_DIR`     | `docs/pmj/attach/`   | Per-ticket recon + supporting files.                    |
| `BRIDGE_NAME`    | `proj-bridge`    | The local file MCP rooted at the project root.              |
| `SEAM_START`     | `1` (greenfield) | First PMJ-native number. If migrating, see Appendix A.      |

> Assumption baked into this spec: there is exactly **one** file-bridge MCP
> rooted at the project root, giving read/write to project files and `docs/`.
> If the project doesn't have one yet, stand it up first — PMJ is unusable
> without it.

---

## 2. Roles — the Triangle 🔺

Three actors, fixed responsibilities. The whole model depends on each one
staying in its lane.

- **R** — direction and the quality gate. Brings the problem. Does QA (DAT).
  Owns the `DAT → Done` transition. Supplies session UUIDs.
- **Claude** (PM / architecture) — writes the problem-statement ticket
  (carrying the recon *prompt* for Cici), works solutioning with R, is the
  **numbering authority**, and runs suspicion-driven verification. **Does no
  recon at problem-statement** (see §6, the no-bleed mechanism).
- **Cici** (Claude Code) — does recon, gathers exact paths, implements the
  locked fix. Works the filesystem natively. Closes `Implementation → DAT`.

---

## 3. Directory layout

```
docs/
	pmj/                          ← TICKETS_DIR (live tickets)
		PROJ-1.md
		PROJ-2.md
		...
		project-index.md          ← master map (optional but recommended)
		attach/                   ← ATTACH_DIR
			PROJ-1/
				recon.md          ← Cici's recon, separate file, no clobber
				<other-notes>.md
		_archive/                 ← ARCHIVE_DIR (dead tickets)
			PROJ-0.md
			...
			<raw-export>.csv      ← if migrating: lossless source of truth
```

Two rules that matter:

- **Filename and key agree.** `PROJ-7.md` must carry `key: PROJ-7` in
  frontmatter. Any rename touches both; Cici confirms agreement.
- **Recon is a separate file**, never appended into the ticket body. That's
  what kills merge clobber when Cici and Claude touch a ticket near the same
  time.

---

## 4. Ticket file format

A ticket is **YAML frontmatter between `---` fences**, then a **markdown body**.

> **Indentation rule:** frontmatter is **spaces** (YAML forbids tabs). The body
> follows the project's normal source convention — if the project indents with
> tabs, the body uses tabs. Keep the two straight; it's the one place the two
> conventions live in the same file.

```
---
key: PROJ-7
summary: One-line title, no status emoji, no backticks needed
status: Backlog
resolution:
priority: 2
fixVersion:
created: 2026-06-27
updated: 2026-06-27
session:
tags: [area, subsystem]
---

## Background
Why this exists. For machine-generated tickets this is the imported
description verbatim.

## Recon (Cici)
RESOLVED — full findings: attach/PROJ-7/recon.md
Short summary of what was found + the exact paths that matter.

## Solution (locked)
The fix criteria R + Claude agreed on. This is the handoff to Cici.

## Implementation
What Cici did. Exact files touched. Deviations from the plan called out.

## DAT (R)
R's QA checklist.

## Discussion
(Optional.) Imported comments or running notes, author + timestamp preserved.
```

Frontmatter fields:

- `key` — must equal the filename stem.
- `summary` — plain one-liner. No status markers in the title; status is
  structured (see §5).
- `status` — from the vocab in §5.
- `priority` — integer. `1`=Urgent, `2`=High, `3`=Medium, `4`=Low.
- `session` — the `claude --resume <uuid>` handle for Cici's working session.
  Lives here now, **not** as a pinned block in the body. R supplies the UUID.
- `created` / `updated` — ISO `YYYY-MM-DD`.
- `tags` — YAML flow list.

The body sections are conventions, not schema — a Backlog ticket may be just
`## Background`. Sections get filled in as the ticket walks the lifecycle.

---

## 5. Status vocabulary

**Live statuses** (used for active work):

- **Backlog** — captured, not yet started.
- **Recon** — Cici is gathering details and exact paths.
- **Solutioning** — R + Claude are locking the fix criteria.
- **Implementing** — Cici is building the locked fix.
- **DAT** — Dev Acceptance Test. R is doing QA.
- **Deferred** — intentionally shelved, *with a reason*. Not expected to resume
  soon.
- **Parked** — blocked/waiting on something external. Expected to resume.
- **Done** — accepted.

**Archive-only historical statuses** (carried verbatim from a prior tracker,
never assigned to live work):

- **Canceled** (one `l`) — won't do.
- **Duplicate** — folded into another ticket.

---

## 6. The lifecycle + the Commandment ⚖️

### The Muwavian Commandment

> **The phase-completer advances the status.** Whoever closes a phase flips the
> `status` field. No handoff dance, no stale-status window — each transition is
> owned by the actor who earned it.

- R + Claude close **Solutioning → Implementing**.
- Cici closes **Implementation → DAT**.
- R closes **DAT → Done**.

### The sequence

Each arrow is a status flip owned by the actor who just finished a phase.

1. **Ticket creation** — R brings the problem. No ticket, no status yet.
2. **Problem statement** — Claude writes a thin ticket carrying the **recon
   prompt** for Cici. **Claude does NO recon here** — writing the prompt is the
   job; reading the files is Cici's. → `status: Recon`.
3. **Recon** — Cici does the initial pass, gathers details, supplies exact
   paths into `ATTACH_DIR/<key>/recon.md`. → `status: Solutioning`.
4. **Solutioning** — R + Claude work the issue and lock the fix criteria into
   `## Solution`. → `status: Implementing`.
5. **Implementation** — Cici implements the locked fix, records what was
   touched in `## Implementation`. → `status: DAT`.
6. **DAT** — R does QA against `## DAT`. → `status: Done` (via PAR if taken).
7. **PAR** (Post-Action Review) — optional, but **MUST be fresh context**. Same
   eyes that authored the code cannot review it.

---

## 7. The no-bleed mechanism (why step 2 matters)

This is the single most important constraint and the easiest one to violate.

At **problem statement**, Claude's job is to write the *prompt that sends Cici
into the codebase* — not to go into the codebase itself. If Claude recons here,
Claude re-reads everything Cici is about to read, the two roles collapse, and
the migration stops paying for itself. The whole point is that recon happens
**once**, by Cici, with the results written down where Claude can read them
cheaply.

So: problem-statement Claude writes the prompt and stops. 🛑

---

## 8. Numbering authority

**Claude owns numbering.** No other actor mints keys.

```
next key = max( KEY_PREFIX-N found anywhere under TICKETS_DIR,
                including _archive/ )  +  1
```

Archive numbers stay in scope so the rule can never collide with a dead
number. Always scan for the real max before minting — don't trust a number
written into an older ticket's prose, since tickets get created after that
prose was written.

If migrating from a prior tracker, you may leave a **deliberate numbering seam**
(e.g. old tracker used `≤ 237`; PMJ-native starts at `251`, leaving `238–250`
empty as a visible boundary between imported and native tickets). Greenfield
projects just start at `SEAM_START = 1`.

---

## 9. Verification model

Claude's second pass is **suspicion-driven, not reduced**. The recon doc is the
**default entry point, never a ceiling**. Claude keeps full authority to verify
Cici against source whenever something smells off — and because Cici supplies
exact paths, that verification is cheap.

This lane is **separate from step 2**. Verification happens *at or after Recon*,
never at problem statement. Reconning to write the prompt = bad (breaks
no-bleed). Reconning because the recon result smells wrong = good and fully
allowed.

---

## 10. Deliberately retired

When standing PMJ up, make sure none of these sneak back in:

- **A second tracker MCP.** One bridge only. A second MCP is the context bleed
  PMJ exists to kill.
- **Tracker-API workarounds.** No-inline-backticks rules, escape-the-dots,
  whole-description-replace caution — all gone. It's plaintext under git.
- **Pinned session block in the body.** Session handle lives in `session:`
  frontmatter now.
- **Status-in-the-title** (traffic-light emoji, etc.). Status is a structured
  field; titles stay clean.

---

## 11. Recommended: encode it as a project skill

Drop a `<project>-pmj` skill into the project's skills dir that restates §3–§10
in a few hundred words, so Claude auto-loads the conventions instead of
re-deriving them each session. The skill should name `TICKETS_DIR`,
`ARCHIVE_DIR`, `ATTACH_DIR`, the status vocab, the Commandment, and the
numbering rule. This is the difference between PMJ being a document someone has
to remember to read and PMJ being how the project just works.

---

## Appendix A — Migrating from an existing tracker 🚚

Only relevant if the project is porting off Jira/Linear/etc. Greenfield
projects skip this.

### The reframe that makes it tractable

Two operations get conflated under the word "convert." Split them and the
hard part dissolves:

- **Machine-gen** — build a `.md` file from an export row (frontmatter + body).
  Cheap, lossless for the body. Do it for **every** ticket.
- **Hand-author** — write the living work sections (Recon / Solution /
  Implementation / DAT, plus comment context). Expensive. Do it **only** for
  tickets actually being worked.

### Three buckets by status

- **Active** (in-progress / deferred / parked) → `TICKETS_DIR`. Hand-authored
  with care. Pull comments from the old tracker's API (non-empty only), append
  as `## Discussion` with author + timestamp preserved. **This is the only
  hand-conversion burden** — usually a small handful of tickets.
- **Backlog** → `TICKETS_DIR`. Machine-gen thin tickets (frontmatter +
  description as `## Background`), `status: Backlog`. No hand-work. Scaffolding
  gets added the day one wakes into Recon.
- **Dead** (done / canceled / duplicate) → `ARCHIVE_DIR`. Machine-gen stubs,
  status preserved verbatim. **Keep the raw export (CSV/JSON) alongside** as the
  lossless source of truth.

### "Still-referenced" is NOT a conversion trigger

This is the trap. In a cross-referenced codebase, "convert anything still
mentioned" drags the whole dead graph back into scope and defeats the goal.
Don't. References resolve against `ARCHIVE_DIR` — `cat _archive/PROJ-99.md`
beats grepping a thousand-row export, and a dead ticket needn't be in PMJ format
to be findable. Promote a dead ticket to live **by hand, as a rare exception**,
never as a rule.

### Two migration gotchas that bite

- **Comments live only on the old tracker's servers.** Machine-gen pulls the
  description, not the comment threads (exports usually drop them). Dropping the
  tracker's MCP doesn't delete the comments — but **cancelling the subscription
  will**. If any comment history matters, do a one-time bulk comment archive
  **before** billing is cancelled.
- **Account-level connectors can't be removed by Cici.** A tracker MCP
  provisioned at the *account* level (e.g. through a claude.ai login) is not a
  local config file — Cici cannot remove it, and until R disconnects it manually
  (claude.ai → Settings → Connectors) the old tracker stays reachable, which
  quietly defeats the one-MCP goal. Also watch for **inert allowlist entries**
  in the local settings file: Cici's self-modification guardrail blocks her from
  editing her own permissions file, so R prunes those by hand. They're dead
  weight, not functional, but they should go.

---

## Appendix B — Bootstrap checklist for Cici ✅

Standing PMJ up cold in a project:

1. Confirm the bridge MCP is rooted at the project root (read a known file to
   verify — a mismatched root can fail in confusing ways).
2. Create `TICKETS_DIR`, `ATTACH_DIR`, `ARCHIVE_DIR`.
3. **Dogfood subdir CRUD through the bridge**: write, read, and delete a file
   one level deep and two levels deep (e.g. `attach/PROJ-1/test.md`). Confirm
   `.md` auto-append and subdir auto-create behave. This is the one real unknown
   worth proving before trusting the system.
4. Write `project-index.md` at the project root (master map).
5. Write the **setup ticket itself** as `PROJ-<SEAM_START>.md` — the migration/
   bootstrap is its own first ticket, walked through the normal lifecycle.
6. If migrating: run Appendix A. If greenfield: you're done.

---

*PMJ is deliberately boring: files, folders, and one MCP. The boring is the
point — it's the part that doesn't bleed, doesn't lag, and doesn't bill.* 🌊