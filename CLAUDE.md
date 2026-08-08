# Maintainer notes for `hw-inventory.sh`

Read this before proposing any change. It records decisions already made and the
reasoning behind them, so they don't get relitigated each session.

---

## The one inviolable rule

**This script is read-only. Every command must be a query.**

Not "read-only by default." Not "read-only unless the user asks." A change that
introduces a write is rejected regardless of how useful the data would be.

If a feature appears to require a write, the answer is to find the read-only path or to
leave the data uncollected. The worked example is Unraid array state: `mdcmd status` is
the obvious call, but it works by writing a command string into `/proc/mdcmd`, so the
script parses emhttp's `.ini` files instead. Same data, no write.

Banned regardless of context: `smartctl -t`, `mdcmd`, `zpool scrub/import/export/create`,
`btrfs balance/scrub/device`, `docker run/exec/rm/pull`, `pct`/`qm` start/stop/set/destroy,
`modprobe`, `mount`/`umount`, any package manager, any write verb on `perccli`/`storcli`/
`megacli`, and `ipmitool chassis`/`sel clear`/`mc reset`/`raw`.

When adding a vendor CLI, allow only `show`-class verbs and say so in a comment.

---

## Rejected proposals — do not re-suggest

These have been evaluated and declined with reasons. Reopening one requires new evidence,
not a fresh opinion.

### `set -o pipefail` — rejected

24 pipelines terminate in `head -N`. `head` exits after N lines, upstream receives
SIGPIPE, and under `pipefail` that surfaces as exit 141. Measured:

```
with pipefail:    exit=141
without pipefail: exit=0
```

Adding `pipefail` would make nearly every pipeline in the file report failure. It is also
directly incompatible with the planned exit-code contract (see Tier 1 below).

### `set -e` / `set -eE` — rejected

This is a best-effort collector. Most commands are *expected* to fail: `dmidecode`
without root, `zpool` on a non-ZFS box, `pct` off a Proxmox host. `set -e` aborts on the
first absent tool and truncates the report. The `have` / `$TMO` / `|| true` combination
handles those cases explicitly instead. `set -u` alone is correct and intentional.

### Removing brace expansion `{0..31}` — rejected

Line 1 declares `#!/usr/bin/env bash`. Numeric brace ranges have worked since bash 3.0
(2004). Swapping to `seq` adds a coreutils dependency to remove a bash dependency from a
bash script. POSIX `sh` support is not a goal.

### Converting whitespace-split lists to arrays for safety — rejected as a priority

Device names from `lsblk` and VMIDs from `pct list` are whitespace-free by construction.
Harmless to do, but it is not a correctness fix and should not be sold as one.

### Splitting the file into `section_*()` functions — deferred, not rejected

Real improvement, but it restructures a working one-shot reporter. Not worth the churn
until there's an actual need for `--skip` / section selection.

---

## Agreed work queue

Ordered. Tier 1 affects whether the report can be trusted; Tier 2 is cheap hygiene.

### Tier 1 — trustworthiness of the artifact

1. **Warning accumulator + meaningful exit code** (F-025, F-026). Sections that produce
   nothing append to a warnings list; the script emits a `## Collection warnings` block
   and exits non-zero. Today, a systemically broken host and a bare host produce
   identical-looking output — and this report is consumed as ground truth, so a silently
   empty section doesn't produce no answer, it produces a confident wrong one. Highest
   priority for that reason. Note this changes the caller contract; nothing wraps the
   script today, but make the change deliberately.
2. **Route all 26 hardcoded `timeout N` sites through `$TMO`** (F-003). A fallback was
   built at line 28 for systems lacking coreutils `timeout`, then bypassed everywhere.
   Making `TMO` an array is the clean fix.
3. **Filter the physical-devices table on `TYPE=="disk"`** (F-012). It currently only
   excludes `loop|ram|zram|sr` by name, so `md*`, `dm-*` and — worst — ZFS zvols appear
   as phantom physical drives. On a Proxmox host with `local-zfs`, every VM disk becomes
   a `/dev/zdN` row *and* gets its own wasted `smartctl` probe. Not yet verified against
   real zvols; confirm before and after.

### Tier 2 — cheap and clearly correct

- `export LC_ALL=C` after `set -u` (F-001). Verified not to mangle the em-dash sentinel
  or awk's `%.2f`.
- Gate `racadm` on `is_root` and give it a real `###` heading (F-020).
- Replace the N+1 `docker inspect` loop with one call over all containers (F-023).
- Emit DIMM rows at record boundary so a module with no Part Number isn't dropped (F-011).
- Named constants for the 22 `head -N` limits, plus a marker when a limit is hit (F-014).
  This bug class has now recurred three times; fix the pattern, not the instance.
- Filter `/proc/cmdline` for `rd.luks.key` and similar before emitting (F-009).

---

## Testing requirements

**Errors are already handled; hangs are the real risk.** Every genuine bug found in this
project so far has been a hang, not an error — three static code reviews missed the one
real defect because none of them ran the script.

Before any PR:

1. **Hostile test.** Put stubs on `PATH` that exit non-zero, and at least one that
   `sleep`s. The script must complete, reach its footer, and exit promptly.
2. **Clean test.** On an ordinary machine with no RAID, BMC or hypervisor, confirm zero
   stderr and no empty table headers.
3. **Mock fixtures** for hardware you don't have. Unraid `disks.ini`/`var.ini`, `pct`/`qm`
   config output, and a `smartctl` that answers on sparse `megaraid,N` IDs have all been
   used successfully.
4. `bash -n` and ShellCheck. Current baseline: **zero errors, zero warnings** on the
   default ruleset (24 findings, all severity `note`; the `SC2016` hits are false
   positives from single-quoted awk programs). Do not regress this.

---

## Conventions

- Comments explain **why**, not what. The `lsblk -P` comment exists specifically so a
  future maintainer doesn't "simplify" it back into a column-shift bug. Keep that habit.
- Guard every external tool with `have`, a timeout, and `2>/dev/null`.
- Whitelist keys when parsing config files rather than dumping them. Unraid's `var.ini`
  contains a `csrf_token`; `ipmitool lan print` contains an SNMP community string. Both
  are filtered deliberately — extend that policy, don't work around it.
- Serials, MACs and IPs **are** emitted on purpose; that's the point of an inventory.
  Secrets are not. The line is "identifying" vs "authenticating."
- Section output is captured to a variable and printed only if non-empty, so absent
  hardware never leaves a bare table header.
