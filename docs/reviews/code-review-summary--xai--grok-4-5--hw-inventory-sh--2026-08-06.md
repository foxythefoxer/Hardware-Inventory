# Code Review Summary: hw-inventory.sh

> **Frozen — historical document, not maintained.** Written 2026-08-06 against
> `hw-inventory.sh` at commit `bc32386` (651 lines). The file is now 990 lines, so
> **every line number and code excerpt below is stale** and will not match `HEAD`.
> Nothing here is edited to keep pace; it is kept as provenance for the finding IDs
> the ledger cites. **[`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) is authoritative** —
> a finding below may have been accepted, narrowed, rejected, or superseded there.

**Target:** `hw-inventory.sh` (v4)  
**Reviewer:** xAI / Grok-4.5  
**Date:** 2026-08-06  
**LOC:** 651  
**Language / Runtime:** Bash (#!/usr/bin/env bash); requires bash features (arrays not used heavily, but brace expansion, `[[` not used, local, etc.)  
**Intended environment:** Linux homelab (Unraid, Proxmox, bare-metal NAS/hypervisor); run as root preferred for dmidecode/smartctl/IPMI; stdout redirected to Markdown file.

## VERDICT

**Approve with comments**

This is a high-quality, deliberately constrained read-only inventory script. The author has clearly thought through the failure modes of storage backends, the ethics of waking spun-down disks, and the danger of writing to `/proc/mdcmd`. The structure is linear and readable, timeouts are applied consistently, and the output is well-formed Markdown + YAML frontmatter. Remaining issues are mostly portability, a few silent-failure paths under unusual hardware, and maintainability of the long sequential body. None are ship-blocking for the intended use case.

## ENGINEERING SCORECARD

| Dimension                        | Score | Rationale (lines) |
|----------------------------------|-------|-------------------|
| Architecture                     | 4     | Clear linear gather-then-print; good helpers (`have`, `dmi`, `kv`, `yk`); no unnecessary abstraction for a one-shot reporter (L20–46, 48–93). |
| Readability & Maintainability    | 4     | Excellent section comments and defensive notes; long sequential body is the main cost (entire file). |
| Safety                           | 5     | Strictly query-only; explicit avoidance of self-tests, scrubs, mounts, package ops, `mdcmd` writes (L4–9, 246–249, 377–379). |
| Error Handling                   | 4     | Timeouts + `\|\| true` + empty-string fallbacks everywhere; `set -u` only (correct choice) (L20, 28, 43, 346). |
| Security                         | 4     | No injection surfaces of consequence; root recommended but never escalates itself; serials/BMC data intentionally emitted (L11–13). |
| Performance                      | 4     | Timeouts prevent hangs; SMART/RAID loops bounded; some repeated `dmidecode`/`lscpu` (L202–206, 158). |
| Portability                      | 3     | Linux + bash-centric (Unraid/Proxmox paths, brace expansion, `timeout`, `lsblk -P`); degrades gracefully elsewhere. |
| Idiomatic Style                  | 4     | Good `have()`, `printf`, local vars, deliberate `-P` parsing (L22, 30, 231–241); minor SC issues. |

**Overall: 4.0 / 5** — Production-ready for its intended Linux homelab niche; a few MEDIUM clean-ups would make it more robust for wider use.

## TOP FINDINGS

| ID    | Risk   | Line(s)     | One-line description |
|-------|--------|-------------|----------------------|
| F-001 | MEDIUM | 345–364     | Brace expansion `{0..31}` is a bashism; fails under pure POSIX or older shells. |
| F-002 | MEDIUM | 234–241, 440–447 | `while` / `for` pipelines put body in subshell; variable mutations (if any) are lost (currently harmless but fragile). |
| F-003 | MEDIUM | 20          | Only `set -u`; missing `pipefail` means pipeline failures can be silent. |
| F-004 | LOW    | 202–206, 158| Repeated full `dmidecode -t memory` / `lscpu` invocations; wasteful and race-prone under concurrent runs. |
| F-005 | LOW    | 231–241     | `fld()` sed regex is brittle on MODEL/SERIAL containing quotes or unusual characters. |
| F-006 | LOW    | 56–57       | Double-sourcing `/etc/os-release` (once for each variable). |
| F-007 | NITPICK| 23          | `NA="—"` (em-dash) may render poorly in some terminals / plain-text consumers. |

## TOP 3 ACTIONS

1. Replace brace expansion and any remaining bashisms with POSIX-compatible constructs (or document “bash ≥ 4 required”).
2. Capture pipeline output into a variable or use process substitution / lastpipe so future mutations stay in the parent shell; add `set -o pipefail`.
3. Cache expensive queries (`dmidecode`, `lscpu`) once at the top.

## WHAT THIS CODE DOES WELL

- **Explicit read-only contract** (L4–9, 246–249, 377–379): documents every dangerous verb that is deliberately omitted and why. This is the single most important design decision for a hardware-inventory tool.
- **Timeout wrapper applied uniformly** (L27–28, used throughout): prevents the classic “script hangs forever on a stuck NFS/SMB/iSCSI mount” failure mode.
- **SMART standby handling** (L253–257): `-n standby` + explicit “not woken” reporting is the correct behaviour on a NAS with spun-down array disks.
- **YAML-safe escaping in `yk()`** (L33–38) and deliberate use of `lsblk -P` (L229–230) to avoid column-shift bugs show careful attention to output correctness.
