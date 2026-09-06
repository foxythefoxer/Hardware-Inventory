# Maintainer notes for `hw-inventory.sh`

Read this before proposing any change. It states the rules this script is built on and
the verdict on every proposal already adjudicated, so they don't get relitigated each
session.

The verdicts here are one line each. The reasoning behind them — measurements, binding
conditions, what was checked against a real host — lives in
[`docs/DISPOSITIONS.md`](docs/DISPOSITIONS.md) under the same IDs: `C-`/`G-`/`O-` for the
three code reviews in `docs/reviews/`, `FR-` for a request submitted from outside the
review cycle, via the vault's Dev Projects Feature Request Log. **A new adjudication,
accepted or rejected, is written out there and indexed here in one line — never written
at length in both files.** This file is loaded into every session; the ledger is opened
when the reasoning is actually wanted, which is why the long form belongs in it.

---

## The one inviolable rule

**This script is read-only. Every command must be a query.**

Not "read-only by default." Not "read-only unless the user asks." A change that
introduces a write is rejected regardless of how useful the data would be.

If a feature appears to require a write, the answer is to find the read-only path or to
leave the data uncollected. The worked example is Unraid array state: `mdcmd status` is
the obvious call, but it works by writing a command string into `/proc/mdcmd`, so the
script parses emhttp's `.ini` files instead. Same data, no write.

This is the design's whole point, not just a safety property incidental to it: the
script was built read-only from the start so it could eventually run unattended — a
cron job, a scheduled sweep — without a human confirming each run against production
hosts first. A write-capable script would need that human in the loop every time; this
one doesn't, by construction. Any change that introduces a write doesn't just add risk,
it breaks the reason the script can be automated at all.

Banned regardless of context: `smartctl -t`, `mdcmd`, `zpool scrub/import/export/create`,
`btrfs balance/scrub/device`, `docker run/exec/rm/pull`, `pct`/`qm` start/stop/set/destroy,
`modprobe`, `mount`/`umount`, any package manager, any write verb on `perccli`/`storcli`/
`megacli`, and `ipmitool chassis`/`sel clear`/`mc reset`/`raw`.

**The ban covers the tool's config, not just its verb.** A banned-verb list can only
describe commands this script writes; it cannot see a tool whose behaviour is defined by
a file on the host. Worked example, measured: `fastfetch` auto-loads `config.jsonc` from
five search paths — `/etc/fastfetch/` among them — and its `command` module runs an
arbitrary shell string, so a bare `fastfetch` with no flags created a file on this host,
and would do it as root under the documented `sudo` invocation (FR-003). Before adding
any dependency, ask what it reads at startup and whether that can execute. A flag that
suppresses it (`-c none` does) is not sufficient on its own: it moves the read-only
guarantee from this script's source into a third party's release notes.

When adding a vendor CLI, allow only `show`-class verbs and say so in a comment.

---

## The exit-code contract

Since C-025/C-026 the script exits `0` when collection is complete and `1` when it is
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

Evaluated and declined. Reopening one requires new evidence, not a fresh opinion. Below
is the verdict and the single fact that settles it; the measurements and the full
argument are in the ledger under the same ID.

- **`set -o pipefail`** (G-003, O). Would break the script. 23 pipelines end in
  `head -N`, which exits early and SIGPIPEs upstream: measured exit `141` with it, `0`
  without. Also incompatible with the exit-code contract above — you cannot have both a
  meaningful exit code and a `pipefail` that reports failure on every successful
  pipeline.
- **`set -e` / `set -eE`** (O). This is a best-effort collector and most commands are
  *expected* to fail (`dmidecode` unprivileged, `zpool` off ZFS, `pct` off Proxmox), so
  it truncates the report at the first absent tool. `have` / `$TMO` / `|| true` handle
  those explicitly. `set -u` alone is deliberate.
- **Removing brace expansion `{0..31}`** (G-001). Line 1 declares `bash`; numeric ranges
  have worked since bash 3.0 (2004). `seq` would add a coreutils dependency to remove a
  bash dependency from a bash script.
- **Converting whitespace-split lists to arrays** (O-001) — rejected as a *priority*, not
  as an edit. Device names from `lsblk` and VMIDs from `pct list` are whitespace-free by
  construction. Harmless to do; not a correctness fix, and not to be sold as one.
- **A `fastfetch` cross-check** (FR-003, issue #1). Two facts settle it. It breaks the
  read-only rule invisibly — a bare `fastfetch` executes `command` modules out of the
  host's `config.jsonc`, verified by watching it create a file. And it is not a second
  source: its `MemTotal` is byte-identical to `/proc/meminfo`, its OS fields come from
  `/etc/os-release`, its model from the same SMBIOS table `dmidecode` decodes. **A tool
  that reads the same file is not a second opinion** — apply that to the next
  cross-check proposal (`neofetch`, `inxi`, `hwinfo`) without re-measuring. The real gap
  it surfaced is FR-004.
- **Splitting the file into `section_*()` functions** (C-031) — deferred, not rejected.
  Real improvement, but it restructures a working one-shot reporter; not worth the churn
  until `--skip` / section selection is actually wanted.

---

## Agreed work queue

### Remaining

- **C-016** — the megaraid probe targets the first non-NVMe disk, which on Unraid is
  often the USB boot device.
- **C-004** (LOW) — escape `|` in Markdown table cells. Most pipe-bearing output already
  sits inside code fences.
- **C-005** — `/etc/os-release` is sourced, which executes it as root.
- **FR-001** — monitor detection via DRM EDID. Accepted with **four binding conditions**
  (never `warn`; gate on bytes read rather than file size; exclude `*-Writeback-*`;
  `ddcutil` stays banned because DDC/CI writes to the monitor).
- **FR-002** — UPS data-connection detection. Accepted with changes, the load-bearing one
  being that the primary signal is a sysfs read of `idVendor` rather than `lsusb`, and
  that `/sys/class/power_supply` cannot be the gate.
- **FR-004** — fill manufacturer/model/motherboard/BIOS from `/sys/devices/virtual/dmi/id/`
  when `dmidecode` is absent or unprivileged; those files are world-readable while
  serials are not. Today an unprivileged run emits `model: null` with the value sitting
  in a readable file. Accepted with **four conditions** (serials stay root-gated; skip it
  inside containers, which see the *host's* DMI; filter `To Be Filled By O.E.M.`-class
  placeholders; never `warn`).

Read the ledger entry before implementing any of these FRs: for an accepted-with-changes
item the conditions **are** the acceptance. Each was written against a real host, and
FR-004 marks the two conditions that could not be verified here — confirm those on a
Proxmox LXC and a whitebox board rather than shipping them on reasoning alone.

### Done — do not re-implement

Verified against the file and covered by `tests/run.sh` where testable.

- **C-025 / C-026** — warning accumulator and meaningful exit code. The contract above is
  the operative statement of it.
- **C-003** — every hardcoded `timeout N` routed through the `have timeout` gate.
- **C-012** — physical-devices table filtered on `TYPE=="disk"` *plus* a `zd[0-9]` name
  exclusion; the `TYPE` filter alone does not catch zvols, which report `TYPE=disk`.
  Still unverified against real zvols — confirm on a `local-zfs` host.
- **C-014** — named constants for every `head -N` limit, consumed through `cap()`. The
  rules that came out of it are under Conventions below; T10/T11 cover them.
- **C-009** — `/proc/cmdline` redacted by parameter **name** and by **value**, the latter
  for credentials embedded in dracut's `netroot=iscsi:user:pass:...@host` form where the
  name gives nothing away. Covered by T9. The name pass alone missed the embedded form
  for two commits: if you add another redaction, ask first whether the secret can hide in
  a value.
- **C-020** `racadm` root-gated under its own `###` heading · **C-023** one
  `docker inspect` over all containers instead of N+1 · **C-011** DIMM rows emitted at
  the record boundary · **C-001** `export LC_ALL=C` after `set -u`.

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
6. **T10/T11 output caps.** T10 is the general case: a stub over a limit gets the
   `--- truncated ---` marker and nothing past it; a stub under the limit is
   byte-for-byte what a bare `head -N` would have produced, marker included (i.e. not
   included) — this second half is what catches a marker leaking onto an untruncated,
   otherwise-empty-should-stay-empty section. T11 is the CNAMES edge case specifically:
   a marker must never reach `docker inspect`'s argument list, and must land after the
   container-networks table, not inside it. Both were run against deliberately
   reintroduced versions of the bugs they guard against, to confirm they actually fail
   without the fix — a stderr-based first draft of T11 did not, since the script
   correctly runs `docker inspect` under `2>/dev/null` and the test was checking a
   channel the script itself discards.
7. `bash -n` (T1) and ShellCheck (T7, skipped when not installed). Baseline was **zero
   errors, zero warnings** on the default ruleset (24 findings, all severity `note`; the
   `SC2016` hits are false positives from single-quoted awk programs). Do not regress
   this — and note it **still** has not been re-verified since the C-025/C-026 work:
   ShellCheck requires `sudo pacman -S shellcheck` on this host and sudo needs an
   interactive password that isn't available to an agent session. Install it by hand and
   run T7 before trusting the baseline.

Some paths are still only reachable as root (`dmidecode`, SMART, `pct`/`qm`, IPMI).
Where sudo isn't available, simulating `is_root() { true; }` against a copy exercises
the branches; it found the `dmidecode` banner problem noted above. Run the suite with
`sudo bash tests/run.sh` when you can — T6's drive probe skips otherwise.

---

## Conventions

- Comments explain **why**, not what. The `lsblk -P` comment exists specifically so a
  future maintainer doesn't "simplify" it back into a column-shift bug. Keep that habit.
- Guard every external tool with `have`, a timeout, and `2>/dev/null`. The timeout is
  `"${TMO[@]}"`, or `tmo N cmd...` where the 10s default is wrong; both run the command
  unwrapped when `timeout` is absent, which is the entire point of the gate (C-003).
  Never hardcode `timeout N` — that bypasses it.
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
- A `head -N` that can genuinely truncate real output goes through `cap()` with a named
  constant, not a bare number — see the constants block near the top. `cap()` is not
  `warn()`: truncation is real data arriving incomplete, not a collector failing, and it
  never touches `WARNCOUNT` or the exit code. Before piping something through `cap()`,
  check whether its output is later word-split into another command's arguments (as
  `CNAMES` is, into `docker inspect`'s) — an inline marker there becomes a bogus argument
  instead of a footnote. That site reads the full list, caps it with plain `head`, and
  defers its marker to after the block instead.
