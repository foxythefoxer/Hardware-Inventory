# Maintainer dispositions

Response to the three reviews in this folder. Every finding is accepted, rejected, or
deferred, with a reason. IDs are prefixed by reviewer, since numbering does not
correspond across documents: `C-` Claude Opus 5, `G-` Grok 4.5, `O-` GPT-5.5.

Claims marked **verified** were checked against the actual file rather than taken on
trust.

---

## Rejected — do not re-open without new evidence

### `set -o pipefail` — G-003, O top-action-3

**Rejected. This would break the script.** 23 pipelines end in `head -N`; 22 of them
terminate there (one, the dmidecode wrapper, pipes `head`'s output on into `sed`, but
still surfaces the same exit code under `pipefail` — the rightmost non-zero status in
the pipeline, not merely the last command's, is what `pipefail` reports). `head` exits
after N lines, upstream receives SIGPIPE, and under `pipefail` that surfaces as exit
141. Measured:

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

Rows marked **Done — `hash`** are implemented and covered by `tests/run.sh`; the hash is
the commit that did it. The rest are accepted but not yet written.

| ID | Finding | Status |
|---|---|---|
| C-025 / C-026 | Errors suppressed at 82 sites, always exits `0`, no debug switch. A systemically broken host and a bare host produce identical output. | **Done — `4c1602d`.** Promoted to top priority; both reviewers who raised it rated it MEDIUM. This output is consumed as machine-readable ground truth, so a silently empty section does not produce no answer — it produces a confident wrong one. Implemented narrowly: a warning means the tool was present, permitted, and still returned nothing. Absent tools stay silent. Exits 1 with a `## Collection warnings` block; the report is still written in full first. Changed the caller contract — T3 previously asserted exit 0 with every tool broken and now asserts 1, still distinguishing 124 (hung). |
| C-003 | 26 call sites hardcode `timeout N`, bypassing the `$TMO` fallback built for systems without coreutils `timeout`. | **Done — `fa84efe`.** Verified: 26 hardcoded vs 23 `$TMO`. Maintainer's own bug. Severity reduced HIGH→MEDIUM — `timeout` is present on all supported platforms — but the inconsistency defeated a deliberate guard. `TMO` became an array and a `tmo N cmd...` function covers the sites needing a non-default duration; both run the command unwrapped when `timeout` is absent. |
| C-012 | "Physical devices" table lacks the `TYPE=="disk"` filter applied elsewhere, so `md*`/`dm-*` appear. | **Done — `d12fafa`, then `de745a8`.** Extended, and the extension was the load-bearing half: the reviewer missed that ZFS zvols report `TYPE=disk`, so the `TYPE` filter alone (`d12fafa`) did not exclude them and every VM disk on a `local-zfs` host would still have become a phantom `/dev/zdN` row drawing its own wasted `smartctl` probe. `de745a8` added a `zd[0-9]` name exclusion to both the `DISKS` variable and the device table. Still not verified against real zvols. |
| C-014 | 22 fixed `head -N` truncations (actually 23 — see below), 13 magic numbers, no marker when a limit is hit. | **Done — `03f4cf7`.** This bug class had recurred three times. 17 named constants, grouped by what they cap (not one per call site — several sites share a purpose, e.g. df+findmnt), consumed through a `cap()` helper that appends a marker only when a limit is actually hit and adds nothing on untruncated or empty input. `cap()` never calls `warn()`: truncation is real data arriving incomplete, not a collector failure. One site (`CNAMES`, word-split into `docker inspect` arguments) cannot use `cap()`'s inline marker without corrupting the argument list, and defers its marker to after the block instead. Covered by T10/T11, both verified against reintroduced versions of the bugs they guard against. |
| C-020 | `racadm` block not root-gated and has no `###` heading; output lands under the previous section. | **Done — `af2a682`.** Verified. Maintainer's bug. Gated on `is_root` and given its own `###` heading. |
| C-023 | N+1: up to 100 serial `docker inspect` calls. | **Done — `13f37b6`.** One call over all containers, using `{{.Name}}` to map results back since docker applies the template once per object in argument order. No test coverage for this path; verified by hand against a stub docker. |
| C-009 | `/proc/cmdline` emitted verbatim; may carry `rd.luks.key` or iSCSI credentials. | **Done — `5a343b7`, completed in `6378cb6`.** Genuine gap in an otherwise deliberate redaction policy. `5a343b7` redacted by parameter **name** (`password`, `secret`, `token`, `key`; `rd.luks.key` falls out of the generic `key` match) — which covered only half of what this very finding names. The iSCSI credentials it also lists live *inside* a value, under the innocuous name `netroot`, so no name match could ever see them; `6378cb6` added a value pass replacing everything between `iscsi:` and `@`, CHAP usernames included, keeping host, port, LUN and target. Covered by T9, verified to fail without the fix. Names are kept throughout. Still a filter, not a proof. |
| C-004 | Markdown table cells unescaped; a literal `\|` corrupts the table. | **Accepted, downgraded to LOW.** Most pipe-bearing output already sits inside code fences. Narrow exposure, cheap fix. |
| C-011 | A DIMM with no Part Number line is dropped from the table but still counted in the slot total. | **Done — `187e16e`.** Rows are emitted at the record boundary rather than on the `Part Number:` line, so every populated slot appears. Verified against a synthetic `dmidecode -t memory` fixture. |
| C-001 | No `LC_ALL=C`. | **Done — `8f1d960`.** Verified harmless to the em-dash sentinel and awk `%.2f`. |
| C-005 | Sourcing `/etc/os-release` executes it as root. | **Accepted.** Was already known; good that it resurfaced independently. |
| C-016 | MegaRAID probe targets the first non-NVMe disk, which on Unraid is often the USB boot device. | **Accepted, LOW.** |
| G-002 | Pipeline bodies run in subshells; variable mutations would be lost. | **Done — `4c1602d`, documented in `75d4261`.** No longer theoretical: the warning accumulator is global state, so a `warn` inside a pipeline body would be silently lost. The storage and network row loops now capture their pipeline and test it outside; the rule is recorded in CLAUDE.md and at the `warn()` definition. |
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

- **"Zero errors and zero warnings on the default ruleset"** (Claude) — **correct** when
  checked. 24 findings, all severity `note`. The 22 `SC2016` hits are false positives
  from single-quoted awk programs where `$2`/`$10` are awk fields, not shell variables.
  **Not re-verified since the C-025/C-026 work** — ShellCheck was not installed in that
  environment, and `tests/run.sh` skips T7 when it is missing. Re-run before trusting it.
- **"107 masked return values" under `-o all`** (Claude) — **exactly correct.**
- **26 hardcoded `timeout` sites** — **correct.** All routed through the gate in
  `fa84efe`; the count is now 0.
- **`racadm` not root-gated** — **correct.** Fixed in `af2a682`.
- **ZFS zvol behaviour** — **still unverified.** No zvols available in the test
  environment. The fix shipped in `de745a8` on reasoning alone (zvols report
  `TYPE=disk`, so the name exclusion is what does the work). Confirm on a Proxmox host
  with `local-zfs` before and after.
- **"22 `head -N` truncation points"** (all three reviews) — **off by one.** The actual
  count is **23**, and has been since the first commit. Fixed in `03f4cf7`.
- **C-009's own wording was the better spec.** It named "`rd.luks.key` **or iSCSI
  credentials**", and the first fix (`5a343b7`) only handled the first. Re-reading the
  finding text after implementing would have caught it two commits earlier — worth doing
  for anything still open here.
