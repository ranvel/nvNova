---
name: nvnova-pmj
description: Use this skill whenever working nvNova issue tracking — creating, reading, transitioning, or numbering PMJ tickets under docs/pmj/, or whenever the conversation references an NVN-key ticket, the Triangle roles (R / Claude / Cici), the recon→solutioning→implementing→DAT phases, or "the board." PMJ is nvNova's plaintext-markdown tracker living under git and served by the single claude-bridge MCP; this skill encodes its conventions so they aren't re-derived each session. Trigger on any nvNova work that touches a ticket or a status.
---

# nvNova PMJ — Poor Man's Jira

nvNova tracks issues as plaintext `.md` tickets under git, served by the **single
`claude-bridge` MCP** — no hosted tracker, and the Atlassian MCP stays dark (a
second tracker MCP is exactly the context bleed PMJ exists to kill). Full spec:
`docs/nvnova-pmj.md`. This skill is the operating summary; read the spec for the
why.

## Parameters

- `KEY_PREFIX` = **NVN** — keys look like `NVN-1`, `NVN-2`, …
- `TICKETS_DIR` = `docs/pmj/` · `ARCHIVE_DIR` = `docs/pmj/_archive/` · `ATTACH_DIR` = `docs/pmj/attach/`
- Bridge = `claude-bridge`, rooted at project root. Greenfield (`SEAM_START = 1`).
- Master map: `docs/pmj/project-index.md`.

## The Triangle — fixed lanes

- **R** — direction + the quality gate. Brings the problem, does DAT (QA), owns
	the `DAT → Done` transition, supplies session UUIDs.
- **Claude** (PM / architecture) — writes problem-statement tickets carrying the
	**recon prompt** for Cici; is the **numbering authority**; runs suspicion-driven
	verification. Does **no recon at problem statement**.
- **Cici** (Claude Code) — does recon, gathers exact paths, implements the locked
	fix. Works the filesystem natively.

## Numbering — Claude only

```
next key = max( NVN-N found anywhere under docs/pmj/, including _archive/ ) + 1
```

Always scan for the real max before minting. Never trust a number written into an
older ticket's prose — tickets get created after that prose was written.

## Lifecycle + the Muwavian Commandment

> **The phase-completer advances the `status` field.** Whoever closes a phase
> flips the status. No handoff dance, no stale-status window.

1. **Problem statement** — Claude writes a thin ticket + the recon prompt.
	**No recon here.** → `Recon`
2. **Recon** — Cici gathers details + exact paths into `attach/<key>/recon.md`.
	→ `Solutioning`
3. **Solutioning** — R + Claude lock `## Solution`. → `Implementing`
4. **Implementation** — Cici builds it, records `## Implementation`. → `DAT`
5. **DAT** — R does QA against `## DAT`. → `Done`
6. **PAR** (optional Post-Action Review) — MUST be fresh context; the eyes that
	authored the code cannot review it.

Transition owners: R + Claude close Solutioning→Implementing; **Cici** closes
Implementation→DAT; **R** closes DAT→Done.

## Status vocabulary

**Live:** `Backlog` · `Recon` · `Solutioning` · `Implementing` · `DAT` ·
`Deferred` (shelved, *with a reason*) · `Parked` (blocked, expected to resume) ·
`Done`.

**Archive-only** (carried verbatim from a prior tracker, never assigned to live
work): `Canceled` (one `l`) · `Duplicate`.

## No-bleed — the constraint easiest to violate

At problem statement, Claude writes the prompt that sends Cici into the code —
Claude does **not** go into the code itself. Recon happens **once**, by Cici,
written where Claude can read it cheaply. Verification is a *separate* lane:
suspicion-driven, at or after Recon, fully allowed. Reconning to write the prompt
= bad (breaks no-bleed). Reconning because a recon result smells wrong = good.

## Ticket format

YAML frontmatter (**spaces** — YAML forbids tabs) between `---` fences, then a
markdown body (**tabs**, per nvNova's source convention). Frontmatter: `key`
(= filename stem), `summary` (no status marker in the title), `status`,
`resolution`, `priority` (`1`=Urgent … `4`=Low), `fixVersion`, `created` /
`updated` (ISO `YYYY-MM-DD`), `session` (R's `claude --resume <uuid>` handle),
`tags` (flow list). Body sections — conventions, filled as the ticket walks:
`## Background`, `## Recon (Cici)`, `## Solution (locked)`, `## Implementation`,
`## DAT (R)`, `## Discussion`.

**Filename and key agree** (`NVN-7.md` carries `key: NVN-7`). **Recon is a
separate file** in `attach/<key>/recon.md`, never appended into the ticket body —
that's what kills merge clobber when Claude and Cici touch a ticket near the same
time.

## Retired — don't let these creep back in

A second tracker MCP · tracker-API workarounds (no-inline-backticks rules,
escape-the-dots, whole-description-replace caution) · a pinned session block in
the body (it's the `session:` field now) · status-in-the-title emoji.
