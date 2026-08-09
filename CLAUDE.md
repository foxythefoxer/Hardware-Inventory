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

## The exit-code contract

Since F-025/F-026 the script exits `0` when collection is complete and `1` when it is
not, having written the report in full either way and ended it with a
`## Collection warnings` block naming what failed. Callers may rely on this.

**The judgment call, which is the whole feature:** a warning means the tool was
**present, permitted, and still returned nothing.** Silence is for things a host
genuinely lacks.

- Tool not installed → silent. A minimal host is not a broken one.
- Tool needs root and the run is unprivileged → silent. The header already says so.
- Tool present, permitted, no output → `warn`.

Judgments already made here, with the reasoning, so they don't get relitigated:

- **`zpool` and `btrfs` never warn.** `zfsutils` and `btrfs-progs` are routinely
  installed as dependencies on hosts that use neither filesystem, where an empty listing
  is the correct answer. A warning there would fire on ordinary ext4 machines and train
  readers to skip the section. `df`, `findmnt`, `lsblk`, `lscpu` and `ip` *do* warn —
  they describe facts every working host has. Both sites carry a comment saying so.
- **`pvecm` never warns.** `pvecm status` fails on a standalone node that was never
  joined to a cluster, which is a normal Proxmox install.
- **`docker info` failing is the section gate, not a warning.** Installed docker with a
  stopped daemon, or a user outside the `docker` group, is legitimate.
- **An empty `systemctl --failed`, zero containers and zero VMs are healthy**, not
  warnings. Where a tool prints a header even with nothing to report (`pct list`,
  `qm list`), test the raw output for emptiness rather than the parsed row count.
- **Test the thing that actually indicates failure, not just emptiness.** `dmidecode -t
  memory` prints a banner to stdout even when it cannot read `/dev/mem`, so that check
  keys off the `Memory Device` record count. An emptiness test there never fires.

`warn` **must only be called from the main shell.** Pipeline bodies and command
substitutions are subshells and their mutations are lost (G-002) — this is no longer a
theoretical fragility now that a global accumulator exists. The storage and network row
loops capture their pipeline into a variable and test it outside; follow that pattern.

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

### Remaining

- Named constants for the `head -N` limits, plus a marker when a limit is hit (F-014).
  This bug class has now recurred three times; fix the pattern, not the instance. Note
  the count is **23**, not the 22 every review states — verified against the file, and it
  has been 23 since the first commit.
- The megaraid probe targets the first non-NVMe disk, which on Unraid is often the USB
  boot device (F-016).
- Escape `|` in Markdown table cells (C-004, LOW — most pipe-bearing output already sits
  inside code fences).
- `/etc/os-release` is sourced, which executes it as root (C-005).

### Done — do not re-implement

Each was verified against the file and covered by `tests/run.sh` where testable.

- **Warning accumulator + meaningful exit code** (F-025, F-026). See the contract below.
- **All hardcoded `timeout N` sites routed through the `have timeout` gate** (F-003).
  `TMO` is now an array (`"${TMO[@]}"`); a `tmo N cmd...` function covers the sites
  needing a duration other than the 10s default. Both fall back to running the command
  unwrapped when `timeout` is absent, which was the whole point of the original guard.
- **Physical-devices table filtered on `TYPE=="disk"`** (F-012), *plus* a `zd[0-9]` name
  exclusion — the reviewer's `TYPE` filter alone does not catch zvols, which report
  `TYPE=disk`. Still unverified against real zvols; confirm on a `local-zfs` host.
- `export LC_ALL=C` after `set -u` (F-001).
- `racadm` gated on `is_root` with its own `###` heading (F-020).
- One `docker inspect` over all containers instead of N+1 (F-023).
- DIMM rows emitted at record boundary (F-011).
- `/proc/cmdline` redacted two ways (F-009): by parameter **name** matching
  `password|secret|token|key`, and by **value** for credentials embedded inside dracut's
  `netroot=iscsi:user:pass:rev_user:rev_pass@host:...` form, where the parameter name
  gives nothing away. Everything between `iscsi:` and `@` is replaced, CHAP usernames
  included; host, port, LUN and target name are kept. Covered by T9. The name-based pass
  alone missed the embedded form for two commits — if you add another redaction, ask
  first whether the secret can hide in the value.

---

## Testing requirements

**Errors are already handled; hangs are the real risk.** Every genuine bug found in this
project so far has been a hang, not an error — three static code reviews missed the one
real defect because none of them ran the script.

Before any PR: **`bash tests/run.sh`, all passing**, plus a new case for what you
changed. The suite now covers what this section used to ask for by hand:

1. **T3 hostile.** Stubs on `PATH` that exit non-zero, one that `sleep`s. The script
   must complete, reach its footer, and exit `1` — `124` means it hung, which is the
   defect class this test exists for. Do not delete it to make the suite faster.
2. **T2 clean.** Zero stderr, no empty table headers, valid YAML frontmatter, exit `0`.
3. **T4/T5/T6 mock fixtures** for hardware you don't have: Unraid `disks.ini`/`var.ini`,
   `pct`/`qm` config output, and a `smartctl` answering on sparse `megaraid,N` IDs.
4. **T8 warning contract.** Both halves: a present-and-failing tool exits `1` and is
   named; a `PATH` where the tools are merely absent still exits `0` and warns about
   nothing. The second half is the one that catches over-eager warnings.
5. **T9 cmdline redaction.** Also both halves: secrets and CHAP usernames gone, and the
   target name, initiator and `rd.iscsi.firmware` still present. Over-redaction is a real
   failure too — a command line scrubbed of its target is no longer useful as inventory.
6. `bash -n` (T1) and ShellCheck (T7, skipped when not installed). Baseline was **zero
   errors, zero warnings** on the default ruleset (24 findings, all severity `note`; the
   `SC2016` hits are false positives from single-quoted awk programs). Do not regress
   this — and note it has not been re-verified since the F-025/F-026 work, because
   ShellCheck was not installed in that environment.

Some paths are still only reachable as root (`dmidecode`, SMART, `pct`/`qm`, IPMI).
Where sudo isn't available, simulating `is_root() { true; }` against a copy exercises
the branches; it found the `dmidecode` banner problem noted above. Run the suite with
`sudo bash tests/run.sh` when you can — T6's drive probe skips otherwise.

---

## Conventions

- Comments explain **why**, not what. The `lsblk -P` comment exists specifically so a
  future maintainer doesn't "simplify" it back into a column-shift bug. Keep that habit.
- Guard every external tool with `have`, a timeout, and `2>/dev/null`.
- Whitelist keys when parsing config files rather than dumping them. Unraid's `var.ini`
  contains a `csrf_token`; `ipmitool lan print` contains an SNMP community string. Both
  are filtered deliberately — extend that policy, don't work around it.
- Serials, MACs and IPs **are** emitted on purpose; that's the point of an inventory.
  Secrets are not. The line is "identifying" vs "authenticating." Worked example: an
  iSCSI CHAP **username** is redacted, because it is half of a credential pair rather
  than a name for a thing — while the target IQN, host and port beside it are kept. When
  a value is arguably both, ask which side it is doing work on.
- Section output is captured to a variable and printed only if non-empty, so absent
  hardware never leaves a bare table header. Row loops that are pipeline bodies must be
  captured too — both to keep that property and because `warn` cannot run inside one.
- Warning text names the tool and says what is missing as a result, so a reader who
  never opens the script can act on it. "`lsblk` is installed but listed no block
  devices — the storage and SMART sections are empty as a result", not "lsblk failed".
