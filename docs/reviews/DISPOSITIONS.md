# Maintainer dispositions

Response to the three reviews in this folder. Every finding is accepted, rejected, or
deferred, with a reason. IDs are prefixed by reviewer, since numbering does not
correspond across documents: `C-` Claude Opus 5, `G-` Grok 4.5, `O-` GPT-5.5.

Claims marked **verified** were checked against the actual file rather than taken on
trust.

---

## Rejected — do not re-open without new evidence

### `set -o pipefail` — G-003, O top-action-3

**Rejected. This would break the script.** 24 pipelines terminate in `head -N`. `head`
exits after N lines, upstream receives SIGPIPE, and under `pipefail` that surfaces as
exit 141. Measured:

```
with pipefail:    exit=141
without pipefail: exit=0
```

Two of three reviewers recommended this. It is also directly incompatible with the
planned exit-code contract (C-026, accepted below) — you cannot have both a meaningful
exit code and a `pipefail` that reports failure on every successful pipeline.

Claude's review was the only one to reach the opposite conclusion, and it correctly
identified the SIGPIPE mechanism.

### `set -e` / `set -eE` — O top-action-3

**Rejected.** This is a best-effort collector. Most commands are *expected* to fail:
`dmidecode` without root, `zpool` on a non-ZFS box, `pct` off a Proxmox host. `set -e`
aborts on the first absent tool. `set -u` alone is deliberate.

### Remove brace expansion `{0..31}` — G-001

**Rejected.** Line 1 declares `#!/usr/bin/env bash`; numeric brace ranges have worked
since bash 3.0 (2004). Grok's own refactor hedges "if bash is guaranteed" — it is, by the
shebang. POSIX `sh` support is not a goal. Swapping to `seq` would add a coreutils
dependency to remove a bash dependency from a bash script.

### Whitespace-delimited iteration, rated MEDIUM — O-001

**Rejected at that severity.** Device names from `lsblk` and VMIDs from `pct list` are
whitespace-free by construction. GPT's own text concedes this is "acceptable in
practice" and then rates it MEDIUM anyway. Harmless to change; not a correctness fix.

### Em-dash sentinel `NA="—"` — G-007

**Rejected.** Verified to render correctly, including under `LC_ALL=C`.

### Locale finding rated HIGH — C-001 severity only

**Fix accepted, severity rejected.** The mechanism is real — `lscpu` and `free` are
gettext-translated. But every supported platform defaults to `en_US`/`C`, so realistic
probability is near zero. The reviewer had no deployment context. One-line fix, so it's
in the accepted queue at Tier 2, not as a HIGH.

---

## Accepted

| ID | Finding | Status |
|---|---|---|
| C-025 / C-026 | Errors suppressed at 82 sites, always exits `0`, no debug switch. A systemically broken host and a bare host produce identical output. | **Accepted, promoted to top priority.** Both reviewers who raised it rated it MEDIUM. This output is consumed as machine-readable ground truth, so a silently empty section does not produce no answer — it produces a confident wrong one. |
| C-003 | 26 call sites hardcode `timeout N`, bypassing the `$TMO` fallback built for systems without coreutils `timeout`. | **Accepted.** Verified: 26 hardcoded vs 23 `$TMO`. Maintainer's own bug. Severity reduced HIGH→MEDIUM — `timeout` is present on all supported platforms — but the inconsistency defeats a deliberate guard. |
| C-012 | "Physical devices" table lacks the `TYPE=="disk"` filter applied elsewhere, so `md*`/`dm-*` appear. | **Accepted, and extended.** The reviewer missed the worse case: ZFS zvols report `TYPE=disk`, so on a Proxmox host with `local-zfs` every VM disk becomes a phantom `/dev/zdN` row *and* draws its own wasted `smartctl` probe. Not yet verified against real zvols. |
| C-014 | 22 fixed `head -N` truncations, 13 magic numbers, no marker when a limit is hit. | **Accepted.** This bug class has now recurred three times. Fix the pattern, not the instance. |
| C-020 | `racadm` block not root-gated and has no `###` heading; output lands under the previous section. | **Accepted.** Verified. Maintainer's bug. |
| C-023 | N+1: up to 100 serial `docker inspect` calls. | **Accepted.** One call over all containers. |
| C-009 | `/proc/cmdline` emitted verbatim; may carry `rd.luks.key` or iSCSI credentials. | **Accepted.** Genuine gap in an otherwise deliberate redaction policy. |
| C-004 | Markdown table cells unescaped; a literal `\|` corrupts the table. | **Accepted, downgraded to LOW.** Most pipe-bearing output already sits inside code fences. Narrow exposure, cheap fix. |
| C-011 | A DIMM with no Part Number line is dropped from the table but still counted in the slot total. | **Accepted.** |
| C-001 | No `LC_ALL=C`. | **Accepted at Tier 2.** Verified harmless to the em-dash sentinel and awk `%.2f`. |
| C-005 | Sourcing `/etc/os-release` executes it as root. | **Accepted.** Was already known; good that it resurfaced independently. |
| C-016 | MegaRAID probe targets the first non-NVMe disk, which on Unraid is often the USB boot device. | **Accepted, LOW.** |
| G-002 | Pipeline bodies run in subshells; variable mutations would be lost. | **Accepted as documentation.** Currently harmless — nothing mutates state in those loops — but correctly flagged as fragile. |
| G, edge cases | Megaraid probe can skip drives at sparse IDs beyond the 10-miss threshold. | **Accepted as a documented tradeoff, not a bug.** Deliberate bound against a 32-iteration worst case. |

---

## Deferred

| ID | Finding | Reason |
|---|---|---|
| C-031 | One ~630-line top-level `main`; extract `section_*()` functions. | Real, but it restructures a working one-shot reporter. Not worth the churn until `--skip` is actually wanted. |
| C-029 | No argument parsing; `--help` prints a full report. | Pairs naturally with C-031. Same reasoning. |
| C-024 | `mapfile -t` instead of word-splitting `for` lists. | Cosmetic given the inputs. Bundle with C-031 if that happens. |

---

## Verified reviewer claims

Checked against ShellCheck 0.10.0 and the file itself:

- **"Zero errors and zero warnings on the default ruleset"** (Claude) — **correct.** 24
  findings, all severity `note`. The 22 `SC2016` hits are false positives from
  single-quoted awk programs where `$2`/`$10` are awk fields, not shell variables.
- **"107 masked return values" under `-o all`** (Claude) — **exactly correct.**
- **26 hardcoded `timeout` sites** — **correct.**
- **`racadm` not root-gated** — **correct.**
- **ZFS zvol behaviour** — **unverified.** No zvols available in the test environment.
  Confirm on a Proxmox host with `local-zfs` before and after the C-012 fix.
