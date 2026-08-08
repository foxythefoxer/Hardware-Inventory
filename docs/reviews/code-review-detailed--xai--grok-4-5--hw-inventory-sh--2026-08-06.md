# Code Review Detailed: hw-inventory.sh

**Target:** `hw-inventory.sh` (v4)  
**Reviewer:** xAI / Grok-4.5  
**Date:** 2026-08-06  
**LOC:** 651  
**Language / Runtime:** Bash via `#!/usr/bin/env bash`  
**Self-identification confirmed:** VENDOR: xAI / MODEL: Grok-4.5

Line numbers below refer to the submitted file as numbered from 1 (`#!/usr/bin/env bash`).

---

## 1. Overview & Context

**What the code does:** Emits a self-contained Markdown document (with YAML frontmatter) describing the local host’s hardware, firmware, storage topology, SMART health, network, PCI devices, BMC/IPMI, Unraid array state, Proxmox VMs/containers, Docker containers, and failed systemd units. It is intentionally read-only: every external command is a pure query.

**Entry points / invocation model:** Manual or cron-style:  
`sudo bash hw-inventory.sh > "$(hostname)-$(date +%F).md"`  
(Recommended to invoke via `bash` so fish/zsh do not interfere.)

**External dependencies (soft):**  
`timeout`, `dmidecode`, `smartctl`, `lsblk`, `lscpu`, `free`, `ip`, `lspci`, `ipmitool`, `perccli`/`storcli`/`megacli`, `pveversion`/`pct`/`qm`/`pvesm`, `docker`, `zpool`, `btrfs`, `systemctl`, Unraid emhttp files, etc. All are probed with `have()`; absence is graceful.

**Required privileges:** Root preferred for dmidecode, smartctl, IPMI, full RAID topology. Non-root still produces a useful (incomplete) report and explicitly marks missing fields.

**Runtime environment assumed:** Modern Linux (kernel sysfs, `/proc`, `/sys`), typically a homelab NAS/hypervisor (Unraid or Proxmox). Not targeted at macOS, BSD, or containers without host device access.

**Assumptions I had to make:**
- The script is never expected to run under a strict POSIX `sh`.
- Output consumers can handle UTF-8 (em-dash, Markdown tables).
- `timeout` from coreutils is present or the script degrades to unbounded waits (rare).
- No concurrent writers to the same stdout redirection.

---

## 2. Architecture Review

**Overall structure:** Classic “gather then emit” linear script. Helpers are defined first (`have`, `kv`, `yk`, `dmi`, `is_root`), then a small set of global variables are populated, then a long sequence of `printf` sections that each query and print. There is no main function or argument parsing.

**Control flow:** Straight-line with early exits only inside helpers. Conditional sections (RAID, Unraid, Proxmox, Docker, BMC) are gated by presence of tools or files.

**Separation of concerns:** Good enough for a one-shot reporter. The helpers cleanly isolate “does this binary exist?”, “emit a table row”, “safe dmidecode string”, and “YAML scalar”. Domain sections are visually delimited by comment banners.

**Data flow:** Almost all state is global (HOST, OSNAME, DISKS, etc.). This is appropriate; there is no concurrent execution or deep call stack. A few values are recomputed later (lscpu output captured again inside the CPU section).

**Configuration strategy:** None. Hard-coded behaviour, hard-coded timeouts (10 s general, 15/25/6/30 s for specific tools). Correct for an inventory snapshot tool.

**Idempotency / re-runnability:** Fully idempotent and side-effect-free (modulo the intentional omission of any write). Safe to run twice or under concurrent copies (they only contend on CPU/IO of the same query tools).

**Failure model:** Soft-fail everywhere. Commands are wrapped in `$TMO … 2>/dev/null || true` or equivalent; missing data becomes the em-dash sentinel. This is the right model for an inventory collector that must never abort mid-report.

**Extension points:** Adding a new section is trivial (copy the banner + table pattern). Adding a new storage backend would require another conditional block. The lack of a plugin mechanism is fine for the current scope.

**ASCII flow (simplified):**

```
start
  → define helpers (have, kv, yk, dmi, is_root)
  → gather globals (hostname, OS, CPU, RAM, platform, dmi fields, DISKS)
  → emit YAML frontmatter
  → emit Identity table
  → emit Snapshot (volatile)
  → emit CPU
  → emit Boot/kernel
  → emit Memory (+ DIMM table if root)
  → emit Storage devices (lsblk -P)
  → emit SMART (if smartctl + root)
  → emit RAID controller + topology + megaraid SMART (if detected)
  → emit Unraid array / slots / shares (if emhttp files)
  → emit filesystems/pools (df, findmnt, zpool, btrfs, pvesm)
  → emit Network
  → emit Notable PCI
  → emit BMC/IPMI (if present)
  → emit Proxmox (LXC + QEMU + cluster)
  → emit Docker
  → emit failed systemd units
  → footer
end
```

**Assessment:** The architecture is the right call for a single-purpose, read-only reporter. Introducing functions-per-section or a configuration file would add complexity without benefit. The linear body is long but navigable thanks to the banner comments.

---

## 3. Section-by-Section Walkthrough

### Lines 1–19 — Header & contract
**What it does:** Shebang, version comment, explicit read-only manifesto, usage note.  
**Assessment:** Excellent. The contract is the most important documentation in the file.  
**Issue:** None.  
**Recommendation:** Keep.

### Lines 20–46 — Setup & helpers
**What it does:** `set -u`, `have()`, `NA`, `TMO`, `kv()`, `yk()`, `dmi()`, `is_root()`.  
**Assessment:** Good. `set -u` alone is correct (see §5). `yk` correctly escapes for YAML. `dmi` is quiet and fails empty.  
**Issue:** None material.  
**Finding:** (see F-003 later).  
**Recommendation:** Consider `set -o pipefail` (F-003).

### Lines 48–93 — Gather phase
**What it does:** Populate HOST, OSNAME/OSID (with Unraid special case), KERN, ARCH, CPUMODEL, RAMTOTAL, PLATFORM, DMI fields, DISKS list.  
**Assessment:** Solid. Fallbacks are sensible. DISKS filter excludes loop/ram/zram/sr.  
**Issue:** Double-sourcing of os-release (L56–57).  
**Finding:** F-006 [LOW]  
**Recommendation:** Source once into a subshell or use a single `.` and capture both variables.

### Lines 94–109 — Frontmatter
**What it does:** YAML block with host/os/kernel/… + role placeholder + collected date.  
**Assessment:** Good. `yk` keeps it valid YAML even with quotes/backslashes.  
**Issue:** None.

### Lines 111–138 — Identity
**What it does:** Markdown table of basic identity + Proxmox version + DMI if root.  
**Assessment:** Correct; non-root path is clear.  
**Issue:** None.

### Lines 140–153 — Snapshot (volatile)
**What it does:** Uptime, load, RAM/swap usage. Explicit comment that this section should be ignored when diffing reports.  
**Assessment:** Excellent design decision (L141–142).  
**Issue:** None.

### Lines 155–173 — CPU
**What it does:** Model, topology via lscpu or /proc/cpuinfo, virtualisation flags.  
**Assessment:** Good. Re-captures lscpu (already done earlier).  
**Issue:** Repeated work (F-004).  
**Recommendation:** Cache `LC` once in the gather phase.

### Lines 175–195 — Boot / kernel
**What it does:** IOMMU groups, nested virt, transparent hugepages, raw cmdline.  
**Assessment:** Useful and correct.  
**Issue:** None.

### Lines 197–223 — Memory
**What it does:** Totals + (root) DIMM slot count, max capacity, detailed installed DIMMs via awk on dmidecode.  
**Assessment:** The awk parser is careful. Repeated `dmidecode -t memory` (F-004).  
**Issue:** Three separate dmidecode invocations for the same data.  
**Finding:** F-004 [LOW]

### Lines 225–244 — Storage physical devices
**What it does:** lsblk -P table with custom `fld()` parser.  
**Assessment:** The comment on L229–230 is exactly right; using `-P` avoids the classic empty-field column shift.  
**Issue:** `fld` sed is somewhat brittle (F-005); pipeline puts the `while` in a subshell (F-002). Currently no variables are mutated outside, so harmless.  
**Finding:** F-002, F-005

### Lines 246–298 — SMART health
**What it does:** Per-disk smartctl -n standby -H -A; extracts health, power-on hours, realloc/pending, wear, temp.  
**Assessment:** Outstanding. The standby policy and the explicit “(standby — not woken)” message are the correct engineering choice for a NAS.  
**Issue:** None material.

### Lines 300–374 — RAID controller
**What it does:** Detect via lspci, invoke perccli/storcli/megacli with show-only verbs, then walk megaraid,N devices for SMART.  
**Assessment:** Excellent read-only discipline. The miss-counter (give up after 10 consecutive empty IDs) is pragmatic.  
**Issue:** `{0..31}` brace expansion (F-001).  
**Finding:** F-001 [MEDIUM]

### Lines 376–456 — Unraid array
**What it does:** Parse var.ini / disks.ini / share .cfg files with carefully whitelisted keys; never touch csrf_token or mdcmd.  
**Assessment:** Perfect. The comment on L377–379 is the model of defensive documentation.  
**Issue:** The `for f in /boot/config/shares/*.cfg` can expand to a literal glob if no files match (classic bash empty-glob behaviour). Mitigated by `[ -r "$f" ] || continue`.  
**Recommendation:** Prefer `shopt -s nullglob` or an explicit test.

### Lines 458–488 — Filesystems & pools
**What it does:** df -hT, findmnt, zpool list/status -x, btrfs show, pvesm status.  
**Assessment:** Good coverage; all under timeout.  
**Issue:** None.

### Lines 490–516 — Network
**What it does:** ip link + addr + speed + default route + resolvers.  
**Assessment:** Clean.  
**Issue:** None.

### Lines 518–528 — Notable PCI
**What it does:** Filtered lspci -nnk for display/network/RAID/NVMe/SATA.  
**Assessment:** Useful diagnostic filter.  
**Issue:** None.

### Lines 530–560 — BMC / IPMI
**What it does:** mc info, lan print (filtered), sdr elist, sel list; racadm if present.  
**Assessment:** Correctly refuses to modprobe; filters community/password strings.  
**Issue:** None.

### Lines 562–640 — Proxmox
**What it does:** pveversion, pct list + config/status for each CT, qm list + config for each VM, pvecm status.  
**Assessment:** Thorough; extracts the useful subset of config keys.  
**Issue:** Nested timeouts inside loops are fine; many short-lived processes.  
**Recommendation:** None critical.

### Lines 642–660 — Docker
**What it does:** version, ps -a table, per-container network/IP via inspect.  
**Assessment:** Good.  
**Issue:** None.

### Lines 662–672 — Failed systemd units
**What it does:** systemctl --failed.  
**Assessment:** Simple and useful.  
**Issue:** None.

### Lines 674–675 — Footer
**What it does:** End marker.  
**Assessment:** Fine.

---

## 4. Readability & Maintainability

Naming is clear and consistent (`have`, `kv`, `yk`, `dmi`, `NA`, `TMO`, section banners). Function length is short. Nesting is shallow. Magic numbers exist (timeout values 6/10/15/25/30, megaraid 0–31, head -N limits) but are reasonable and locally documented by context.

Comments are high-quality: they explain *why* a choice was made (standby, -P, no mdcmd, no csrf_token). There is almost no dead code. The long sequential body is the only real maintainability cost; a future maintainer will still be able to navigate via the banner comments.

Cyclomatic complexity is low per block; the highest is the megaraid loop + the Unraid awk. Neither needs splitting.

Discoverability of knobs is poor (all hard-coded), but that matches the tool’s design.

---

## 5. Shell Scripting Best Practices

| Practice | Status | Lines | Notes |
|----------|--------|-------|-------|
| Shebang `env bash` | Good | 1 | Matches features used. |
| `set -euo pipefail` | Partial | 20 | Only `-u`. `-e` would be harmful (many commands are expected to fail). `pipefail` is missing → F-003. |
| Quoting | Mostly good | throughout | Variables are quoted in almost all expansions. |
| `[[` vs `[` | Acceptable | many | Uses `[` consistently; sufficient. |
| Command substitution | Good | many | Prefers `$( )`. |
| Arrays vs strings | N/A | — | Space-delimited DISKS is fine because names are simple. |
| `local` | Good | 34, 385, 443 | Used in functions. |
| `printf` vs `echo` | Excellent | 30, 37, etc. | Correct choice for tables. |
| Safe iteration | Acceptable | 234, 440 | `read -r` used; empty-glob mitigated. |
| Temp files | N/A | — | None created. |
| Exit codes | Soft | — | Always exits 0; appropriate for a reporter. |
| Argument parsing | None | — | Correct; no args expected. |

Brace expansion `{0..31}` (L345) is a pure bashism → F-001.

---

## 6. Error-Handling Audit

| Line(s) | Operation | Can fail? | Detected? | Handled? | Consequence |
|---------|-----------|-----------|-----------|----------|-------------|
| 43 | dmidecode | Y | Y (empty) | Y | Empty string → NA later |
| 51 | hostname | Y | Y | Y | “unknown” |
| 56–57 | source os-release | Y | Y | Y | Falls through |
| 70, 158 | lscpu | Y | Y | Y | Falls back to /proc |
| 91–92 | lsblk | Y | Y | Y | DISKS empty |
| 232–241 | lsblk -P + while | Y | partial | Y | Empty table |
| 253+ | smartctl | Y | Y (STANDBY / empty) | Y | Explicit message or NA |
| 313–319 | perccli/storcli | Y | Y (timeout) | Y | Partial/empty topology |
| 346 | smartctl megaraid | Y | Y (miss counter) | Y | Stops after 10 misses |
| 385+ | awk on var.ini | Y | Y | Y | Empty fields |
| 440–447 | glob + read cfg | Y (no matches) | Y (`[ -r ]`) | Y | Empty shares section |
| many | `$TMO cmd` | Y (timeout) | Y (empty) | Y | NA / skip |

**Trap coverage:** None. Acceptable — the script creates no resources that need cleanup.

**Partial-failure state:** None left behind (no files written).

**Silent failure paths:**  
- Pipeline status without `pipefail` (F-003).  
- `fld` sed returning empty on pathological MODEL strings (F-005).  
- Brace expansion under non-bash (F-001) would cause a syntax error at parse time, which is loud.

Overall error handling is strong for the domain.

---

## 7. Static Analysis Findings (ShellCheck-Style)

| Code | Line | Severity | Message | Fix |
|------|------|----------|---------|-----|
| SC2034 | (none major) | — | — | — |
| SC2086 | various | info | Double-quote to prevent globbing | Already mostly quoted |
| SC2001 | 43, 231 | style | See if sed can be replaced | Acceptable |
| SC2162 | (none) | — | — | — |
| SC2207 | (none) | — | — | — |
| [no-rule-id] | 345 | medium | Brace expansion non-portable | Use `seq` or C-style for loop |
| SC1091 | 55–56 | info | Not following sourced file | Already disabled |
| SC2155 | (none) | — | — | — |

**Recommended local / CI commands:**
```bash
shellcheck -x -e SC1091 hw-inventory.sh
bash -n hw-inventory.sh
# optional: shellcheck -s bash -S warning
```

---

## 8. Edge Cases & Failure Modes

**CONFIRMED**
- Non-root: correctly marks incomplete fields (L115, 136, 251).
- Disk in standby: reported without waking (L253–257).
- No smartctl / no lsblk / no dmidecode: sections omitted or marked.
- Empty `/boot/config/shares/*.cfg`: handled by `[ -r ]`.
- Missing IPMI device node: explicit message, no modprobe (L548–551).
- Controller in HBA mode: falls back to normal SMART path (L370).

**SUSPECTED** (could not fully verify without hardware)
- MODEL/SERIAL containing double quotes or newlines → `fld` may truncate or misparse (F-005).
- Very large number of megaraid devices (>32 or sparse beyond miss limit) → some drives skipped.
- Extremely long `dmidecode` or `smartctl` output → `head` truncates, possible incomplete rows.
- Concurrent runs while a drive is mid-SMART → possible transient empty readings (harmless).

**Not applicable / deliberately out of scope:** network mounts that hang (mitigated by timeout), disk-full (no writes), filename with newline (device names from lsblk are clean).

---

## 9. Performance & Profiling Opportunities

Hot paths: the megaraid 0–31 loop (up to 32 short smartctl), the Proxmox CT/VM loops (one config + status each), and the three separate `dmidecode -t memory` calls.

- Repeated dmidecode / lscpu → **SPECULATIVE** saving of 50–200 ms on typical hardware.  
- Brace loop vs seq → negligible.  
- Many short-lived processes under timeout → acceptable for a rare inventory job.

**Measurement instructions:**
```bash
# wall-clock
time sudo bash hw-inventory.sh > /dev/null

# syscall / process count
strace -c -f -e trace=process,file sudo bash hw-inventory.sh > /dev/null

# per-section timing (add temporarily)
PS4='+ $EPOCHREALTIME ' bash -x hw-inventory.sh 2>trace.log
```

None of the findings require a change for performance reasons alone.

---

## 10. Security Review

- **Injection:** None. All external data is filtered through awk/sed/printf and never evaluated.
- **Secrets:** BMC community strings and passwords are explicitly grepped out (L538, 555). csrf_token never read (L378–379). Serial numbers and service tags are intentionally emitted (expected for inventory).
- **Privilege:** Script does not escalate; it merely recommends root. No `sudo` inside.
- **TOCTOU / symlink:** Minimal; reads of `/sys`, `/proc`, `/var/local/emhttp` are not security-sensitive in this context.
- **CWE:** None critical. Closest is CWE-200 (Information Exposure) for serials/BMC, but that is the purpose of the tool.

Overall security posture is appropriate.

---

## 11. Portability Review

| Platform | Status | Notes |
|----------|--------|-------|
| Linux (glibc) | Works | Primary target |
| Linux (musl/Alpine) | Degraded | May lack some tools; bash must be present |
| macOS | Broken | No lsblk, different dmidecode, no /sys, no smartctl -d megaraid, etc. |
| FreeBSD / other BSD | Broken | Different device model, no systemd, different smartctl |
| WSL | Degraded | Limited hardware visibility; some /sys paths missing |
| Pure POSIX sh | Broken | Brace expansion, some bashisms, `local` |

**Specific blockers:**
- `{0..31}` (L345) → replace with `for n in $(seq 0 31); do` or C-style `for ((n=0;n<=31;n++))`.
- `timeout` (coreutils) assumed.
- `lsblk -P`, `ip -o`, `/sys/class/net/*/speed` are Linux-specific.
- Unraid/Proxmox paths are hard-coded (intentional).

Document “Linux + bash ≥ 4” as the supported platform.

---

## 12. Suggested Refactors

### Refactor 1 — Eliminate brace expansion (F-001)
**Rationale:** Portability / correctness under non-bash.  
**Before (L345):**
```bash
for n in {0..31}; do
```
**After:**
```bash
for n in $(seq 0 31); do
# or, if bash is guaranteed:
# for ((n=0; n<=31; n++)); do
```
**Risk:** Low. `seq` is ubiquitous on the target platforms. Verify with a megaraid controller.

### Refactor 2 — Cache expensive queries (F-004)
**Rationale:** Correctness under concurrent change + minor performance.  
Capture `dmidecode -t memory` and `lscpu` once in the gather phase and reuse the strings.

### Refactor 3 — pipefail + safer pipelines (F-002/F-003)
Add after `set -u`:
```bash
set -o pipefail
```
And, for the lsblk loop, capture first:
```bash
LSBLK_OUT=$($TMO lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,MODEL,SERIAL 2>/dev/null) || true
printf '%s\n' "$LSBLK_OUT" | while IFS= read -r line; do
  ...
done
```
(or use process substitution / lastpipe if bash ≥ 4.2).

All three refactors are small, preserve behaviour, and themselves satisfy the review standards.

---

## 13. Prioritized Action List

| ID    | Risk   | Line(s)     | Issue | Recommended Fix | Effort |
|-------|--------|-------------|-------|-----------------|--------|
| F-001 | MEDIUM | 345–364     | Brace expansion non-portable | `seq 0 31` or C-style for | S |
| F-002 | MEDIUM | 234–241, 440–447 | Pipeline subshell | Capture output first or use process subst | S |
| F-003 | MEDIUM | 20          | No pipefail | `set -o pipefail` | S |
| F-004 | LOW    | 158, 202–206 | Repeated dmidecode/lscpu | Cache once in gather phase | S |
| F-005 | LOW    | 231–241     | Brittle fld() sed | Prefer `lsblk -J` + jq if available, or tighter sed | M |
| F-006 | LOW    | 56–57       | Double source of os-release | Source once | S |
| F-007 | NITPICK| 23          | Em-dash sentinel | Keep or use ASCII “-” | S |

---

## 14. Engineering Scorecard

| Dimension | Score | Justification | What a 5 would look like |
|-----------|-------|---------------|--------------------------|
| Architecture | 4 | Linear gather-print is ideal; helpers are clean. | Same + optional plugin section hooks. |
| Readability & Maintainability | 4 | Banner comments + defensive notes are outstanding; length is the only cost. | Extracted section functions or a lightweight template engine. |
| Safety | 5 | Read-only contract is ironclad and documented. | (already 5) |
| Error Handling | 4 | Soft-fail + timeouts everywhere; missing pipefail is the gap. | pipefail + explicit non-zero exit only on total catastrophic failure. |
| Security | 4 | No injection, secrets filtered, privilege not escalated. | Optional redaction mode for serials/BMC. |
| Performance | 4 | Timeouts prevent hangs; repeated queries are minor. | Single-pass caching of dmidecode/lscpu. |
| Portability | 3 | Correctly Linux-centric; a few pure bashisms remain. | Documented “bash ≥ 4 on Linux” + seq instead of braces. |
| Idiomatic Style | 4 | printf, have(), local, deliberate -P parsing. | Same + consistent use of `[[` if desired. |

**Overall: 4.0.** The single highest-leverage change is F-001 + F-003 (portability + pipeline safety). After those, the script is excellent for its domain.

---

## 15. Testing Recommendations

Concrete cases that would catch the findings:
1. Run under `bash --posix` or `dash` → expect F-001 to surface.
2. Run with `set -o pipefail` temporarily and force a failing pipeline mid-report.
3. Mock `lsblk` that emits a MODEL containing `"` → exercise F-005.
4. Non-root + no smartctl → verify graceful degradation messages.
5. Empty `/boot/config/shares` directory → verify no literal `*.cfg` appears.
6. Simulate standby drive (`smartctl` returns “STANDBY mode”) → check message.
7. `timeout` absent → confirm TMO becomes empty string and commands still run.

**CI / local tooling:**
```bash
shellcheck -x -e SC1091 hw-inventory.sh
bash -n hw-inventory.sh
# bats-core tests for the helper functions and a few mocked sections
```

No formal test suite exists today; adding a small bats suite for the pure helpers (`have`, `yk`, `kv`, `fld`) would be high value for future changes.
