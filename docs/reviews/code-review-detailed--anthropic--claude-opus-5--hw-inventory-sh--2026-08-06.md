# Code Review — Extensive Engineering Review

> **Frozen — historical document, not maintained.** Written 2026-08-06 against
> `hw-inventory.sh` at commit `bc32386` (651 lines). The file is now 990 lines, so
> **every line number and code excerpt below is stale** and will not match `HEAD`.
> Nothing here is edited to keep pace; it is kept as provenance for the finding IDs
> the ledger cites. **[`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) is authoritative** —
> a finding below may have been accepted, narrowed, rejected, or superseded there.

    VENDOR: Anthropic
    MODEL:  Claude Opus 5

| | |
|---|---|
| **Target** | `hw-inventory.sh` v4 (uploaded as `hw-inventory_1_.sh`) |
| **Reviewer** | Anthropic / Claude Opus 5 |
| **Date** | 2026-08-06 |
| **LOC** | 651 total; 515 non-blank, non-comment |
| **Language** | Bash |
| **Verified against** | bash 5.2.21 (`bash -n`: clean), ShellCheck 0.11.0 |

**Line numbering.** The submitted file carries no line numbers. Numbering throughout both documents is 1-based from the first line of the file as submitted — line 1 is `#!/usr/bin/env bash`, line 651 is the closing `printf`. The numbering is identical in the summary document.

**Slug note.** The upload arrived as `hw-inventory_1_.sh`; the `_1_` is a browser de-duplication suffix, not part of the name. The filename slug uses the script's own declared name from line 2.

---

## 1. Overview & Context

### What it does

`hw-inventory.sh` is a single-file, read-only hardware and platform inventory collector. It interrogates the host through standard tooling and emits one self-contained Markdown document on stdout: a YAML frontmatter block (lines 95–109) followed by ~15 report sections covering identity, CPU, boot parameters, memory and DIMM layout, physical disks, SMART health, hardware RAID, Unraid array state, filesystems, network interfaces, PCI devices, BMC/IPMI, Proxmox guests, Docker containers, and failed systemd units.

The output is clearly designed to be checked into a homelab knowledge base — the frontmatter carries `tags: [homelab, inventory, hardware]` (line 108) and a hand-fill `role:` field (line 105), which are Obsidian/Jekyll conventions rather than machine-parsing ones.

### Entry points and invocation model

There is exactly one entry point: the top of the file. There is no `main`, no function dispatch, and no argument parsing. Execution is straight-line from line 20 to line 651.

The documented invocation is line 16:

```
sudo bash hw-inventory.sh > "$(hostname)-$(date +%F).md"
```

Interactive, root, output redirected by the caller. Line 18 explains the `bash` prefix rather than `./` — the author runs fish as a login shell and is sidestepping the executable bit / shebang question. That is a real-world note worth keeping.

This is **not** cron-shaped or systemd-shaped as written, for reasons developed in §6: it always exits 0, it writes nothing itself, and its runtime is unbounded in the worst case. It could become cron-shaped with modest changes (F-026, F-015).

### External dependencies

None are required; all are probed. This is the script's defining architectural property.

| Dependency | Probed at | Assumed version / provenance | Consequence if absent |
|---|---|---|---|
| `timeout` | 28 | GNU coreutils 8.x+ / busybox | `$TMO` empties (safe); but 25 hardcoded sites still fail — F-003 |
| `dmidecode` | 42, 129, 201, 210 | 3.x; needs root | Model/serial/DIMM sections marked `(needs root)` |
| `lscpu` | 69, 157 | util-linux 2.3x | Falls back to `/proc/cpuinfo` (lines 72, 166) |
| `free` | 75, 149, 199 | procps-ng 3.3+ | RAM fields dropped |
| `lsblk` | 91, 227 | util-linux, `-P` and `TRAN` need ≥ 2.22 | Disk table replaced by a manual-entry notice (line 245) |
| `smartctl` | 251, 337 | smartmontools 7.x for NVMe `Percentage Used` | SMART sections skipped |
| `lspci` | 299, 517 | pciutils; `-nnk` | RAID detection and PCI section skipped |
| `ip` | 492 | iproute2 | Network section replaced by a notice (line 493) |
| `perccli64`/`storcli64`/`megacli` | 305, 321 | vendor CLIs | Notice at line 332 |
| `ipmitool` | 531, 549 | 1.8.18+ | Section skipped |
| `racadm` | 554 | Dell OMSA / iDRAC tools | Skipped |
| `pveversion`/`pct`/`qm`/`pvecm` | 561, 564, 573, 597, 617 | PVE 6–8 | Proxmox section skipped |
| `docker` | 624 | Engine 17.06+ for `--format 'table'` | Section skipped |
| `systemctl` | 641 | systemd 230+ for `--no-legend` | Section skipped |
| `awk`, `sed`, `grep`, `paste`, `head`, `wc`, `basename`, `hostname`, `uname`, `id`, `date`, `cat` | — | **Never probed.** GNU/POSIX assumed present. | Undefined |

The last row is the honest gap: the script is scrupulous about probing the exotic tools and silently assumes the ordinary ones. That is a defensible line to draw — but `paste -sd', ' -` (lines 455, 500, 510, 605, 606) is GNU-flavoured, and `grep -P` is correctly avoided throughout.

### Required privileges

Root is *requested*, not required (lines 11–13). Eight sites gate on it via `is_root` (115, 129, 201, 210, 253, 337, 531, 549). Without root the script still produces a valid document with labelled gaps. The privilege model is correct and clearly communicated.

### Target environment

Linux, unambiguously. `/proc/cpuinfo`, `/proc/loadavg`, `/proc/cmdline`, `/sys/kernel/iommu_groups`, `/sys/module/kvm_*`, `/sys/class/net/*`, `/var/local/emhttp/*` are all Linux-specific with no fallbacks. Specifically targeted platforms, inferable from the code: generic Linux, Proxmox VE, Unraid, and Dell/HPE/Broadcom hardware with a BMC and a RAID controller.

### Assumptions I had to make because the code does not say

Each of these is a gap in the header comment, not necessarily a defect:

1. **Target platforms are Linux only.** Strongly implied but never stated. `#!/usr/bin/env bash` invites a macOS user to try it; they would get a mostly-empty document.
2. **The locale is English.** Nothing in the file mentions locale, and nothing pins it. See F-001.
3. **Expected runtime is "seconds."** Never stated, and not true in the worst case (§9).
4. **The output file's permissions are the caller's problem.** Line 16 shows a plain `>` redirect, which uses the caller's umask — commonly `0022`, so world-readable. Given the document contains service tags, disk serials, MACs and BMC addresses, this deserves a line in the usage block. See F-028.
5. **The minimum bash version is 3.2.** Inferred from `{0..31}` (line 345) and `${v//pat/rep}` (lines 35–36). Never declared.
6. **`v4` is the version.** Hardcoded twice — line 2 (comment) and line 107 (`collector: hw-inventory.sh v4`). Cannot determine from the code alone whether these are kept in sync manually or whether one is stale.
7. **Whether the author intends this to run unattended.** The usage line suggests interactive; the report format suggests periodic capture. The right error-handling design differs between the two (§6).

---

## 2. Architecture Review

### Overall structure and control flow

The program is a **linear pipeline of independent, capability-gated collectors writing to a single stdout stream.** There is no dispatch table, no section registry, and no state machine. Execution order is source order.

```
line 20   set -u                          [no -e, no pipefail — deliberate, correct]
     |
     +-- 22-46   helper definitions        have() NA kv() yk() dmi() is_root()  TMO probe
     |
     +-- 48-92   GATHER PHASE  ------------ HOST OSNAME OSID KERN ARCH CPUMODEL
     |                                      RAMTOTAL PLATFORM PROD MFR SERIAL
     |                                      BOARD BIOS DISKS
     |           (exists only because the frontmatter must be printed before
     |            the body, so these values must be resolved first)
     |
     +-- 94-109  EMIT frontmatter --------- consumes gather-phase globals via yk()
     |
     +-- 111-651 EMIT body ---------------- 15 independent gated collectors:
                 |
                 +-- 112-115  header + root caveat
                 +-- 117-138  Identity            gate: pveversion / is_root+dmidecode
                 +-- 140-153  Snapshot (volatile) gate: /proc/loadavg, free
                 +-- 155-173  CPU                 gate: lscpu
                 +-- 175-195  Boot / kernel       gate: sysfs paths
                 +-- 197-223  Memory + DIMMs      gate: is_root + dmidecode
                 +-- 225-246  Physical disks      gate: lsblk        [defines fld()]
                 +-- 248-293  SMART               gate: smartctl + $DISKS + is_root
                 +-- 295-374  RAID controller     gate: lspci match  -> vendor CLI
                 |                                     -> per-drive megaraid probe
                 +-- 376-458  Unraid              gate: emhttp .ini  [defines uval() g()]
                 +-- 460-488  Filesystems/pools   gate: df findmnt zpool btrfs pvesm
                 +-- 490-512  Network             gate: ip
                 +-- 514-524  PCI                 gate: lspci
                 +-- 526-558  BMC / IPMI          gate: ipmitool + is_root + /dev/ipmi*
                 |            554-558 racadm      gate: racadm ONLY  <-- F-020
                 +-- 560-621  Proxmox             gate: pveversion|pct|qm  [defines cfgget()]
                 +-- 623-638  Docker              gate: docker + docker info succeeds
                 +-- 640-649  Failed systemd units gate: systemctl
                 +-- 651      footer
```

**Is the decomposition sound?** Partly. The *conceptual* decomposition — one gated collector per subsystem, each independently skippable — is the right model for this problem and it is applied consistently. The *mechanical* decomposition is not: those collectors are not functions, so they cannot be named, tested, reordered, selected, or timed individually. The structure exists in comments (the `# ----- SECTION ---` banners) rather than in code. See F-031.

### Separation of concerns

Weak, and the weakness is systematic. Every collector does four jobs inline: capability probing, data collection, parsing, and Markdown emission. Lines 267–283 are the clearest example — eleven lines that shell out, parse five different SMART attribute formats with fallbacks, and format a table row, with no boundary between them.

The consequence is concrete rather than theoretical: **there is no way to test the parsing without a machine that has the hardware.** The SMART attribute fallback chain at lines 269–281 encodes real knowledge (ATA `Power_On_Hours` in field 10, NVMe `Power On Hours` after a colon, `Percentage Used` vs `Wear_Leveling_Count`) and none of it can be exercised against a captured `smartctl` fixture. §15 develops this.

The counter-argument, which I think the author would make and which has force: extracting these into functions in bash buys you testability at the cost of passing everything through globals or subshells anyway, because bash functions cannot return structured values. That is true. But it does not apply to the *parsing* half, which is pure text-in/text-out and would be trivially testable if split from the collection half.

### Data flow and global state

Roughly 40 globals, all module-scope. Three categories:

1. **Configuration constants** — `NA` (23), `TMO` (27). Neither is `readonly`; nothing reassigns them, so this is latent rather than actual.
2. **Gather-phase results** — `HOST`, `OSNAME`, `OSID`, `KERN`, `ARCH`, `CPUMODEL`, `RAMTOTAL`, `PLATFORM`, `PROD`, `MFR`, `SERIAL`, `BOARD`, `BIOS`, `DISKS` (51–92). These are genuinely shared: `HOST` is used at 96, 112, 651; `DISKS` at 251, 257, 339; `CPUMODEL` at 159, 165. Making these globals is correct — they cross section boundaries by design.
3. **Section-local scratch** — `LC`, `SM`, `MCINFO`, `LANINFO`, `SENS`, `SEL`, `CTROWS`, `VMROWS`, `DNET`, `FAILED`, plus lowercase loop variables. These are globals only because bash has no block scope. Most are contained inside `while`-in-a-pipeline subshells (234–242, 496–505, 631–634) and genuinely cannot leak. The Proxmox `for` loops (576–588, 600–609) are **not** in a subshell, so `id`, `st`, `net0`, `ctip`, `ctbr`, `mem`, `unp`, `vst`, `vdisks`, `vnet` and `CFG` all persist to end of script. No bug results today — nothing downstream reads them — but it is the kind of latency that turns into a bug on the next edit.

The one piece of genuinely **hidden coupling** is `cfgget()` (line 570), which reads the global `$CFG` set by whichever loop is currently running. Its signature says it takes a key; its actual contract is "takes a key, and also requires that `CFG` was assigned by the enclosing loop." See F-021 — the impact is smaller than it first appears, and I verified why rather than assuming.

### Configuration strategy

**There is none.** No arguments, no environment variables, no config file. Everything tunable is a literal in the body:

- 22 `head -N` truncation limits across 13 distinct values (F-014)
- 12 distinct `timeout` durations: 5, 6, 10, 15, 20, 25, 30 seconds
- The megaraid probe range `{0..31}` and the give-up threshold `10` (lines 345, 350)
- Device filter patterns `loop|ram|zram|sr` — written twice, at line 92 and line 233, in **two different syntaxes** (an ERE against a bare name vs an ERE against `NAME="..."`)
- The `NA` sentinel — defined once at line 23 and hardcoded again as a literal em dash five times inside the Unraid awk program at lines 402, 406, 411, 412, 413 (F-017)

For a v4 script deployed across heterogeneous hosts, the absence of even a `--quick` / `--no-smart` switch is the most likely source of future friction. The megaraid probe (F-015) is exactly the thing an operator will want to skip, and there is no way to.

**Was "no configuration" the right call?** For v1, yes — configuration is the most common form of premature generality, and a script with zero knobs is a script with zero knob bugs. At v4, with 15 sections of wildly varying cost, it has stopped being right. The alternative is not a config file; it is `getopts` with three flags (`--only`, `--skip`, `--quick`) and named `readonly` constants, which is perhaps 25 lines.

### Idempotency and re-runnability

**Excellent, and this is the script's best architectural property.** Running it twice, ten times, or twice concurrently changes nothing:

- No file is created, modified, or deleted anywhere in 651 lines. I checked for `>`, `>>`, `tee`, `rm`, `mv`, `cp`, `mkdir`, `touch`, `mktemp`, `dd`, `install`, `sed -i` — the only redirections are `>/dev/null` and `2>/dev/null`.
- No lock file, so no stale-lock failure mode.
- `smartctl -n standby` (lines 260, 346) means even the *side effect of observation* is avoided: a spun-down array disk is reported as standby rather than woken. On a NAS with 20 parity-protected disks this is the difference between a free query and a 20-disk spin-up.
- Vendor RAID CLIs use `show` only (lines 313, 316, 319, 324, 327); MegaCLI uses `-LDInfo`/`-PDList` with `-NoLog`, which also avoids writing the vendor's own log file.
- Unraid state comes from `.ini` files rather than `mdcmd` (lines 377–379), avoiding a write into `/proc/mdcmd`.

The one caveat I cannot verify from the code: `smartctl -n standby -d megaraid,N` (line 346) — whether `-n standby` is honoured for drives behind a MegaRAID controller depends on the controller passing through the power-mode query. If it is not honoured, the 32-iteration probe could spin up drives it was trying not to disturb. Flagged as SUSPECTED in §8; it needs a real controller to confirm.

### Failure model

The script **fails soft, and fails silent.** Every collector independently degrades to "produce nothing" and the document continues. That is the right *shape* — a hardware inventory that aborts at the first missing tool is useless.

The problem is that "fails soft" and "fails silent" have been fused into one behaviour, when they are separable. There are three distinct outcomes the script currently renders identically:

| Reality | What the report shows |
|---|---|
| No RAID controller present | Section absent |
| RAID controller present, vendor CLI missing | Notice at line 332 ✔ |
| RAID controller present, CLI present, `timeout` missing so every call died | Empty code fence |
| RAID controller present, CLI present, CLI returned an error | Empty code fence |

Rows 3 and 4 are indistinguishable from row 1 at a glance, and they are the two that mean "your report is wrong." Line 332 shows the author already knows how to render row 2 correctly — the fix is to extend that pattern, not invent one. See F-025.

### Extension points

Adding a section means appending another `if have X; then printf '### ...'; ... fi` block. That works and requires understanding nothing else about the file — genuinely low friction, and worth crediting.

What it does not survive is the *next* class of request, which for a script at v4 is predictable: "run only the storage section," "skip the slow probe," "emit JSON as well as Markdown," "tell me which sections came back empty." Each of those requires touching all 15 collectors because the emission format is welded into each one.

The concrete alternative, and its cost: extract each collector into `section_<name>()`, keep a `SECTIONS=(identity snapshot cpu boot memory ...)` array, and dispatch in a loop. The tradeoff is real — bash function extraction adds an indirection layer and forces you to be explicit about which globals each section reads (`DISKS`, `NA`, `TMO`, `CPUMODEL`), which is 30 lines of `local`/comment work with no user-visible benefit on day one. I would not have asked for it at v1. At v4, with F-015 (unbounded runtime) and F-030 (undeliverable stable/volatile split) both blocked behind it, the churn is now justified.

### The stable/volatile split — an architectural claim the structure does not support

Lines 141–142 tell the reader to ignore the "Snapshot (volatile)" section when diffing two reports to spot hardware changes. That is good intent and exactly the right instinct for a document meant to be version-controlled.

It does not work, because volatile data is scattered through nearly every later section: SMART temperature and power-on hours (283), Unraid disk temps and fs-used percentages (412–413), array state and sync errors (386–392), Proxmox guest status (579, 603), Docker container status and IPs (628, 632), failed systemd units (642), IPMI sensor readings and SEL entries (544, 547), and uptime/load (144–147). A `git diff` between two runs a day apart will be dominated by noise from six sections the comment does not mention.

Two alternatives, with their tradeoffs:

- **Emit two documents** (`--stable` / `--volatile`). Clean separation, diffs become meaningful, but doubles the invocation complexity and splits the "one file per host" model the frontmatter implies.
- **Tag volatile fields inline** and post-process. Keeps one document, but requires a filter tool to make diffs clean, so the benefit is not self-contained.

I lean to the first. Either way, the comment at 141–142 currently overpromises and should be corrected even if the structure is not changed. Filed as F-030.

### Architectural summary

| Decision | Verdict | Why |
|---|---|---|
| `set -u` without `-e` or `pipefail` | **Right** | Best-effort collection makes `-e` actively harmful; `head -N` everywhere makes `pipefail` harmful |
| Capability probing via `have()` | **Right** | Zero hard dependencies; degradation is per-section |
| Gather phase before emit phase | **Right** | Forced by frontmatter ordering; correctly minimal (only 14 values) |
| Straight-line body, no functions per section | **Wrong at v4** | Blocks section selection, per-section timing, and testing (F-031) |
| Zero configuration surface | **Wrong at v4** | 22 magic limits and 12 timeouts, none reachable (F-014) |
| Fail-soft, fail-silent | **Half right** | Fail-soft is correct; fail-silent conflates "absent" with "broken" (F-025) |
| No traps | **Right** | Nothing to clean up. Only gap is an INT/TERM truncation marker (F-027) |
| Read-only by construction | **Right, and rigorously executed** | The standout property of this script |

---

## 3. Section-by-Section Walkthrough

### Lines 1–18 — Header comment block
**What it does:** Declares name and version, states the read-only contract, enumerates what is *deliberately absent* (`smartctl -t`, `zpool scrub/import`, `btrfs balance/scrub`, `docker run/exec`, `mount/umount`, `systemctl start/stop`, package operations), explains the Unraid `.ini`-over-`mdcmd` decision, describes the root requirement, and gives a usage line.

**Assessment:** Good — unusually so. Documenting the *negative space* of a script ("here is what I chose not to call, and why") is rare and is the single most useful thing in this file for a future maintainer. It converts a safety property from something you'd have to re-derive by reading 651 lines into something you can verify against a stated list. Line 18's fish-shell note is the kind of environment-specific gotcha that costs someone twenty minutes if it isn't written down.

**Issue:** Three things the block does not say, each of which a reader will assume wrongly: target OS (Linux only), expected runtime, and the sensitivity of the output.

**Finding:** F-028 [MEDIUM] (output sensitivity — developed in §10)

**Recommendation:** Add three lines: `# Linux only.`, `# Typical runtime 5-20s; can exceed several minutes on a large NAS or MegaRAID host — see the probe at line 345.`, and `# Output contains serial numbers, MACs and BMC addresses. umask 077 before redirecting.`

---

### Lines 20–28 — Shell options, `have()`, `NA`, `TMO`
**What it does:** `set -u` only. Defines `have()` as a `command -v` wrapper, the `NA` em-dash sentinel, and probes for `timeout` to build the `TMO` prefix string.

**Assessment:** Good on three counts and problematic on one.

`set -u` without `-e`: correct, and correct for a reason worth stating precisely. In a collector where `have zpool` legitimately fails on 90% of hosts, `-e` turns every absent tool into an abort. `-u` alone gives you the one guarantee you actually want here — that a typo'd variable name surfaces rather than silently expanding to empty and producing a plausible wrong report. Omitting `pipefail` is equally right: 22 pipelines end in `head -N`, which closes the pipe and SIGPIPEs the upstream producer; with `pipefail` every one of those would report failure.

`have()` using `command -v` rather than `which` or `type`: correct. `which` is an external binary with inconsistent exit semantics across distros; `command -v` is a shell builtin, is POSIX, and costs no fork.

`TMO` (lines 27–28): the *intent* is right — wrap anything that can block on a dead NFS mount, and degrade gracefully if `timeout` is absent. The *mechanism* is a space-containing string relied upon to word-split at 23 call sites. I verified this works in both states (empty and set). But it is fragile in a specific way: the moment anyone writes `"$TMO" cmd` — the change every quoting-conscious reviewer will reflexively suggest — the script breaks with `command not found`, and if `TMO` is empty it breaks even when quoted correctly. An array has neither failure mode.

**Issue:** `TMO` as a splitting string rather than an array; and the fallback it exists to provide is bypassed at 25 other sites.

**Finding:** F-002 [LOW], F-003 [HIGH]

**Recommendation:** `TMO=(); have timeout && TMO=(timeout 10)`, then `"${TMO[@]}" cmd` — which is safe when empty and does not depend on `IFS`. Route every hardcoded `timeout N` through a `run_to()` helper. Full code in §12 R-1.

---

### Lines 30–38 — `kv()` and `yk()` emitters
**What it does:** `kv()` prints a Markdown table row with an `NA` default. `yk()` emits a YAML scalar, escaping backslashes then double quotes, and emitting bare `null` for empty values.

**Assessment:** Good. `yk()` is the most carefully written function in the file. Escaping backslash *before* quote (line 35 then 36) is the correct order — reversing it would double-escape the backslashes introduced by the quote pass. Emitting `null` rather than `""` for a missing value is the right YAML semantic: a consumer can distinguish "not collected" from "collected as empty string." `local v=${2:-}` correctly survives `set -u` when called with one argument. This is the only function in the file that uses `local`.

**Issue:** The care taken over YAML escaping has no counterpart for Markdown. `kv()` at line 30 passes `$2` straight into a `| %s |` format with no handling of a literal `|`, which terminates the cell. The same gap exists at every other table-row `printf` (240–241, 444–446, 586, 607, 633). A container named `web|prod`, a disk model containing a pipe, or an Unraid share name with one, silently corrupts the table.

`yk()` also does not handle a literal newline in a value, which would break the frontmatter block. Unlikely from these sources, but it is the same class of defect and the fix is the same place.

**Finding:** F-004 [MEDIUM]

**Recommendation:** Add a `md()` escaper — `v=${v//|/\\|}` plus newline flattening — and route all table-cell values through it. Full code in §12 R-2.

---

### Lines 40–46 — `dmi()` and `is_root()`
**What it does:** `dmi()` wraps `dmidecode -s <keyword>`, returning empty if `dmidecode` is missing or the call fails; strips comment lines, takes the first, trims whitespace. `is_root()` tests `id -u` against 0.

**Assessment:** Acceptable. `dmi()` is correct: `grep -v '^#'` removes the informational lines older `dmidecode -s` emits before the value, `head -1` guards against multi-line output, and the `sed` trim handles the leading whitespace some versions produce. The `have dmidecode || { echo ""; return; }` guard means callers never need to check.

`is_root()` is a pragmatic proxy rather than the truth. What the script actually needs to know is "can I read `/dev/mem` and the raw SMART device," and euid 0 is neither necessary (a process with `CAP_SYS_RAWIO` can, without being root) nor sufficient (root inside an unprivileged container cannot). For the homelab targets in question the proxy is right ~99% of the time and the alternative — attempt-and-check — would cost a probe call per capability. I would keep it.

**Issue:** Minor: `id -u` forks a process; it is called 8 times (115, 129, 201, 210, 253, 337, 531, 549). `$EUID` is a bash builtin and free. Also `dmi()` runs a 4-stage pipeline for each of 5 calls at lines 83–87.

**Finding:** F-032 [NITPICK]

**Recommendation:** `is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }` — keeps the fallback for a hypothetical non-bash shell while paying the fork only once.

---

### Lines 48–92 — Gather phase
**What it does:** Resolves the 14 values the frontmatter needs before any output is printed: hostname, OS name and ID (from `/etc/os-release`, falling back to `/etc/unraid-version`, then `uname -o`), kernel, arch, CPU model (from `lscpu`, falling back to `/proc/cpuinfo`), total RAM, virtualisation platform, five DMI strings, and the disk list.

**Assessment:** Mostly good; one real defect and one design smell.

The fallback chains are the right shape. `OSNAME` tries three sources in decreasing reliability order (lines 54–63). `CPUMODEL` tries `lscpu` then `/proc/cpuinfo` (70–72). `HOST` has an `|| echo unknown` (51). Each degrades to something rather than to empty, which is what the frontmatter needs.

Sourcing `/etc/os-release` inside `$( )` (lines 56–57) is the right *containment* choice — the subshell means the ~10 variables that file defines never reach the parent scope. But sourcing it at all means executing it, as root, and `os-release` is a data file. The standard-conformant parse is one `awk` line and has no execution semantics at all.

Line 91–92 is well-constructed: `lsblk -dn -o NAME,TYPE`, filter to `TYPE=="disk"` in awk, exclude the pseudo-device prefixes, `|| true` to absorb grep's exit-1-on-no-match. Capturing `DISKS` once and reusing it at 251, 257 and 339 rather than re-running `lsblk` three times is the right call.

**Issue (1):** No `LC_ALL=C`. `lscpu` binds the `util-linux` gettext textdomain and `free` binds `procps-ng` — I verified both by inspecting the binaries. Both ship translated `.po` files upstream. Under, say, `de_DE.UTF-8` with language packs installed, `lscpu` prints `Modellname:` and `free` prints `Speicher:`, so the awk patterns `/^Model name/` (line 70) and `/^Mem:/` (line 75) match nothing. `CPUMODEL` then falls through to `/proc/cpuinfo`, which is never translated, so the CPU survives — but `RAMTOTAL` has no fallback and comes back empty, as do the socket/core/thread counts at 160–163 and the swap figures at 151 and 200.

**Issue (2):** Sourcing a data file executes it.

**Finding:** F-001 [HIGH], F-005 [LOW]

**Recommendation:** `export LC_ALL=C` immediately after line 20. Replace the source with `awk -F= '$1=="PRETTY_NAME"{gsub(/"/,"",$2); print $2; exit}' /etc/os-release`. Full code in §12 R-1.

---

### Lines 94–109 — YAML frontmatter
**What it does:** Emits the `---`-delimited frontmatter using `yk()`, plus four literal lines: a blank `role:` for manual completion, the collection date, the collector version, and tags.

**Assessment:** Good. `printf -- '---\n'` (95, 109) uses `--` to stop option parsing before a format string beginning with `-`; without it `printf` would try to interpret `---` as flags. That is a detail most shell authors get wrong once and never again, and it appears correctly at all three sites (95, 109, 651).

Leaving `role:` blank with an inline enumeration of valid values (line 105) is a nice touch — it makes the document a form rather than just a dump.

**Issue:** `date` is invoked separately at line 106 and line 114. A run that crosses midnight puts two different dates in one document. More practically: the frontmatter date carries no timezone or offset, so a fleet of reports collected across timezones cannot be ordered reliably.

**Finding:** F-007 [LOW]

**Recommendation:** Capture once in the gather phase: `NOW_DATE=$(date '+%Y-%m-%d')`, `NOW_FULL=$(date '+%Y-%m-%d %H:%M %Z')`, and consider `date -u '+%Y-%m-%dT%H:%M:%SZ'` for the frontmatter field, which sorts lexically and is unambiguous.

---

### Lines 111–138 — Header and Identity table
**What it does:** Prints the `## hostname` heading, a blockquote with collection timestamp and a conditional not-root caveat, then the Identity table; adds a Proxmox version row if `pveversion` exists, and DMI rows if root.

**Assessment:** Good. Line 115 is the cleverest line in the file and it is clever in the right way: `"$(is_root || echo ' — **not run as root**, some fields incomplete')"` short-circuits to empty output when `is_root` succeeds, so the caveat renders exactly when it applies with no `if` block. It is readable rather than cryptic because the intent is legible from the string itself.

The else-branch at line 136 is the pattern the rest of the script should follow: it does not just omit the fields, it says *why* they are missing and what to do about it.

**Issue:** None material.

**Recommendation:** None.

---

### Lines 140–153 — Snapshot (volatile)
**What it does:** Uptime, load average, RAM and swap used, each individually gated.

**Assessment:** Acceptable. The `uptime -p` with fallback to `uptime | sed` (line 144) handles the pre-2014 procps that lacks `-p`. Reading load from `/proc/loadavg` rather than parsing `uptime` output (146–147) is the right choice — it is a stable kernel interface rather than a human-formatted string.

**Issue:** The comment at 141–142 claims this section isolates volatile data. It does not — see F-030 in §2. Also `free -h` is invoked twice here (150, 151) for values from the same output, and a third and fourth time at 75 and 200.

**Finding:** F-030 [MEDIUM], F-010 [MEDIUM]

**Recommendation:** Capture `FREE_OUT=$(free -h 2>/dev/null)` once in the gather phase. Correct or scope the comment at 141–142.

---

### Lines 155–173 — CPU
**What it does:** Model, sockets, cores per socket, threads per core, logical CPUs from a single captured `lscpu`; falls back to `/proc/cpuinfo` counting; then detects VT-x/AMD-V from cpuinfo flags.

**Assessment:** Acceptable. Capturing `lscpu` into `LC` at line 158 and parsing it five times is better than five `lscpu` invocations — the author clearly knew to do this here. The `/^CPU\(s\):/` anchor at 163 correctly avoids matching `NUMA node0 CPU(s):` and `On-line CPU(s) list:`, which is a real trap in `lscpu` output and is handled.

**Issue (1):** `lscpu` still runs twice overall — once at line 70 for `CPUMODEL`, once at 158. The line-70 call could have populated `LC`.
**Issue (2):** All five awk patterns are English-locale-dependent (F-001).
**Issue (3):** `grep -qm1 ' vmx'` (170–171) anchors only on the left, so a hypothetical flag `vmx_foo` would match. Also reads `/proc/cpuinfo` twice.

**Finding:** F-001 [HIGH], F-010 [MEDIUM], F-033 [NITPICK]

**Recommendation:** Hoist the `lscpu` capture into the gather phase. Use `grep -qm1 -E '(^| )vmx( |$)'`.

---

### Lines 175–195 — Boot and kernel parameters
**What it does:** IOMMU group presence and count, nested-virt setting for whichever KVM module is loaded, transparent hugepage state, and the raw kernel command line in a fenced block.

**Assessment:** Acceptable. Testing `[ -d ... ] && [ -n "$(ls -A ...)" ]` as two separate `[ ]` commands rather than `[ ... -a ... ]` (line 177) is correct — `-a` inside `[ ]` is deprecated and has parsing ambiguities. Checking `kvm_amd` then `kvm_intel` via `elif` (182–186) correctly reflects that only one can be loaded.

**Issue (1):** `ls -A` and `ls | wc -l` (177–178) — ShellCheck SC2012 fires at line 178. Directory entries here are kernel-generated integers so the usual filename hazards do not apply, but a glob into an array is both safer and forkless.

**Issue (2):** `/proc/cmdline` is emitted verbatim inside a code fence (191–195). On systems using encrypted root this can contain `rd.luks.key=`, `rd.luks.serial=`, iSCSI `netroot=` strings with embedded credentials, or `root=` pointing at a path that discloses internal topology. The script filters IPMI passwords at line 540 and excludes the Unraid `csrf_token` at 378–379 — so a redaction policy exists; this is a hole in it, not an absence of one.

**Finding:** F-008 [LOW], F-009 [MEDIUM]

**Recommendation:** Replace lines 177–178 with a nullglob-guarded array count. For cmdline, filter through `sed -E 's/(rd\.luks\.key|rd\.luks\.serial|.*password[^ ]*)=[^ ]*/\1=<redacted>/g'` before emitting, and note in the header comment that the filter is best-effort.

---

### Lines 197–223 — Memory and DIMM layout
**What it does:** Total RAM and swap; if root, DIMM slot occupancy, maximum supported capacity from DMI type 16, and a per-DIMM table of locator, size, speed, vendor and part number.

**Assessment:** Good on domain knowledge, problematic on cost. The author knows dmidecode: `-t memory` selects types 5, 6, 16 and 17, so `grep -c '^Memory Device$'` (202) correctly counts type-17 structures only; `-t 16` (205) is the Physical Memory Array where `Maximum Capacity` actually lives; and `/^\tLocator:/` (213) is correctly anchored to a leading tab so it does not also match `Bank Locator:`. The `sp==""` guard at line 215 takes the first `Speed:` and ignores `Configured Memory Speed:`. Each of those is a specific trap that has been avoided.

`awk '/^\tSize:/ && $2 != "No"'` at line 203 works because awk's default field splitting strips the leading tab, making `$2` the numeric size or the literal `No` from `No Module Installed`.

**Issue (1):** `dmidecode -t memory` is executed three times — lines 202, 203, and 211 — for data that one invocation provides. Adding `-t 16` at 205 and the five `dmi()` calls at 83–87, the script runs `dmidecode` **nine times per report**.

**Issue (2):** The awk at 211–219 emits a row only when it encounters a `Part Number:` line (217). A DIMM whose SMBIOS record omits Part Number — which happens on some OEM-branded and older modules — is silently dropped from the table while still being counted in the `FILLED` total at 203, so the two disagree with no indication.

**Finding:** F-010 [MEDIUM], F-011 [LOW]

**Recommendation:** `DMI_MEM=$(dmidecode -t memory 2>/dev/null)` once in the gather phase, then `printf '%s\n' "$DMI_MEM" | ...` at each use. Move the row emission to the next `/^Memory Device$/` boundary plus an `END` block, so a record missing Part Number still emits with an `NA` in that column. §12 R-4.

---

### Lines 225–246 — Storage, physical devices
**What it does:** Table of device, size, model, serial, HDD/SSD, and bus, parsed from `lsblk -P` key="value" output via the local `fld()` helper.

**Assessment:** Good decision, imperfect execution. The comment at 229–230 explains exactly why `-P` was chosen over columnar output — empty `MODEL`/`SERIAL` fields collapse and shift every subsequent column — and that comment is the reason a future maintainer will not "simplify" it back into a silent data-corruption bug. That is the single highest-value comment in the file.

Header (228) and `printf` argument order (240–241) match correctly: Device, Size, Model, Serial, Type, Bus ← `name, size, model, serial, kind, tran`. I checked this specifically because column-order drift is the classic bug in hand-built tables; it is right.

**Issue (1):** Line 92 filters `TYPE=="disk"`; line 232 does not. `lsblk -d` suppresses dependents but not top-level `md*` RAID arrays or `dm-*` mapper devices, so those can appear in a table headed "physical devices" with an empty model and serial. `DISKS` and this table can therefore disagree about what exists on the same host.

**Issue (2):** `fld()` (231) forks `printf` plus `sed` per field — 12 processes per disk, so 288 on a 24-bay chassis, to extract data bash could parse natively.

**Issue (3):** `fld()` is defined inside the `if` block but bash function definitions are global, so it silently joins the top-level namespace under a very generic name.

**Finding:** F-012 [MEDIUM], F-013 [LOW], F-035 [MEDIUM]

**Recommendation:** Add `TYPE` to the `-o` list and skip rows where it is not `disk`. Replace `fld()` with a `read`-based parse or bash pattern matching. Hoist the definition to the helper block at 22–46.

---

### Lines 248–293 — SMART health
**What it does:** For each disk in `DISKS`, queries `smartctl -n standby -H -A -d auto`, detects standby and reports without waking, then extracts health, power-on hours, reallocated/pending sectors, wear indicator and temperature — each with an ATA-format primary pattern and an NVMe/SCSI-format fallback.

**Assessment:** Good, and the strongest domain knowledge in the file. `-n standby` with the comment at 258–259 explaining why is exactly right for a NAS. The dual parse chains are correct: `Power_On_Hours` field 10 is the ATA attribute table's RAW_VALUE (269) while `Power On Hours:` after a colon is the NVMe/SCSI health-log form (270); `Percentage Used` is NVMe wear while `Wear_Leveling_Count` field 4 is the SATA SSD normalised value (276–277). Someone has actually read `smartctl` output from several device classes.

The three-way outcome at 261–265 — standby, no data, real data — is handled explicitly rather than collapsing into one empty row. `|| true` on line 260 correctly absorbs the exit-2 that `-n standby` returns by design.

**Issue (1):** `smartctl --scan` runs twice (286, 288) — once to test for output, once to produce it — costing a second 15-second timeout window on a host where it hangs.

**Issue (2):** The loop is unbounded in aggregate: N disks × 15 s. A 24-bay chassis where the HBA is wedged is a six-minute silent stall.

**Issue (3):** `for d in $DISKS` relies on word splitting. Safe here — kernel block-device names cannot contain whitespace — but it is the habit that becomes a bug when the same pattern is copied to a list that can.

**Finding:** F-010 [MEDIUM], F-015 [MEDIUM], F-024 [LOW]

**Recommendation:** `SCAN=$(smartctl --scan 2>/dev/null); [ -n "$SCAN" ] && ...`. Read `DISKS` into an array with `mapfile -t`. Emit a progress note to stderr before each disk so a stall is attributable.

---

### Lines 295–374 — Hardware RAID controller
**What it does:** Detects a controller by `lspci` string match; if found, tries `perccli64`/`perccli`/`storcli64`/`storcli` then `megacli`/`MegaCli64` for topology; then probes device IDs 0–31 behind the controller with `smartctl -d megaraid,N`, giving up after 10 consecutive misses.

**Assessment:** Acceptable. The comment at 296–297 restating the read-only constraint at the vendor-CLI boundary is well placed — this is precisely where a maintainer would be tempted to add a `set` verb. Preference order (305) puts Dell's `perccli` before Broadcom's `storcli`, correct for the PERC-branded controllers this most often meets. Falling back to MegaCLI with `-NoLog` (324, 327) avoids the vendor tool writing its own log file, which is a genuinely obscure read-only detail to have caught. The `misses` counter with a threshold (344–353) correctly handles sparse device IDs rather than stopping at the first gap.

**Issue (1):** Worst-case cost. 32 iterations × `timeout 6` = 192 s ceiling; the 10-miss break caps a *no-drives-answer* run at ~60 s. During that time the script produces no output and no indication it is alive. On a host where `lspci` matched but the drives are actually in HBA/IT mode — which line 370 shows the author anticipated — that minute is spent to print a one-line notice.

**Issue (2):** The probe target (338–342) is "the first non-NVMe entry in `DISKS`." On a host where that happens to be a USB boot stick or a SATA DOM rather than a device behind the controller, all 32 probes fail and the full miss budget is spent. The controller's actual devices are discoverable — `/sys/class/scsi_host/host*/proc_name` contains `megaraid_sas` — which would make the target selection deterministic.

**Issue (3):** Every `timeout` here is hardcoded (313, 316, 319, 324, 327, 346), bypassing `$TMO`.

**Finding:** F-003 [HIGH], F-015 [MEDIUM], F-016 [LOW]

**Recommendation:** Lower the miss threshold to 4 and the per-probe timeout to 3 s (a controller that is going to answer answers immediately); select the target via `/sys/class/scsi_host/*/proc_name`; gate the whole probe behind a `--deep` flag.

---

### Lines 376–458 — Unraid array
**What it does:** Reads emhttp's `var.ini` for array state, parses `disks.ini` with a substantial awk program into a per-slot table with human-readable sizes, reads share cache policy from `/boot/config/shares/*.cfg`, and reads flash identity from `ident.cfg`.

**Assessment:** Good. Three specific decisions are right:

The `.ini`-over-`mdcmd` choice with its stated reason (377–379) is the read-only contract applied at its hardest point — the obvious way to get Unraid array state writes a command into `/proc/mdcmd`, and the author declined and documented the decline.

Whitelisting `var.ini` keys explicitly (386–393) rather than dumping the file is a deliberate security decision, and the comment names the exact reason: `var.ini` also holds a `csrf_token`. A blanket dump would have leaked a live session token into a document destined for a git repository.

The glob guard at 440–441 — `for f in ...*.cfg` followed by `[ -r "$f" ] || continue` — correctly handles the unmatched-glob case where bash leaves the literal pattern in `$f`. I verified this behaves as intended. It achieves what `shopt -s nullglob` would, without changing global shell state that would then affect every later glob in the file. That is the better of the two options here.

The awk at 398–429 is competent: a `row()` function called at both section boundaries and `END` so the last record is not dropped, guards against emitting empty rows (408–409), and sensible unit thresholds.

**Issue (1):** `uval()` (385) re-reads and re-parses `var.ini` eight times — one awk process per field.

**Issue (2):** `g()` (443) is redefined on every loop iteration and implicitly closes over the loop variable `$f` rather than taking it as a parameter. It works, but a reader cannot tell what file `g shareUseCache` reads without scrolling up to the loop header.

**Issue (3):** The `NA` sentinel is hardcoded as a literal em dash five times inside the awk program (402, 406, 411, 412, 413) rather than passed in with `-v`. Changing `NA` at line 23 silently desynchronises this section from every other table.

**Issue (4):** `kv2` (455) is a variable whose name reads as a variant of the `kv` *function*, in a file where `kv` is called 30-odd times.

**Finding:** F-010 [MEDIUM], F-017 [LOW], F-018 [LOW], F-019 [NITPICK]

**Recommendation:** Have `uval()` parse the file once into an associative array. Define `g()` once at the top as `g() { awk -F= -v k="$1" '...' "$2"; }`. Pass the sentinel in with `awk -v na="$NA"`. Rename `kv2` to `IDENT`.

---

### Lines 460–488 — Filesystems and pools
**What it does:** A single fenced block containing `df -hT` (pseudo-filesystems filtered), `findmnt --real`, `zpool list` and `zpool status -x`, `btrfs filesystem show`, and `pvesm status`.

**Assessment:** Acceptable. Using `--real` on `findmnt` (469) is the right flag — it excludes pseudo-filesystems at the source instead of grepping them out afterwards. `zpool status -x` (476) rather than plain `status` is a good choice: it prints only pools that are *not* healthy, so a clean host produces one line instead of forty.

The `timeout 20` on the zpool calls (474, 476) versus `$TMO`'s 10 elsewhere reflects that a degraded pool genuinely takes longer to report — a considered choice, not an inconsistency.

**Issue (1):** Raw command output inside a code fence is the least useful form for the stated purpose. Every other storage section produces a Markdown table that diffs cleanly; this one produces column-aligned text whose whitespace shifts whenever a device name changes length, so a diff between two reports shows spurious changes.

**Issue (2):** `df -hT`'s filter operates on the device column, but `df` wraps long device names onto a second line, which both breaks the filter and misaligns the output.

**Issue (3):** Four hardcoded `head` limits (60, 60, 20) with no truncation marker.

**Finding:** F-014 [MEDIUM]

**Recommendation:** Add `-P` (POSIX output, never wraps) to `df`. Emit a `_… truncated at N lines_` marker when output hits a limit. Consider `findmnt --json` for a stable structure.

---

### Lines 490–512 — Network interfaces
**What it does:** Table of interface, operstate, MAC, IPv4 addresses and link speed, built by enumerating `ip -o link show` and reading sysfs per interface; then default route and resolvers.

**Assessment:** Good. Three details are right. `ip -o link show` piped through `awk -F': '` correctly extracts the name from `2: eno1: <BROADCAST...>`, and `sed 's/@.*//'` (496) strips the `veth0@if12` suffix that would otherwise produce a sysfs path that does not exist. Reading operstate and MAC from `/sys/class/net/` rather than re-parsing `ip` output is more robust — those are stable kernel files. `read -r` (496) is correct and appears at all three read sites in the file.

Line 503 deserves specific comment: `[ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null` handles the case where `/sys/class/net/X/speed` returns `-1` or `EINVAL` on a down interface. I verified the degradation: with a non-numeric value, `[` errors, the redirect swallows the message, the test is false, and the else-branch assigns `NA`. It works. But it works by *suppressing an error* rather than by checking the precondition, which means a reader cannot tell whether the `2>/dev/null` is load-bearing or decorative.

**Issue:** The idiom at 503 is correct but self-obscuring. In bash, `[[ $spd =~ ^[0-9]+$ ]] && (( spd > 0 ))` states the actual intent — "is this a positive integer" — and produces no error to suppress.

**Finding:** F-034 [LOW]

**Recommendation:** Use the regex form, or add a comment saying the redirect handles non-numeric sysfs values.

---

### Lines 514–524 — Notable PCI devices
**What it does:** `lspci -nnk` filtered by an awk state machine that keeps a device's full multi-line block when the header line matches a class of interest.

**Assessment:** Good. The state machine (519–522) is the correct approach and the non-obvious one: `lspci -nnk` output is a header line followed by indented `Subsystem:`/`Kernel driver in use:` lines, so a naive `grep` would match the header and discard the driver information — which the comment at 515–516 correctly identifies as the thing that actually matters when diagnosing. Setting `keep` on the header line and printing on it for subsequent lines preserves whole records. Using `-nn` for vendor:device IDs is right for the same reason.

**Issue:** `head -60` can cut mid-record, leaving a device header with its driver line severed and no indication.

**Finding:** F-014 [MEDIUM]

**Recommendation:** Truncate on record boundaries, or raise the limit and mark truncation.

---

### Lines 526–558 — BMC / IPMI and racadm
**What it does:** If `ipmitool` exists, the user is root, and an IPMI device node is present, emits controller info, BMC network config, sensor list and the last 15 SEL entries. Otherwise, if `ipmitool` exists and root but no device node, prints an explanatory notice. Separately, if `racadm` exists, emits `getsysinfo`.

**Assessment:** Good on the IPMI half. The triple gate at 531 — tool, privilege, *and* device node — is the correct precondition set, and the comment at 527–530 explaining that the script will not `modprobe ipmi_si` because loading a module is a state change is the read-only contract applied consistently at a place where it would be very easy to justify an exception. The `elif` at 549 turning the missing-device case into an actionable notice rather than silence is the pattern the rest of the file should copy.

The credential filtering at 539–541 is defence in depth done properly: a `grep -viE` blacklist for `community|password|cipher|auth type` followed by a `grep -E` whitelist restricting output to four network fields. Either alone would suffice; both together mean a new sensitive field added by a future `ipmitool` version fails closed.

**Issue (1):** The `racadm` block (554–558) is gated on the tool alone — not root, unlike its `ipmitool` neighbour. It also emits `**racadm getsysinfo**` as a bare bold paragraph with no `###` heading. If the IPMI block did not run (no device node, or not root), that output appears under whatever section preceded it — in a typical run, "Notable PCI devices." The document structure silently misattributes it.

**Issue (2):** `racadm getsysinfo` output is filtered for `password|community` but not restricted by whitelist the way IPMI is, so it is the weaker of the two redactions.

**Finding:** F-020 [MEDIUM]

**Recommendation:** Gate on `is_root`, wrap in its own `### Dell RAC` heading, and apply a whitelist rather than a blacklist.

---

### Lines 560–621 — Proxmox
**What it does:** Package versions; a table of LXC containers with hostname, status, OS, cores, RAM, root disk, privilege mode, features, IP and bridge; a table of QEMU VMs with disks and network; and cluster status.

**Assessment:** Acceptable. `cfgget()` (570) sensibly centralises "pull key K out of the config text," and using `sub(/^[^:]*: /,"")` rather than taking `$2` correctly preserves values that themselves contain `: ` — which `rootfs` and `net0` values routinely do. Deriving IP and bridge from `net0` with anchored `sed` captures (581–582) is right. The `unprivileged` mapping at 585 defaulting an absent value to `no` is correct Proxmox semantics: the key is omitted for privileged containers.

**Issue (1):** `cfgget` depends on the global `$CFG` with nothing in its signature to say so. I tested the `set -u` interaction specifically: because every call site is inside `$( )`, an unbound `CFG` kills only the subshell — the field comes back empty, bash prints `CFG: unbound variable` to stderr, and the script continues. So the risk is *not* a crash; it is an invisible contract that will break quietly the first time someone calls `cfgget` from a new location. Rated accordingly.

**Issue (2):** The row-accumulation strings at 586–587 and 607–608 span a physical newline inside a double-quoted assignment. It works, but line 586 is 200+ characters containing seven command substitutions and an embedded literal newline — the least readable construct in the file.

**Issue (3):** `${mem:-$NA} MiB` (586) renders as `— MiB` when memory is unset, and `$(cfgget memory) MiB` (607) renders as a bare ` MiB`. Both are worse than an unadorned `NA`.

**Issue (4):** Container hostnames and VM names go into table cells unescaped (F-004).

**Finding:** F-004 [MEDIUM], F-021 [LOW], F-022 [LOW]

**Recommendation:** Make `cfgget` take the config text as `$2`. Build rows with a `printf -v row` into an array and emit with `printf '%s\n'`. Move the unit inside the substitution: `${mem:+$mem MiB}` with an `NA` fallback.

---

### Lines 623–638 — Docker
**What it does:** If `docker` exists and `docker info` succeeds, emits server version and `docker ps -a` in a fence, then a per-container network/IP table built from `docker inspect`.

**Assessment:** Good gating. `have docker && $TMO docker info >/dev/null 2>&1` (624) is exactly right — the binary being installed says nothing about whether the daemon is running or the caller is in the `docker` group, and `docker info` is the cheapest reliable probe for both. Wrapping it in `$TMO` matters because a wedged daemon makes `docker info` hang indefinitely. The comment at 630 noting that `inspect` is read-only maintains the file's convention.

**Issue (1):** N+1 query pattern. Line 631 lists names, then line 632 runs one `docker inspect` per container inside the loop — up to 100 sequential invocations at `timeout 5` each, a 500-second ceiling. `docker inspect` accepts multiple names in one call, and `docker ps` can emit the same data via `--format` without a second command at all.

**Issue (2):** `timeout 5` hardcoded (632) rather than `$TMO`.

**Issue (3):** Container names are unescaped in a Markdown table (633).

**Finding:** F-003 [HIGH], F-004 [MEDIUM], F-023 [MEDIUM]

**Recommendation:** One call: `docker ps -a --format '{{.Names}}'` into an array, then a single `docker inspect` over all of them with a `{{range}}` template that emits `name|networks` lines.

---

### Lines 640–649 — Failed systemd units
**What it does:** Lists failed units, or prints `None.` if there are none.

**Assessment:** Good. `--no-legend --no-pager` is the correct pair for machine consumption — without `--no-pager`, `systemctl` invokes `less` when stdout is a TTY and the script would hang waiting for input. Explicitly printing `None.` rather than omitting the section (647) is the right choice and is the *only* place in the file that distinguishes "checked, found nothing" from "did not check." That distinction is what F-025 asks for everywhere else.

**Issue:** None material.

**Recommendation:** None. This block is the template for the F-025 fix.

---

### Line 651 — Footer
**What it does:** Emits a horizontal rule and a closing line naming the host.

**Assessment:** Acceptable. `printf --` is correctly used again. The footer doubles as a completeness marker: its absence tells a reader the run was interrupted, which is genuinely useful.

**Issue:** It is also the script's last command, so its exit status becomes the script's — always 0 regardless of what happened. And nothing tells the reader whether sections were skipped because they did not apply or because collection failed.

**Finding:** F-026 [MEDIUM], F-027 [LOW]

**Recommendation:** Precede it with a collection-warnings block and follow it with an explicit `exit` reflecting whether any section failed. §12 R-3.

---

## 4. Readability & Maintainability

The test applied here: a stranger opens this file in six months, needs to add a section for a new storage controller, and needs to be confident they have not broken the read-only guarantee.

That stranger does well for the first 250 lines and then starts working harder than they should.

### Naming

Generally good. `have`, `is_root`, `kv`, `yk`, `dmi` are short but each is used often enough that the brevity pays for itself, and each does exactly what its name says. Uppercase globals versus lowercase loop-locals is applied consistently and is the right convention for shell.

Three exceptions:

- `kv2` (455) reads as a sibling of the `kv()` function and is neither — it holds the Unraid flash identity string. Filed as F-019.
- `fld` (231) is a very generic name occupying the global function namespace for a helper that only parses `lsblk -P` output. `lsblk_field` would cost nine characters.
- `TMO` (27) does not convey that it is a *command prefix* rather than a duration. `TIMEOUT_PREFIX`, or an array named `TMO`, would.

### Function length and nesting

No function exceeds 10 lines; the longest is `yk()` at 6. In isolation that is excellent.

But the file's real unit of work is not the functions — it is the 630-line top-level body, and that is where nesting lives. Maximum depth is 5 (lines 337→343→345→347→350: `if is_root` → `if -n MRTGT` → `for n` → `if ! grep` → `if misses`). Depth 5 in shell, where there is no early-return and no exception, is the point at which a reader loses track of which guard they are inside.

### Cyclomatic complexity

A grep-based proxy over non-comment lines counts 74 `if`, 3 `elif`, 8 `for`, 3 `while`, ~27 `case` branches, 52 `&&` and 25 `||` — roughly **190 decision points in a single unit**. The proxy over-counts somewhat (some `&&` and `||` occur inside quoted awk and sed programs), but even halving it leaves a "function" an order of magnitude past any conventional threshold; 10–15 is the usual review limit and 50 is where most tools stop distinguishing degrees of bad.

The honest framing is that this metric is not really measuring complexity here — it is measuring the absence of decomposition. Each individual collector is simple. There are just fifteen of them in one scope with no boundaries. The number is the argument for F-031, not an independent finding.

### Magic numbers and magic strings

The densest maintainability problem in the file.

| Category | Count | Examples |
|---|---|---|
| `head -N` limits | 22 sites, 13 distinct values | 60, 45, 20, 100, 90, 70, 40, 35, 30, 15, 8, 6, 4 |
| `timeout` durations | 25 sites, 7 distinct values | 5, 6, 10, 15, 20, 25, 30 |
| Probe bounds | 2 | `{0..31}` (345), `misses >= 10` (350) |
| Device-exclusion pattern | 2 sites, 2 syntaxes | `^(loop\|ram\|zram\|sr)` (92) vs `NAME="(loop\|ram\|zram\|sr)[0-9]*"` (233) |
| `NA` sentinel | 6 sites, 2 mechanisms | `$NA` (23) vs literal `—` in awk (402, 406, 411, 412, 413) |
| Version string | 2 sites | line 2 comment, line 107 output |

None of these is reachable without editing the body, and the last three are duplications that can silently drift apart. The device-exclusion pattern is the one most likely to bite: adding `nbd` or `md` to the exclusion list requires finding and correctly translating between two different regex forms 140 lines apart.

### Comment coverage

The strongest dimension of the file, and worth being specific about why. The comments answer *why*, not *what*:

- Lines 4–9 enumerate the commands deliberately not called — the safety contract as a checkable list.
- Lines 25–26 say which tools block on dead mounts and therefore why `TMO` exists.
- Lines 229–230 explain the `lsblk -P` choice by naming the exact bug the obvious alternative causes.
- Lines 249–250, 258–259 explain the SMART flag choices in terms of drive side effects.
- Lines 296–297, 335–336 restate the read-only rule at the vendor-CLI boundary, where it is most tempting to break.
- Lines 377–379 explain the `.ini`-over-`mdcmd` choice *and* name the `csrf_token` that the key whitelist exists to exclude.
- Lines 515–516 explain why `-nnk` rather than plain `lspci`.
- Lines 527–530 explain why the script will not `modprobe`.

I found no misleading comments and no redundant ones. The only *missing* comments are at line 503 (why the `2>/dev/null` on a `[` test is load-bearing) and line 340 (why NVMe devices are excluded from megaraid target selection).

The banner comments (`# ------ STORAGE ---`) are doing structural work that code should be doing. They are effective as navigation, which is exactly the tell for F-031: when comments are the only thing marking your module boundaries, you have modules that want to be functions.

### Dead code and duplication

No dead code — every function is called, every variable read. Verified: ShellCheck reports zero SC2034 (unused variable).

Real duplication:

- `uval()` (385) and `g()` (443) are the **same awk program** — `-F= -v k="$1" '$1==k{gsub(/"/,"",$2); print $2; exit}'` — differing only in which file they read. One parameterised function replaces both.
- The awk fragment `{gsub(/^[ \t]+/,"",$2); print $2; exit}` appears at lines 70, 72, 205, 267, 280, 354, 355, 356, 361 — nine times.
- The SMART parse chain at 267–283 and the megaraid parse chain at 354–361 are the same logic against the same tool with different fallback keys. They will drift.
- The device-exclusion pattern, in two syntaxes (92, 233).

### Hidden coupling

Three instances, in decreasing severity:

1. `cfgget()` (570) reads the global `$CFG`, which is set by the loop that calls it. The signature does not say so. F-021.
2. `g()` (443) closes over the loop variable `$f` rather than taking it as an argument.
3. `DISKS` (91) is produced once in the gather phase and consumed at 251, 257, 339 — 250 lines away, with no marker at the definition saying who depends on it. This one is legitimate shared state, but it deserves a comment at line 90 naming its consumers.

### Discoverability of configuration knobs

Zero. There is no knob block, no `readonly` constants section, no argument parsing, no environment variable. A maintainer wanting to shorten the megaraid probe must read to line 345 to find `{0..31}` and line 350 to find the miss threshold, and there is nothing at the top of the file to suggest either exists.

### Line length

Line 586 is 219 characters; line 607 is 174; line 551 is 195. Line 586 contains seven command substitutions and an embedded literal newline in a single quoted assignment. This is the one place in the file where I had to read the line three times to be sure of what it does.

### Verdict — 4/5

Docked one point, and only one, because the comments genuinely carry the file. A stranger *can* maintain this. They will just spend their first hour discovering that four of the nine functions are defined 200–550 lines below the other five, and that the thing they want to tune is a literal buried in a loop.

---

## 5. Shell Scripting Best Practices

| Practice | Followed? | Lines | Assessment |
|---|---|---|---|
| Shebang matches features used | **Yes** | 1, 35–36, 345 | `#!/usr/bin/env bash` is correct: `${v//pat/rep}` and `{0..31}` are bashisms that would fail under `#!/bin/sh` on a dash system. `env` rather than `/bin/bash` is right for portability across distros that put bash elsewhere. |
| `set -e` | **Correctly omitted** | 20 | See below. |
| `set -u` | **Yes** | 20 | See below. |
| `set -o pipefail` | **Correctly omitted** | 20 | See below. |
| Quoting discipline | **Yes, with one deliberate exception** | throughout; 43, 91, 257, 339, 576, 600 | Every variable in an argument position is quoted. The exceptions are intentional word-splitting: `$TMO` in command position and `$DISKS`/`$CTIDS`/`$VMIDS` in `for` lists. ShellCheck flags **zero** SC2086 — it does not warn on command-position expansion, because that is a recognised idiom. |
| `[[ ]]` vs `[ ]` | **`[ ]` throughout** | all 65 test sites | Internally consistent, and deliberate. But this is a bash script, and `[[ ]]` would prevent the class of bug at line 503. See below. |
| Arithmetic contexts | Mixed | 348, 350, 503 | `$((misses + 1))` is correct and correctly omits `$` on the operand. `[ "$misses" -ge 10 ]` and `[ "$spd" -gt 0 ]` would read better as `(( misses >= 10 ))`. |
| `$( )` vs backticks | **Yes** | throughout | Not a single backtick used for substitution. All backticks in the file are literal Markdown code-span delimiters. |
| Arrays vs delimited strings | **No** | 27, 91, 344, 575, 599 | `TMO`, `DISKS`, `MRROWS`, `CTROWS`, `VMROWS` are all newline- or space-delimited strings where an array is the correct type. F-002, F-024. |
| `local` in functions | **Once out of nine** | 34 | Only `yk()` uses `local`. The others assign nothing, so no leak occurs today — but `fld()`, `uval()`, `g()`, `cfgget()` are one edit away from silently clobbering a caller's variable. |
| `readonly` for constants | **No** | 23, 27 | `NA` and `TMO` are conceptually constants. Nothing reassigns them, so this is latent. |
| `printf` vs `echo` | **Yes, essentially throughout** | 30, 37, 95–113, and ~60 more | `echo` appears only for literal fence labels (463, 468, 473) and bare newlines (138, 153) where it cannot misbehave. Every value-bearing emission uses `printf` with a **literal** format string — ShellCheck reports zero SC2059 (variable in format string), which is the bug this practice exists to prevent. |
| Useless use of cat/grep/echo | **A few** | 160–163, 183, 185, 188, 193, 498, 499, 502 | `echo "$LC" \| awk` five times where one awk pass suffices; `$(cat file)` where bash offers `$(<file)`. Minor. |
| Safe filename iteration | **Yes** | 234, 440, 496, 631 | `read -r` at all three read sites — ShellCheck reports zero SC2162. Globs used rather than parsing `ls`, with the unmatched-glob case guarded at 441. The only `ls` uses (177–178) are on a kernel-generated directory of integers. No `for f in $(find ...)` anywhere — zero SC2044. |
| `mktemp` and cleanup | **N/A** | — | No temp files are created. Correct: the script has nothing to persist. |
| Exit codes | **No** | 651 | Always 0. F-026. |
| Argument parsing | **None** | — | No `getopts`, no `--help`, no `--version`, no `--` handling. `hw-inventory.sh --help` prints a full report. F-029. |

### On `set -e`, and why omitting it was right

This is the decision most reviewers would flag as a defect, so it is worth being explicit that it is not.

`set -e` aborts on any command returning non-zero outside a tested context. In this script, non-zero is the *normal* outcome for a large fraction of commands: `have zpool` fails on every non-ZFS host, `dmidecode` fails without root, `grep -Ev` returns 1 when it filters everything, `smartctl -n standby` returns 2 **by design** when a drive is asleep, `grep -c` returns 1 when the count is zero. Under `set -e` the script would abort at the first absent tool and emit a truncated document — the worst possible outcome for a collector, because a truncated Markdown file looks like a complete one.

The script instead handles each case explicitly: `have` guards before use, `|| true` at lines 92, 260, 346, 577, 601, and `2>/dev/null` throughout. That is more work than `set -e` and it is the correct trade for this program shape.

### On `set -o pipefail`, and why omitting it was also right

22 pipelines terminate in `head -N`. `head` exits after N lines and closes the pipe, which SIGPIPEs the upstream producer, which then exits non-zero. With `pipefail` every one of those pipelines would report failure despite having worked perfectly. Combined with `set -e` it would be fatal; alone it would poison any exit-status logic built on top. Correctly omitted.

### On `set -u`, and what it does and does not buy here

`-u` is the right flag to keep: it catches variable-name typos, which in a script with 40 globals and no compiler is the realistic silent-corruption vector. `${2:-}` at line 34 and `${VAR:-}` at 102, 104, 130–134 show the author knows where `-u` needs an explicit default.

One nuance worth recording, because it is easy to get wrong in either direction: under `set -u`, an unbound variable *inside a command substitution* kills only the subshell. I tested this specifically for the `cfgget`/`$CFG` case at line 570 — the parent continues, the field comes back empty, and bash writes `CFG: unbound variable` to stderr. So `-u` is providing less protection at that site than it appears to. That is why F-021 is rated LOW rather than HIGH.

### On `[ ]` versus `[[ ]]`

The script uses `[ ]` exclusively, 65 times. ShellCheck's optional `require-double-brackets` check flags all 65 (SC2292).

Choosing one and applying it consistently is worth something, and `[ ]` habits port to `sh`. But this file is committed to bash (line 1, and the bashisms at 35–36 and 345), so the portability argument does not apply, and one concrete bug is left on the table: line 503's `[ "$spd" -gt 0 ] 2>/dev/null` only works because the error `[` prints on non-numeric input is being swallowed. `[[ $spd =~ ^[0-9]+$ ]] && (( spd > 0 ))` expresses the actual intent, produces no error, and needs no redirect. That is the practical cost of the choice, and it is small — this is a preference with one real consequence, not a defect.

---

## 6. Error-Handling Audit

### Operation-level audit

| Line(s)          | Operation                    | Can it fail?                      | Detected?                    | Handled?  | Consequence of failure                                                                       |
| ---------------- | ---------------------------- | --------------------------------- | ---------------------------- | --------- | -------------------------------------------------------------------------------------------- |
| 28               | `have timeout`               | Yes                               | Yes                          | Yes       | `TMO` empties — but only 23 of 48 timeout sites benefit (F-003)                              |
| 43               | `dmidecode -s` pipeline      | Yes (no root, no SMBIOS)          | Partially                    | Yes       | Empty string; caller renders `NA`. Correct.                                                  |
| 51               | `hostname`                   | Yes                               | Yes                          | Yes       | `\|\| echo unknown`. Correct.                                                                |
| 54–57            | `. /etc/os-release`          | Yes (unreadable, syntax error)    | `[ -r ]` + `&&`              | Yes       | Falls to `/etc/unraid-version` then `uname -o`                                               |
| 60               | `sed` on unraid-version      | Yes                               | No                           | No        | `OSNAME` becomes the literal `Unraid ` with empty suffix                                     |
| 65–66            | `uname -r` / `-m`            | Practically no                    | No                           | No        | `set -u` would not fire; empty frontmatter field                                             |
| 70, 72           | `lscpu` / cpuinfo awk        | **Yes — locale**                  | **No**                       | **No**    | **Silent empty CPU model (F-001)**                                                           |
| 75               | `free -h` awk                | **Yes — locale**                  | **No**                       | **No**    | **Silent empty RAM total (F-001)**                                                           |
| 79               | `systemd-detect-virt`        | Yes (returns 1 when bare metal)   | Yes                          | Yes       | `\|\| true`, then `-n`/`!= none` guard. Correct.                                             |
| 91–92            | `lsblk` pipeline             | Yes                               | Partially                    | Yes       | `\|\| true` absorbs grep exit 1; `DISKS` empty → SMART section skipped **silently**          |
| 106, 114         | `date`                       | Practically no                    | No                           | No        | Two invocations can disagree (F-007)                                                         |
| 147              | `awk` on `/proc/loadavg`     | No (guarded by `-r`)              | Yes                          | Yes       | Correct                                                                                      |
| 158              | `lscpu` capture              | Yes                               | No                           | Partially | `LC` empty → five `NA` rows, no explanation                                                  |
| 178              | `ls \| wc -l`                | Yes                               | No                           | No        | Count of 0 printed as `0 (IOMMU active)` — contradictory                                     |
| 183–188          | `cat` of sysfs               | Yes (module unloaded mid-read)    | `[ -r ]` only                | Partially | TOCTOU window; empty value                                                                   |
| 193              | `cat /proc/cmdline`          | Practically no                    | No                           | No        | Emits secrets if present (F-009)                                                             |
| 202–205, 211     | `dmidecode -t` ×3            | Yes                               | No                           | No        | Empty DIMM table with no notice                                                              |
| 232–242          | `lsblk -P` + `fld` loop      | Yes                               | `[ -z "$name" ] && continue` | Partially | Malformed line skipped silently                                                              |
| 260              | `smartctl` per disk          | Yes (exit 2 = standby, by design) | Yes                          | Yes       | `\|\| true` + explicit standby and no-data branches. **Best-handled operation in the file.** |
| 267–283          | SMART attribute parses       | Yes                               | Yes                          | Yes       | Every field has `${x:-$NA}`. Correct.                                                        |
| 286, 288         | `smartctl --scan` ×2         | Yes                               | Yes (`grep -q .`)            | Yes       | Block omitted. Correct.                                                                      |
| 299              | `lspci` grep                 | Yes                               | Yes                          | Yes       | `RAIDCTL` empty → section skipped. Correct.                                                  |
| 313–329          | vendor CLI `show`            | Yes                               | **No**                       | **No**    | **Empty code fence, indistinguishable from "no data to show"**                               |
| 346              | megaraid probe ×32           | Yes (expected)                    | Yes                          | Yes       | `misses` counter + break. Correct design.                                                    |
| 386–393          | `uval` ×8                    | Yes                               | No                           | Partially | `kv` renders `NA`. Acceptable.                                                               |
| 398–429          | Unraid disks awk             | Yes                               | `[ -n "$UDISKS" ]`           | Yes       | Section omitted. Correct.                                                                    |
| 440–447          | shares glob + `g`            | Yes                               | `[ -r "$f" ] \|\| continue`  | Yes       | Correct — handles unmatched glob                                                             |
| 464–486          | df/findmnt/zpool/btrfs/pvesm | Yes                               | **No**                       | **No**    | **Empty fence**                                                                              |
| 496–505          | `ip` + sysfs per interface   | Yes                               | `\|\| echo "$NA"` per field  | Yes       | Correct                                                                                      |
| 503              | `[ "$spd" -gt 0 ]`           | Yes (non-numeric)                 | Via `2>/dev/null`            | Yes       | Works; obscure (F-034)                                                                       |
| 519              | `lspci -nnk`                 | Yes                               | **No**                       | **No**    | **Empty fence**                                                                              |
| 534–547          | ipmitool ×4                  | Yes                               | Yes (`[ -n ]` per block)     | Yes       | Each block omitted independently. Correct.                                                   |
| 555              | `racadm getsysinfo`          | Yes                               | Yes                          | Yes       | Guarded by `[ -n "$RAC" ]`                                                                   |
| 574–579, 598–603 | pct/qm list, config, status  | Yes                               | Partially                    | Partially | `[ -z "$CFG" ] && continue`; but a failed `pct list` yields an empty table with no notice    |
| 624              | `docker info`                | Yes                               | Yes                          | Yes       | Whole section gated. **Correct pattern.**                                                    |
| 628–632          | `docker ps` / `inspect`      | Yes                               | `[ -n "$nets" ]`             | Partially | Per-container skip is silent                                                                 |
| 642              | `systemctl --failed`         | Yes                               | Yes                          | Yes       | Explicit `None.` branch. **The template for the fix.**                                       |
| 651              | final `printf`               | No                                | —                            | —         | Exit status always 0 (F-026)                                                                 |

### Trap coverage

**There are no traps.** EXIT, ERR, INT, TERM are all unhandled.

For this script that is **the correct default**, and I want to be clear that it is not an oversight to fix reflexively. The standard reasons for a trap do not apply: no temp files to remove, no lock to release, no partial write to roll back, no service left in a modified state. Adding `trap cleanup EXIT` here would be cargo cult.

There is one real gap. The documented invocation redirects stdout to a file (line 16). If the run is interrupted — SIGINT during the 60-second megaraid probe is the realistic case — the shell has already written everything up to that point, and the user is left with a `.md` file that is truncated but structurally valid Markdown. Nothing marks it as incomplete. A minimal `trap` that emits a truncation marker costs three lines and converts a silent corruption into a visible one:

```bash
trap 'printf "\n\n> **REPORT TRUNCATED** — interrupted at $(date +%T).\n"; exit 130' INT TERM
```

Filed as F-027 [LOW] — low because the failure is recoverable by re-running, not because it is unimportant.

### Partial-failure state

If the script dies at line N, what is left behind is: nothing on the machine, and a partial file wherever the caller redirected. There is no lock to go stale, no half-written temp file, no modified device state. Re-running after any failure is safe and produces a complete report.

This is a direct dividend of the read-only architecture and it is worth stating plainly: **the script has no partial-failure state to speak of.** That property is rarer than it sounds.

### Are errors reported to stderr with actionable messages?

Almost never. `2>/dev/null` appears **82 times**. Nothing is written to stderr by the script itself at any point.

The four places that do communicate a problem all write it into the *document* rather than to stderr: line 136 (`needs root — install/run dmidecode as root`), 245 (`lsblk not available`), 332 (`no vendor CLI found`), 493 (`ip not available`), 551 (`ipmi modules not loaded`). Those five messages are excellent — specific, actionable, and placed where the reader of the report will see them. The problem is that they cover five failure modes out of dozens.

### Does the exit code communicate anything?

No. Line 651 is the last command, so the script exits with `printf`'s status, which is 0 unless stdout is closed. A cron entry, a CI step, or an Ansible task cannot distinguish:

- a complete report from a healthy host,
- a report from a host where `timeout` was missing and eight sections silently blanked,
- a report from a host where the user forgot `sudo`.

All three exit 0. F-026.

### Silent failure paths — enumerated

This is the most important list in the review. Each of these produces a report that a reader will take at face value.

1. **Non-English locale** (70, 75, 150–151, 160–163, 199–200). CPU model, socket/core/thread counts, RAM total and swap all render as `NA` or vanish. The report looks like it ran on a machine with no discoverable CPU topology. **F-001.**
2. **`timeout` not installed** (25 sites). Every hardcoded `timeout N` fails with `command not found` into `2>/dev/null`. SMART, RAID topology, IPMI, Proxmox and Docker sections all render empty. The report looks like a bare, diskless machine. **F-003.**
3. **Vendor RAID CLI present but erroring** (313–329). Empty code fence. Indistinguishable from a controller with no arrays configured.
4. **`df`/`findmnt`/`zpool`/`btrfs`/`pvesm` erroring** (464–486). Empty code fence. Indistinguishable from a host with no filesystems, which is impossible and therefore should have been obvious.
5. **`lspci -nnk` erroring** (519). Empty fence under a heading that promises devices.
6. **`lsblk` producing nothing** (91–92). `DISKS` empties, so the entire SMART section (251) never renders. No heading, no notice — the section simply is not there, exactly as if the host had `smartctl` missing.
7. **A DIMM without a Part Number field** (217). Dropped from the table while still counted in `FILLED` at 203, so the two numbers disagree with no indication. **F-011.**
8. **`head -N` truncation** (22 sites). A 40-drive enclosure is cut at `head -70`; the table simply ends. **F-014.**
9. **`pct list` / `qm list` failing** (574, 598). Empty `CTROWS`/`VMROWS` suppresses the table entirely (589, 610) — a Proxmox host with running guests reports as having none.
10. **A Markdown-breaking character in any value** (F-004). The table renders wrong rather than absent, which is the worst variant: the reader sees data and it is misaligned.

Items 1, 2, 6 and 9 share a signature worth naming: **the section disappears entirely rather than appearing empty**, so the reader has no cue that anything was attempted. That is the specific behaviour F-025 asks to change, and line 647's `None.` shows the author already knows the right shape for the fix.

**Finding:** F-025 [MEDIUM], F-026 [MEDIUM], F-027 [LOW]

---

## 7. Static Analysis Findings (ShellCheck)

I ran ShellCheck 0.11.0 against the file rather than estimating. Results are reproducible with the commands at the end of this section.

### Default ruleset — 0 errors, 0 warnings, 24 notes

This is a strong result for 651 lines and deserves to be stated as such before the table.

| Code | Line | Severity | Message | Fix |
|---|---|---|---|---|
| SC1091 | 57 | note | Not following: `/etc/os-release` was not specified as input | **Real, and precise:** the `# shellcheck disable=SC1091` at line 55 applies only to the *next command*, which is line 56. Line 57 sources the same file and is still flagged. Move the directive to file scope or duplicate it above line 57 — or apply F-005 and stop sourcing entirely. |
| SC2012 | 178 | note | Use `find` instead of `ls` to better handle non-alphanumeric filenames | Genuine pattern, harmless target (kernel-generated integers). Replace with a glob into an array. Line 177's `ls -A` is the same pattern, not separately flagged. |
| SC2016 | 113, 245, 287, 302, 332, 370, 434, 450, 456, 493, 508, 510, 536, 542, 545, 548, 551, 557, 566, 619, 632, 645 | note | Expressions don't expand in single quotes | **All 22 are false positives.** They are Markdown code-span backticks in `printf` format strings, awk `$1`/`$2` field references, and the Go template `$k`/`$v` at line 632. All must stay unexpanded. |

### What ShellCheck does *not* flag — and why that matters

I checked specifically for the classic shell defects. **None is present:**

| Code | What it catches | Count |
|---|---|---|
| SC2086 | Unquoted expansion causing word splitting or globbing | **0** |
| SC2046 | Unquoted command substitution | **0** |
| SC2181 | `if [ $? -ne 0 ]` instead of testing directly | **0** |
| SC2164 | `cd` without `\|\| exit` | **0** |
| SC2044 | `for f in $(find ...)` | **0** |
| SC2162 | `read` without `-r` | **0** |
| SC2155 | `local x=$(cmd)` masking the exit status | **0** |
| SC2115 | `rm -rf "$x/"` with a possibly-empty variable | **0** |
| SC2059 | Variable used as a `printf` format string | **0** |
| SC2034 | Assigned but never used | **0** |
| SC2015 | `a && b \|\| c` mistaken for if-then-else | **0** |

Two of these deserve comment. SC2059 being zero means every `printf` in the file uses a literal format string — that is the single most common way shell scripts acquire an injection bug and it is entirely absent. SC2115 and SC2164 being zero is a structural consequence of the read-only design: there is no `rm` and no `cd` to get wrong.

The zero on SC2086 is worth reading carefully rather than as vindication. ShellCheck deliberately does not warn about unquoted expansion in **command-name position**, because `$TMO cmd` is a recognised idiom. So F-002 is invisible to the linter by design. That gap is exactly where a human review earns its keep — the finding is not "this is wrong today," it is "this is a fragile mechanism that the next quoting-conscious edit will break."

### Optional checks (`shellcheck -o all`) — 427 notes

Not defects, but two of the four are diagnostically useful:

| Code | Count | Message | Verdict |
|---|---|---|---|
| SC2312 | 107 | Consider invoking this command separately to avoid masking its return value | **Take seriously.** This is the machine-readable form of §6's central complaint: 107 places where a command's exit status is discarded inside a substitution. Not all 107 need fixing, but the sites at 313–329, 464–486 and 519 are exactly the silent-failure paths enumerated above. |
| SC2292 | 65 | Prefer `[[ ]]` over `[ ]` in bash | Style, with one real consequence at line 503. §5. |
| SC2250 | 230 | Prefer braces around variable references | Pure style. Opt in only if you want it fleet-wide; it is a large diff for no behaviour change. |
| SC2249 | 1 (line 340) | Consider adding a default `*)` case | Minor. `case "$d" in nvme*) continue;; esac` intends fall-through. Adding `*) ;;` documents that. Note lines 239 and 585 both do have `*)` defaults — this is the only omission. |

### Commands to run locally

```bash
# The gate — must stay clean
shellcheck --severity=warning --shell=bash hw-inventory.sh

# Full default output, including the three real notes
shellcheck --shell=bash --format=gcc hw-inventory.sh

# Diagnostic pass for masked return values (do not gate on this)
shellcheck --shell=bash --enable=check-extra-masked-returns hw-inventory.sh

# Syntax-only, no linter needed
bash -n hw-inventory.sh

# Formatter, if you want one
shfmt -d -i 2 -ci hw-inventory.sh
```

### For CI

```yaml
- name: shellcheck
  run: shellcheck --severity=warning --shell=bash hw-inventory.sh
- name: syntax
  run: bash -n hw-inventory.sh
- name: format
  run: shfmt -d -i 2 -ci hw-inventory.sh
```

Gate on `--severity=warning` — the file passes that today, so the gate is meaningful from day one rather than starting red. Add the three default-level notes to a `# shellcheck disable=` with a reason comment (or fix them, which for SC1091 and SC2012 is a two-line change) so the note level can be gated later.

---

## 8. Edge Cases & Failure Modes

Split into CONFIRMED (I can trace the failure through the code as submitted) and SUSPECTED (plausible from the code but requiring hardware or an environment I cannot inspect to verify). Nothing here is presented as fact that I could not trace.

### CONFIRMED

| # | Trigger | Resulting behaviour | Fix |
|---|---|---|---|
| C-1 | Non-English locale with util-linux/procps translations installed | `lscpu` prints `Modellname:`/`Nom du modèle :`, `free` prints `Speicher:`. Patterns at 70, 75, 150–151, 160–163, 199–200 match nothing. CPU model survives via the `/proc/cpuinfo` fallback (72); socket/core/thread counts, RAM total and swap do not. Report shows a machine with no memory. (Mechanism confirmed by inspecting the binaries: `lscpu` binds textdomain `util-linux`, `free` binds `procps-ng`.) | `export LC_ALL=C` after line 20 — F-001 |
| C-2 | `timeout` not on `PATH` | Line 28 correctly empties `$TMO`, but the 25 hardcoded sites emit `timeout: command not found` into `2>/dev/null` and return empty. SMART, RAID, IPMI, Proxmox and Docker sections all blank. | Route all sites through `$TMO` — F-003 |
| C-3 | Any value containing `\|` — container named `web\|prod`, disk model with a pipe, Unraid share name with one | Cell boundary breaks; the Markdown table renders with shifted or merged columns. Worse than omission because the reader sees plausible data in the wrong columns. | `md()` escaper — F-004 |
| C-4 | Encrypted root with `rd.luks.key=` on the kernel command line | Emitted verbatim at line 193 into a document destined for a git repository. | Filter before emitting — F-009 |
| C-5 | Host with a top-level `md0` or `dm-0` device | Appears in the "physical devices" table (232) with empty model and serial, because that query omits the `TYPE=="disk"` filter that line 92 applies. `DISKS` and the table disagree about what exists. | Add `TYPE` to `-o` and filter — F-012 |
| C-6 | More than 60 filesystems, 70 physical drives behind a controller, 100 Docker containers, or 45 IPMI sensors | Output is cut at the `head -N` limit with no marker. The table simply ends. | Truncation markers — F-014 |
| C-7 | MegaRAID controller present in `lspci` but drives are in HBA/IT mode | 32 probes × `timeout 6`, capped by the 10-miss break at ~60 s, to print the one-line notice at 370. No output during the wait. | Reduce timeout and threshold; gate behind a flag — F-015 |
| C-8 | Empty glob: `/boot/config/shares/` exists but contains no `.cfg` | `$f` holds the literal pattern; `[ -r "$f" ] \|\| continue` catches it. **Handled correctly** — I verified this behaves as intended. | None |
| C-9 | Drive spun down (standby) | `smartctl -n standby` returns 2, `\|\| true` absorbs it, the `grep -qi 'STANDBY mode'` branch at 261 emits an explicit standby row. **Handled correctly, and this is the well-designed path.** | None |
| C-10 | Not run as root | Line 115 adds the caveat to the header; 136, 254 explain the specific gaps. **Handled correctly.** | None |
| C-11 | `lsblk` missing or producing nothing | `DISKS` empties, so the entire SMART section (251) is never emitted — no heading, no notice. Indistinguishable from `smartctl` being absent. | Emit a notice — F-025 |
| C-12 | DIMM present but its SMBIOS record has no `Part Number` field | Row dropped from the table at 217 while still counted in `FILLED` at 203. The slot count and the table silently disagree. | Emit at record boundary — F-011 |
| C-13 | Run interrupted (SIGINT during the megaraid probe) | Shell has already written a partial file; it is valid Markdown, truncated, and unmarked. | INT/TERM trap emitting a marker — F-027 |
| C-14 | Arguments passed (`--help`, `--version`, anything) | Silently ignored; a full report is printed to stdout. | `getopts` — F-029 |
| C-15 | Concurrent invocation | Both runs succeed independently. No shared state, no lock, no temp file. **Correct by construction.** | None |
| C-16 | Re-run after a failed run | Identical output. No residue from the previous run exists. **Correct by construction.** | None |
| C-17 | Disk full / read-only filesystem on the output target | The script itself never writes; the caller's `>` redirect fails and the shell reports it. Failure is the caller's and is visible. **Correct division of responsibility.** | None |
| C-18 | Interface with a name containing `@` (`veth0@if12`) | `sed 's/@.*//'` at 496 strips it before the sysfs lookup. **Handled correctly.** | None |
| C-19 | Interface down, `/sys/class/net/X/speed` returns `-1` or `EINVAL` | `[ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null` degrades to `NA`. **Works** — verified. Obscure but correct. | Comment or regex form — F-034 |
| C-20 | `pct list` succeeds but every `pct config` fails | `[ -z "$CFG" ] && continue` skips all, `CTROWS` stays empty, the table is suppressed at 589. A Proxmox host with running containers reports none. | Emit a warning — F-025 |
| C-21 | Non-numeric or absent memory in a Proxmox config | Renders as `— MiB` (586) or a bare ` MiB` (607). | Move the unit inside the substitution — F-022 |
| C-22 | `unprivileged` key absent from a container config | Defaults to `no` at line 585, which is **correct** Proxmox semantics — the key is omitted for privileged containers. | None |

### SUSPECTED — not verifiable from the code alone

| # | Hypothesis | Why I cannot confirm | What would confirm it |
|---|---|---|---|
| S-1 | `smartctl -n standby -d megaraid,N` (346) may not honour `-n standby`, so the 32-iteration probe could wake drives the script is trying not to disturb — undermining the read-only intent at its most sensitive point | Depends on whether the MegaRAID firmware passes through the power-mode query. Cannot be determined from the script. | Run on a host with a PERC/MegaRAID controller and spun-down drives; watch drive LEDs or `smartctl -i -n standby` before/after |
| S-2 | `df -hT` (464) wraps long device names onto a second line, breaking both the pseudo-filesystem filter and the column alignment | Whether wrapping occurs depends on device-name length and terminal width at run time | Run on a host with long LVM or iSCSI device paths and inspect the fence |
| S-3 | Non-English locale may also change gawk's decimal separator, so the Unraid `sprintf("%.2f TB", ...)` at 402 emits `1,82 TB` | Depends on gawk version and whether `LC_NUMERIC` is honoured for output formatting | `LC_ALL=de_DE.UTF-8 gawk 'BEGIN{printf "%.2f\n", 1.5}'` |
| S-4 | A DIMM whose `Locator` or `Size` appears *after* `Part Number` in dmidecode output would emit a row with stale field values, because the awk at 211–219 prints on the `Part Number` line | dmidecode's field order within a type-17 record is consistent in every version I know of, but it is not guaranteed by SMBIOS | `dmidecode -t 17` on several vendors' hardware |
| S-5 | `lsblk -P` `MODEL` values containing the literal sequence `SERIAL="` would defeat `fld()`'s greedy `.*` prefix at 231 | Requires a real disk with such a model string; I know of none | Craft a fixture and run `fld` against it |
| S-6 | `/proc/cmdline` content containing a triple backtick would break out of the code fence at 192–194 | Would require a deliberately hostile kernel command line | Boot with such a parameter |
| S-7 | Aggregate worst-case runtime on a large NAS exceeding several minutes | Depends on disk count, controller responsiveness, and daemon health — none inspectable from source | `time bash hw-inventory.sh > /dev/null` on the real host (§9) |

---

## 9. Performance & Profiling Opportunities

### Process-spawn inventory (static, from source)

The script is fork-bound, not CPU- or I/O-bound. Source counts: **129 command substitutions**, 45 `awk` invocations, 23 `head`, 21 `grep`, 13 `sed`, 7 `cat`, 5 `paste`, 1 each of `wc` and `basename` — before loop multiplication.

Runtime spawn count on a representative Proxmox host (4 disks, 10 containers, 5 VMs, root, no RAID controller, no IPMI, no Docker), estimated statically:

| Source | Spawns | Note |
|---|---|---|
| Gather phase (51–92) | ~25 | Includes two `. /etc/os-release` subshells |
| `is_root` (8 calls) | 8 | Each forks `id -u` |
| `dmidecode` | **9** | 5 × `dmi()` + `-t memory` ×3 + `-t 16` ×1 |
| `lscpu` | 2 | Lines 70 and 158 |
| `free -h` | 4 | Lines 75, 150, 151, 200 |
| CPU field parsing (160–163) | 10 | 5 × (`echo` subshell + `awk`) |
| `fld()` in disk loop | **~48** | 12 per disk × 4 disks |
| SMART loop | ~45 | 4 × (1 `smartctl` + ~9 parse subshells) |
| Network loop | ~40 | 5 interfaces × 8 |
| Proxmox loops | **~200** | 15 guests × (config + status + ~10 `cfgget`, each a subshell + `awk`) |
| Everything else | ~60 | |
| **Total** | **~450** | |

On a 24-bay NAS with a MegaRAID controller and 60 Docker containers the same estimate lands nearer **1,500–2,000**, dominated by `fld()` (288), the SMART loop (~250), the megaraid probe (up to 32 `smartctl`), and `docker inspect` (60).

### Optimisation candidates

| # | Change | Lines | Before → After | Confidence |
|---|---|---|---|---|
| P-1 | Cache `dmidecode -t memory` in one variable | 202, 203, 211 | 3 invocations → 1 | **MEASURED-OBVIOUS** — the count is deterministic from source |
| P-2 | Cache `lscpu` from the gather phase | 70, 158 | 2 → 1 | **MEASURED-OBVIOUS** |
| P-3 | Cache `free -h` | 75, 150, 151, 200 | 4 → 1 | **MEASURED-OBVIOUS** |
| P-4 | Cache `smartctl --scan` | 286, 288 | 2 → 1, and removes a second 15 s timeout window | **MEASURED-OBVIOUS** |
| P-5 | One awk pass for the five CPU fields | 160–163 | 10 spawns → 1 | **MEASURED-OBVIOUS** |
| P-6 | Replace `fld()` with bash parameter expansion | 231–238 | 12 spawns/disk → 0 | **MEASURED-OBVIOUS** — 288 → 0 on a 24-bay chassis |
| P-7 | Parse `var.ini` once into an associative array | 385–393 | 8 awk → 1 | **MEASURED-OBVIOUS** |
| P-8 | Single `docker inspect` over all containers | 631–634 | up to 100 invocations → 1; removes a 500 s worst case | **MEASURED-OBVIOUS** on spawn count; **SPECULATIVE** on wall-clock, which depends on daemon responsiveness |
| P-9 | `$EUID` instead of `id -u` | 46 | 8 forks → 0 | **MEASURED-OBVIOUS** |
| P-10 | Reduce megaraid probe: `timeout 3`, miss threshold 4 | 345–352 | ~60 s → ~12 s worst case when nothing answers | **SPECULATIVE** — assumes a responsive controller answers within 3 s, which I cannot verify without hardware |
| P-11 | Overall wall-clock improvement | — | Unknown | **SPECULATIVE** — fork cost is ~1–2 ms on modern Linux, so ~1,000 avoidable forks is on the order of 1–2 s, likely dwarfed by `smartctl` and `dmidecode` I/O latency |

The honest summary: **P-1 through P-9 are certain reductions in work done and cost almost nothing to implement, but I cannot claim they will visibly change runtime.** The script's wall-clock time is almost certainly dominated by blocking I/O — `smartctl` waiting on a drive, `dmidecode` reading `/dev/mem`, `docker inspect` waiting on the daemon — not by process creation. Do them because they are free and because they reduce the surface area, not because they will make the script feel faster. P-10 is the only change likely to produce a user-visible difference, and only on hosts that hit that path.

### How to actually measure this

Do not take the estimates above on faith. Run these on the real target hosts:

```bash
# 1. Total wall-clock, repeated, on the actual host
hyperfine --warmup 1 --runs 5 'sudo bash hw-inventory.sh > /dev/null'
# If hyperfine is unavailable:
for i in 1 2 3; do /usr/bin/time -f '%e s  %F majflt  %c involuntary-ctx' \
  sudo bash hw-inventory.sh > /dev/null; done

# 2. Where the time actually goes — per-line timestamps
PS4='+ $EPOCHREALTIME ${BASH_SOURCE##*/}:${LINENO}: ' \
  sudo bash -x hw-inventory.sh > /dev/null 2> trace.log
# Then find the gaps:
awk '/^\+ /{t=$2; if(p){d=t-p; if(d>0.05) printf "%6.3fs  %s\n", d, pl} p=t; pl=$0}' trace.log \
  | sort -rn | head -30

# 3. Confirm the fork count
sudo strace -f -c -e trace=clone,execve,fork bash hw-inventory.sh > /dev/null

# 4. Which binaries dominate
sudo strace -f -e trace=execve bash hw-inventory.sh 2>&1 >/dev/null \
  | grep -oP 'execve\("\K[^"]+' | xargs -n1 basename | sort | uniq -c | sort -rn | head -20
```

**What would confirm or refute the hypotheses:** if step 2 shows the largest gaps at lines 260 (`smartctl`), 346 (megaraid probe) and 632 (`docker inspect`), then P-8 and P-10 matter and P-1 through P-9 are cosmetic. If step 3 shows >1,000 `execve` calls and step 2 shows time spread thinly across hundreds of small gaps, then fork reduction is worth the effort. **I would expect the former, and the optimisations are worth doing anyway because they simplify the code — but I have not benchmarked this and will not claim otherwise.**

---

## 10. Security Review

The security posture here is better than most operational scripts, and the gaps are gaps in an existing policy rather than an absence of one. That distinction matters for how to fix them.

### Input validation and injection surface

**Command injection: none found.** No `eval` anywhere. No variable is used as a `printf` format string (ShellCheck: zero SC2059). No user-controlled string reaches a command position. The only dynamic execution is `"$RCLI"` (313, 316, 319) and `"$MCLI"` (324, 327), both of which are the output of `command -v` against a fixed whitelist of four and two literal names respectively (305, 322) — so the value is a path resolved from `PATH`, not attacker-chosen text. That is a sound construction.

**Path traversal: not applicable.** Every path in the file is a literal; nothing is built from external input.

**One construction worth naming, even though it is safe here.** `fld()` at line 231 interpolates `$1` directly into a `sed` regular expression:

```bash
sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"
```

All six call sites pass literals (`NAME`, `SIZE`, `ROTA`, `TRAN`, `MODEL`, `SERIAL`), so no injection exists today. But this is the *shape* of a regex-injection bug, and it is one refactor away from becoming one if someone parameterises the field list. Worth a comment saying the argument must be a literal.

**No sanitisation of collected data before emission.** Disk models, container names, share names and interface names go straight into Markdown. This is not a security issue in the classic sense — it is an output-integrity issue (F-004) — but if these documents are rendered by a static site generator that permits raw HTML in Markdown, a crafted container name becomes a stored-XSS vector in the rendered wiki. That is a stretch for a homelab, and I flag it as a consideration rather than a finding.

### Secret handling

| Vector | Status | Lines |
|---|---|---|
| Hardcoded credentials | **None** | — |
| Secrets in `argv` (visible to `ps`) | **None** — no command takes a password argument | — |
| IPMI community strings and passwords | **Filtered, well** — blacklist `community\|password\|cipher\|auth type` plus a four-field whitelist | 539–541 |
| Unraid `csrf_token` | **Excluded by design** — `var.ini` keys are whitelisted, and the comment names this as the reason | 378–379, 386–393 |
| `racadm getsysinfo` output | **Weakly filtered** — blacklist only (`password\|community`), no whitelist, unlike its IPMI neighbour | 555–556 |
| `/proc/cmdline` | **Not filtered** | 191–195 |
| `dmidecode` output | System serial and service tag emitted by design | 85, 132 |
| Disk serial numbers | Emitted by design | 238, 241, 355 |
| MACs, IPv4 addresses, BMC IP, default route, resolvers | Emitted by design | 499, 500, 504, 508, 510, 541 |

**F-009 [MEDIUM] — `/proc/cmdline` emitted verbatim.** CWE-532 (insertion of sensitive information into a log file). Realistic contents on the target platforms: `rd.luks.key=/path/to/keyfile`, `rd.luks.serial=`, `netroot=iscsi:user:password@host` for iSCSI boot, `root=UUID=` disclosing storage topology, and out-of-tree module parameters. The reason this is a finding and not a nitpick is the contrast: the script filters IPMI credentials and excludes a session token deliberately, so a reader is entitled to assume the whole document has been through a redaction pass. It has not.

**F-028 [MEDIUM] — output sensitivity is undocumented.** CWE-532 again, at the handling layer. The finished document contains the system service tag, every disk serial, every MAC, the BMC's IP, internal IP ranges, DNS resolvers, and a full inventory of running guests. Individually mundane; collectively this is a reconnaissance summary. Two concrete consequences: a service tag plus a model number is often sufficient to open a warranty case with a hardware vendor by phone, and disk serials plus a BMC address is enough to make a convincing pretext.

The script itself writes nothing, so it does not own the file permissions — but line 16 documents `> "$(hostname)-$(date +%F).md"`, which uses the caller's umask, commonly `0022`, producing a world-readable file. The usage block should say so.

### File permissions, umask, temp files

- **No temp files.** No `mktemp`, no `/tmp` path anywhere. This eliminates the entire class of insecure-temp-file and symlink-attack vulnerabilities (CWE-377, CWE-59) by construction, which is the correct way to eliminate them.
- **No umask is set.** Correct, because the script creates nothing. The caveat belongs in the docs (F-028), not in the code.
- **No file is created, modified or deleted.** Verified by searching for `>`, `>>`, `tee`, `rm`, `mv`, `cp`, `mkdir`, `touch`, `dd`, `sed -i`.

### TOCTOU

Several `[ -r file ]` checks followed by a read (146, 182, 184, 187, 191, 380, 383, 397, 439, 441, 454). Each is a nominal TOCTOU window (CWE-367). All targets are `/proc`, `/sys`, and root-owned config files; the exploit would require an attacker who can already replace root-owned paths, which means they already have root. **Not a real finding**, and I note it only to record that I checked rather than to pad the list.

### Privilege boundaries

- Root is requested but not required (11–13), and the script degrades honestly without it. Correct.
- No `sudo` is invoked from within the script — privilege is the caller's decision, made once, at the documented invocation. This is the right design: a script that sudos internally hides its own privilege escalation.
- Root is used for exactly what needs it: `dmidecode`, `smartctl`, `ipmitool`. No section runs as root that does not need to.
- The `racadm` block (554) is the one inconsistency — it is not root-gated while its `ipmitool` neighbour is. F-020.

### Unsafe execution patterns

- No `eval`, no `curl \| sh`, no dynamic sourcing of remote content, no unsafe deserialisation.
- **One dynamic execution: `. /etc/os-release` (56, 57).** `os-release` is specified as a data file that happens to be shell-syntax-compatible, and sourcing it is a common idiom — but sourcing is executing, and this executes as root. The precondition for exploitation is a writable `/etc/os-release`, which normally implies the attacker already has root, so the practical risk is low. It becomes non-trivial on a system where `/etc` permissions have drifted, or in a container where `/etc/os-release` is bind-mounted from a less-trusted source. The standard-conformant parse is one `awk` line with no execution semantics. F-005 [LOW], loosely CWE-829 (inclusion of functionality from an untrusted control sphere).

### Supply chain

The script vendors nothing, downloads nothing, and installs nothing. Its dependency surface is whatever is already on the host. It does invoke closed-source vendor binaries (`perccli64`, `storcli64`, `MegaCli64`, `racadm`, `ipmitool`) as root with `show`-class verbs only — an appropriate constraint, and the comments at 296–297 and 527–530 show it was a considered one.

### Summary

| Area | Verdict |
|---|---|
| Command injection | Clean |
| Path traversal | N/A |
| Hardcoded secrets | Clean |
| Secrets in argv | Clean |
| Insecure temp files / symlink attacks | Eliminated by construction |
| TOCTOU | Nominal only; not exploitable without pre-existing root |
| `eval` / dynamic execution | One sourcing of a data file (F-005) |
| Secrets in output | **Two gaps: `/proc/cmdline` (F-009), and undocumented output sensitivity (F-028)** |
| Privilege boundaries | Correct, with one un-gated block (F-020) |
| Supply chain | Minimal and appropriately constrained |

---

## 11. Portability Review

### Compatibility matrix

| Platform | Status | Notes |
|---|---|---|
| Linux, glibc (Debian/Ubuntu/RHEL/Arch) | **Works** | The design target. All assumptions hold. |
| Linux, musl (Alpine) | **Degraded** | BusyBox `awk` lacks gawk extensions; the Unraid awk at 398–429 uses `function` definitions and `sprintf` — POSIX awk, so it should survive, but BusyBox `awk` is not fully POSIX. BusyBox `lsblk` has no `-P`. BusyBox `free` output differs. `paste -sd', ' -` is supported. **Verdict: runs, produces a much thinner report.** Untested by me. |
| Unraid (Slackware base) | **Works** | Explicitly targeted; `/var/local/emhttp` and `/boot/config` handled at 376–458. |
| Proxmox VE (Debian base) | **Works** | Explicitly targeted; `pct`/`qm`/`pvecm`/`pvesm` handled. |
| WSL2 | **Degraded** | `/proc` and `/sys` are partially emulated. `dmidecode` fails (no `/dev/mem`), `smartctl` fails (no raw device access), `systemd-detect-virt` reports `wsl`. Identity, CPU and network sections work. **Fails safe** — every failure hits an existing guard. |
| Docker/LXC container | **Degraded, correctly** | `/sys/kernel/iommu_groups` and `/dev/ipmi*` absent, `dmidecode` blocked, host `/proc/cpuinfo` visible so CPU works. All guarded. |
| macOS | **Broken** | No `/proc`, no `/sys`, no `lsblk`, no `free`, no `lspci`. `uname -o` is GNU-only and fails. Output would be a near-empty document with a `NA`-filled Identity table. |
| FreeBSD / other BSD | **Broken** | Same reasons. Additionally `#!/usr/bin/env bash` requires bash from ports. |

macOS and BSD rows are kept rather than dropped because `#!/usr/bin/env bash` actively invites someone to try. The fix is not to add support — it is to say "Linux only" in the header and, optionally, fail fast:

```bash
[ "$(uname -s)" = "Linux" ] || { printf 'hw-inventory.sh: Linux only (found %s)\n' "$(uname -s)" >&2; exit 2; }
```

### Specific blockers

| # | Issue | Lines | Portable replacement |
|---|---|---|---|
| 1 | **No locale pinning.** The most impactful portability defect in the file, and it bites on the *primary* platform, not an exotic one. | 20 (absent) | `export LC_ALL=C` — F-001 |
| 2 | `uname -o` is a GNU extension; not in POSIX, absent on macOS/BSD | 63 | `uname -s`, or drop the fallback |
| 3 | `paste -sd', ' -` — the `-s` with a multi-char delimiter is GNU-flavoured; BSD `paste` accepts only single-character delimiter lists | 455, 500, 510, 605, 606 | An awk join, or a bash `${arr[*]}` with `IFS=', '` |
| 4 | `lsblk -P` and the `TRAN` column need util-linux ≥ 2.22 | 232 | Guard on `lsblk --help \| grep -q ' -P'`, or fall back to columnar with the caveat the author already documented at 229–230 |
| 5 | `systemctl --no-legend` requires systemd ≥ 230 | 642 | Acceptable — systemd 230 is 2016 |
| 6 | `docker --format 'table ...'` requires Engine ≥ 17.06 | 628 | Acceptable |
| 7 | `smartctl` NVMe `Percentage Used` parsing needs smartmontools ≥ 6.5, and `-d nvme` reliability improved substantially in 7.0 | 276 | Falls back to `Wear_Leveling_Count` (277); degrades correctly |
| 8 | Brace expansion `{0..31}` is a bashism | 345 | Fine under the bash shebang; would break under `sh`. `seq 0 31` if ever needed |
| 9 | `${v//pat/rep}` pattern substitution is a bashism | 35, 36 | Fine under the bash shebang |
| 10 | GNU awk assumptions: `\t` in a regex, `gsub`, `sprintf` with `%.2f` | 203, 211–219, 398–429 | All POSIX awk except the `\t` escape in a bracket-free regex, which mawk and BusyBox awk handle differently. Worth testing under mawk. |
| 11 | Hardcoded absolute paths, all Linux-specific | 54, 59, 72, 146, 166, 170–171, 177, 182–191, 380–397, 439–454, 498–509, 531 | Correct for the target; the point is that they define the target |
| 12 | Assumed `$PATH` contents | throughout | `awk`, `sed`, `grep`, `head`, `paste`, `wc`, `basename`, `cat`, `hostname`, `uname`, `id`, `date` are never probed by `have()` while every exotic tool is. Defensible, but `paste` and `basename` are the two most likely to be absent in a minimal container. |
| 13 | Filesystem case-sensitivity | — | No assumption made; not an issue |
| 14 | Architecture | 166 | `grep -c ^processor /proc/cpuinfo` works on x86, ARM and RISC-V. `/proc/cpuinfo` `model name` (72) is **x86-specific** — ARM uses `Processor` or `CPU implementer`, so `CPUMODEL` on a Raspberry Pi falls back to empty when `lscpu` is also unavailable. Minor; `lscpu` is almost always present. |

### Minimum runtime

**bash 3.2** — set by brace expansion (345) and pattern substitution (35–36). Neither is declared. Adding a version guard is three lines and prevents a confusing failure on a genuinely old system:

```bash
if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ]; then
  printf 'hw-inventory.sh: requires bash 3.2 or newer\n' >&2; exit 2
fi
```

If the array refactor in §12 R-1 is adopted, the floor **stays at bash 3.2**. Expanding an empty array as `"${arr[@]}"` under `set -u` errors on bash before 4.4, so R-1 deliberately never expands `TMO` — it tests `${#TMO[@]}` (safe on 3.2) and branches. R-5, however, uses an associative array and **raises the floor to bash 4.2**; that is called out in §12 and is a reason to take R-5 last, or not at all if any target host predates it.

---

## 12. Suggested Refactors

Every block below was written into a scratch script, executed, and run through ShellCheck 0.11.0 (default ruleset, zero output) before being included here. None is pseudocode and none contains an elision.

---

### R-1 — Locale pinning, `TMO` as an array, and a `run_to` helper
**Fixes:** F-001 [HIGH], F-002 [LOW], F-003 [HIGH], F-005 [LOW]
**Rationale:** Portability and Error Handling. F-001 and F-003 are the two findings that can silently blank core sections of the report, and both are fixed here. The churn is small — one added line, one changed line, and a mechanical substitution at 25 call sites — and it makes the fallback the author already designed at line 28 actually load-bearing rather than decorative.

**Before** (lines 20–28, 54–58):

```bash
set -u

have() { command -v "$1" >/dev/null 2>&1; }
NA="—"

# Wrap anything that can block on an unresponsive network mount or storage
# backend. df, findmnt and pvesm are the usual suspects.
TMO=""
have timeout && TMO="timeout 10"
```

```bash
OSNAME=""; OSID=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  OSNAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-}}")
  OSID=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
fi
```

**After:**

```bash
set -u

# Pin the locale before anything shells out. lscpu (util-linux) and free
# (procps-ng) are gettext-translated: under de_DE or fr_FR their field labels
# change and every awk pattern below silently matches nothing. This also fixes
# awk's decimal separator for the size formatting in the Unraid section.
export LC_ALL=C

have() { command -v "$1" >/dev/null 2>&1; }
readonly NA="—"

# Wrap anything that can block on an unresponsive network mount or storage
# backend. df, findmnt and pvesm are the usual suspects. An array, not a
# string: this never depends on word splitting and cannot be broken by the
# reflexive "you forgot to quote $TMO" edit.
TMO=()
have timeout && TMO=(timeout 10)

# Per-call timeout with the same fallback. Use this everywhere instead of a
# bare `timeout N`, so a host without coreutils' timeout degrades to running
# the command unwrapped rather than to "command not found" swallowed by 2>&-.
run_to() {
  local secs=$1; shift
  if [ ${#TMO[@]} -gt 0 ]; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

# /etc/os-release is a data file. Parsing beats sourcing: sourcing executes it,
# as root, and pulls ~10 variables into scope even inside a subshell.
osr() {
  awk -F= -v k="$1" '$1==k{gsub(/^"|"$/,"",$2); print $2; exit}' \
    /etc/os-release 2>/dev/null
}
```

```bash
OSNAME=""; OSID=""
if [ -r /etc/os-release ]; then
  OSNAME=$(osr PRETTY_NAME); [ -z "$OSNAME" ] && OSNAME=$(osr NAME)
  OSID=$(osr ID)
fi
```

Then the mechanical substitution across the file: `$TMO cmd` → `run_to 10 cmd`, and each hardcoded `timeout N cmd` → `run_to N cmd`. The 25 hardcoded sites are lines 260, 286, 288, 313, 316, 319, 324, 327, 346, 474, 476, 534, 539, 544, 547, 555, 565, 574, 577, 579, 598, 601, 603, 618, 632; the 23 `$TMO` sites are the rest.

**Risk:** Low, but not zero — this touches 48 call sites. The `run_to` signature moves the duration from a bare literal to a first argument, so an incorrectly transcribed site becomes `run_to smartctl -n standby ...`, which fails loudly rather than silently. `readonly NA` will error if anything reassigns it; nothing does today.

**Verification:**
```bash
# 1. No bare `timeout` should remain outside the run_to definition
grep -nE '(^|[^A-Za-z_])timeout [0-9]+' hw-inventory.sh | grep -v 'have timeout'
# Expect: only the line inside run_to

# 2. No $TMO uses should remain
grep -n '\$TMO' hw-inventory.sh   # expect: no output

# 3. The fallback path actually works
PATH=/usr/bin:/bin bash -c 'command -v timeout' >/dev/null && echo "timeout present"
# Simulate absence in a throwaway dir:
mkdir -p /tmp/nt && ln -sf /bin/bash /tmp/nt/bash
env -i PATH=/tmp/nt:/usr/bin:/bin bash hw-inventory.sh | head -40

# 4. The locale fix
LC_ALL=de_DE.UTF-8 bash hw-inventory.sh | grep -E '^\| (Model|Total RAM|Sockets) '
# Expect: populated values, not "—"

# 5. Diff the whole report before and after on a known host
sudo bash hw-inventory.sh.orig > /tmp/before.md
sudo bash hw-inventory.sh      > /tmp/after.md
diff <(grep -v '^> Collected' /tmp/before.md) <(grep -v '^> Collected' /tmp/after.md)
# Expect: no differences except the intended ones
```

---

### R-2 — Markdown cell escaping
**Fixes:** F-004 [MEDIUM]
**Rationale:** Correctness of the artifact. The author already wrote `yk()` to escape YAML; this is the same discipline applied to the other output format the script emits. Without it, one pipe character in a container name or disk model corrupts a table into misaligned-but-plausible data, which is worse than an omission because the reader has no cue.

**Before** (line 30):

```bash
kv() { printf '| %s | %s |\n' "$1" "${2:-$NA}"; }
```

**After:**

```bash
# Markdown table cell escaper. A literal | terminates a cell; a newline
# terminates the row. Both appear in real disk model strings, container names
# and Unraid share names. Applied at every table-cell emission site, the same
# way yk() is applied at every frontmatter site.
md() {
  local v=${1:-}
  v=${v//|/\\|}
  v=${v//$'\n'/ }
  v=${v//$'\r'/}
  printf '%s' "${v:-$NA}"
}

kv() { printf '| %s | %s |\n' "$(md "$1")" "$(md "${2:-}")"; }
```

The other table-emission sites need the same treatment. Line 240–241 becomes:

```bash
        printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
          "$(md "$name")" "$(md "$size")" "$(md "$model")" \
          "$(md "$serial")" "$(md "$kind")" "$(md "$tran")"
```

and line 586 becomes:

```bash
      CTROWS+="| $(md "$id") | $(md "$(cfgget hostname)") | $(md "${st:-}") |"
      CTROWS+=" $(md "$(cfgget ostype)") | $(md "$(cfgget cores)") |"
      CTROWS+=" $(md "${mem:+$mem MiB}") | $(md "$(cfgget rootfs)") |"
      CTROWS+=" ${unp} | $(md "$(cfgget features)") | $(md "${ctip:-}") |"
      CTROWS+=" $(md "${ctbr:-}") | $(md "$(cfgget onboot)") |"$'\n'
```

That rewrite also fixes F-022 — `${mem:+$mem MiB}` yields the empty string when `mem` is unset, which `md()` then renders as `NA`, instead of the current `— MiB`.

**Risk:** Very low. `md()` is pure string manipulation with no external calls and cannot fail. It does add one subshell per cell; if that matters, inline the substitutions with `printf -v`.

**Verification:**
```bash
# Unit-check the escaper directly
md 'web|prod'          # expect: web\|prod
md ''                  # expect: —
md "$(printf 'a\nb')"  # expect: a b

# End to end: create a container with a pipe in its name on a test host,
# render the report, and confirm the table still has the right column count
awk -F'|' '/^\| /{print NF}' report.md | sort -u
# Expect: one value per table, matching that table's header
```

---

### R-3 — Collection warnings, debug mode, exit code, and an interrupt marker
**Fixes:** F-025 [MEDIUM], F-026 [MEDIUM], F-027 [LOW]
**Rationale:** Error handling. This is the change that converts the script's central weakness — "a broken host and a bare host produce the same document" — into a visible signal. It is modelled directly on line 647, where the author already distinguishes "checked, found nothing" from "did not check." The churn is justified because every other finding in this review is discoverable by reading the code, while this class of failure is discoverable only by not trusting the output.

**Before:** (nothing — this is additive; only line 651 changes)

```bash
printf -- '---\n*End of report for %s.*\n' "$HOST"
```

**After** — add near the helpers at the top:

```bash
# Collection warnings. A section that produces nothing because the host does
# not have that hardware is silence; a section that produces nothing because
# collection failed is a warning. The report currently renders both the same,
# which is the difference between "no RAID controller" and "your RAID data is
# missing". Set HWINV_DEBUG=1 to also see them live on stderr as they happen.
WARNINGS=()
DEBUG=${HWINV_DEBUG:-0}

warn() {
  WARNINGS+=("$1")
  [ "$DEBUG" = 1 ] && printf 'hw-inventory: %s\n' "$1" >&2
  return 0
}

emit_warnings() {
  [ ${#WARNINGS[@]} -eq 0 ] && return 0
  printf '\n### Collection warnings\n\n'
  printf '%s\n' "${WARNINGS[@]}" | sed 's/^/- /'
  printf '\n_These sections were attempted and produced no data. Treat their absence above as unknown, not as absent hardware._\n\n'
}

# Nothing to clean up — the script writes no files and holds no locks — but an
# interrupted run leaves the caller's redirect holding a truncated document
# that is still valid Markdown. Mark it so it cannot be mistaken for complete.
trap 'printf "\n\n> **REPORT TRUNCATED** — interrupted at %s.\n" "$(date +%T)"; exit 130' INT TERM
```

Then call `warn` at each silent-failure site enumerated in §6. Three representative examples:

```bash
# Replaces line 251's silent skip when lsblk produced nothing
if have smartctl && [ -z "$DISKS" ]; then
  warn 'SMART: smartctl is present but no disks were enumerated (lsblk failed or returned nothing).'
fi
```

```bash
# Inside the vendor RAID CLI block, replacing lines 312-320
printf '#### Controller and array topology\n\n```\n'
RAIDOUT=$(run_to 25 "$RCLI" /call show 2>/dev/null)
if [ -n "$RAIDOUT" ]; then
  printf '%s\n' "$RAIDOUT" | head -45
else
  warn "RAID: ${RCLI##*/} is installed but '/call show' returned nothing."
fi
```

```bash
# Replacing the Proxmox container table suppression at line 589
if [ -n "$CTROWS" ]; then
  printf '#### LXC containers\n\n'
  printf '| VMID | Hostname | Status | OS | Cores | RAM | Root disk | Unpriv | Features | IP | Bridge | Onboot |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n%s\n' "$CTROWS"
elif [ -n "$CTIDS" ]; then
  warn 'Proxmox: pct listed container IDs but every `pct config` returned nothing.'
fi
```

and replace line 651 with:

```bash
emit_warnings
printf -- '---\n*End of report for %s.*\n' "$HOST"

if [ ${#WARNINGS[@]} -gt 0 ]; then
  exit 1   # report generated, but incomplete — visible to cron, CI and Ansible
fi
exit 0
```

**Risk:** Medium, and the risk is behavioural rather than technical. Any caller currently treating exit 0 as "success" will start seeing exit 1 on hosts where a section legitimately failed. That is the point of the change, but it must be announced. If you want to stage it, add `emit_warnings` first and the `exit 1` in a later release.

**Verification:**
```bash
# 1. Clean host — expect no warnings section, exit 0
sudo bash hw-inventory.sh > /tmp/r.md; echo "exit=$?"
grep -c 'Collection warnings' /tmp/r.md   # expect 0

# 2. Force a failure — hide smartctl, expect a warning and exit 1
sudo env PATH=/usr/bin:/bin bash -c 'PATH=${PATH//\/usr\/sbin/} bash hw-inventory.sh' > /tmp/r2.md
echo "exit=$?"                              # expect 1
grep -A5 'Collection warnings' /tmp/r2.md

# 3. Debug mode writes to stderr and leaves stdout byte-identical
HWINV_DEBUG=1 sudo bash hw-inventory.sh > /tmp/r3.md 2> /tmp/r3.err
diff /tmp/r2.md /tmp/r3.md && echo "stdout unchanged by DEBUG"
cat /tmp/r3.err

# 4. Interrupt marker
sudo bash hw-inventory.sh > /tmp/r4.md & sleep 1; kill -INT %1; wait
tail -3 /tmp/r4.md   # expect the TRUNCATED marker
```

---

### R-4 — Cache `dmidecode` output
**Fixes:** F-010 [MEDIUM], F-011 [LOW]
**Rationale:** Performance and correctness together. Three identical `dmidecode -t memory` calls become one, and restructuring the awk to emit at record boundaries fixes the silent drop of DIMMs whose SMBIOS record omits `Part Number`.

**Before** (lines 201–223):

```bash
if is_root && have dmidecode; then
  SLOTS=$($TMO dmidecode -t memory 2>/dev/null | grep -c '^Memory Device$')
  FILLED=$($TMO dmidecode -t memory 2>/dev/null | awk '/^\tSize:/ && $2 != "No" {c++} END{print c+0}')
  kv "DIMM slots (filled / total)" "$FILLED / $SLOTS"
  MAXCAP=$($TMO dmidecode -t 16 2>/dev/null | awk -F: '/Maximum Capacity/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
  kv "Max supported" "${MAXCAP:-$NA}"
fi
echo

if is_root && have dmidecode; then
  MODLINES=$($TMO dmidecode -t memory 2>/dev/null | awk '
    /^Memory Device$/ {loc="";size="";sp="";pn="";mf=""}
    /^\tLocator:/ {sub(/^\tLocator:[ \t]*/,""); loc=$0}
    /^\tSize:/ {sub(/^\tSize:[ \t]*/,""); size=$0}
    /^\tSpeed:/ && sp=="" {sub(/^\tSpeed:[ \t]*/,""); sp=$0}
    /^\tManufacturer:/ {sub(/^\tManufacturer:[ \t]*/,""); mf=$0}
    /^\tPart Number:/ {sub(/^\tPart Number:[ \t]*/,""); pn=$0
      if (size !~ /^No/) printf "| %s | %s | %s | %s | %s |\n", loc, size, sp, mf, pn}
  ')
  if [ -n "$MODLINES" ]; then
    printf '#### Installed DIMMs\n\n| Slot | Size | Speed | Vendor | Part number |\n|---|---|---|---|---|\n%s\n\n' "$MODLINES"
  fi
fi
```

**After** — capture once in the gather phase (near line 87):

```bash
# dmidecode is slow (reads /dev/mem) and was previously invoked nine times per
# report, three of them the identical `-t memory` dump. Capture once.
DMI_MEM=""; DMI_ARRAY=""
if is_root && have dmidecode; then
  DMI_MEM=$(run_to 10 dmidecode -t memory 2>/dev/null)
  DMI_ARRAY=$(run_to 10 dmidecode -t 16 2>/dev/null)
fi
```

then in the Memory section:

```bash
if [ -n "$DMI_MEM" ]; then
  SLOTS=$(printf '%s\n' "$DMI_MEM" | grep -c '^Memory Device$')
  FILLED=$(printf '%s\n' "$DMI_MEM" | awk '/^\tSize:/ && $2 != "No" {c++} END{print c+0}')
  kv "DIMM slots (filled / total)" "$FILLED / $SLOTS"
  MAXCAP=$(printf '%s\n' "$DMI_ARRAY" | awk -F: '/Maximum Capacity/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
  kv "Max supported" "${MAXCAP:-}"
fi
echo

if [ -n "$DMI_MEM" ]; then
  # Emit at the record boundary and in END, not on the Part Number line: a DIMM
  # whose SMBIOS record omits Part Number was previously dropped from the table
  # while still counting toward FILLED above, so the two silently disagreed.
  MODLINES=$(printf '%s\n' "$DMI_MEM" | awk -v na="$NA" '
    function flush() {
      if (loc == "" || size ~ /^No/) return
      printf "| %s | %s | %s | %s | %s |\n",
        (loc==""?na:loc), (size==""?na:size), (sp==""?na:sp),
        (mf==""?na:mf), (pn==""?na:pn)
    }
    /^Memory Device$/ { flush(); loc="";size="";sp="";pn="";mf=""; next }
    /^\tLocator:/       { sub(/^\tLocator:[ \t]*/,"");       loc=$0 }
    /^\tSize:/          { sub(/^\tSize:[ \t]*/,"");          size=$0 }
    /^\tSpeed:/ && sp=="" { sub(/^\tSpeed:[ \t]*/,"");       sp=$0 }
    /^\tManufacturer:/  { sub(/^\tManufacturer:[ \t]*/,"");  mf=$0 }
    /^\tPart Number:/   { sub(/^\tPart Number:[ \t]*/,"");   pn=$0 }
    END { flush() }
  ')
  if [ -n "$MODLINES" ]; then
    printf '#### Installed DIMMs\n\n| Slot | Size | Speed | Vendor | Part number |\n|---|---|---|---|---|\n%s\n\n' "$MODLINES"
  fi
fi
```

Note the sentinel is now passed in with `-v na="$NA"` rather than hardcoded, which is the same fix F-017 needs in the Unraid awk at lines 402–413.

**Risk:** Low. The `flush()` restructure changes which line triggers emission, so the row count can legitimately *increase* on hardware where a DIMM lacked a Part Number — that is the fix, not a regression. Verify against known hardware before rolling out.

**Verification:**
```bash
# Row count must now equal the FILLED count, which it previously might not
sudo dmidecode -t memory | grep -c '^Memory Device$'                      # total slots
sudo dmidecode -t memory | awk '/^\tSize:/ && $2 != "No"{c++} END{print c+0}'  # filled
sudo bash hw-inventory.sh | awk '/#### Installed DIMMs/,/^$/' | grep -c '^| /*[A-Za-z]'
# The third number must equal the second

# Confirm dmidecode now runs twice, not nine times
sudo strace -f -e trace=execve bash hw-inventory.sh 2>&1 >/dev/null \
  | grep -c 'dmidecode'
```

---

### R-5 — Fork-free `lsblk -P` parsing
**Fixes:** F-013 [LOW], and contributes to F-012 [MEDIUM]
**Rationale:** Performance and readability. `fld()` forks `printf` plus `sed` per field — 12 processes per disk, 288 on a 24-bay chassis — to do string splitting bash can do natively. The replacement is also easier to read than the escaped `sed` expression.

**Caveat, stated up front:** this uses an associative array and therefore **raises the minimum bash version from 3.2 to 4.2**. Every current Linux distribution ships bash 5.x, but if any target host is genuinely ancient, take R-1 through R-4 and leave this one.

**Before** (lines 231–242):

```bash
  fld() { printf '%s' "$2" | sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"; }
  $TMO lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,MODEL,SERIAL 2>/dev/null \
    | grep -Ev 'NAME="(loop|ram|zram|sr)[0-9]*"' \
    | while IFS= read -r line; do
        name=$(fld NAME "$line");   [ -z "$name" ] && continue
        size=$(fld SIZE "$line");   rota=$(fld ROTA "$line")
        tran=$(fld TRAN "$line");   model=$(fld MODEL "$line")
        serial=$(fld SERIAL "$line")
        case "$rota" in 1) kind="HDD";; 0) kind="SSD/NVMe";; *) kind="$NA";; esac
        printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
          "$name" "${size:-$NA}" "${model:-$NA}" "${serial:-$NA}" "$kind" "${tran:-$NA}"
      done
```

**After** — define with the other helpers at the top of the file:

```bash
# Parse one lsblk -P line (KEY="value" KEY="value" ...) into the global F.
# -P is used rather than columnar output because columnar collapses empty
# MODEL/SERIAL fields and silently shifts every later column. Splitting here
# in bash rather than with sed saves two forks per field: on a 24-bay chassis
# that is 288 processes.
lsblk_fields() {
  local line=$1 key val
  declare -gA F=()
  while [ -n "$line" ]; do
    key=${line%%=*}; key=${key## }
    line=${line#*=\"}
    val=${line%%\"*}
    line=${line#*\"}
    F[$key]=$val
  done
}
```

and in the storage section:

```bash
  # TYPE is now requested and filtered on, matching the DISKS query at line 91.
  # Without it, top-level md* and dm-* devices appear in a table headed
  # "physical devices" with empty model and serial.
  run_to 10 lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,TYPE,MODEL,SERIAL 2>/dev/null \
    | while IFS= read -r line; do
        lsblk_fields "$line"
        [ "${F[TYPE]:-}" = "disk" ] || continue
        case "${F[NAME]:-}" in loop*|ram*|zram*|sr*) continue;; esac
        case "${F[ROTA]:-}" in
          1) kind="HDD";;
          0) kind="SSD/NVMe";;
          *) kind="";;
        esac
        printf '| /dev/%s | %s | %s | %s | %s | %s |\n' \
          "$(md "${F[NAME]:-}")"   "$(md "${F[SIZE]:-}")" \
          "$(md "${F[MODEL]:-}")"  "$(md "${F[SERIAL]:-}")" \
          "$(md "$kind")"          "$(md "${F[TRAN]:-}")"
      done
```

The device-exclusion pattern is now a `case` on the name rather than a `grep -Ev` against the raw `NAME="..."` text, which removes the second syntax of the duplicated filter noted in §4. Combined with the `TYPE` filter, this table and `DISKS` can no longer disagree.

**Risk:** Low-to-medium. The `while` loop still runs in a subshell (it is on the right of a pipe), so `F` does not leak — but it also means `F` cannot be read after the loop, which nothing does. The parser assumes `lsblk -P`'s exact `KEY="value"` grammar; a value containing an escaped quote would break it, as it would break the `sed` version. Test against `lsblk -P` output from every disk type you actually run.

**Verification:**
```bash
# 1. Unit-test the parser against real and adversarial fixtures
lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,TYPE,MODEL,SERIAL > /tmp/lsblk.fixture
while IFS= read -r l; do lsblk_fields "$l"; echo "${F[NAME]}|${F[MODEL]}|${F[SERIAL]}"; done < /tmp/lsblk.fixture

# 2. Empty MODEL must not shift columns — the exact bug -P exists to avoid
lsblk_fields 'NAME="nvme0n1" SIZE="931.5G" ROTA="0" TRAN="nvme" TYPE="disk" MODEL="" SERIAL="S4EW"'
echo "${F[NAME]} / '${F[MODEL]}' / ${F[SERIAL]}"   # expect: nvme0n1 / '' / S4EW

# 3. md* and dm* must no longer appear
sudo bash hw-inventory.sh | awk '/### Storage — physical devices/,/^$/' | grep -E '/dev/(md|dm-)'
# expect: no output

# 4. Fork count
sudo strace -f -e trace=execve bash hw-inventory.sh 2>&1 >/dev/null | grep -c '/sed'
```

---

## 13. Prioritized Action List

| ID | Risk | Line(s) | Issue | Recommended fix | Effort |
|---|---|---|---|---|---|
| F-001 | HIGH | 20, 70, 72, 75, 150–151, 160–163, 199–200 | No locale pinning; translated `lscpu`/`free` labels silently empty CPU topology, RAM and swap | `export LC_ALL=C` after line 20 (R-1) | **S** |
| F-003 | HIGH | 260, 286, 288, 313, 316, 319, 324, 327, 346, 474, 476, 534, 539, 544, 547, 555, 565, 574, 577, 579, 598, 601, 603, 618, 632 | 25 hardcoded `timeout N` bypass the `$TMO` fallback; without `timeout`, five sections blank silently | `run_to` helper at all 48 sites (R-1) | **M** |
| F-004 | MEDIUM | 30, 240–241, 444–446, 586, 607, 633 | Markdown table cells unescaped; a `\|` corrupts the table | `md()` escaper (R-2) | **M** |
| F-009 | MEDIUM | 191–195 | `/proc/cmdline` verbatim; may contain LUKS keyfile paths, iSCSI credentials. CWE-532 | `sed` filter before emitting | **S** |
| F-010 | MEDIUM | 70, 75, 150–151, 158, 199–200, 202–203, 205, 211, 286, 288, 385–393 | `dmidecode -t memory` ×3, `lscpu` ×2, `free` ×4, `smartctl --scan` ×2, `uval` ×8 | Capture once in gather phase (R-4) | **M** |
| F-012 | MEDIUM | 232–233 vs 91–92 | "Physical devices" table lacks the `TYPE=="disk"` filter; `md*`/`dm-*` appear | Add `TYPE` to `-o` and filter (R-5) | **S** |
| F-014 | MEDIUM | 288, 313, 316, 319, 324, 328–329, 464, 469, 481, 522, 535, 541, 544, 547, 556, 565, 618, 628, 631, 642 | 22 `head -N` limits, 13 magic values, no truncation marker | Named `readonly` constants + a marker when the limit is hit | **M** |
| F-015 | MEDIUM | 257–284, 345–352 | Unbounded aggregate runtime; megaraid probe alone can burn ~60 s silently | `timeout 3`, miss threshold 4, gate behind `--deep`, progress to stderr | **M** |
| F-020 | MEDIUM | 554–558 | `racadm` block not root-gated and has no `###` heading; output misattributed to the previous section | Gate on `is_root`, add heading, whitelist-filter | **S** |
| F-023 | MEDIUM | 631–634 | N+1: up to 100 serial `docker inspect` calls, 500 s ceiling | One `docker inspect` over all containers | **S** |
| F-025 | MEDIUM | 82 sites; esp. 313–329, 464–486, 519, 574, 598 | Blanket stderr suppression, no debug mode; broken host and bare host look identical | `warn()` + `emit_warnings()` + `HWINV_DEBUG` (R-3) | **L** |
| F-026 | MEDIUM | 651 | Always exits 0; callers cannot detect an incomplete report | `exit 1` when warnings exist (R-3) | **S** |
| F-030 | MEDIUM | 141–142 | Declared stable/volatile split is not achievable; volatile data spans six later sections | Correct the comment now; consider `--stable-only` later | **S** (comment) / **L** (structural) |
| F-031 | MEDIUM | 48–651 | One ~630-line `main`, ~190 decision points, no section selection or per-section timing | Extract `section_*()` functions + a `SECTIONS` array | **L** |
| F-035 | MEDIUM | 231, 385, 443, 570 | Four of nine helpers defined mid-file, conditionally, under generic names | Hoist to the helper block at 22–46 | **S** |
| F-002 | LOW | 27–28, 43, +21 sites | `TMO` is a splitting string, not an array; breaks if anyone "fixes" the quoting | `TMO=()` array (R-1) | **S** |
| F-005 | LOW | 54–58 | Sourcing `/etc/os-release` executes it as root | `osr()` awk parse (R-1) | **S** |
| F-007 | LOW | 106, 114 | Two `date` calls can straddle midnight; no timezone in the frontmatter date | Capture once; use `date -u +%FT%TZ` | **S** |
| F-008 | LOW | 177–178 | `ls -A` / `ls \| wc -l` (SC2012) | Glob into an array | **S** |
| F-011 | LOW | 217–218 | DIMM without a `Part Number` line silently dropped, while still counted in `FILLED` | Emit at record boundary + `END` (R-4) | **S** |
| F-013 | LOW | 231–238 | `fld()` forks 12 processes per disk | Bash-native parse (R-5) | **M** |
| F-016 | LOW | 338–342 | MegaRAID probe target is "first non-NVMe disk", possibly a USB stick | Select via `/sys/class/scsi_host/*/proc_name` | **M** |
| F-017 | LOW | 23 vs 402, 406, 411–413 | `NA` sentinel duplicated as a literal em dash inside awk | Pass with `awk -v na="$NA"` | **S** |
| F-018 | LOW | 440–447 | `g()` redefined per iteration, closes over `$f` implicitly | Define once, take the file as `$2` | **S** |
| F-021 | LOW | 570, 576–588, 600–609 | `cfgget()` silently depends on the global `$CFG` | Pass the config text as an argument | **S** |
| F-022 | LOW | 586, 607 | `— MiB` / bare ` MiB` when memory is unset | `${mem:+$mem MiB}` (R-2) | **S** |
| F-024 | LOW | 257, 339, 345, 576, 600 | Word-splitting `for` lists rather than arrays | `mapfile -t` | **S** |
| F-027 | LOW | none (absent) | No INT/TERM trap; interrupted run leaves an unmarked truncated document | 3-line trap (R-3) | **S** |
| F-028 | MEDIUM | 16, and output generally | Output contains service tag, disk serials, MACs, BMC IP; no handling guidance. CWE-532 | Add `umask 077` guidance to the usage block | **S** |
| F-029 | LOW | none (absent) | No argument parsing; `--help` prints a full report | `getopts` with `--help`, `--version`, `--skip` | **M** |
| F-034 | LOW | 503 | `[ "$spd" -gt 0 ] 2>/dev/null` works by suppressing an error rather than checking a precondition | `[[ $spd =~ ^[0-9]+$ ]] && (( spd > 0 ))` | **S** |
| F-006 | NITPICK | 55–57 | `# shellcheck disable=SC1091` covers only line 56; line 57 still flagged | Moot after F-005 | **S** |
| F-019 | NITPICK | 455 | `kv2` reads as a variant of the `kv()` function | Rename to `IDENT` | **S** |
| F-032 | NITPICK | 46, +8 call sites | `is_root` forks `id -u` 8 times | `${EUID:-$(id -u)}` | **S** |
| F-033 | NITPICK | 170–171 | `grep -qm1 ' vmx'` not right-anchored; reads cpuinfo twice | `grep -qm1 -E '(^\| )vmx( \|$)'` | **S** |

**CRITICAL: None.** No finding in this review can cause data loss, security compromise, or silent corruption of anything outside the generated document. That is a property of the architecture, not luck.

Counts: 0 CRITICAL, 2 HIGH, 14 MEDIUM, 15 LOW, 4 NITPICK.

---

## 14. Engineering Scorecard

### Architecture — 3/5

The conceptual model is right: independent, capability-gated collectors that degrade individually, with a minimal gather phase forced by frontmatter ordering (lines 48–92). Gating is applied consistently across all fifteen sections, and the read-only constraint is preserved at every boundary where breaking it would have been convenient (lines 296–297, 335–336, 377–379, 527–530). The mechanical structure has not kept up with the conceptual one: the collectors are comment-delimited regions of a 630-line top-level scope (48–651) rather than functions, so nothing can be selected, skipped, timed or tested independently — which is what blocks fixes for F-015 and F-030.

**What a 5 looks like here:** each section is a `section_<name>()` function; a `SECTIONS=(...)` array drives a dispatch loop; `--only` and `--skip` select from it; per-section elapsed time is available under `HWINV_DEBUG`; and the stable/volatile distinction promised at 141–142 is expressed in the structure rather than in a comment.

### Readability & Maintainability — 4/5

Comments explain *why* at every non-obvious decision (4–13, 229–230, 249–250, 258–259, 296–297, 335–336, 377–379, 515–516, 527–530) and I found none that were misleading or redundant. Naming is consistent, no function exceeds ten lines, and there is no dead code. Docked for four of nine helpers being defined mid-file under generic names (231, 385, 443, 570), 22 unnamed `head -N` limits, the `uval`/`g` duplication (385, 443), and line 586 at 219 characters.

**What a 5 looks like:** all helpers in one block at the top; a `readonly` constants section holding every limit and timeout; the `uval`/`g` awk written once and parameterised; line 586 built through an array.

### Safety — 5/5

The read-only claim survives a line-by-line audit. No `>`, `>>`, `tee`, `rm`, `mv`, `cp`, `mkdir`, `touch`, `mktemp`, `dd` or `sed -i` appears anywhere. The two hardest cases are handled rather than excused: Unraid state read from `.ini` rather than `mdcmd` (377–379), and SMART queried with `-n standby` (260, 346) so a sleeping drive is reported rather than woken. Vendor CLIs are `show`-only, MegaCLI carries `-NoLog`, and the script explicitly declines to `modprobe` (527–530). There is no partial-failure state because there is no state. Re-runs and concurrent runs are safe by construction.

**What a 5 looks like:** this. The only refinement I would suggest is verifying S-1 — whether `-n standby` is honoured through a MegaRAID controller — and documenting the answer.

### Error Handling — 2/5

`set -e` and `pipefail` are correctly omitted with reasoning that holds up (§5), and the SMART block at 260–265 is a genuinely well-handled three-way outcome. But `2>/dev/null` appears 82 times with no way to disable it, the script always exits 0 (651), 22 truncation points are unmarked, and ten distinct silent-failure paths (§6) produce reports that look complete and are not. ShellCheck's `check-extra-masked-returns` finds 107 discarded exit statuses. The five explanatory notices (136, 245, 332, 493, 551) and the `None.` branch at 647 prove the author knows the right pattern — it is applied in six places out of dozens.

**What a 5 looks like:** every section that attempts collection and gets nothing appends to a warnings list; the report ends with a `Collection warnings` block; `HWINV_DEBUG=1` passes stderr through; the exit code distinguishes complete from partial; and an INT/TERM trap marks truncation.

### Security — 3/5

No `eval`, no injection surface, no hardcoded secrets, no secrets in `argv`, no temp files (which eliminates the symlink-attack class by construction), and no `curl | sh`. IPMI credentials are filtered with a blacklist *and* a whitelist (539–541), and the Unraid `csrf_token` is excluded by a deliberate key whitelist whose reason is written down (378–379). Held at 3 by two gaps in that same policy: `/proc/cmdline` emitted verbatim (191–195, CWE-532) and no guidance on handling a document containing the service tag, every disk serial, every MAC and the BMC address (F-028). The un-gated `racadm` block (554) is a third, smaller inconsistency.

**What a 5 looks like:** one redaction function applied to every emitted block rather than per-section filters; `/proc/cmdline` passed through it; a `# Output is sensitive — umask 077` line in the usage block; `racadm` gated and whitelisted the way `ipmitool` already is.

### Performance — 3/5

Every blocking call is wrapped in a timeout, which is the important thing and is done deliberately (25–26). The `lscpu` capture at 158 and the `DISKS` capture at 91 show the author knows to avoid re-invocation. But `dmidecode -t memory` runs three times (202, 203, 211), `free` four times, `smartctl --scan` twice (286, 288), `uval` re-parses `var.ini` eight times (386–393), `fld()` forks 12 processes per disk, and `docker inspect` is called once per container (632) — an estimated ~450 process spawns on a modest host and 1,500–2,000 on a large one. The megaraid probe (345–352) has a ~60 s silent worst case.

**What a 5 looks like:** each external tool invoked once and cached; `docker inspect` batched; `fld` replaced by bash string operations; the megaraid probe bounded and skippable; and a documented expected runtime range.

### Portability — 2/5

Linux-only is the right scope and every path choice is consistent with it. The score is low because the most damaging portability defect lands on the *primary* platform: no `LC_ALL=C`, so a German or French host silently loses its CPU topology, RAM total and swap figures (F-001). Beyond that: `uname -o` is GNU-only (63), `paste -sd', '` is GNU-flavoured (5 sites), the bash floor of 3.2 is undeclared, and nothing states that macOS and BSD are out of scope despite `#!/usr/bin/env bash` inviting the attempt.

**What a 5 looks like:** `export LC_ALL=C`; an explicit `uname -s` guard with a clear message; a declared bash minimum; a one-line scope statement in the header; and the GNU-specific flags either replaced or documented as requirements.

### Idiomatic Style — 3/5

Strong fundamentals, verified rather than assumed: `command -v` over `which`, `$( )` with not a single backtick substitution, `read -r` at all three read sites, `printf` with literal format strings everywhere (zero SC2059), `--` before `-`-leading format strings at all three sites, globs instead of parsing `ls`, and the unmatched-glob guard at 441. ShellCheck's default ruleset produces zero warnings and zero errors. Docked for `TMO` as a splitting string rather than an array, `for` lists relying on word splitting (257, 339, 576, 600), `local` used in one function out of nine, no `readonly` on constants, and `[ ]` throughout a bash script where `[[ ]]` would have prevented the awkwardness at line 503.

**What a 5 looks like:** arrays wherever a list is meant; `local` in every function that assigns; `readonly` on `NA` and the new limit constants; `[[ ]]` and `(( ))` in bash-only code; and `mapfile -t` instead of word-split `for` lists.

### Overall — 3.3 / 5

Weighted: Safety 20%; Architecture, Readability, Error Handling and Security 15% each; Portability 10%; Performance and Idiomatic Style 5% each.

What the number means in practice: **this is a script I would run on my own production hosts today without hesitation, and would not yet trust the output of without spot-checking.** The safety engineering is genuinely above average — better than most operational tooling I see, and the read-only discipline is enforced rather than merely claimed. The gap is entirely on the reporting side. A document that silently omits the SMART section because `timeout` was missing is more dangerous than one that fails loudly, because it will be filed, diffed, and eventually trusted.

### The single change that would most improve the score

**Add `export LC_ALL=C` on the line after `set -u`.**

One line. It fixes F-001 outright — the highest-risk finding — eliminates a whole class of locale-dependent parse failures across `lscpu`, `free`, `df` and awk's numeric formatting, and it costs nothing and risks nothing.

If the question is instead which change most improves the *engineering*, the answer is R-3: the warnings-plus-exit-code work. That is the change that converts "the report looks fine" into "the report tells you when it isn't," and every other improvement compounds on it.

---

## 15. Testing Recommendations

The script currently has no tests, and the reason is structural rather than negligent: collection and parsing are welded together in every section, so nothing can be exercised without the hardware. The good news is that the *parsing* half is pure text-in/text-out and becomes testable the moment it is split out — which R-4 and R-5 already begin.

### Tooling

**[bats-core](https://github.com/bats-core/bats-core)** — the right choice here. It runs bash directly (so `local`, arrays and `${var//}` behave as they do in the script), fixtures are plain files, and the assertion helpers are adequate. `shellspec` is more expressive and worth considering if the suite grows past ~50 cases; `shunit2` is fine but less actively maintained. Any of the three beats none.

### Fixture strategy

This is the part that matters most and the part most shell test suites skip. Capture real output once, from real hardware, and commit it:

```bash
mkdir -p test/fixtures
sudo dmidecode -t memory       > test/fixtures/dmidecode-memory-4dimm.txt
sudo dmidecode -t memory       > test/fixtures/dmidecode-memory-no-partnum.txt   # hand-edit one record
sudo dmidecode -t 16           > test/fixtures/dmidecode-array.txt
lscpu                          > test/fixtures/lscpu-en.txt
LC_ALL=de_DE.UTF-8 lscpu       > test/fixtures/lscpu-de.txt      # the F-001 regression fixture
free -h                        > test/fixtures/free-en.txt
lsblk -dn -P -o NAME,SIZE,ROTA,TRAN,TYPE,MODEL,SERIAL > test/fixtures/lsblk-p.txt
sudo smartctl -H -A /dev/sda   > test/fixtures/smart-ata.txt
sudo smartctl -H -A /dev/nvme0 > test/fixtures/smart-nvme.txt
sudo smartctl -n standby -H -A /dev/sdb > test/fixtures/smart-standby.txt
cp /var/local/emhttp/disks.ini test/fixtures/unraid-disks.ini   # scrub serials first
pct config 100                 > test/fixtures/pct-config.txt
```

The `lscpu-de.txt` fixture is the one that would have caught F-001 and is worth capturing even if nobody on the team runs a German locale.

### Test cases that would have caught the findings above

| Finding | Test |
|---|---|
| F-001 | Parse `lscpu-de.txt`; assert the CPU model is non-empty. **Fails on the current code.** |
| F-003 | Run the whole script with `PATH` stripped of `timeout`; assert the SMART section heading is present and the table has ≥1 data row. **Fails today.** |
| F-004 | Feed `md`/`kv` a value containing `\|`; assert the rendered row has exactly the expected field count. |
| F-011 | Parse `dmidecode-memory-no-partnum.txt`; assert the emitted row count equals the `FILLED` count. **Fails today.** |
| F-012 | Feed a fixture containing `TYPE="raid1"`; assert no `/dev/md` row is emitted. **Fails today.** |
| F-022 | Feed a `pct config` fixture with no `memory:` key; assert the cell is `NA`, not `— MiB`. |
| F-026 | Run against a fixture host where a section fails; assert exit status 1 and the presence of a `Collection warnings` section. |
| F-027 | Send SIGINT mid-run; assert the output ends with the truncation marker. |
| — | **Golden-file test:** run against a full fixture set, diff against a committed `expected.md` with the timestamp lines filtered. This is the highest-value single test — it catches formatting regressions across every section at once. |
| — | **Markdown validity:** for every table in the output, assert every row has the same pipe count as its header. Catches F-004 generically, including from sources nobody thought to fixture. |

### Example bats file

```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parse.sh"   # the extracted parsing helpers
  FIX="${BATS_TEST_DIRNAME}/fixtures"
}

@test "F-001: CPU model parses under a German locale" {
  run parse_cpu_model "$(cat "$FIX/lscpu-de.txt")"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "F-011: every populated DIMM slot produces a row" {
  filled=$(awk '/^\tSize:/ && $2 != "No"{c++} END{print c+0}' "$FIX/dmidecode-memory-no-partnum.txt")
  run parse_dimms "$(cat "$FIX/dmidecode-memory-no-partnum.txt")"
  [ "$(printf '%s\n' "$output" | grep -c '^|')" -eq "$filled" ]
}

@test "F-004: a pipe in a value does not break the table" {
  run kv "Model" 'Sea|gate ST8000'
  [ "$(printf '%s' "$output" | tr -cd '|' | wc -c)" -eq 3 ]
}

@test "F-012: md/dm devices are excluded from physical disks" {
  run parse_lsblk 'NAME="md0" SIZE="16T" ROTA="1" TRAN="" TYPE="raid1" MODEL="" SERIAL=""'
  [ -z "$output" ]
}

@test "golden: full report matches expected output" {
  run env HWINV_FIXTURE_DIR="$FIX" bash "${BATS_TEST_DIRNAME}/../hw-inventory.sh"
  diff <(printf '%s\n' "$output" | grep -vE '^(> Collected|collected:)') \
       <(grep -vE '^(> Collected|collected:)' "$FIX/expected.md")
}
```

### What to add to CI

```yaml
name: hw-inventory
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: shellcheck --severity=warning --shell=bash hw-inventory.sh
      - run: bash -n hw-inventory.sh
      - run: shfmt -d -i 2 -ci hw-inventory.sh
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get install -y bats
      - run: bats test/
  smoke:
    strategy:
      matrix:
        image: [ubuntu:24.04, debian:12, alpine:3.20]
    runs-on: ubuntu-latest
    container: ${{ matrix.image }}
    steps:
      - uses: actions/checkout@v4
      - run: apk add bash || apt-get update && apt-get install -y bash
      - run: bash hw-inventory.sh > /tmp/report.md
      - run: grep -q '^## ' /tmp/report.md    # produced a document
      - run: awk -F'|' '/^\| /{if(NF!=p&&p)exit 1; p=NF}' /tmp/report.md  # tables well-formed
```

The `smoke` job is worth more than it looks. It runs the script in three deliberately impoverished environments where most tools are missing — which is precisely the condition under which F-003 and F-025 manifest — and asserts only that a structurally valid document comes out. That is the cheapest possible regression test for the degradation behaviour that is the whole point of the script's design.

### Sequencing

1. **Lint gate first.** It passes today at `--severity=warning`, so it starts green and stays meaningful.
2. **Smoke job second.** No refactoring required; catches the degradation regressions immediately.
3. **Extract parsing helpers into `lib/parse.sh`** as part of R-4 and R-5, then add unit tests against fixtures.
4. **Golden-file test last**, once the output format has stopped moving.

---

*End of review. 35 findings: 0 CRITICAL, 2 HIGH, 14 MEDIUM, 15 LOW, 4 NITPICK.*
