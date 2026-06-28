# nvNova — PMJ Index 🗂️

Plaintext ticket tracker per `docs/nvnova-pmj.md`. One bridge (`claude-bridge`),
no hosted tracker — the Atlassian MCP stays dark on purpose. Numbering authority:
Claude. Next key = `max(NVN-N anywhere under docs/pmj/, incl _archive/) + 1`.

Params: `KEY_PREFIX=NVN` · `TICKETS_DIR=docs/pmj/` · `ARCHIVE_DIR=docs/pmj/_archive/` ·
`ATTACH_DIR=docs/pmj/attach/` · `SEAM_START=1` (greenfield).

## Live tickets

| Key | Summary | Status | Pri |
|-----|---------|--------|-----|
| NVN-1 | Stand up PMJ tracker for nvNova | Implementing | 2 |
| NVN-3 | Excise Carbon file-I/O substrate (FSRef) → NSFileManager atomic | Backlog | 1 |
| NVN-4 | Fix `moveFileToTrash:` silent success on trash-resolution failure | Backlog | 2 |
| NVN-5 | Excise Carbon stragglers (FSFindFolder, UTCDateTime, LSCopy…, residual IconRef) | Backlog | 3 |
| NVN-6 | Native arm64 — re-vendor deps (multimarkdown; crypto per NVN-11), flip ARCHS | Backlog | 1 |
| NVN-7 | P0 — make accidental note deletion harder | Parked | 2 |
| NVN-10 | Excise Carbon directory watching (FNNotify) → FSEvents + GCD | Backlog | 1 |
| NVN-11 | Crypto layer arm64 viability — relink OpenSSL vs. CommonCrypto | Backlog | 1 |
| NVN-9 | Regenerate @2x Retina asset variants | Backlog | 4 |

## Done ✅

| Key | Summary | Resolution | Ref |
|-----|---------|-----------|-----|
| NVN-8 | Confirm + commit HiDPI fix; resolve UI scale | Fixed | `23738eb` |
| NVN-2 | Excise Carbon directory-persistence (Alias Manager + IconRef) → plain path/URL | Fixed | `5d1e2ea` |

## Sequencing

**The gate (R):** no UI or feature work until the base layer is proven
replaceable. The base-layer spine is **P1**, all on the known-good x86_64 build:

- **NVN-2** (directory persistence → plain path/URL), **NVN-3** (file-I/O
	substrate → NSFileManager atomic), and **NVN-10** (directory watching →
	FSEvents) run in parallel — one variable at a time within each.
- **NVN-11** (crypto: relink OpenSSL vs. re-home to CommonCrypto) runs parallel
	as recon-first; its answer **sizes the crypto half of NVN-6**.

Then **NVN-6** (the arm64 flip — the Rosetta exit) once the spine validates on
x86_64. **NVN-5** stragglers clean up around the spine (`FNNotify` moved to
NVN-10). Only then features: **NVN-7** (leans on **NVN-4** for real
recoverability) and **NVN-9** (after UI scale settles). **NVN-8** done.
