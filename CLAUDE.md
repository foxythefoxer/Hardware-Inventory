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

These have been evaluated and declined with reasons. Reopening one requires new evidence,
not a fresh opinion.

### `set -o pipefail` — rejected

23 pipelines end in `head -N`; 22 of them terminate there (one, the dmidecode wrapper,
pipes `head`'s output on into `sed`, but still surfaces the same exit code under
`pipefail` — the rightmost non-zero status in the pipeline, not merely the last command's,
is what `pipefail` reports). `head` exits after N lines, upstream receives SIGPIPE, and
under `pipefail` that surfaces as exit 141. Measured:

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

- The megaraid probe targets the first non-NVMe disk, which on Unraid is often the USB
  boot device (C-016).
- Escape `|` in Markdown table cells (C-004, LOW — most pipe-bearing output already sits
  inside code fences).
- `/etc/os-release` is sourced, which executes it as root (C-005).
- **Monitor detection via DRM EDID** (FR-001, accepted with changes). Displays are the
  one category of attached hardware the script cannot see. Read
  `/sys/class/drm/card*-*/edid` — plain sysfs reads, so it works headless and over SSH,
  where `xrandr` needs a session. `ddcutil` stays banned and the reason belongs in a
  comment at the site, not just here: DDC/CI is bidirectional and needs `i2c-dev`, so it
  writes to the monitor. Four conditions came out of checking this against a real host:
  - **It must never `warn`.** A host with no connected display is not a broken host, and
    an LXC has no `/sys/class/drm` at all. Same call as `zpool`/`btrfs`, for the same
    reason — a warning here would fire on every headless server in the estate and train
    readers to skip the section.
  - **Gate on bytes actually read, not on file size.** Every `edid` attribute reports
    `stat -c%s` = 0, including the three connectors on this host that return a full 256
    bytes. A `[ -s ]` test would skip every monitor that is present. This is the
    `dmidecode` banner trap again (see the exit-code contract): test the thing that
    indicates the fact, not emptiness.
  - **Exclude `*-Writeback-*` connectors.** They are virtual encoders, not physical
    outputs — the same class of false row as the zvols that a `TYPE=="disk"` filter alone
    did not catch (C-012).
  - `edid-decode` is a parser and is fine under `have` + `$TMO` + `2>/dev/null`. Where it
    is absent, `strings` over the same bytes still recovers the product name and serial,
    which is enough for inventory. Both were verified against a `VX2768-2KP` on DP-1. The
    panel serial is emitted on purpose: identifying, not authenticating.
- **UPS data-connection detection** (FR-002, accepted with changes). Whether a host can
  actually talk to its UPS is currently knowable only by asking. Three mechanisms exist
  across the estate (apcupsd, UPower, nothing at all), so detection has to be layered
  rather than assume a tool:
  - **The primary signal is a direct sysfs read of `/sys/bus/usb/devices/*/idVendor`, not
    `lsusb`.** Same move as parsing emhttp's `.ini` instead of calling `mdcmd`: the data
    is already in a file, so read the file. `lsusb -v` in particular is out — it issues
    USB control transfers to the device instead of reading descriptors the kernel has
    already cached.
  - **That path is load-bearing, not a fallback.** Verified here: a CyberPower
    `CP1500PFCLCDa` (`0764`) is attached and visible in sysfs with neither apcupsd nor
    NUT installed. Both daemon-based checks report nothing on this host.
  - **`/sys/class/power_supply` cannot be the gate.** It is empty on that same host
    despite the UPS being attached and claimed by `usbhid`. Useful as corroboration where
    it is populated; useless as the test.
  - The vendor-ID list (APC `051d`, CyberPower `0764`) is a heuristic that will go stale.
    Say so in a comment where it is defined, so whoever adds a third brand knows it is a
    whitelist and not a protocol.
  - `apcaccess status` is a query to apcupsd's NIS port and is allowed, but detection must
    not depend on the daemon answering; `/etc/apcupsd/apcupsd.conf` records the configured
    intent independent of daemon state. `upower -e` / `-i` are reads and are allowed as a
    third signal, though they yield little on a headless host with no session.
  - **It must never `warn`, and it stays silent when nothing is found.** Most hosts have
    no UPS. Emitting "no UPS detected" would break the standing rule that a section prints
    only if non-empty; absence of the section is the negative answer, exactly as it is for
    every other category of hardware.
  - Load percentage and battery age are explicitly out of scope for the accepted item.
    Presence of a data connection is the whole deliverable.

`FR-` marks a request submitted from outside the review cycle. `C-`/`G-`/`O-` stay
reserved for the three code reviewers, per `docs/reviews/DISPOSITIONS.md`.

### Done — do not re-implement

Each was verified against the file and covered by `tests/run.sh` where testable.

- **Warning accumulator + meaningful exit code** (C-025, C-026). See the contract below.
- **All hardcoded `timeout N` sites routed through the `have timeout` gate** (C-003).
  `TMO` is now an array (`"${TMO[@]}"`); a `tmo N cmd...` function covers the sites
  needing a duration other than the 10s default. Both fall back to running the command
  unwrapped when `timeout` is absent, which was the whole point of the original guard.
- **Named constants for every `head -N` limit, plus a marker when one is actually hit**
  (C-014, 03f4cf7). 17 named constants (grouped by what they cap: SMART, RAID
  CLI, filesystem tables, IPMI, Proxmox, Docker, systemd — some intentionally share a
  constant, e.g. df+findmnt; none share one across categories even when the number
  coincides, so MegaCLI's PD cap and df's table cap stay independently tunable) replace
  the 19 sites where a `head -N` truncation was safe to mark inline via `cap()`. `cap()`
  itself never calls `warn()` and cannot: a truncated list is real data, not a collector
  failure, and cap runs as the tail of a pipeline (a subshell) where a `warn()` mutation
  would be lost anyway (G-002). One site — `CNAMES` in the Docker section — is
  deliberately NOT run through `cap()`: that list is word-split into `docker inspect`
  arguments, so an inline marker would be passed as a bogus container name. It reads the
  full list, caps it with plain `head`, and defers its own marker to after the container-
  networks table instead. Covered by T10 (general `cap()` behaviour) and T11 (the CNAMES
  hazard specifically); both were verified against negative controls that reproduce the
  bug being guarded against.
- **Physical-devices table filtered on `TYPE=="disk"`** (C-012), *plus* a `zd[0-9]` name
  exclusion — the reviewer's `TYPE` filter alone does not catch zvols, which report
  `TYPE=disk`. Still unverified against real zvols; confirm on a `local-zfs` host.
- `export LC_ALL=C` after `set -u` (C-001).
- `racadm` gated on `is_root` with its own `###` heading (C-020).
- One `docker inspect` over all containers instead of N+1 (C-023).
- DIMM rows emitted at record boundary (C-011).
- `/proc/cmdline` redacted two ways (C-009): by parameter **name** matching
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
- A `head -N` that can genuinely truncate real output goes through `cap()` with a named
  constant, not a bare number — see the constants block near the top. `cap()` is not
  `warn()`: truncation is real data arriving incomplete, not a collector failing, and it
  never touches `WARNCOUNT` or the exit code. Before piping something through `cap()`,
  check whether its output is later word-split into another command's arguments (as
  `CNAMES` is, into `docker inspect`'s) — an inline marker there becomes a bogus argument
  instead of a footnote. That site reads the full list, caps it with plain `head`, and
  defers its marker to after the block instead.
