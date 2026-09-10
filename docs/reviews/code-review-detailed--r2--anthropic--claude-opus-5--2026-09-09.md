# Code review R2, extensive engineering review

| Field | Value |
|---|---|
| Target | `hw-inventory.sh` v7 |
| Commit SHA | `34ca470a0f454abd4b1a85a3b979cda200f2d4ed` — filled in at filing, per the instruction this cell carried. The reviewer was handed the file and not the SHA; the working tree was clean at this commit and its `hw-inventory.sh` is the 1,205-line file that was attached. Nothing else in this document is edited. |
| Reviewer vendor | Anthropic |
| Reviewer model | Claude Opus 5 |
| Date | 2026-09-09 |
| LOC | 1,205 lines |
| Shell / runtime | bash, `#!/usr/bin/env bash`, `set -u`, `export LC_ALL=C`. Stated floor bash 3.0. Linux only. |

**Sections 1 to 16, complete.**

---

## 1. Overview and context

### What the code does

`hw-inventory.sh` collects a hardware and platform inventory of the host it runs on and
writes one Markdown document to stdout. The document opens with a YAML frontmatter block
(lines 288 to 302) and continues with up to eighteen `###` sections. Each section covers one
subsystem. A section prints only when the host has the thing it describes.

### Entry point and invocation model

There is one entry point. The file is a top-level script with no `main`, no functions that
wrap a section, and no argument parsing. Execution runs from line 29 to line 1205 in source
order. The documented invocation is `sudo bash hw-inventory.sh > file.md` (line 16 and
README line 11). The script accepts no arguments and reads no environment variables other
than `EUID` (line 207) and `PATH`. It sets `LC_ALL` rather than reading it (line 30).

### External dependencies and assumed versions

Nothing is required except bash and the shell's own builtins. Every external tool passes
through `have` (line 136) first. The version assumptions the code makes, which the code
itself never states:

| Tool | Construct | Version the construct needs |
|---|---|---|
| util-linux `lsblk` | `-P -o NAME,TYPE,SIZE,ROTA,TRAN,MODEL,SERIAL` (line 276) | `TRAN` column, util-linux 2.22 or later |
| util-linux `findmnt` | `--real` (line 744) | util-linux 2.28 or later. See F-015. |
| procps `free` | `-h` (line 245) and an `available` column (line 346) | procps-ng 3.3.10 or later. BusyBox `free` has neither. See F-009. |
| coreutils `timeout` | optional, gated at line 145 | any |
| `smartctl` | `-n standby`, `-d megaraid,N` (lines 504, 609) | smartmontools 5.4x or later |
| `docker` | `--format` with Go templates (lines 1118, 1162) | Docker 1.9 or later |
| `ipmitool` | `sdr elist` (line 998) | any |
| bash | `"${TMO[@]}"` on an empty array under `set -u` (line 1106) | **bash 4.4 or later.** The README states 3.0. See F-007. |

### Required privileges

The script runs unprivileged and degrades. Six regions are root-gated: `dmidecode` identity
(line 322), `dmidecode` memory (lines 423 and 439), SMART (line 493), the megaraid probe
(line 594), IPMI (line 979) and `racadm` (line 1008). Two more warn only as root, because the
tool needs root to answer at all: `pvesm` (line 771) and `pct`/`qm` list (lines 1038 and
1068). That gating is correct and consistent.

### Target runtime

Linux. The script reads `/proc`, `/sys`, `/etc/os-release`, `/var/local/emhttp` and
`/boot/config`, and calls `lsblk`, `ip` and `dmidecode`. README's matrix names Unraid,
Proxmox VE, Arch, Fedora/RHEL and Debian/Ubuntu as supported, Alpine and WSL as degraded, and
macOS/BSD as out of scope.

### Assumptions I had to make

1. **The commit SHA.** Not supplied. Stated above.
2. **`tests/fixtures/` was not supplied.** I read `tests/run.sh`, so I know what each test
   asserts, but not what the stub binaries emit. Where a finding depends on fixture content I
   say so. F-013 is the one case where this mattered, and I built my own stub instead.
3. **The vendor CLI binaries were not available to me.** F-001 rests on documented StorCLI
   behavior and on the file's own `-NoLog` at lines 581 and 584, not on a run.
4. **`docs/FIELD-TESTS.md` and `docs/PRIOR-ART.md` were not supplied.** Neither appears in
   the WHAT YOU HAVE BEEN GIVEN list, so this is not a gap in the submission. It does mean I
   cannot tell whether an `FT-` id already covers a question I raise. Where I ask for a field
   test I describe it rather than citing an id.
5. **I assumed `/var/local/emhttp` is LF and `/boot/config` is CRLF**, because `CLAUDE.md` and
   the FR-005 ledger entry say so and I have no Unraid host.
6. **I assumed the maintainer's host is the whitebox AM5 desktop class** named in `QUEUE.md`,
   which is why the megaraid, UPS-daemon and zvol paths are unverified there.

### Documents named in the prompt that were not supplied

None. `hw-inventory.sh`, `CLAUDE.md`, `.claude/rules/collectors.md`, `docs/DISPOSITIONS.md`,
`docs/QUEUE.md`, `README.md`, `tests/run.sh` and `tests/Tests_README.md` all arrived.

---

## 2. Architecture review

### Overall structure and control flow

```
  set -u, LC_ALL=C                              lines 29-30
  named constants                               lines 32-97
  helpers: cap have TMO tmo warn row kv yk dmi  lines 99-207
  GATHER  ── hostname, os-release, uname,       lines 209-285
             lscpu, free, virt, dmi x5, lsblk
  EMIT    ── frontmatter (needs gather)         lines 287-302
          ── header + Identity                  lines 304-334
          ── Snapshot, CPU, Boot, Memory        lines 336-455
          ── Storage devices, SMART             lines 457-542
          ── RAID controller ─ vendor CLI       lines 544-637
                             └ megaraid probe
          ── Unraid, Filesystems, Network, PCI  lines 639-840
          ── Displays, UPS, BMC, racadm         lines 842-1014
          ── Proxmox ─ LXC loop ─ VM loop       lines 1016-1099
          ── Docker, systemd units              lines 1101-1188
  WARNINGS block, if WARNCOUNT > 0              lines 1190-1198
  footer, then exit 0 or 1                      lines 1200-1205
```

The gather-then-emit split is the one real structural decision, and it is correct. The
frontmatter needs `CPUMODEL` and `RAMTOTAL` before anything prints, so those two collectors
have to run early. Rather than reach forward from the frontmatter into a later section, the
author hoisted every value the frontmatter needs into one block and commented why (lines 234
to 237). The alternative, buffering the whole report and printing at the end, would let
sections run in any order but would lose the property that a killed run still leaves a
partial, readable report on stdout.

**Assessment: right call.** The cost is that `LSCPU`, `FREE`, `DMIMEM` and `LSBLK_RAW` become
long-lived globals read hundreds of lines later. The comments at lines 234, 263 and 424 all
name that coupling, which is what makes it survivable.

### Separation of concerns and data flow

Three concerns are separated cleanly:

- **Formatting** lives in `row`, `kv`, `yk` and `cap` (lines 125 to 199). Every escaping rule
  sits in exactly one place, which is what made C-004 and FR-005 one-site fixes.
- **Tool access** lives in `have`, `TMO` and `tmo` (lines 136 to 151).
- **Error accounting** lives in `warn`, `WARNINGS` and `WARNCOUNT` (lines 164 to 170).

Data flows one way: gather writes globals, sections read them, sections write rows to stdout
or to a row-accumulator string, `warn` writes to one accumulator, the footer reads it. No
section reads another section's output. That is the property that lets a section be deleted
without breaking anything downstream.

**What is global and why.** Fourteen globals cross a section boundary: `HOST`, `OSNAME`,
`OSID`, `KERN`, `ARCH`, `PLATFORM`, `PROD`, `MFR`, `SERIAL`, `BOARD`, `BIOS`, `CPUMODEL`,
`RAMTOTAL`, plus the four capture variables above and `NA`, `TMO`, `WARNINGS`, `WARNCOUNT`.
Every one of them is either frontmatter input or a deliberate single-capture hoist. `CFG`
(line 1030) is the one global with no such justification: `cfgget` reads it implicitly rather
than taking it as an argument, which couples the helper to whichever loop last ran. It works
because both loops set `CFG` immediately before calling `cfgget`, but a third caller would
have to know that rule. See section 5.

### Configuration strategy

There are no arguments and no environment variables. Tuning knobs are named constants in one
block (lines 44 to 97), each with a comment giving the reasoning rather than the value. The
block also states the rule for when two constants that share a number should stay separate
(lines 39 to 42). That is better than most production shell.

**Assessment: right call for a one-shot reporter.** Adding `--skip` or `--section` would need
the `section_*()` split that C-031 defers, and C-031 correctly says the churn is not worth it
until someone wants the feature. Two knobs escape the block: `tail -15` at line 1001 (F-016)
and the `{0..31}` and `-ge 10` bounds of the megaraid probe (lines 608 and 613, F-013).

### Idempotency and re-runnability

Every command is a query, so re-running changes nothing and concurrent runs cannot collide.
There are no temp files, no lock files and no caches. `smartctl -n standby` (line 504) goes
further than idempotency requires: it declines to wake a sleeping disk, so a run does not even
change the power state of the hardware it inspects. That is the strongest form of the property
and the README is right to call it out.

Two exceptions break the guarantee, and both are findings rather than design:

**F-001 [CRITICAL]: the vendor RAID CLI writes a log file into the working directory.**

Lines 570, 573 and 576:

```
    tmo 25 "$RCLI" /call show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "controller summary lines"
    tmo 25 "$RCLI" /call/vall show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "virtual drive lines"
    tmo 25 "$RCLI" /call/eall/sall show 2>/dev/null | cap "$RAID_CLI_DRIVES_LINES" "physical drive lines"
```

`$RCLI` is `perccli64`, `perccli`, `storcli64` or `storcli` (line 562). Broadcom's StorCLI and
its Dell rebrand PercCLI append every command and its output to a log file in the current
working directory unless the caller adds the trailing keyword `nolog`. The verb is a `show`
verb, so the banned-verb hook and T1's `(storcli|perccli|megacli)[^|]*(add|delete|set |start )`
pattern both pass it. This is the exact failure mode `CLAUDE.md` describes: "A banned-verb list
can only describe commands this script writes; it cannot see a tool whose behaviour is defined
by a file on the host." Here it is a tool whose behavior is defined by nothing at all, just a
default.

The file already contains the counter-example. Eleven lines below, the MegaCLI branch passes
`-NoLog` (lines 581 and 584), which exists for exactly this reason and stops `MegaSAS.log`
appearing in the working directory.

**Concrete scenario in which damage occurs.** The README documents the automation target as a
cron job or a scheduled sweep, and the documented invocation is `cd ~/inventory && sudo bash
hw-inventory.sh > ...`. On a Dell PowerEdge with `perccli64` installed, that run creates a
root-owned log file in the operator's inventory directory on every sweep. Three further
consequences follow. A sweep driven from `/` writes into `/`. A host whose root filesystem is
mounted read-only fails the write, and StorCLI in that state can exit non-zero and print
nothing, which turns into an empty RAID section rather than a warning. And the guarantee the
whole design rests on, that no human has to confirm a run against a production host, is no
longer true.

**Recommendation.** Append `nolog` to all three calls. Then extend T1's banned pattern so a
future call without it fails the suite. Because I could not run the binary, verify the default
first on a host that has one: run `perccli64 /call show` from a directory you own, list that
directory, and see whether a log file appeared. If it did not on your version, add `nolog`
anyway as one word of insurance and downgrade this to LOW in the ledger. If `nolog` turns out
to be unsupported on some version you care about, the fallback is to drop the vendor CLI
section rather than keep the write, per the standing rule.

**F-002 [HIGH]: `upower -e` starts a system daemon.**

Line 966:

```
  UPWR=$("${TMO[@]}" upower -e 2>/dev/null | grep -i 'ups' | paste -sd', ' -)
```

`upower` is a D-Bus client. It calls `org.freedesktop.UPower` on the system bus. UPower ships
a D-Bus activation file, `/usr/share/dbus-1/system-services/org.freedesktop.UPower.service`,
with a `SystemdService=upower.service` line. On a host where `upowerd` is installed but not
running, the first call activates it, and the daemon then stays running and begins polling
power-supply devices. The script has therefore changed the running state of the host.

**This contradicts a supplied document.** `docs/DISPOSITIONS.md`, FR-002, line 198: "`upower
-e` / `-i` are reads and are allowed as a third signal, though they yield little on a headless
host with no session." The read half of that sentence is true of the call itself. It is not
true of the activation the call triggers.

**New evidence, and the field test that settles it.** My evidence is the activation file, not
a run: this container has no system bus. The measurement is two commands on a host with
`upower` installed and the daemon stopped.

```
systemctl is-active upower; bash hw-inventory.sh >/dev/null; systemctl is-active upower
```

If the answer changes from `inactive` to `active`, FR-002 needs amending. This is a
`FIELD-TESTS.md` question in the repository's own idiom: one command, one small answer, on a
host class the development machine may not be.

**Recommendation.** Gate the probe on the daemon already running, which keeps the signal where
it is free and removes the activation. `systemctl is-active` is itself a query and does not
activate the unit it asks about. The alternative is to delete the probe: sysfs is the gate by
FR-002's own finding, `power_supply` and apcupsd config are the corroboration, and UPower is
described in the same entry as yielding little.

### Failure model

The model is **fail soft with an accounted tail**, and it is the right choice. A best-effort
collector that stops at the first absent tool produces a truncated report, which is why `set
-e` is rejected. A collector that fails silently produces a confident wrong answer, which is
why `warn` exists. The script does neither: it runs every collector, records which ones failed
while present and permitted, prints the whole report, appends a named warnings block and exits
1.

The one place the model breaks is a shell-level abort. `set -u` on an unset variable kills the
main shell with exit 1 and no warnings block, and a caller cannot tell that from an honest
incomplete collection. A-001 and T12 fixed one instance. F-007 is a second instance with a
different trigger.

### Extension points

Adding a collector means: `have` the tool, wrap it in `"${TMO[@]}"` or `tmo N`, redirect
stderr, capture the output, print only when non-empty, and decide warn or silent. That is a
real and teachable contract, stated in README Contributing and in
`.claude/rules/collectors.md`. Three sharp edges a newcomer will hit, all of which the existing
code handles and none of which the contract states:

1. A row loop written as a pipeline body cannot `warn`. The convention says capture the
   pipeline. It does not say the same about a `for` loop over a glob, which is safe.
2. A `head -N` needs `cap()` unless the output is later word-split into arguments. That
   exception exists once, at CNAMES, and is documented only there.
3. A variable assigned inside a guard and tested outside it kills the script. Two sites
   initialize before the guard for that reason (lines 422 and 1159) and both carry comments.

**Recommendation, no finding:** promote those three to the Conventions list in
`.claude/rules/collectors.md`. Two of them already appear there in some form. The third, the
`for`-versus-pipeline distinction, does not.

---

## 3. Blocking-call audit

### How I scoped this table

The prompt asks for one row per invocation of an external binary. Taken literally that is
about 190 rows, most of them `awk`, `sed` and `grep` reading a string already in memory or a
file already in page cache. Those cannot block, and burying the real rows among them would
defeat the purpose of the audit. So I apply one blanket ruling and then list every invocation
it does not cover.

**Blanket ruling.** `awk`, `sed`, `grep`, `head`, `tail`, `wc`, `paste`, `cut`, `cat`, `ls`,
`readlink`, `date`, `uname` and `command -v` cannot block when their input is a shell variable,
a pipe from a process already accounted for, or a file under `/proc`, `/etc` or `/var`. The
script has 190-odd such invocations and I clear all of them. Four uses of those tools fall
outside the ruling and appear in the table: the three `cat` reads under `/sys/class/net`, the
`wc -c` read of an EDID blob, the `awk` reads under `/boot/config`, and `ls` on
`/sys/kernel/iommu_groups`.

Every invocation that queries hardware, a daemon, a filesystem or a subsystem is below.

### The table

| Line(s) | Command | `have` guarded | Timeout wrapper | Can it block | Verdict |
|---|---|---|---|---|---|
| 212 | `hostname` | no | none | no, one syscall | OK |
| 229, 231, 232 | `uname -o -r -m` | no | none | no | OK |
| 239 | `lscpu` | yes | `${TMO[@]}` 10s | yes, walks `/sys/devices/system/cpu` | OK |
| 245 | `free -h` | yes | `${TMO[@]}` 10s | no | OK, but see F-009 |
| 253 | `systemd-detect-virt` | yes | **none** | unlikely, reads DMI and `/proc/1` | **F-005** |
| 204 (called 257-261) | `dmidecode -s` x5 | yes | `${TMO[@]}` 10s | yes, `/dev/mem` or `/sys/firmware/dmi` | OK |
| 276 | `lsblk -dn -P` | yes | `${TMO[@]}` 10s | yes, stats every block device, including an unresponsive iSCSI or multipath node | OK |
| 299, 307 | `date` | no | none | no | OK |
| 319 | `pveversion` | yes | **none** | **yes**, `/etc/pve` is the pmxcfs FUSE mount and stops answering when corosync loses quorum | **F-003** |
| 340 | `uptime` | no | none | no, reads `/proc/uptime` | OK |
| 373, 374 | `ls -A /sys/kernel/iommu_groups` | no | none | no, a directory read | OK |
| 379, 381, 384 | `$(</sys/...)` | builtin | none | no, static attributes | OK |
| 426, 434 | `dmidecode -t memory`, `-t 16` | yes | `${TMO[@]}` 10s | yes | OK |
| 504 | `smartctl -n standby -H -A -d auto` | yes | `tmo 15` | **yes**, a failing disk can hold a SCSI command for the full HBA timeout | OK |
| 535, 537 | `smartctl --scan` twice | yes | `tmo 15` each | yes | **F-006** |
| 550 | `lspci` | yes | `${TMO[@]}` 10s | **yes**, this is the 240s incident | OK |
| 570, 573, 576 | `perccli64` / `storcli64` `show` | yes, loop at 562 | `tmo 25` | yes, controller firmware | timeout OK, **F-001** on read-only |
| 581, 584 | `MegaCLI -LDInfo`, `-PDList` | yes | `tmo 25` | yes | OK |
| 609 | `smartctl -d megaraid,N` x up to 32 | yes | `tmo 6` | yes | OK per call, **F-004** in aggregate, **F-013** on logic |
| 714 | `awk` on `/boot/config/shares/*.cfg` | n/a | none | **cannot determine.** `/boot` on Unraid is the FAT32 USB flash device. If that device drops off the bus, the read enters uninterruptible sleep and no timeout helps. | see note below |
| 737 | `df -hT` | yes | `${TMO[@]}` 10s | **yes**, statfs on a dead NFS or CIFS mount | OK |
| 744 | `findmnt --real` | yes | `${TMO[@]}` 10s | yes | OK, but see F-015 |
| 757, 759 | `zpool list`, `zpool status -x` | yes | `tmo 20` each | **yes**, a suspended pool blocks in the kernel | OK |
| 764 | `btrfs filesystem show` | yes | `${TMO[@]}` 10s | yes, scans devices | OK |
| 769 | `pvesm status` | yes | `${TMO[@]}` 10s | **yes**, iterates every configured storage including NFS and CIFS | OK, but 10s is thin for a host with several remote storages |
| 784 | `ip -o link show` | yes | `${TMO[@]}` 10s | no, netlink dump | OK |
| 793, 794, 797 | `cat /sys/class/net/$ifc/{operstate,address,speed}` | no | **none** | **cannot determine.** `operstate` and `address` are cached. `speed` calls the driver's ethtool handler. A NIC whose firmware has crashed can hold that read in uninterruptible sleep, where `timeout` would not help either. | note below |
| 795 | `ip -o -4 addr show dev` per interface | yes | `${TMO[@]}` 10s | no | OK, N+1 |
| 809 | `ip route show default` | yes | `${TMO[@]}` 10s | no | OK |
| 827 | `lspci -nnk` | yes | `${TMO[@]}` 10s | yes | OK |
| 866 | `wc -c < /sys/class/drm/.../edid` | no | **none** | no. The `edid` attribute returns the blob cached at connector detect. It does not re-probe the bus. | OK |
| 870 | `edid-decode` | yes | `${TMO[@]}` 10s | no, stdin parser | OK |
| 886 | `strings -n 4` | yes | **none** | no, 256 bytes on stdin | **F-005** |
| 925, 938 | `cat` on `/sys/bus/usb/devices/*/{idVendor,manufacturer,product,idProduct}` | no | none | no, cached descriptors | OK |
| 933 | `readlink` on a sysfs symlink | no | none | no | OK |
| 942 | `grep -lx UPS /sys/class/power_supply/*/type` | no | none | no, static attribute | OK |
| 958 | `apcaccess status` | yes | `tmo 10` | **yes**, TCP to apcupsd's NIS port | OK |
| 966 | `upower -e` | yes | `${TMO[@]}` 10s | **yes**, D-Bus round trip, and an activation on first call | timeout OK, **F-002** on read-only |
| 982 | `ipmitool mc info` | yes, plus node gate 979 | `tmo 15` | **yes**, KCS is slow and a wedged BMC does not answer | OK |
| 993 | `ipmitool lan print 1` | yes | `tmo 15` | yes | OK |
| 998 | `ipmitool sdr elist` | yes | `tmo 30` | **yes**, dozens of sensors one at a time over KCS. 30s is not generous on a large chassis. | OK, note |
| 1001 | `ipmitool sel list` | yes | `tmo 25` | yes | OK |
| 1009 | `racadm getsysinfo` | yes | `tmo 20` | **yes**, talks to the iDRAC | OK |
| 1021 | `pveversion -v` | yes | `tmo 15` | yes, dpkg plus pmxcfs | OK |
| 1037, 1067 | `pct list`, `qm list` | yes | `tmo 20` each | **yes**, pmxcfs | OK |
| 1044, 1046 | `pct config`, `pct status` per container | yes | `tmo 10` each | yes | OK per call, **F-004** in aggregate |
| 1074, 1076 | `qm config`, `qm status` per VM | yes | `tmo 10` each | yes | OK per call, **F-004** in aggregate |
| 1096 | `pvecm status` | yes | `tmo 15` | **yes**, corosync | OK |
| 1106 | `docker info` | yes | `${TMO[@]}` 10s | **yes**, daemon socket | OK |
| 1108, 1118, 1145 | `docker version`, `docker ps -a` x2 | inside gate | `${TMO[@]}` 10s each | yes | OK, **F-019** on the duplicate |
| 1162 | `docker inspect` over all names | inside gate | `tmo 15` | yes | OK |
| 1181 | `systemctl --failed` | yes | `${TMO[@]}` 10s | **yes**, D-Bus to PID 1 | OK |

**No hardcoded `timeout N` survives anywhere in the file.** I checked: the only literal is
`have timeout && TMO=(timeout 10)` at line 145, which is the gate itself. C-003 is fully
applied.

### Notes on the two rows I could not decide

Both are `/sys` reads that look inert and are not, and neither is fixable with a timeout,
because an uninterruptible kernel sleep ignores SIGTERM. I raise no finding for either. I name
them so a future hang is diagnosed in minutes rather than by another three static reviews.

- **`/sys/class/net/$ifc/speed` at line 797.** Condition: a NIC whose driver or firmware has
  stopped responding to ethtool. Symptom: the script stops inside the interface loop, and T3
  would report 124 only if the outer harness has its own timeout.
- **`/boot/config/shares/*.cfg` at line 714 and `/boot/config/ident.cfg` at line 728.**
  Condition: an Unraid flash device that has dropped off the USB bus, which is a known Unraid
  failure mode. Symptom: the script stops inside the Unraid region.

### F-003 [HIGH]: `pveversion` runs with no timeout wrapper

Line 319:

```
  kv "Proxmox VE" "$(pveversion 2>/dev/null | head -1)"
```

Every other Proxmox call in the file is wrapped. The same binary is wrapped at line 1021 with
`tmo 15`. `pveversion` reads `/etc/pve`, which is pmxcfs, a FUSE filesystem backed by corosync.
When a node loses quorum, reads under `/etc/pve` block rather than fail. The comment at lines
34 to 36 names this exact line as one of the deliberate bare `head -1` sites, so the author
looked at it while thinking about `cap()` and did not think about `$TMO` at the same time.

**Consequence.** On a Proxmox node with a wedged cluster filesystem, the script stops at line
319, which is before every section. No frontmatter consumer gets a report at all. This is the
worst position in the file for an unwrapped call, because it is early.

**Recommendation.** `kv "Proxmox VE" "$(tmo 10 pveversion 2>/dev/null | head -1)"`. Use `tmo`
rather than `"${TMO[@]}"` only if you want a duration other than 10s. Either is correct here.

### F-004 [MEDIUM]: no aggregate deadline

Each call is bounded. The run is not. Worst-case wall clock is the arithmetic sum of every
budget, and nothing checks elapsed time.

Worked arithmetic for a Proxmox VE host with 12 disks, 20 LXC containers, 8 VMs, four
interfaces, ZFS and Docker, no BMC and no RAID controller:

| Region | Calls | Budget |
|---|---|---|
| Gather (lines 239 to 276) | lscpu, free, 5x dmidecode, lsblk | 80s |
| Memory (426, 434) | 2x dmidecode | 20s |
| SMART (504, 535, 537) | 12 disks at 15s, plus two scans | 210s |
| Filesystems (737 to 769) | df, findmnt, 2x zpool, btrfs, pvesm | 80s |
| Network (784 to 809) | link, 4x addr, route | 60s |
| PCI (550, 827) | 2x lspci | 20s |
| UPS (966) | upower | 10s |
| Proxmox (1021 to 1096) | pveversion -v, 2x list, 28 guests at 20s, pvecm | 630s |
| Docker (1106 to 1162) | info, version, 2x ps, inspect | 55s |
| systemd (1181) | systemctl | 10s |
| **Total** | | **1,175s, about 20 minutes** |

A host that also has a RAID controller adds up to 192s for the megaraid probe at line 609 (32
IDs at `tmo 6`) plus 75s for the vendor CLI. A 24-disk NAS adds 180s to the SMART row. The
README says "PERC and SMART sections can take a minute", which understates the bound by more
than an order of magnitude.

**This is not a hang.** Every call returns. The consequence is a cron job that overruns its
window and a `tee` that looks frozen. **Recommendation:** add one named constant, for example
`RUN_BUDGET_S=600`, and check bash's `SECONDS` builtin at the top of the two unbounded loops
(the megaraid probe at line 608 and the guest loops at lines 1043 and 1073). On exceeding it,
break and `warn` that the collection was cut short. `SECONDS` is a bash builtin present since
2.0, so the 3.0 floor is safe, and reading it is not a write.

### F-005 [LOW]: two tools run outside the timeout convention

Line 253 and line 886:

```
  DV=$(systemd-detect-virt 2>/dev/null || true)
    disp=$(strings -n 4 2>/dev/null < "$e" | grep -E ...
```

Both are `have`-guarded and both redirect stderr, so they satisfy two thirds of the convention
stated in `.claude/rules/collectors.md`: "Guard every external tool with `have`, a timeout, and
`2>/dev/null`." Neither can realistically block. `systemd-detect-virt` reads DMI attributes and
`/proc/1/environ`. `strings` reads 256 bytes from a redirect. **Fix them anyway**, because the
convention's value is that it holds without exception, and an exception invites the next one.
Both become `"${TMO[@]}" cmd`.

### F-006 [LOW]: `smartctl --scan` runs twice

Lines 535 and 537:

```
    if tmo 15 smartctl --scan 2>/dev/null | grep -q .; then
      printf '**`smartctl --scan` sees:**\n\n```\n'
      tmo 15 smartctl --scan 2>/dev/null | cap "$SMART_SCAN_LINES" "scan lines"
```

The first call decides whether the block prints. The second produces it. Two costs: the budget
for this step doubles to 30s, and a device that appears or disappears between the two calls
gives a header with nothing under it or a scan whose result was already discarded.
**Recommendation:** capture once, then test the variable, which is the pattern the rest of the
file uses for exactly this reason.

```
    SCAN=$(tmo 15 smartctl --scan 2>/dev/null | cap "$SMART_SCAN_LINES" "scan lines")
    [ -n "$SCAN" ] && printf '**`smartctl --scan` sees:**\n\n```\n%s\n```\n\n' "$SCAN"
```

---

## 4. Section-by-section walkthrough

### Lines 1 to 30 — header comment, `set -u`, `LC_ALL=C`

**What it does:** documents the read-only promise, names the verbs deliberately absent, states
the invocation and both exit codes, then sets `set -u` and exports `LC_ALL=C`.

**Assessment: Good.** `export LC_ALL=C` on line 30 sits before the first external command,
which is where it has to be. Every `awk` field match, every `sort` order and every decimal
separator in the file depends on it. The verb list in the comment is load-bearing rather than
decorative: T1 strips comments before its banned-verb grep precisely so this list can name the
verbs the script does not use.

### Lines 32 to 97 — named constants

**What it does:** thirteen `head -N` limits with a comment each, plus the rule at lines 39 to 42
for when two constants sharing a number stay separate.

**Assessment: Good.** Comments give reasoning, not restatement. `IPMI_IDENTITY_LINES=6` at line
73 explains that it tracks an expected field count and not an open-ended corpus, which is the
sentence that stops someone raising it to 60 during an unrelated change.

**Finding:** F-020 [NITPICK]

**Recommendation:** none of the thirteen is `readonly`. A `readonly SMART_SCAN_LINES=40` costs
nothing and turns an accidental reassignment into an error rather than a silently different
report. Optional.

### Lines 99 to 134 — `cap()`

**What it does:** reads stdin, emits at most N lines, appends one truncation marker if an
(N+1)th line existed.

**Assessment: Good, and the reasoning behind it is the best comment in the file.** Three
decisions are each correct and each documented. Building on `head -n $((n+1))` rather than a
read loop keeps `head` attached to the pipe, so a slow producer still takes SIGPIPE, which is
the behavior the `pipefail` rejection depends on (lines 104 to 109). Zero in gives zero out
including the marker, so a section that prints only when non-empty is not defeated at every
call site at once (lines 111 to 115). And `cap` never calls `warn`, both because truncation is
not a failure and because `cap` runs in a subshell where the mutation would vanish (lines 117
to 120).

The boundary arithmetic is right. N lines in gives no marker, N+1 gives the marker, and I
checked both. One behavior is undocumented: `out=$(head ...)` strips trailing blank lines, so
`cap` also eats a trailing blank line from its input. Inside a code fence that is invisible.

### Lines 136 to 207 — helpers

**What it does:** `have`, `NA`, the `TMO` array and `tmo()`, `warn`, `row`, `kv`, `yk`, `dmi`,
`is_root`.

**Assessment: Problematic in one respect, otherwise good.** `row()` at lines 185 to 189 does
two jobs in one pass, the `|` escape and the CR strip, and the comment explains why the CR
strip belongs in a cell builder rather than at four call sites. `warn()` accumulates a string
rather than an array, and line 156 says why: an empty array under `set -u` on older bash. The
author knew about that hazard. It is the same hazard as F-007, in the same file, applied to a
different array.

**Finding:** F-007 [HIGH] — `"${TMO[@]}"` on an empty array aborts under `set -u` below bash
4.4.

Lines 144 to 145:

```
TMO=()
have timeout && TMO=(timeout 10)
```

When `timeout` is absent, `TMO` stays empty. Before bash 4.4, `"${arr[@]}"` on an empty array
under `set -u` raises "unbound variable" and the shell exits. Bash 4.4 changed this. The
README states a floor of bash 3.0, so by the project's own stated contract this construct is
out of bounds, and the `WARNINGS` comment at line 156 shows the author already knows the class
of bug.

There are 24 `"${TMO[@]}"` expansions. Twenty-three sit inside a command substitution or a
pipeline element, so the abort kills a subshell and the parent survives with an empty capture.
The consequences there are wrong warnings rather than a dead script: `LSCPU` comes back empty
and line 354 warns that `lscpu` returned nothing, when in fact `lscpu` never ran.

**One site is in the main shell.** Line 1106:

```
if have docker && "${TMO[@]}" docker info >/dev/null 2>&1; then
```

On bash 4.3 with no `timeout` installed, this aborts the script. The report ends mid-file with
no Docker section, no systemd section, no `## Collection warnings` block and no footer, and
bash exits 1. A caller reading only `$?` sees an honest incomplete collection. That is the
exact failure A-001 and T12 exist to prevent, reached by a different route.

**Confidence and trigger.** The construct is unsafe below bash 4.4. I could not reproduce it
here, because this container runs bash 5.2.21, where it is correct. The trigger needs both an
old bash and no `timeout`, which in practice means a minimal container or an older enterprise
distribution. Verify with `bash --version` on the oldest host in the estate, or directly:

```
bash -c 'set -u; A=(); "${A[@]}" true; echo survived'
```

**Recommendation.** Replace all 24 expansions with `${TMO[@]+"${TMO[@]}"}`, which expands to
nothing when the array is unset or empty and is a no-op on bash 4.4 and later. This does not
reopen A-004: the `TMO` array stays, `tmo()` stays, and both keep their current roles. The
alternative, dropping the README floor to 4.4, is worse, because it trades a one-token fix for
a narrower support claim.

**Second, smaller point in this region.** `yk()` at lines 194 to 199 escapes backslash and
double quote but not CR or LF, while `row()` three lines above strips CR. **Finding: F-010
[LOW].** A CR reaching `yk` produces `os: "Unraid 7.0\r"`, which parses as YAML but carries a
stray control character into every downstream consumer. No current caller can supply one, since
`/etc/unraid-version` is on the root filesystem rather than the FAT32 flash. The asymmetry is
still worth one line, because FR-005's whole lesson was that a CR arrives from a direction
nobody predicted. Add `v=${v//$'\r'/}` next to the existing substitutions.

### Lines 209 to 285 — gather stage

**What it does:** hostname, OS identity, kernel, arch, CPU model, RAM total, virtualization
platform, five `dmi` fields, and one `lsblk -P` capture that feeds three later sections.

**Assessment: Good, with one portability defect.** Three decisions stand out. `/etc/os-release`
is parsed as `KEY=value` rather than sourced (lines 215 to 224), which removes a root-level code
execution path and is anchored so `^ID=` cannot match `ID_LIKE`. The `lsblk -P` capture (lines
272 to 285) feeds the device table, the disk list and the megaraid probe from one call, and the
comment explains both why `-P` rather than columns and why zvols are excluded by name rather
than by `TYPE`. And the emptiness test at line 284 keys on `LSBLK_RAW` rather than `DISKS`,
with the comment stating that a host with all devices filtered out is real and a host with zero
block devices is not.

**Finding:** F-009 [MEDIUM] — `free -h` produces a false warning on BusyBox.

Lines 245 to 249:

```
have free && FREE=$("${TMO[@]}" free -h 2>/dev/null)
RAMTOTAL=$(printf '%s\n' "$FREE" | awk '/^Mem:/{print $2}')
```

BusyBox `free` accepts `-b`, `-k`, `-m` and `-g` and rejects `-h`. On Alpine without procps,
`free -h` writes a usage error to the stderr this line discards, `FREE` is empty, `RAMTOTAL` is
empty, and line 248 warns that `free` reported no total memory. The script then exits 1. By the
letter of the contract that warning is defensible, because `free` was present and permitted and
returned nothing. By its intent it is wrong: the tool did not fail, the script asked it a
question it does not answer, and the answer is sitting in `/proc/meminfo`.

The file already solves this exact problem one paragraph above. Line 241 falls back from
`lscpu` to `/proc/cpuinfo` for the CPU model. RAM has no equivalent.

**Recommendation.** Add the matching fallback before the warn, then warn only if both fail.

```
[ -z "$RAMTOTAL" ] && RAMTOTAL=$(awk '/^MemTotal:/{printf "%.0fGi", $2/1048576}' /proc/meminfo 2>/dev/null)
```

Keep the existing warn, but move it below the fallback so it fires only when both sources are
silent. The `Snapshot` rows at lines 346 to 347 read `$3` and `$7` of the same `free` output and
degrade to blank cells on the same host, which the fallback does not fix. Those are cosmetic
and I raise no separate finding.

### Lines 287 to 302 — frontmatter

**What it does:** emits the YAML block every downstream consumer parses.

**Assessment: Good.** Every value goes through `yk`, which is the only escaping the block
needs. `collector: hw-inventory.sh v7` at line 300 is the field T1 cross-checks against the
header comment, so a stale version number is a failing test rather than a misfiled report.

**Finding:** F-022 [NITPICK] — line 299 and line 307 each call `date` independently. A run that
crosses midnight files the report under one day in `collected:` and prints another in the
header. Capture once into a variable and format twice.

### Lines 304 to 334 — header and Identity

**What it does:** prints the host heading, a collection timestamp with a not-run-as-root marker,
and the identity table.

**Assessment: Acceptable.** The root marker at line 308 uses `$(is_root || echo ' ...')` inline,
which is compact and correct. The four-field emptiness test at line 328 is the right shape: it
warns only when `dmidecode` as root produced nothing at all, not when one field is blank.

**Finding:** F-003 [HIGH], already stated in section 3. Line 319 is the unwrapped `pveversion`.

### Lines 336 to 349 — volatile snapshot

**Assessment: Good.** Grouping volatile fields under one heading so a diff can exclude them
(README documents the `sed` that does it) is a small design decision that pays for itself every
time two reports are compared. Correct as written.

### Lines 351 to 369 — CPU

**Assessment: Good.** The `lscpu`-present and `lscpu`-absent branches both emit a Model row, so
the table shape does not change with the tool. The `/proc/cpuinfo` fallback at line 241 means
the Model row is populated on a host with no `lscpu` at all. `VIRT` at lines 365 to 367 tests
`' vmx'` and `' svm'` with a leading space, which stops a match inside another flag name.
Correct as written.

### Lines 371 to 416 — boot and kernel parameters

**What it does:** IOMMU group count, nested-virt flag, transparent hugepages, then the redacted
kernel command line.

**Assessment: Good, with one over-redaction.** The two-pass `awk` at lines 405 to 414 is the
right structure, and the comment at lines 389 to 404 explains why one pass cannot work: a
credential can hide in a parameter's name or inside its value, and dracut's iSCSI form puts it
in the value under the innocuous name `netroot`. The value pass uses `iscsi:[^@]+@`, and because
a bracket-negated class cannot cross `@`, a target IQN containing a later `@` does not extend
the redaction. That is correct and easy to get wrong.

**Finding:** F-011 [LOW] — the name pass over-redacts `keymap`.

Line 409:

```
      if (tok ~ /=/ && tolower(name) ~ /(password|secret|token|key)/) tok=name"=REDACTED"
```

`key` is an unanchored substring. `rd.vconsole.keymap=us` and `vconsole.keymap=us` both contain
it, so both become `REDACTED` on any Fedora, RHEL or Arch host using dracut. The prompt asks
for both directions of the redaction audit, and this is the over-redaction direction. The lost
value is trivial, which is why this is LOW, but the pattern will get worse as keywords are
added: `id` or `pass` would each strip far more.

**Recommendation.** Exclude the known-safe names rather than tightening the keyword, because
tightening `key` to `\.key$|keyfile|luks` risks the under-redaction direction, which is worse.

```
      if (tok ~ /=/ && tolower(name) ~ /(password|secret|token|key)/ && tolower(name) !~ /keymap|keyboard/) tok=name"=REDACTED"
```

Then add a case to T9's over-redaction half, which already asserts that the target name and
`rd.iscsi.firmware` survive.

### Lines 418 to 455 — Memory and DIMMs

**What it does:** total RAM, swap, DIMM slot counts from `dmidecode -t memory`, max supported
capacity from type 16, and the installed-DIMM table.

**Assessment: Good.** `DMIMEM=""` at line 422 is initialized before its own root gate, which is
the pattern T12 was written to protect and which the Docker section copies at line 1159. The
`SLOTS` test at line 432 keys on the `Memory Device` record count rather than on `DMIMEM` being
empty, and the comment at lines 429 to 431 explains that `dmidecode` prints a banner to stdout
even when it cannot read `/dev/mem`, so an emptiness test would never fire. That is the sharpest
observation in the file and it generalizes.

**Finding:** F-012 [LOW] — two Markdown tables build rows without `row()` or `esc()`.

Line 442:

```
      if (size != "" && size !~ /^No/) printf "| %s | %s | %s | %s | %s |\n", loc, size, sp, mf, pn
```

and line 893:

```
  MONROWS="${MONROWS}| ${conn} | ${disp:-(EDID present, not parsed)} |
```

C-004's ledger entry says `|` is escaped in "every table cell, through one `row()` helper that
`kv()` also calls, plus an `esc()` in the one table built in awk". There are two tables built
outside `row()`, not one. The Unraid `disks.ini` awk at line 673 has `esc()`. The DIMM awk at
lines 440 to 451 does not, and the Displays accumulator at line 893 does not either.

The trigger is unlikely in both cases. SMBIOS part numbers and manufacturer strings are vendor
free text and can contain anything, but a `|` in one would be strange. The `strings` fallback
for displays filters through `^[[:alnum:]][[:alnum:] ._+/-]{5,}$` at line 887, which excludes
`|` already, and only the `edid-decode` path at line 870 is unfiltered. I rate this LOW on
likelihood, not on consequence: a shifted DIMM row attributes a part number to the wrong slot,
which is the kind of wrong answer this report exists to prevent.

**Recommendation.** Add the same three-line `esc()` from line 673 to the DIMM awk and apply it
at the `printf`. Route the Displays row through `row "$conn" "${disp:-...}"` instead of building
the string by hand. Both are mechanical. Extend T15 to assert a `|` in a display name survives
escaped, next to its four existing assertions.

### Lines 457 to 486 — Storage, physical devices

**What it does:** parses the hoisted `lsblk -P` capture into a device table.

**Assessment: Problematic in one respect.** The structure is right: the row loop is a pipeline
body, so it is captured into `DEVROWS` and tested outside, which keeps `warn` in the main shell
and stops an empty table header printing. The comment at lines 462 to 463 states both reasons.
The double-warn guard at line 480, which stays quiet when `LSBLK_RAW` was already empty, is the
CI-001 lesson applied correctly.

**Finding:** F-008 [MEDIUM] — `fld()` matches an unanchored greedy pattern.

Line 460:

```
  fld() { printf '%s' "$2" | sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"; }
```

The leading `.*` is greedy, and the `[[:space:]]\{0,\}` before the key matches zero characters,
so the key is not anchored to a word boundary. When two columns exist whose names end the same
way, `fld` returns the last one. Today's seven columns are all distinct suffixes, so the code is
correct as written. It stops being correct the moment someone adds a column.

**Measured.** I ran the function against a synthetic line with `KNAME` added, which is the most
likely next column and ends with `NAME`:

```
  NAME="sda" KNAME="sdz" TYPE="disk" SIZE="1.8T"     ->  fld NAME returns  sdz
```

`fld NAME` returned `sdz`. `PARTLABEL` against `LABEL` and `PKNAME` against `NAME` fail the same
way. The device column would then name a device that is not the one the row describes, and every
`smartctl` probe downstream would target the wrong node.

**Recommendation.** Anchor the key to start-of-line or a space, and drop the greedy prefix.

```
  fld() { printf '%s' "$2" | sed -n "s/^\(.*[[:space:]]\)\{0,1\}$1=\"\([^\"]*\)\".*/\2/p"; }
```

Add a comment saying why the anchor is there, in the same spirit as the `lsblk -P` comment at
lines 264 to 267, which exists to stop someone simplifying that construct back into a
column-shift bug. This is the same bug wearing different clothes. T6 already asserts the device
row, so add `KNAME` to the fixture's `lsblk` stub output and the existing assertion catches a
regression for free.

### Lines 488 to 542 — SMART health

**What it does:** per-disk `-H -A` with `-n standby`, then `--scan`.

**Assessment: Good.** `-n standby` is the decision worth naming: on a NAS with spun-down array
disks, the obvious implementation wakes every drive to answer a question about its health. This
one reports `(standby — not woken)` and counts it as a successful query, which is right, because
the drive was reached. The `for d in $DISKS` loop at line 500 runs in the main shell rather than
as a pipeline body, and the comment says so, so `SMOK` survives and the warn at line 532 works.
The two-way fallbacks for `poh`, `wear` and `tmp` read ATA and SCSI spellings, which A-005
correctly refused to collapse into one helper.

**Finding:** F-006 [LOW], already stated in section 3.

### Lines 544 to 637 — RAID controller and megaraid probe

**What it does:** detects a controller from `lspci`, runs a vendor CLI if one exists, then walks
`-d megaraid,N` for drives the controller hides.

**Assessment: Problematic.** This is the most complex region in the file and it carries two
findings, one of them the CRITICAL. The `lspci` emptiness test at line 554 is correct and its
comment is the clearest statement of the whole contract: an empty PCI list means "cannot be
trusted as none present", not "none present". The `MRTGT` selection at lines 603 to 605 is C-016
done right, including the detail that an empty `TRAN` stays eligible because controller-backed
disks routinely report none.

**Finding:** F-001 [CRITICAL], stated in full in section 2.

**Finding:** F-013 [MEDIUM] — the probe finds nothing when the lowest device ID is 10 or higher.

Lines 608 to 614:

```
      for n in {0..31}; do
        MS=$(tmo 6 smartctl -n standby -H -A -d "megaraid,$n" "/dev/$MRTGT" 2>/dev/null || true)
        if ! printf '%s' "$MS" | grep -qiE '^Device Model:|^Model Number:|^Product:|^Serial Number:'; then
          misses=$((misses + 1))
          # Device IDs can be sparse; give up only after a long empty run.
          [ "$misses" -ge 10 ] && break
```

`misses` starts at 0 and is armed from the first iteration, so the loop gives up at `n=9` if no
ID below 10 has answered. Every drive on a controller whose device IDs start at 10 or higher is
lost.

**Measured.** I built a stub `smartctl` that answers only at chosen device IDs, a stub `lsblk`
producing one SAS disk as the probe target, a stub `lspci` producing a `RAID bus controller`
line, and ran the real script with `is_root` forced true:

| Lowest device ID that answers | Drive rows emitted |
|---|---|
| 0, 1, 2, 3 | 4 |
| 9, 10, 11 | 3 |
| 10, 11, 12 | **0** |
| 12, 13, 14, 15 | **0** |

At base ID 10 and above, the report prints "_No drives answered `-d megaraid,N`. The controller
may be in HBA/IT mode..._" on a host with a working array behind the controller, and exits 0.

**This refines an adjudicated item and I am naming it.** `docs/DISPOSITIONS.md` line 123: "G,
edge cases | Megaraid probe can skip drives at sparse IDs beyond the 10-miss threshold. |
Accepted as a documented tradeoff, not a bug. Deliberate bound against a 32-iteration worst
case." The accepted tradeoff is partial loss, some drives missing from a table that still
appears. The measurement above shows total loss and a sentence asserting the opposite, which is
the same symptom the ledger classified as a wrong answer rather than a missing one when it fixed
C-016. T6's fixture answers at IDs 0, 1, 8 and 9, so the suite cannot see this.

I rate it MEDIUM rather than HIGH because I cannot establish how often a controller numbers from
10 or higher, and because the printed sentence hedges rather than asserting the array is empty.
Rate it HIGH if the field answer below comes back common. The one command that settles it, on
any host with the vendor CLI, is `perccli64 /call/eall/sall show nolog | grep -i DID`, reading
off the lowest device ID the controller reports.

**Recommendation.** Arm the miss counter only after the first hit, and bound the whole probe by
elapsed time rather than by consecutive misses, which also serves F-004.

```
        if [ "$hits" -eq 0 ] && [ "$n" -ge 12 ]; then break; fi
        [ "$hits" -gt 0 ] && [ "$misses" -ge 10 ] && break
```

with `hits=0` initialized beside `misses=0` at line 607 and `hits=$((hits+1))` beside
`misses=0` at line 616. That keeps a no-controller host at 12 wasted calls, 72s, rather than
today's 10, and finds an array based anywhere in the range. Add a T6 fixture variant whose stub
answers only at IDs 12 to 15 and assert the rows appear.

### Lines 639 to 731 — Unraid

**Assessment: Good.** The whole region exists because `mdcmd status` would write into
`/proc/mdcmd`, and it reads emhttp's own files instead. That is the worked example the rest of
the project points at. Keys are whitelisted rather than dumped, and the comment at line 642 names
the `csrf_token` in `var.ini` as the reason. The `disks.ini` awk carries `esc()` at line 673 and
the emit-at-record-boundary structure is the same shape as the DIMM parser. The empty-glob case
at line 711 is handled by the `[ -r "$f" ]` guard, so a shares directory with no `.cfg` files
produces nothing rather than a row for a literal `*.cfg` path.

**Finding:** F-024 [NITPICK] — `g()` at line 714 is defined inside the loop and reads `$f` from
the enclosing scope. It works, and redefining a function 40 times costs nothing measurable, but
a helper that silently depends on a loop variable is the kind of coupling that breaks when
someone moves the call. Pass the file as `$2`.

**Finding:** F-014 [MEDIUM] — `paste -sd', '` cycles its delimiter list. First site is line 728.

`paste -d LIST` treats LIST as a set of delimiters used circularly, not as one multi-character
separator. With `-s`, three input lines join using the first delimiter then the second. I
measured it here:

```
  printf 'a\nb\nc\n' | paste -sd', ' -     ->  a,b c
  printf 'a\nb\n'    | paste -sd', ' -     ->  a,b
```

Two items look correct, which is why this has survived. Three do not. Eight sites use the
pattern:

| Line | Value | Three or more items realistic |
|---|---|---|
| 728 | Unraid `NAME` and `COMMENT` | no, exactly two keys |
| 795 | IPv4 addresses on one interface | **yes**, a bridge with several addresses |
| 812 | `/etc/resolv.conf` nameservers | **yes**, three is the classic maximum and the common case |
| 942 | `power_supply` UPS names | rare |
| 960 | `apcaccess` MODEL and STATUS, `-sd'; '` | no, exactly two |
| 966 | UPower UPS device paths | rare |
| 1078 | VM disks, `-sd'; '` | **yes**, a Proxmox VM with three disks |
| 1079 | VM network devices, `-sd'; '` | occasionally |

A host with three resolvers renders `Resolvers: 192.0.2.1,198.51.100.1 203.0.113.1`. The data is
all there, so this is a fidelity defect rather than data loss, which is why it is MEDIUM and not
HIGH. A consumer splitting that cell on `, ` gets two fields, not three.

**This is not FR-005 reopened.** That entry diagnosed a CR sitting in front of `paste`'s
delimiter and concluded, correctly, that the symptom was not a join bug. It was looking at line
728, which has exactly two items and where the cycling never shows. This is an independent
defect at three or more items.

**Recommendation.** Replace every one with `tr '\n' ','` plus a trailing trim, or with an `awk`
join, both of which take a real multi-character separator.

```
  addrs=$("${TMO[@]}" ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{printf "%s%s", sep, $4; sep=", "}')
```

That form already appears in this file at line 949 for the apcupsd config, so it is the local
idiom rather than a new one. Add a T2 or T4 assertion on a three-item join.

### Lines 733 to 775 — filesystems and pools

**Assessment: Acceptable.** The zpool and btrfs silence is adjudicated and the comment at lines
748 to 753 states the reasoning at the site, which is the convention. `pvesm` warns only as root,
correctly.

**Finding:** F-015 [MEDIUM] — `findmnt --real` fails on util-linux below 2.28.

Lines 744 to 746:

```
  FMOUT=$("${TMO[@]}" findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | cap ...)
  printf '%s\n' "$FMOUT"
  [ -z "$FMOUT" ] && warn '`findmnt` is installed but listed no mounted filesystems.'
```

`--real` arrived in util-linux 2.28, released in 2016. RHEL 7 and CentOS 7 ship 2.23. On those
hosts `findmnt` writes "unrecognized option" to the discarded stderr, produces nothing on stdout,
and line 746 warns that it listed no mounted filesystems. The mount table is missing from the
report and the script exits 1, on a distribution the README's matrix lists as Full support.

This is also the one place in the file where an emptiness test conflates two different causes.
The `df` test three lines above cannot make the same mistake, because `df` always prints a header
row that survives the `grep -Ev` filter, so `DFOUT` is empty only when `df` itself produced
nothing. That is correct, and it is correct for a reason nobody wrote down.

**Recommendation.** Probe the flag once and fall back.

```
  FMOUT=$("${TMO[@]}" findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | cap "$FS_TABLE_LINES" "filesystem table lines")
  [ -z "$FMOUT" ] && FMOUT=$("${TMO[@]}" findmnt -t nosquashfs,notmpfs,nodevtmpfs -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | cap "$FS_TABLE_LINES" "filesystem table lines")
```

Then add a one-line comment at the `df` test saying the header is what makes its emptiness test
safe, so a future change that adds `--output=` does not quietly break it.

**Finding:** F-023 [NITPICK] — the `### Storage — filesystems and pools` heading and its code
fence at lines 733 to 734 and 775 print unconditionally, before any tool is known to exist. On a
host with none of `df`, `findmnt`, `zpool`, `btrfs` or `pvesm`, the report grows an empty fence.
`df` is coreutils, so this is close to unreachable. It is still the one section that does not
follow the capture-then-print-if-non-empty convention.

### Lines 777 to 814 — network interfaces

**Assessment: Good.** The row loop is captured into `IFROWS` for the same two reasons as the
storage table, and the comment says so. The three `cat` reads at lines 793 to 797 are the
measured exception documented in A-009, and the comment at lines 786 to 792 explains that
`$(<file)` reports a missing file on bash's own stderr, which a redirect inside the substitution
does not catch, and that this would break T2's empty-stderr assertion on someone else's host.
That is a comment doing exactly the job this project says comments are for. The `[ "$spd" -gt 0 ]
2>/dev/null` guard at line 798 handles the `-1` a bridge or a wireless interface returns.

**Finding:** F-014 [MEDIUM] at lines 795 and 812, stated above.

### Lines 816 to 840 — PCI devices

**Assessment: Good.** This is CI-001 fixed and the comment at lines 820 to 826 is the record of
it: the raw list and the filtered list are separate variables because a host can legitimately
match none of the keep-filter's device classes, and warning on the filtered emptiness called
those hosts broken. The warn at line 837 fires only when plain `lspci` worked and `lspci -nnk`
did not, which is the narrow case that is actually a failure. Correct as written.

### Lines 842 to 899 — displays

**Assessment: Good.** Three decisions are right and documented. EDID comes from sysfs rather than
`xrandr`, so it works headless and over SSH. `ddcutil` is refused with the reason stated at lines
847 to 849: DDC/CI is bidirectional over i2c-dev, so querying a monitor writes to it. And the
gate at lines 863 to 867 counts bytes read rather than trusting `stat`, because every `edid`
attribute stats as zero, which is the `dmidecode` banner trap recognized a second time.

**Finding:** F-012 [LOW] at line 893, stated above.

### Lines 901 to 972 — UPS

**Assessment: Problematic in one respect.** The layering is right and FR-002's reasoning holds:
sysfs `idVendor` is the gate because `/sys/class/power_supply` was measured empty on a host with
an attached UPS, and `lsusb -v` is refused because it issues control transfers rather than
reading cached descriptors. The vendor-ID whitelist carries the comment saying it will go stale,
which is the honest thing to write next to a two-entry list.

**Finding:** F-002 [HIGH] at line 966, stated in full in section 2.

### Lines 974 to 1014 — BMC, IPMI and racadm

**Assessment: Good.** The section gate at line 979 requires `ipmitool`, root, and a live device
node, which is the right three-part test: with the node present, a BMC that will not identify
itself is a real failure, and line 989 warns. The `elif` at line 1003 prints an explanation
rather than silence when the modules are not loaded, and says explicitly that the script will not
load them.

**Finding:** F-016 [LOW] — `tail -15` at line 1001 is an unnamed truncation constant.

```
  SEL=$(tmo 25 ipmitool sel list 2>/dev/null | tail -15)
```

The Conventions list says a `head -N` that can genuinely truncate real output goes through
`cap()` with a named constant. This truncates real output. It cannot use `cap()`, because `cap`
takes the head and this needs the tail, and the truncation is disclosed in the heading text at
line 1002. What is missing is the named constant: 15 is a tuning knob living 900 lines away from
the block where every other knob lives. **Recommendation:** add `IPMI_SEL_LINES=15` to the
constants block with a comment saying it is a tail and therefore not a `cap()` site, and use it
in both the `tail` and the heading `printf`.

### Lines 1016 to 1099 — Proxmox

**Assessment: Problematic in one respect.** The emptiness tests on `pct list` and `qm list` at
lines 1038 and 1068 are correct and the comment says why: those commands print a header even with
zero guests, so an entirely empty result means the command failed. The `unprivileged` mapping at
line 1052 defaults an absent key to `no`, which is the right default. The `pvecm` silence is
adjudicated and commented at the site.

**Finding:** F-017 [MEDIUM] — a failing `pct config` or `qm config` drops a guest with no warning.

Lines 1044 to 1045, and identically at 1074 to 1075:

```
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
```

`pct list` already told us this VMID exists. If `pct config` then returns nothing, the tool was
present, permitted and returned nothing, which is the exact definition of a warning in this
project's contract. Instead the guest vanishes from the table.

Two scenarios. In the narrow one, a container is destroyed between `list` and `config` and one
row is missing, which is benign. In the wider one, pmxcfs is degraded enough that `pct list`
answers from cache while `pct config` times out for every guest. Then `CTROWS` stays empty, the
`if [ -n "$CTROWS" ]` at line 1058 suppresses the whole table, and a Proxmox host with 20
containers produces a report with no LXC section and **exit 0**. A consumer reading that report
concludes the host runs no containers. That is the silent-wrong-answer direction the contract
calls the worse one.

**Recommendation.** Count the skips and warn once, outside both loops, in the main shell.

```
      [ -z "$CFG" ] && { ctskip=$((ctskip + 1)); continue; }
```

with `ctskip=0` beside `CTROWS=""` at line 1042, and after the loop:

```
    [ "$ctskip" -gt 0 ] && warn "\`pct config\` returned nothing for $ctskip of the container(s) \`pct list\` reported — those containers are absent from the LXC table."
```

Both loops are `for` loops in the main shell, not pipeline bodies, so `warn` is safe here. T5
covers Proxmox parsing already: add a stub whose `pct list` reports two VMIDs and whose `pct
config` fails for one, then assert the warning names it and the exit code agrees.

### Lines 1101 to 1176 — Docker

**Assessment: Good, with two small findings.** This region carries the most hard-won detail in
the file and all of it is documented. `DNET=""` at line 1159 is initialized before the guard that
assigns it, with the comment naming A-001 and T12. The CNAMES site refuses `cap()` and defers its
marker to after the table, because the list is word-split into `docker inspect`'s arguments and a
marker line would become a bogus container name. The truncation test at line 1151 compares the
capped and uncapped lists rather than counting, and the comment explains why that comparison is
exact in both directions. The container-networks table is deliberately exempt from the `|` escape
because `|` is that parser's own field separator, and the comment says so.

**Finding:** F-018 [LOW] — the gate cannot distinguish a refusal from a timeout.

Line 1106:

```
if have docker && "${TMO[@]}" docker info >/dev/null 2>&1; then
```

The adjudicated rule is that `docker info` failing is the section gate and not a warning, because
a stopped daemon or a user outside the `docker` group is a legitimate state. I am not reopening
that. The narrower case is exit code 124, which `timeout` returns and which means the daemon
socket exists and did not answer within 10s. That is closer to present-and-permitted-and-silent
than to absent. **Recommendation:** capture the status and warn only on 124, leaving every other
non-zero status silent as today. If you would rather not split the gate, the alternative is one
comment at line 1106 saying the timeout case is deliberately folded into the gate, which makes
the judgment explicit instead of implicit.

**Finding:** F-019 [LOW] — `docker ps -a` runs twice.

Lines 1118 and 1145 both call `docker ps -a --format`, once for the table and once for the names.
`CNAMES_ALL` is field one of `DPSRAW`. Two costs: a second 10s budget against the daemon, and a
window in which a container created between the calls appears in one table and not the other.

```
  CNAMES_ALL=$(printf '%s\n' "$DPSRAW" | cut -f1)
```

That removes the round trip and the race. Verify against T11, whose stub answers with 105
containers, and T12, whose stub answers with zero, since `cut` on an empty string yields an empty
string and the existing comparison at line 1151 still holds.

### Lines 1178 to 1188 — failed systemd units

**Assessment: Good.** This is the one section that prints an explicit negative, `None.`, rather
than disappearing. That is correct and not an inconsistency: "no failed units" is a fact worth
recording, whereas "no RAID controller" is the absence of hardware. Correct as written.

### Lines 1190 to 1206 — warnings block, footer and exit

**Assessment: Good.** The warnings block prints before the footer so the footer stays last, the
prose tells the reader to treat the named sections as unknown rather than empty, and the exit is
the last statement in the file. `[ "$WARNCOUNT" -eq 0 ] || exit 1` followed by `exit 0` is
explicit rather than relying on the last command's status. Correct as written.

**Finding:** F-021 [NITPICK] — the file uses `printf` for everything with a format and `echo` for
bare separator strings such as `echo "--- df -hT ---"` at line 736 and `echo "--- virtual drives
---"` at line 572. Nine such sites exist. Under bash's builtin `echo` a leading `---` prints
literally, so nothing is broken. `cap()` at line 132 already writes `printf -- '--- ...'` with the
`--` guard, so the file demonstrates both habits. Pick one.

**WALKTHROUGH COMPLETE — every region from line 1 to line 1205 is covered above.**

---

## 5. Readability and maintainability

### The stranger-in-six-months test

This file passes it, and it passes for a specific reason: the comments record decisions, not
mechanics. A stranger reading lines 264 to 267 learns that `lsblk -P` is not a style preference
but the fix for a column-shift bug. A stranger reading lines 429 to 431 learns that
`dmidecode` prints a banner on failure, which is why the test counts records. Neither fact is
recoverable from the code.

### Naming

Two-tier and mostly consistent. Globals are uppercase (`DISKS`, `LSBLK_RAW`, `MRROWS`), loop
locals are lowercase (`name`, `size`, `poh`, `tmp`). The helpers are terse: `fld`, `kv`, `yk`,
`osr`, `uval`, `g`, `hs`, `pct` inside awk. Short names are defensible in a file this dense, and
each has a definition within a few lines of every use, except two. `g` at line 714 is one
character and is defined inside a loop. `pct` as an awk function at line 669 shares its name with
the Proxmox `pct` binary used 90 lines later. Neither causes a bug. Both cost a reader a second
look.

### Function length and nesting

No function exceeds ten lines. The longest is `cap` at nine. The nesting lives in the top-level
sections instead, and the deepest is the megaraid probe: `if have lspci` to `if [ -n "$RAIDCTL" ]`
to `if is_root && have smartctl` to `if [ -n "$MRTGT" ]` to `for n` to `if !`, six levels at line
610. The Docker region reaches five.

### Cyclomatic complexity read, lines 544 to 637

I counted the decision points in the RAID region: 1 base, plus 14 `if` and `elif` branches, plus
2 loops, plus 5 short-circuit operators, plus 3 `case`-equivalent grep alternations that gate
control flow. That is roughly **25**, in 93 lines, which is high for shell and the highest in this
file. The Docker region scores about 16 and the network region about 12.

**Does it need splitting? Not on complexity alone.** The region does three separable things:
detect a controller, run whichever vendor CLI exists, and probe drives behind the controller. The
third is the complex part and it is already the natural extraction. Pulling lines 592 to 636 into
`megaraid_probe()` would cut the region to about 14 and give F-013's fix a place to live where a
test can call it directly. That is a smaller move than C-031's full `section_*()` split and does
not reopen it. I raise no finding, because the churn is only justified if you take F-013.

### Magic numbers and strings

Thirteen are named and documented (lines 44 to 97). Three are not: `tail -15` at line 1001
(F-016), `{0..31}` at line 608 and `-ge 10` at line 613 (both inside F-013). The `-n 4` in
`strings -n 4` at line 886 and the `{5,}` in the filter at line 887 are parser tuning rather than
output caps and are fine inline, though a word on why 4 and 5 would help.

### Comment coverage, judged against this project's standard

Missing, misleading and redundant are all defects. I found:

- **Missing, three places.** No comment says why `fld`'s pattern is shaped as it is (F-008). No
  comment says why the `df` emptiness test is safe while `findmnt`'s is not (F-015). No comment
  records the racadm never-warns judgment, which every other never-warns site carries (F-025,
  section 7).
- **Misleading, none found.** Every comment I checked against the code was accurate. I checked
  the `cap` SIGPIPE claim, the `$(<file)` stderr claim, the `power_supply` gate claim, the
  CNAMES word-split claim and the `TYPE=disk` zvol claim. All hold.
- **Redundant, none.** I looked for restated code specifically because this project's convention
  invites over-correction in the other direction. I did not find any.

### Dead code, duplication, hidden coupling

No dead code. The remaining duplication is deliberate and adjudicated: the two SMART parse
blocks differ in three of eight fields and A-005 refused to merge them, correctly. Hidden
coupling has two instances. `cfgget` at line 1030 reads the global `CFG` implicitly, so it works
only when called immediately after a loop sets it. `g` at line 714 reads `$f` the same way. Both
would take one parameter and lose the coupling.

### Discoverability of the tuning knobs

Good. One block, thirteen constants, a comment each, and a rule for when to merge two. A new
maintainer changing a cap does not have to grep for a number. F-016 and F-013's bounds are the
three exceptions.

---

## 6. Shell idiom review

### Shebang

`#!/usr/bin/env bash` at line 1. Correct for the features used: arrays (line 144), `$'...'`
quoting (line 187), `${var//pattern/repl}` (line 187), brace expansion (line 608), process
substitution (line 1124), `$(<file)` (line 379) and `EUID` (line 207). All are bash 3.0 or
earlier, so the shebang matches the stated floor. The `env` form is right for Unraid and Arch,
where bash may not be at `/bin/bash` in the way a hardcoded path assumes. Line 18 tells the
operator to invoke with `bash` explicitly so a fish login shell cannot interfere, which is a real
problem this project has hit.

**One construct exceeds the floor**, and it is F-007's `"${TMO[@]}"` on an empty array, which
needs bash 4.4.

### `set -u`, and whether conditionally assigned variables are initialized

`set -u` at line 29 is deliberate and `set -e` and `pipefail` are adjudicated, so I audited only
the third question the prompt asks. I traced every variable that is assigned inside a conditional
and read outside it:

| Variable | Assigned inside | Read outside | Initialized first |
|---|---|---|---|
| `DMIMEM` | `is_root && have dmidecode` (426) | 440 | **yes**, line 422 |
| `DNET` | `[ -n "$CNAMES" ]` (1162) | 1170 | **yes**, line 1159 |
| `LSBLK_RAW`, `LSBLK_DISKS`, `DISKS` | `have lsblk` (276) | 480, 491, 603 | **yes**, lines 272 to 274 |
| `LSPCI_RAW`, `RAIDCTL` | `have lspci` (550) | 558, 837 | **yes**, lines 547 to 548 |
| `LSCPU`, `FREE` | `have lscpu`, `have free` (239, 245) | 346, 356, 421 | **yes**, lines 238, 244 |
| `MONROWS`, `UPSROWS` | loops (893, 937) | 896, 970 | **yes**, lines 856, 918 |
| `MRROWS`, `CTROWS`, `VMROWS` | loops (625, 1053, 1080) | 628, 1058, 1085 | **yes**, lines 607, 1042, 1072 |
| `DPSROWS` | `[ -n "$DPSRAW" ]` (1122) | 1126 | **yes**, line 1119 |
| `OSNAME`, `OSID` | `[ -r /etc/os-release ]` (221) | 229, 291 | **yes**, line 214 |
| `WARNINGS`, `WARNCOUNT` | `warn` | 1192 | **yes**, lines 164 to 165 |
| `CFG` | both guest loops (1044, 1074) | `cfgget` (1030) | no, but every call follows an assignment in the same iteration |
| `n` (edid byte count) | 866 | 867 | uses `${n:-0}`, belt and braces |

**Every one is safe.** This is the cleanest part of the review. The two that matter, `DMIMEM` and
`DNET`, both carry comments naming the bug that taught the lesson. `set -u` is used correctly
throughout, and the only `set -u` hazard in the file is the empty-array expansion, which is a
bash-version problem rather than an initialization problem.

### Quoting discipline

One unquoted expansion is intentional and marked: `$CNAMES` at line 1162 with `# shellcheck
disable=SC2086` and a comment. Two more rely on word splitting without a directive: `for d in
$DISKS` at line 500 and `for id in $CTIDS` and `$VMIDS` at lines 1043 and 1073. O-001 adjudicated
those as harmless because the values are whitespace-free by construction, and rejected converting
them as a priority rather than as an edit. That verdict is right and I am not reopening it.

**One thing the O-001 note and the line 1133 comment both address only half of.** Unquoted
expansion is subject to pathname expansion as well as word splitting. A container name containing
`*`, `?` or `[` would glob against the working directory. Docker's own name grammar is
`[a-zA-Z0-9][a-zA-Z0-9_.-]*`, which excludes all three, so the code is safe. Kernel device names
and Proxmox VMIDs are equally safe. The comments say "whitespace-free by construction", which
covers splitting and not globbing. One extra clause would close the reasoning. No finding.

Everything else is quoted, including every `"$@"`-style expansion, every path built from a runtime
value (`"/dev/$d"`, `"/sys/class/net/$ifc/speed"`, `"$dev/manufacturer"`), and every `[ ]` operand.

### `[[ ]]` versus `[ ]`, and arithmetic

The file uses `[ ]` exclusively and `case` for pattern matching (lines 470, 862, 926, 1052). That
is the right choice at a bash 3.0 floor and it also keeps the code readable to anyone who works in
POSIX shell. Arithmetic uses `$(( ))` throughout with no `$` inside, which is correct. No `let`,
no `expr`.

### Arrays versus whitespace-split strings

`TMO` is the only array and it is used for argument building, which is the case where an array is
genuinely required. `WARNINGS`, `MRROWS`, `CTROWS`, `VMROWS`, `DPSROWS`, `UPSROWS` and `MONROWS`
are newline-joined strings, and the comment at line 155 says why: an array would be empty at
`set -u` time on older bash. That reasoning is correct, and it is the same reasoning F-007 says
was not applied to `TMO`.

### `local` and `readonly`

Every helper that needs `local` has it: `cap` (126 to 127), `tmo` (149), `row` (186), `yk` (195).
`cap` splits `local out` from `out=$(...)` on separate lines, which avoids the SC2155 trap where
`local x=$(cmd)` masks the command's exit status. That is a deliberate and easily missed detail.
`fld`, `have`, `kv`, `is_root`, `osr`, `uval`, `g` and `cfgget` use only positional parameters or
globals and need nothing. No constant is `readonly` (F-020).

### `printf` versus `echo`

`printf` for everything with a format or a variable, `echo` for nine bare separator strings
(F-021). No `echo "$var"` anywhere, which is the case that actually breaks.

### Subprocess cost and useless use of cat, grep, echo

No useless `cat` outside the three documented sysfs reads at lines 793 to 797, which are a
measured exception with the measurement recorded. No `cat file | grep`. No `grep | wc -l`, since
line 427 uses `grep -c` directly. The costly patterns are `fld` at six `sed` forks per disk (line
460) and `uval` at eight `awk` forks over the same small file (line 648). Both are cheap in
absolute terms. See section 10.

### Safe iteration over filenames

Four glob loops, all guarded. Lines 857, 711, 931 and 923 each test `[ -r ]` or `[ -e ]` on the
first line of the body, so an unmatched glob that expands to its own literal pattern is skipped
rather than processed. `for f in /boot/config/shares/*.cfg` is the case that would otherwise
produce a share named `*`. No `for f in $(ls ...)` anywhere.

### Exit codes

Two, 0 and 1, documented at lines 20 to 27 and in README's exit-code table, and both meaningful.
`124` is deliberately not produced by the script and T3 asserts against it, so a 124 from the
suite means a hang rather than a collector failure. That is a real and useful third state
obtained for free.

**One weakness, which is F-007's consequence rather than a separate finding.** Exit 1 has two
possible causes: an honest incomplete collection, and a shell abort. The first prints a warnings
block, the second does not. `rc_agrees` in the test suite tests exactly that distinction, which
means the suite already encodes the right invariant. A caller in production has no equivalent, so
the README's `|| echo "incomplete"` idiom cannot tell the two apart. Suggesting a distinct exit
code for the abort case is not possible without a trap, and a trap is out of scope here.

### Minimum bash version for anything I recommend

Every construct I recommend in this review works on bash 2.0 or later: `${TMO[@]+"${TMO[@]}"}`,
`SECONDS`, `cut -f1`, an `awk` join, and an extra `case` arm. Nothing I propose raises the floor.

---

## 7. Error handling and the exit-code contract

### The contract as stated

From `.claude/rules/collectors.md`: the report is written in full either way, exit 0 means
collection complete, exit 1 means one or more collectors failed and the report ends with a `##
Collection warnings` block naming them. A warning means the tool was present, permitted, and
still returned nothing. A tool that is absent, or that needs root on an unprivileged run, is
silent.

### Does every collector's warn-or-silent decision match the rule?

I checked all 21 `warn` call sites and every collector that chooses not to warn.

**Warns where it should be silent, confirmed: two.**

- **Line 248, `free`.** F-009. BusyBox `free` rejects `-h`, so an Alpine host warns and exits 1
  while `/proc/meminfo` sits readable.
- **Line 746, `findmnt`.** F-015. `--real` does not exist below util-linux 2.28, so RHEL 7 warns
  and exits 1.

Both share a shape: the emptiness test cannot tell "the tool answered nothing" from "the tool
rejected the flag". That is the same class as the `dmidecode` banner problem the memory section
already solved, and neither site has the equivalent of that section's record count.

**Warns where it should be silent, suspected: two. I could not verify either.**

- **Line 284, `lsblk` in a container.** In an unprivileged LXC or a Docker container, `lsblk`
  usually enumerates the host's block devices through `/sys`, in which case the warning never
  fires. If a container's `/sys` is masked, it would. `QUEUE.md` already wants an unprivileged-LXC
  answer for FR-004, so this is one more question for the same host: run the script in an
  unprivileged LXC and check whether the warnings block names `lsblk`.
- **Line 806, `ip` with only loopback.** A container started with no network namespace attachment
  has only `lo`, which is a legitimate state, and this warns. Out of scope for the README's
  platform matrix, so I raise no finding.

**Silent where it should warn, confirmed: one.**

- **Lines 1044 and 1074, `pct config` and `qm config`.** F-017. Present, permitted, returned
  nothing, guest silently dropped.

**Silent where it should warn, arguable: one. This is a finding.**

**F-025 [LOW]: the racadm section never warns and does not say why.**

Lines 1008 to 1014:

```
if have racadm && is_root; then
  RAC=$(tmo 20 racadm getsysinfo 2>/dev/null \
    | grep -viE 'password|community' | cap "$RACADM_LINES" "racadm lines")
  if [ -n "$RAC" ]; then
```

There is no `else`. `racadm` present plus root means present and permitted, which is the same
shape as `ipmitool mc info` 20 lines above, and that one warns at line 989. The difference is
that IPMI has a hardware-presence gate, `[ -e /dev/ipmi0 ]` at line 979, and racadm has none.
`racadm` arrives with Dell OMSA and can be installed where no iDRAC answers, so silence is
probably the right call. The defect is not the decision. It is that this is the only never-warns
site in the file with no comment recording the decision. Lines 748 to 753 (zpool and btrfs), 853
to 855 (displays), 915 to 917 (UPS) and 1092 to 1094 (pvecm) all carry one, and that consistency
is what stops the next maintainer "fixing" it. **Recommendation:** add two lines saying racadm has
no device-node gate, so an absent iDRAC and a silent one are indistinguishable here, and silence
is the deliberate choice.

**Correct in both directions, and worth affirming: the rest.** `zpool`, `btrfs`, `pvecm`,
displays and UPS never warn, all adjudicated and all commented at the site. `docker info` is a
gate rather than a warning. `pvesm`, `pct list` and `qm list` warn only as root. The `lspci`
warning fires on the raw list and not the filtered one. The `lsblk` warning fires on
`LSBLK_RAW` and not `DISKS`, and the second `lsblk` warning at line 481 stays quiet when the
first already fired.

### Does anything test for emptiness where emptiness is not the failure signal?

| Line | Test | Verdict |
|---|---|---|
| 284 | `[ -z "$LSBLK_RAW" ]` | correct, raw not filtered, commented |
| 432 | `[ "$SLOTS" -eq 0 ]` | correct, record count not emptiness, commented |
| 481 | `[ -n "$LSBLK_RAW" ]` before warning | correct, avoids the double warn |
| 554 | `[ -z "$LSPCI_RAW" ]` | correct, raw not filtered, commented |
| 739 | `[ -z "$DFOUT" ]` | correct, but by accident. `df` always prints a header that survives the `grep -Ev`, so `DFOUT` is empty only on total failure. Nothing says so. |
| 746 | `[ -z "$FMOUT" ]` | **wrong.** Conflates an unsupported flag with no mounts. F-015. |
| 837 | `[ -n "$LSPCI_RAW" ] && [ -z "$PCIRAW" ]` | correct, this is CI-001 |
| 866 | `[ "${n:-0}" -gt 0 ]` | correct, bytes read not `stat` size, commented |
| 1038, 1068 | `[ -z "$PCTRAW" ]` | correct, the header is always present, commented |
| 1151 | `[ "$CNAMES" = "$CNAMES_ALL" ]` | correct, prefix comparison rather than a count, commented |

### Every `warn` reachable from inside a subshell

**None.** I enumerated all 21 call sites and traced the enclosing construct of each.

| Lines | Enclosing construct | Subshell |
|---|---|---|
| 242, 248, 284 | top-level, or inside `if have ...` | no |
| 329, 354, 432 | inside `if`, top level | no |
| 481 | `if`/`else` after `DEVROWS=$(...)` completes | no |
| 532 | after the `for d in $DISKS` loop, which is itself in the main shell | no |
| 554, 705, 739, 746, 772 | inside `if`, top level | no |
| 806 | `if`/`else` after `IFROWS=$(...)` completes | no |
| 838, 989, 1025, 1039, 1069, 1110 | inside `if`, top level | no |

The two places that could have gone wrong, the storage device loop at line 464 and the interface
loop at line 784, are both `... | while read` pipelines and therefore subshells. Both are captured
into a variable and tested outside, with the reason stated in a comment at each site. That is the
G-002 rule applied correctly.

**One thing the linter does not cover, and I measured it.** I fed ShellCheck 0.9.0 a five-line
script that mutates a global from a `warn()` function called inside a pipeline body. ShellCheck
reported nothing. SC2030 and SC2031 catch a direct assignment inside a pipeline, and do not follow
the mutation through a function call. So the G-002 rule is held by the convention, the comments
and code review, and by nothing mechanical. That is worth knowing before anyone assumes CI would
catch a regression.

### Failure table

| Line(s) | Operation | Can it fail | Detected | Handled | Consequence |
|---|---|---|---|---|---|
| 212 | `hostname` | yes | `\|\| echo unknown` | yes | frontmatter says `unknown` |
| 219 to 229 | os-release parse | yes | falls to `/etc/unraid-version`, then `uname -o` | yes | OS field degrades, never empty |
| 239, 241 | `lscpu`, then `/proc/cpuinfo` | yes | line 242 warns if both fail | yes | correct |
| 245 | `free -h` | yes | line 248 warns | **partly** | false warn on BusyBox, F-009 |
| 253 | `systemd-detect-virt` | yes | `\|\| true`, `PLATFORM` stays `bare-metal` | yes | a VM may be reported as bare metal, silently. Acceptable: the field is a hint, not a fact. |
| 276 | `lsblk` | yes | line 284 warns on empty raw | yes | correct |
| 319 | `pveversion` | **hangs** | no | **no** | F-003, script stops before any section |
| 426 | `dmidecode -t memory` | yes | line 432, record count | yes | correct |
| 504 | `smartctl` per disk | yes | `(no data)` row, `SMOK` counter, line 532 | yes | correct |
| 609 | `smartctl -d megaraid,N` | yes | miss counter | **partly** | F-013, total loss above base ID 10, no warn |
| 570 to 576 | vendor CLI | yes | empty output, section prints an empty fence | partly | an empty fence is ugly but honest |
| 661 | `disks.ini` awk | yes | line 705 warns | yes | correct |
| 737 | `df` | yes | line 739 | yes | correct, see the header note |
| 744 | `findmnt --real` | yes | line 746 | **no** | F-015, false warn on old util-linux |
| 784 | `ip -o link` | yes | line 806 | yes | correct |
| 827 | `lspci -nnk` | yes | line 837, gated on raw | yes | correct, CI-001 |
| 958, 966 | `apcaccess`, `upower` | yes | none, row omitted | yes | correct, UPS never warns by design |
| 982 | `ipmitool mc info` | yes | line 989 | yes | correct |
| 1009 | `racadm getsysinfo` | yes | none | **arguable** | F-025, section vanishes silently |
| 1037, 1067 | `pct list`, `qm list` | yes | lines 1039, 1069 as root | yes | correct |
| 1044, 1074 | `pct config`, `qm config` | yes | none | **no** | F-017, guest or whole table vanishes, exit 0 |
| 1106 | `docker info` | yes | gate | yes | adjudicated. 124 folded in, F-018 |
| 1162 | `docker inspect` | yes | `NF==2` filter drops bad rows | partly | a malformed row is dropped silently, which is right for a parser gate |

### Partial-failure state

If the script dies at line N the report is truncated at line N, with no warnings block and no
footer. Two things can kill it and only two, because `set -e` is absent and every external
failure is absorbed.

1. **A `set -u` unbound variable in the main shell.** A-001 was one instance and T12 covers it.
   F-007 is a second. Both produce exit 1 with no warnings block, which a caller cannot
   distinguish from an honest incomplete collection.
2. **A signal**, including an outer `timeout` around the whole script, or an uninterruptible
   kernel read as described in section 3.

The footer at line 1200 is therefore load-bearing: its presence is the only in-band evidence that
the script reached the end. T2 and T3 both assert it, and `rc_agrees` asserts the
warnings-block-if-and-only-if-exit-1 half. Together those two invariants cover the whole
partial-failure space, which is a better test design than most projects manage.

### Silent failure paths, enumerated

Every path below produces a report that reads as fact and is not. Six are correct by design and
adjudicated. Three are findings.

| Path | By design | Finding |
|---|---|---|
| `zpool` / `btrfs` empty | yes, adjudicated | no |
| `pvecm` fails on a standalone node | yes, adjudicated | no |
| Displays section absent | yes, adjudicated | no |
| UPS section absent | yes, adjudicated | no |
| Docker section absent after a failed `docker info` | yes, adjudicated | F-018 only for the 124 case |
| A single blank `dmi` field, as root, with the other three populated | yes, cell shows `—` | no |
| `MAXCAP` empty | yes, cell shows `—` | no |
| `pct status` / `qm status` empty | yes, cell shows `—`, the row still appears | no |
| **`pct config` / `qm config` empty** | **no** | **F-017** |
| **megaraid probe with base device ID 10 or higher** | **no** | **F-013** |
| **`racadm` present, root, returns nothing** | undocumented | **F-025** |

F-013 deserves one more sentence here, because it sits on the boundary. The section does print a
hedged sentence rather than vanishing, so it is not fully silent. But the sentence names two
causes, HBA mode and `cciss`, and does not name the third, which is that the probe stopped
before reaching the drives. A reader acts on the two causes given.

---

## 8. Static analysis

### What I actually ran

ShellCheck 0.9.0 was available in this environment, so this section is measured rather than
assumed.

```
shellcheck -S warning -f gcc hw-inventory.sh   ->  no output, rc 0
shellcheck -f gcc hw-inventory.sh              ->  43 notes, rc 2
```

**The stated baseline holds.** Zero errors and zero warnings at severity `warning`, which is
exactly what T7 asserts at line 261 of `tests/run.sh`. The 43 notes break down as 42 x SC2016 and
1 x SC2012, and neither reaches the baseline's severity.

The 42 SC2016 hits are all false positives by construction: "Expressions don't expand in single
quotes" fires on every single-quoted warning message containing a backtick-wrapped tool name, such
as line 248's `'`free` is installed but reported no total memory...'`. Those backticks are
Markdown, not command substitution. Nothing to fix, and raising the CI severity to catch notes
would flood the log with them.

### What the default ruleset misses

The interesting output of this section is not what ShellCheck found. It is what it cannot.

| Code | Line | Severity | Message | Fix |
|---|---|---|---|---|
| SC2012 | 374 | note | `Use find instead of ls to better handle non-alphanumeric filenames.` | Not worth fixing. The path is `/sys/kernel/iommu_groups` and its entries are integers. A `find ... \| wc -l` would be slower and no safer. Below the CI baseline, so it costs nothing today. |
| `[no-rule-id]` | 144 to 145, and 24 expansion sites | would be error | Empty array expanded under `set -u`. ShellCheck has no check for the bash-version boundary at 4.4. | F-007. `${TMO[@]+"${TMO[@]}"}` |
| `[no-rule-id]` | 460 | would be warning | Unanchored greedy `sed` capture returns the last matching key. No linter models this. | F-008 |
| `[no-rule-id]` | 728, 795, 812, 942, 960, 966, 1078, 1079 | would be warning | `paste -d` given a two-character list is a delimiter cycle, not a separator. ShellCheck does not model `paste` semantics. | F-014 |
| `[no-rule-id]` | 570, 573, 576 | would be error | A dependency writes a file the script never names. No static tool can see this. This is the fastfetch lesson, and F-001 is the same class. | F-001 |
| SC2030 / SC2031 | n/a | n/a | **Measured: does not fire.** I gave ShellCheck 0.9.0 a script that mutates a global from a `warn()`-shaped function inside a pipeline body. It reported nothing. The G-002 rule has no mechanical enforcement. | Keep the convention and the comments. Consider a T1 grep for `warn ` on a line inside a `\| while` block, which is crude but would catch the obvious regression. |
| SC2016 x42 | many | note | False positive on Markdown backticks inside single quotes. | None. Do not "fix" these by switching to double quotes, which would turn the backticks into command substitution and is a genuinely dangerous edit. |

### The one `disable` directive, and whether it hides a problem

Line 1161:

```
    # shellcheck disable=SC2086
    DNET=$(tmo 15 docker inspect -f '...' $CNAMES 2>/dev/null \
```

**It does not hide a problem, and it is correctly placed.** SC2086 warns about word splitting and
globbing on an unquoted expansion. Splitting is the intent here, and the comment at lines 1132 to
1134 says so. Globbing is not addressed by that comment, and is safe only because Docker's name
grammar excludes `*`, `?` and `[`. The directive is scoped to the single line rather than
file-wide, which is the right granularity. **Recommendation, no finding:** extend the existing
comment by one clause naming glob metacharacters, so the reasoning is complete on the page rather
than in someone's head.

### Two constructs a linter passes and a reviewer should not

- **Line 798:** `if [ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null; then`. The redirect applies to
  the second `[` only. When `$spd` is non-numeric, `[` writes "integer expression expected" to the
  stderr that redirect discards and exits 2, which `&&` treats as false. The construct works and
  is correct. It works by relying on a builtin's error going to its own stderr, which is subtle
  enough to deserve the half-line comment it does not have.
- **Line 1129:** `[ "$(printf '%s\n' "$DPSRAW" | wc -l)" -gt "$DOCKER_LIST_LIMIT" ]`. When
  `DPSRAW` is empty this counts 1, not 0, because `printf '%s\n' ""` emits one newline. The
  comparison against 100 is unaffected, so there is no bug. The same idiom at a limit of 0 would
  be wrong.

## 9. Edge cases and failure modes

Format is trigger, then resulting behavior, then fix. I ran the script's own `cap()` and `row()`
against the hostile inputs below rather than reasoning about them, so the first two groups are
measured. CONFIRMED and SUSPECTED are separated at the end of each group.

### A tool is present and returns empty output

| Trigger | Behavior | Verdict |
|---|---|---|
| `lscpu` exits 0 with no output | line 354 warns, the Model row falls back to `/proc/cpuinfo` | CONFIRMED correct |
| `free -h` rejected as an unknown flag | line 248 warns, RAM fields blank | CONFIRMED wrong, F-009 |
| `findmnt --real` rejected as an unknown flag | line 746 warns, mount table missing | CONFIRMED wrong, F-015 |
| `dmidecode -t memory` prints its banner and no records | line 432 keys on the record count and warns | CONFIRMED correct, and this is the pattern the other two need |
| `docker ps -a` returns zero containers | line 1159 pre-initializes `DNET`, the section reaches its footer | CONFIRMED correct, T12 |
| `pct config` returns nothing for every guest | table silently absent, exit 0 | CONFIRMED wrong, F-017 |

### A tool returns malformed output

| Trigger | Behavior | Verdict |
|---|---|---|
| An `lsblk -P` line with no `NAME=` field | line 466 `[ -z "$name" ] && continue` drops the row | CONFIRMED correct |
| `docker inspect` emits a line with more or fewer than two `\|` fields | line 1164 `NF==2` drops it | CONFIRMED correct, and the comment says why no escape pass runs here |
| `pct config` emits a key with no `: ` separator, such as a bare `description:` | `cfgget` returns empty, the cell shows `—` | CONFIRMED acceptable |
| A future `lsblk` gains a column whose name ends with an existing one | `fld` returns the wrong column | CONFIRMED, measured, F-008 |
| `smartctl` prints an ATA attribute table with shifted columns | `awk '{print $10}'` at lines 516, 519, 520, 523, 526 reads whatever is in field 10 | SUSPECTED. Positional field reads on vendor-formatted output are inherently brittle. I found no case where current smartmontools shifts them, and the two-way fallbacks cover the ATA-versus-SCSI split, so I raise no finding. |

### `cap()` at exactly the boundary

Measured against the real function, limit 3:

| Input lines | Output | Marker |
|---|---|---|
| 0 | 0 bytes | no |
| 3 | 3 lines | no |
| 4 | 3 lines | yes, `--- truncated at 3 lines ---` |

CONFIRMED correct in all three directions, which is what T10 asserts. One undocumented behavior:
input of `1`, `2`, blank produced two lines, not three. `out=$(head ...)` strips trailing
newlines, so `cap` also eats trailing blank lines. Inside a code fence that is invisible, and no
current caller cares. Worth one clause in the comment at line 111.

### Cells containing spaces, `|`, CR, or unicode

Measured against the real `row()`:

| Input cell | Output | Verdict |
|---|---|---|
| `a\|b` | `\| a\\\|b \|` | CONFIRMED correct, C-004 |
| `cr<CR>here` | `\| crhere \|` | CONFIRMED correct, FR-005 |
| `Nöthing 日本語` | passes through unchanged | CONFIRMED correct |
| a device model with spaces | passes through, one cell | CONFIRMED correct |
| a cell containing a newline | **the row breaks after the newline** | see below |

**Unicode is safe for a reason worth stating.** `LC_ALL=C` at line 30 makes bash and every tool
byte-oriented. `${c//|/\\|}` at line 187 therefore matches bytes, and that is safe only because
UTF-8 is ASCII-transparent: no continuation byte of a multi-byte sequence can be `0x7C`. If the
script ever switched to a different multi-byte encoding the escape would corrupt text. It will
not, so this is an affirmation rather than a finding.

**Unicode is lost in one place, and this is CONFIRMED.** The `strings` fallback for displays
filters through `grep -E '^[[:alnum:]][[:alnum:] ._+/-]{5,}$'` at line 887. Under `LC_ALL=C`,
`[[:alnum:]]` is ASCII only, so a monitor whose product name contains a non-ASCII character is
dropped from the fallback entirely and the row prints `(EDID present, not parsed)`. The
`edid-decode` path is unaffected. The consequence is small and the filter exists to drop timing
bytes, so I raise no finding. It belongs in the FR-004 field-test note if anyone tests EDID
against a non-English panel.

**The newline case, SUSPECTED, and it touches a ledger note.** `row()` strips CR and does not
fold LF. The FR-005 entry records that a newline fold was drafted and cut as unreachable, on the
grounds that "`awk` splits on newlines before a value ever reaches a cell, and every other
`row`/`kv` call site is single-line by construction (`paste -s`, `head -1`, `printf`
accumulation)". Line 938 is the one call site that fits none of those three descriptions:

```
  UPSROWS="${UPSROWS}$(kv "USB device" \
    "$(cat "$dev/manufacturer" 2>/dev/null) $(cat "$dev/product" 2>/dev/null) ($vid:$(cat "$dev/idProduct" 2>/dev/null)$drv)")
```

`manufacturer` and `product` are USB string descriptors supplied by the device, not generated by
the kernel. A device that reports a descriptor containing `0x0A` would break the UPS row. I have
no such device and cannot demonstrate it, so this is SUSPECTED and I raise no finding. If you
ever revisit the fold, this is the counter-example to "unreachable".

### Unset variables under `set -u` where the assignment is inside a conditional

Fully audited in section 6. Every conditionally assigned variable read outside its guard is
initialized first. The one hazard is F-007, which is a bash-version problem rather than an
initialization problem.

### Empty glob expansion

Four glob loops, all measured safe by the same guard. With no matching file, `for f in
/tmp/eg/empty/*.cfg` yielded the literal pattern and `[ -r "$f" ] || continue` skipped it.
Lines 711, 857, 923 and 931 all follow that shape. CONFIRMED correct, and this is the case that
would otherwise produce a share named `*.cfg` in the report.

### A `/sys` attribute that exists but reads empty

| Trigger | Behavior | Verdict |
|---|---|---|
| `/sys/class/net/br0/speed` returns EINVAL | `cat` fails, `spd` empty, `[ -n "$spd" ]` false, cell shows `—` | CONFIRMED correct |
| an `edid` attribute that stats 0 and reads 256 bytes | line 866 counts bytes read, not `stat` size | CONFIRMED correct, and T15's symlink fixture defends it |
| `/sys/bus/usb/devices/*/manufacturer` absent while `product` exists | line 938 produces a cell with a leading space, `\|  Model (051d:0002) \|` | CONFIRMED cosmetic. No fix needed. |
| an `edid` attribute that reads exactly 0 bytes | connector skipped | CONFIRMED correct |

### CRLF input from a FAT32 mount

`row()` strips CR at line 187 and the `ident.cfg` awk strips it at line 728, which together cover
every Unraid `/boot` path. CONFIRMED correct, and T4 anchors whole rows with `^...$` rather than
grepping for the first cell, which is the assertion shape that actually catches a regression.

Two CR paths are not covered, both SUSPECTED and both raised elsewhere. `yk()` does not strip CR
(F-010), so a CRLF `/etc/os-release` would carry one into the frontmatter. The `disks.ini` `esc()`
does not strip CR, which the ledger notes as a deliberate asymmetry because `/var/local/emhttp` is
tmpfs and LF. That asymmetry is documented at the site and I agree with it. **FT-010 in
`QUEUE.md` already asks the right question**, whether those `.ini` files really are LF.

### Unexpected locale

`export LC_ALL=C` at line 30 runs before the first external command, which is the only correct
place for it. It fixes `awk` field splitting, `grep` character classes, decimal separators in
`dmidecode` and `smartctl` output, and month names in any date a tool prints. `LC_ALL` overrides
`LANG`, `LANGUAGE` and every `LC_*`, so no caller environment can defeat it. CONFIRMED correct.
Two consequences follow and both are acceptable: the ASCII-only `[[:alnum:]]` noted above, and
`date '+%Y-%m-%d %H:%M %Z'` printing an English timezone abbreviation, which is what a report
consumer wants anyway.

### One more CONFIRMED edge case, and it is a finding

**F-026 [LOW]: the `df` exclusion filter is an unanchored prefix match.**

Line 737:

```
  DFOUT=$("${TMO[@]}" df -hT 2>/dev/null | grep -Ev '^(tmpfs|devtmpfs|efivarfs|overlay|none)' | cap ...)
```

The alternation is anchored at the start and not at the end, so it drops any line whose
Filesystem column merely begins with one of the five words. Measured:

```
  nonessential   zfs    2.0T ...   -> dropped
  overlayfs-x    fuse    50G ...   -> dropped
```

A ZFS dataset named `nonessential/data`, a pool named `none-pool`, or an LVM device mapper name
beginning with `tmpfs` disappears from the filesystem table with no warning, because the
emptiness test at line 739 still sees the header. This is a silent omission from a report
consumed as ground truth, which is the category the exit-code contract exists to prevent. The
trigger is unlikely, which is why it is LOW and not MEDIUM.

**Fix:** require whitespace after the word, which `df` always emits.

```
  DFOUT=$("${TMO[@]}" df -hT 2>/dev/null | grep -Ev '^(tmpfs|devtmpfs|efivarfs|overlay|none)[[:space:]]' | cap "$FS_TABLE_LINES" "filesystem table lines")
```

---

## 10. Performance

**This is a one-shot reporter and almost nothing here needs changing.** I measured a full run in
this container at **0.41 s wall clock, 113 lines, 9 sections, zero stderr, exit 0**. The tools
present were `lscpu`, `free`, `lsblk`, `df`, `findmnt`, `systemctl` and `timeout`. On a real host
with `smartctl` and `dmidecode` the dominant cost is waiting on hardware, not shell overhead.

I also counted the processes one run forks, using the kernel's last-pid counter before and after:
**181 processes** on that minimal container. Most of those are the `awk`, `sed` and `printf`
helper layer rather than collectors, because most collectors were skipped. A host with 12 disks
and 20 containers would add roughly another 200. That is still irrelevant next to a single
`smartctl` call.

So this section is short by design, and I want to be explicit that the one number worth acting on
is not throughput. It is F-004, the aggregate wall-clock bound, which is a robustness problem
wearing a performance costume.

### Subprocess counts inside loops

| Site | Cost | Label | Command that confirms or refutes |
|---|---|---|---|
| `fld` at line 460, six calls per disk | 6 `sed` forks per disk, 144 on a 24-disk NAS | SPECULATIVE | `time (for i in $(seq 24); do for k in NAME TYPE SIZE ROTA TRAN MODEL; do fld $k "$L" >/dev/null; done; done)` |
| SMART parse at lines 514 to 527 | about 8 `awk` forks per disk | SPECULATIVE | same shape, and it will be dwarfed by the 15 s `smartctl` budget above it |
| `uval` at line 648, eight calls | 8 `awk` forks over one tmpfs file | SPECULATIVE | negligible, the file is in page cache |
| `g` at line 714, five calls per share | 5 `awk` forks per share | SPECULATIVE | negligible |
| `cfgget` at line 1030, twelve calls per container | 12 `awk` forks per guest, 240 on a 20-container host | SPECULATIVE | one `awk` pass emitting all keys would replace them, at the cost of readability |

None of these is worth the churn. I list them so a future reader does not rediscover them and
assume nobody looked. The right rule for this file is the one A-008 already applied: hoist a call
that costs real time, leave a fork that costs microseconds alone.

### Repeated invocation of the same expensive tool

| Site | Duplication | Label |
|---|---|---|
| Lines 535 and 537 | `smartctl --scan` twice | MEASURED-OBVIOUS, F-006 |
| Lines 1118 and 1145 | `docker ps -a` twice | MEASURED-OBVIOUS, F-019 |
| Lines 257 to 261 | `dmidecode -s` five times, each a separate read of `/dev/mem` | SPECULATIVE. Confirm with `time (for f in system-product-name system-manufacturer system-serial-number baseboard-product-name bios-version; do dmidecode -s $f >/dev/null; done)` against `time dmidecode -t system -t baseboard -t bios >/dev/null`. If the delta is under 100 ms, leave it: `dmi()` is clearer than a shared parse and A-008's rule is about real time, not elegance. |

### N+1 patterns against a daemon

C-023 already removed the worst one, replacing up to 100 serial `docker inspect` calls with a
single call over all names at line 1162. One remains.

**F-027 [LOW]: `pct status` and `qm status` re-ask for data the list already returned.**

Lines 1037, 1046, 1067 and 1076:

```
    PCTRAW=$(tmo 20 pct list 2>/dev/null)
      st=$(tmo 10 pct status "$id" 2>/dev/null | awk '{print $2}')
```

`pct list` prints `VMID Status Lock Name`, and `qm list` prints `VMID NAME STATUS MEM BOOTDISK
PID`. Both already contain the status the loop then asks for again, one call per guest. On a
28-guest host that is 28 extra pmxcfs round trips and 280 s of the 630 s the Proxmox region
contributes to F-004.

**MEASURED-OBVIOUS in call count, SPECULATIVE in wall clock**, because on a healthy cluster each
call returns in well under a second. It matters only on a degraded one, which is the case F-004
is about. Confirm with `time pct status 100` against the cost of the `pct list` you already have.

**One caveat, and it is the reason this is LOW rather than a recommendation I would push.** The
column order of `pct list` is not part of any documented interface. Read it from the header row
rather than by fixed position, or fall back to `pct status` when the parsed field is empty. The
refactor in section 13 does the latter.

---

## 11. Security review

### Input validation and injection surface

The script executes no host-supplied string as code. There is no `eval`, no `source`, no
backtick, no `sh -c`, and no variable in command position. That closes the whole class before it
starts, and it is the single most important security property here.

Host output becomes part of a command in exactly five places. I checked each.

| Line | Value | Origin | Quoted | Verdict |
|---|---|---|---|---|
| 504, 609 | `"/dev/$d"`, `"/dev/$MRTGT"` | `lsblk` NAME | yes | safe. The `/dev/` prefix also removes any leading-dash concern. |
| 795, 793 to 797 | `"$ifc"` in an argument and in a path | `ip -o link show` | yes | safe |
| 570 to 584 | `"$RCLI"`, `"$MCLI"` in command position | `command -v` | yes | safe. The value comes from `PATH` resolution, not from host data. |
| 1044 to 1076 | `"$id"` | `pct list`, `qm list` | yes | safe, and VMIDs are numeric |
| 1162 | `$CNAMES` | `docker ps -a` | **no, deliberately** | safe, see below |

**CWE-88, argument injection, is the one to think about at line 1162.** `$CNAMES` is unquoted so
that it word-splits into `docker inspect`'s argument list. A container named `--format` or
`-f` would be read as a flag rather than an operand. Docker's own name grammar is
`[a-zA-Z0-9][a-zA-Z0-9_.-]*`, so the first character cannot be a dash and the attack does not
exist. **CWE-155, pathname expansion, is the half the comment does not mention.** The same
unquoted expansion is subject to globbing, and it is safe only because that grammar also excludes
`*`, `?` and `[`. The reasoning is complete, but only one half of it is written down. Extend the
comment at lines 1132 to 1134 by one clause.

### Files the script parses that a simpler implementation would execute

This is the sharpest security question about this file, and the author has already answered it
five times. Every one of these is shell-sourceable in appearance:

| File | Line | Read as | What sourcing would have done |
|---|---|---|---|
| `/etc/os-release` | 219 | `sed -n 's/^KEY=//p'` | execute a `$(...)` in any value, as root, on every run. **CWE-78.** This is C-005 and T18 defends it. |
| `/etc/unraid-version` | 226 | `sed` | same, on Unraid |
| `/boot/config/shares/*.cfg` | 714 | `awk -F=` | Unraid share configs are `key="value"` and look exactly like a shell fragment |
| `/boot/config/ident.cfg` | 728 | `awk -F=` | same |
| `/var/local/emhttp/*.ini` | 648, 661 | `awk -F=` | same, and this one is the file that holds `csrf_token` |

Five files, five parsers, zero `source`. That is a consistent and deliberate policy and it should
be stated as such in `.claude/rules/collectors.md`, which currently frames the rule as key
whitelisting rather than as parse-never-execute. Those are two different rules and the file
follows both.

**The sixth instance of the same class is a dependency rather than a file**, and that is FR-003:
`fastfetch` executes `command` modules out of `config.jsonc`. **CWE-94.** F-001 is the write side
of the identical class, a dependency doing something the verb does not name.

### Secret handling, both directions

**Values deliberately emitted:** system serial, disk serials, MACs, IPv4 addresses, BMC network
configuration, container and VM names and addresses, iSCSI target IQN, host and port. The README
states this and it is the product.

**Values deliberately filtered, and I checked each filter:**

| Secret | Line | Filter | Verdict |
|---|---|---|---|
| Unraid `csrf_token` | 648 | key whitelist of eight `md*`/`fs*`/`sb*` names | correct, and a whitelist is the right shape here because the file grows |
| IPMI SNMP community string | 994 | `grep -viE 'community\|password\|cipher\|auth type'` then a four-field whitelist | correct, and double-filtered |
| `racadm` credentials | 1010 | `grep -viE 'password\|community'` | correct |
| Kernel cmdline, by name | 409 | `password\|secret\|token\|key` | correct, over-broad on `keymap`, F-011 |
| Kernel cmdline, by value | 410 | `iscsi:[^@]+@` | correct, including the CHAP usernames, and the negated class cannot cross a later `@` in the IQN |
| apcupsd config | 949 | three-key whitelist | correct |

**Over-redaction, audited as asked.** One case, F-011, `vconsole.keymap`. Nothing else. The
`grep -viE '\| ns \|'` at line 998 drops sensors in a no-reading state, which is data reduction
rather than redaction and is correct.

**Under-redaction, one disclosed gap and no finding.** The value pass knows one form, dracut's
iSCSI root. A kernel command line carrying `systemd.setenv=API_TOKEN=...` would pass both passes,
because the parameter name is `systemd.setenv` and the secret sits in the value. The comment at
lines 402 to 404 and the README both say plainly that this is a filter and not a proof, so the
gap is disclosed rather than hidden. If you want one more word of coverage, adding `setenv` to
the name alternation redacts the whole token, which is acceptable because the variable name is
not inventory data. Optional.

### File permissions, TOCTOU and privilege boundaries

The script creates nothing, so there are no permissions to get wrong. It reads root-only paths
only when root: `/dev/mem` through `dmidecode`, SMART device nodes, `/dev/ipmi0`, pmxcfs.

**CWE-367, TOCTOU.** Every `[ -r "$f" ]` followed by a read is a race in principle: lines 711 to
714, 858 to 866, 924 to 925, 932 to 933, and the four `[ -r /var/local/emhttp/... ]` gates. All
are benign. The script only reads, the window changes nothing about privilege, and the worst
outcome is a missing row. No finding.

**One real note on the same paths.** When run as root the script reads `/boot/config/*.cfg` and
`/var/local/emhttp/*.ini` and copies their contents into the report. Anyone who can write those
files can put arbitrary text into a root-generated report. On Unraid both are root-owned, so this
is theoretical. It is worth knowing if the script is ever pointed at a path a service account can
write.

**CWE-426, untrusted search path.** The script calls about 25 external binaries by bare name and
is documented to run under `sudo`. If `sudo` is configured without `secure_path`, or invoked as
`sudo -E` with a preserved `PATH`, a user-writable directory earlier in `PATH` substitutes any of
them and runs as root. This is true of essentially every shell script and I raise no finding. It
is worth one line in the README next to the existing `sudo` guidance, because the test suite
itself demonstrates the technique by prepending stub directories to `PATH`.

**Privilege boundaries.** Root is required exactly where it is used and nowhere else. The
unprivileged path is not a degraded afterthought: the header marks the run, six regions gate on
`is_root`, and two more suppress a warning that would otherwise fire for lack of privilege rather
than for failure. That is the correct shape.

### No CWE fits F-001 cleanly, and I am not going to force one

The closest recognized classes are CWE-377 and CWE-379, both of which are about insecure
temporary files, and neither describes the problem. The problem is not that the log file is
insecure. It is that the file exists at all, on a host where the script's contract says nothing
will be written. Report it as a contract violation and leave the CWE column empty.

---

## 12. Portability review

**Scope: Linux only.** I audited against README's matrix rather than inventing one, and macOS and
BSD do not appear below.

### The class of defect this section is actually about

Three separate findings in this review share one shape, and it is worth naming before the table.
A collector calls a tool with a GNU-only or procps-only flag, discards stderr, and then treats
empty stdout as "the tool answered nothing". On a host whose implementation rejects the flag, the
script cannot tell that from a failure, so it warns and exits 1. F-009 is `free -h`, F-015 is
`findmnt --real`, and the suspected `df -hT` case below is the third.

**The general fix is one line per site:** probe the flag once, fall back to a portable form, and
warn only if both are empty. The memory section already demonstrates the principle at line 432,
where it tests a record count rather than emptiness because `dmidecode` prints a banner on
failure. This is the same insight applied to a different cause.

### glibc versus musl and Alpine

| Item | Status |
|---|---|
| `bash` required | README states it. Alpine needs `apk add bash`. Correct as documented. |
| BusyBox `free` rejects `-h` | **CONFIRMED blocker.** F-009. Portable replacement: `/proc/meminfo`. |
| BusyBox `df` and `-T` | **SUSPECTED blocker.** BusyBox builds `df -T` behind a compile-time option. Verify with `df -hT >/dev/null 2>&1; echo $?` on Alpine. If it fails, `DFOUT` is empty and line 739 raises a false warning, exactly F-009's shape. Portable replacement: `findmnt` output already carries FSTYPE, or drop `-T` and lose the Type column. |
| BusyBox `ip` and `-o` | **SUSPECTED.** BusyBox `ip` implements a subset. Verify with `ip -o link show >/dev/null 2>&1; echo $?`. If it fails, line 806 raises a false warning about the network table. |
| BusyBox `timeout` | present, so `TMO` populates and F-007 does not trigger on a normal Alpine host |
| `lsblk`, `lscpu` | util-linux, absent from a BusyBox-only install. `have` gates both and the CPU model falls back to `/proc/cpuinfo`. Correct. |
| `strings` | binutils, often absent. `have` gates it and the Displays row still prints. Correct. |
| `paste`, `readlink`, `wc`, `head`, `tail`, `cut`, `grep -E`, `grep -m1`, `ls -A` | all present in BusyBox | 

### WSL

`/sys` is partial and `lspci` is usually absent. `have` gates `lspci`, `dmidecode` and `smartctl`,
so the report shortens correctly. Two risks, both SUSPECTED and both the over-warning direction:
on WSL1 `lsblk` may enumerate nothing, tripping line 284, and `/sys/class/net/*/speed` is often
missing, which is handled. `systemd-detect-virt` reports `wsl` on WSL2, so `PLATFORM` is correct
there. Verify with one unprivileged run and a look at the warnings block.

### The named distributions

| Platform | Verdict |
|---|---|
| Unraid | No portability blocker found. GNU coreutils throughout. The FAT32 CR handling is the platform-specific work and it is done. |
| Proxmox VE | No blocker. F-003 and F-017 are Proxmox-specific defects rather than portability ones. |
| Arch / CachyOS | No blocker. F-011 applies, since dracut and `vconsole.keymap` are common here. |
| Fedora / RHEL 8 and 9 | No blocker. F-011 applies. |
| **RHEL 7 / CentOS 7** | **Blocker: F-015.** util-linux 2.23 has no `findmnt --real`. README lists Fedora/RHEL as Full support without qualifying the version. Either fix F-015 or add the version qualifier to the matrix. |
| Debian / Ubuntu | No blocker. Debian 9 and later ship util-linux 2.29, past F-015's boundary. |

### Flag and binary portability, enumerated

| Construct | Line | Portability | Replacement if needed |
|---|---|---|---|
| `df -hT` | 737 | GNU. BusyBox conditional. | see above |
| `findmnt --real` | 744 | util-linux 2.28 or later | `findmnt -t no...` exclusion list, or drop the section |
| `free -h`, `$7` available column | 245, 346 | procps-ng 3.3.10 or later | `/proc/meminfo` |
| `lsblk -P -o ...TRAN` | 276 | util-linux 2.22 or later | none needed, `have` gates it |
| `grep -m1` | 366, 367 | GNU and BusyBox, not POSIX | `grep \| head -1`, not worth changing |
| `ls -A` | 373 | GNU and BusyBox, not POSIX | none needed |
| `tail -15` | 1001 | obsolescent form, accepted everywhere | write `tail -n 15` when F-016 adds the constant |
| `readlink` without `-f` | 933 | portable | none |
| `grep -P` | nowhere | correctly avoided | |
| `stat` | nowhere | correctly avoided, see line 863 | |
| `sed` BRE only, no `-i`, no `-E` | throughout | POSIX | none |
| `date '+%Y-%m-%d %H:%M %Z'` | 299, 307 | POSIX | none |
| `paste -s -d` | eight sites | POSIX, and the semantics are the problem rather than the portability, F-014 | |

### Hardcoded paths and assumed binaries

Eleven hardcoded paths: `/etc/os-release`, `/etc/unraid-version`, `/etc/resolv.conf`,
`/etc/apcupsd/apcupsd.conf`, `/proc/{cpuinfo,loadavg,cmdline}`, `/sys/...`,
`/var/local/emhttp/{var,disks}.ini`, `/boot/config/{shares,ident.cfg}`, `/dev/ipmi{0,/0,dev/0}`.
Every one is guarded by `[ -r ]`, `[ -d ]` or `[ -e ]` except the three `/proc/cpuinfo` reads at
lines 241, 362 and 366, which degrade to an empty string or a zero count. That is correct
behavior and I raise no finding. Assumed binaries: none. Every external tool passes `have` first,
which is unusual discipline and worth saying.

### Minimum bash version

README states 3.0. The features used need 3.0 or earlier: arrays, `$'...'`, `${var//p/r}`, brace
expansion, process substitution, `$(<file)`, `EUID`. **The stated floor is not met, because of
F-007.** `"${TMO[@]}"` on an empty array under `set -u` needs 4.4. The fix restores the 3.0 floor
and I recommend that over lowering the claim, because the no-`timeout` path is a documented
supported configuration and is precisely what C-003 was built for.

Nothing I recommend anywhere in this review raises the floor above 3.0.

---

## 13. Suggested refactors

I re-read the hard constraints before writing this section. Every replacement below is read-only.
None creates a file, a lock, a temp directory or a log. None adds a dependency. None re-proposes
anything on the rejection list. Two touch adjudicated ground and both say so and carry the
measurement.

### R1 — F-001, stop the vendor CLI writing a log file

**Rationale:** restores the read-only invariant, which is the reason the script can run
unattended. Ship-blocking.

**Before,** lines 569 to 577:

```
    printf '#### Controller and array topology\n\n```\n'
    tmo 25 "$RCLI" /call show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "controller summary lines"
    echo
    echo "--- virtual drives ---"
    tmo 25 "$RCLI" /call/vall show 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "virtual drive lines"
    echo
    echo "--- physical drives ---"
    tmo 25 "$RCLI" /call/eall/sall show 2>/dev/null | cap "$RAID_CLI_DRIVES_LINES" "physical drive lines"
    printf '```\n\n'
```

**After:**

```
    # `nolog` is not cosmetic: StorCLI and its Dell rebrand PercCLI append every
    # command and its output to a log file in the CURRENT WORKING DIRECTORY
    # unless it is given. The verb is `show`, so no banned-verb list can see the
    # write. Same reason MegaCLI below is called with -NoLog. Do not remove it.
    printf '#### Controller and array topology\n\n```\n'
    tmo 25 "$RCLI" /call show nolog 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "controller summary lines"
    printf '\n--- virtual drives ---\n'
    tmo 25 "$RCLI" /call/vall show nolog 2>/dev/null | cap "$RAID_CLI_SUMMARY_LINES" "virtual drive lines"
    printf '\n--- physical drives ---\n'
    tmo 25 "$RCLI" /call/eall/sall show nolog 2>/dev/null | cap "$RAID_CLI_DRIVES_LINES" "physical drive lines"
    printf '```\n\n'
```

**Risk.** If a StorCLI version rejects `nolog`, all three commands fail and the topology block
becomes an empty code fence with no warning. That is a visible regression rather than a silent
one, but verify before merging. This edit also folds F-021's `echo` sites into `printf`, which is
free while you are here.

**Verify.** On a host with the binary, from a directory you own: list the directory, run
`perccli64 /call show nolog >/dev/null`, list it again. Nothing new should appear, and the command
should exit 0. Then add the T1 assertion in R10 below.

### R2 — F-007, expand `TMO` safely on every bash the README claims

**Rationale:** restores the stated bash 3.0 floor and stops the script aborting mid-report at
line 1106 on a host with no `timeout`. Does not reopen A-004: the array stays, `tmo()` stays.

**Before,** the main-shell site, line 1106:

```
if have docker && "${TMO[@]}" docker info >/dev/null 2>&1; then
```

**After:**

```
if have docker && ${TMO[@]+"${TMO[@]}"} docker info >/dev/null 2>&1; then
```

**Before,** the helper site, line 204:

```
  "${TMO[@]}" dmidecode -s "$1" 2>/dev/null | grep -v '^#' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
```

**After:**

```
  ${TMO[@]+"${TMO[@]}"} dmidecode -s "$1" 2>/dev/null | grep -v '^#' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
```

The remaining 22 sites take the identical transform. They are at lines 239, 245, 276, 426, 434,
550, 737, 744, 764, 769, 784, 795, 809, 827, 870, 966, 1108, 1118, 1145 and 1181. The whole edit
is one command:

```
sed -i 's/"\${TMO\[@\]}"/${TMO[@]+"${TMO[@]}"}/g' hw-inventory.sh
```

Add one line to the comment block at line 139 saying that the `+` form is required because bash
before 4.4 treats an empty array as unset under `set -u`, next to the `WARNINGS` comment at line
155 that already records the same hazard for a different variable.

**Risk.** None on bash 4.4 and later, where the two forms are identical. **Verify:** `bash -n`,
then the full suite, then `PATH` without `timeout` as in R10.

### R3 — F-003, wrap `pveversion`

**Before,** lines 318 to 320:

```
if have pveversion; then
  kv "Proxmox VE" "$(pveversion 2>/dev/null | head -1)"
fi
```

**After:**

```
if have pveversion; then
  # Wrapped like every other Proxmox call: pveversion reads /etc/pve, which is
  # the pmxcfs FUSE mount and blocks rather than fails when the node loses
  # quorum. Unwrapped here, that stalls the run before any section prints.
  kv "Proxmox VE" "$(tmo 10 pveversion 2>/dev/null | head -1)"
fi
```

**Risk.** None. **Verify:** T5, plus the stub test in R10.

### R4 — F-013, find drives whose controller device IDs start above 9

**Rationale:** the measured behavior is that an entire array vanishes. Also bounds the probe in
time, which is the largest single term in F-004 after the guest loops.

**Before,** lines 606 to 627:

```
    if [ -n "$MRTGT" ]; then
      MRROWS=""; misses=0
      for n in {0..31}; do
        MS=$(tmo 6 smartctl -n standby -H -A -d "megaraid,$n" "/dev/$MRTGT" 2>/dev/null || true)
        if ! printf '%s' "$MS" | grep -qiE '^Device Model:|^Model Number:|^Product:|^Serial Number:'; then
          misses=$((misses + 1))
          # Device IDs can be sparse; give up only after a long empty run.
          [ "$misses" -ge 10 ] && break
          continue
        fi
        misses=0
```

**After:**

```
    if [ -n "$MRTGT" ]; then
      MRROWS=""; misses=0; hits=0; probe_start=$SECONDS
      for n in {0..31}; do
        # Two bounds, not one. The miss counter is armed only AFTER the first
        # drive answers, because a controller whose lowest device ID is 10 or
        # higher would otherwise be abandoned at n=9 with a full array behind
        # it — measured: base ID 9 finds every drive, base ID 10 finds none,
        # and the section then prints "no drives answered" on a healthy host.
        # Before the first hit the walk is bounded by MEGARAID_PROBE_S instead,
        # so a host with no controller-backed drives still stops promptly.
        [ "$hits" -eq 0 ] && [ "$((SECONDS - probe_start))" -ge "$MEGARAID_PROBE_S" ] && break
        MS=$(tmo 6 smartctl -n standby -H -A -d "megaraid,$n" "/dev/$MRTGT" 2>/dev/null || true)
        if ! printf '%s' "$MS" | grep -qiE '^Device Model:|^Model Number:|^Product:|^Serial Number:'; then
          misses=$((misses + 1))
          # Device IDs can be sparse; give up only after a long empty run.
          [ "$hits" -gt 0 ] && [ "$misses" -ge 10 ] && break
          continue
        fi
        misses=0; hits=$((hits + 1))
```

Add to the constants block, beside the RAID group at line 49:

```
MEGARAID_PROBE_S=75          # seconds spent walking `-d megaraid,N` before the
                              # first drive answers. Past the first hit the
                              # 10-consecutive-miss rule takes over. Not a cap()
                              # constant: this bounds time, not output lines.
```

**Risk.** A host with no controller-backed drives now spends up to 75 s rather than up to 60 s in
this loop, and reaches roughly device ID 12 rather than 9. That is the price of the fix and it is
bounded. `SECONDS` is a bash builtin, so nothing new is executed and nothing is written.

**Verify.** T6 as it stands, which asserts drives at IDs 0, 1, 8 and 9 and asserts the probe stops
before ID 20. Then add the T6 variant in R10.

### R5 — F-014, join lists with a real separator

**Rationale:** `paste -d` takes a delimiter cycle, not a separator. Three or more items render
wrong today.

**Before,** line 795, line 812 and lines 1077 to 1079:

```
    addrs=$("${TMO[@]}" ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{print $4}' | paste -sd', ' -)
    printf 'Resolvers: `%s`\n\n' "$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd', ' -)"
      vdisks=$(printf '%s\n' "$CFG" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' \
        | grep -v 'media=cdrom' | sed 's/: /=/' | paste -sd'; ' -)
      vnet=$(printf '%s\n' "$CFG" | grep -E '^net[0-9]+:' | sed 's/: /=/' | paste -sd'; ' -)
```

**After:**

```
    # `paste -d', '` is a delimiter CYCLE, not a separator: three items join as
    # "a,b c". The awk accumulator below is the same idiom the apcupsd config
    # line already uses, and it takes a real multi-character separator.
    addrs=$(${TMO[@]+"${TMO[@]}"} ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{printf "%s%s", sep, $4; sep=", "}')
    printf 'Resolvers: `%s`\n\n' "$(awk '/^nameserver/{printf "%s%s", sep, $2; sep=", "}' /etc/resolv.conf 2>/dev/null)"
      vdisks=$(printf '%s\n' "$CFG" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' \
        | grep -v 'media=cdrom' | sed 's/: /=/' | awk '{printf "%s%s", sep, $0; sep="; "}')
      vnet=$(printf '%s\n' "$CFG" | grep -E '^net[0-9]+:' | sed 's/: /=/' | awk '{printf "%s%s", sep, $0; sep="; "}')
```

The other four sites, at lines 728, 942, 960 and 966, join at most two items today. Convert them
for consistency or leave them. If you leave them, put the reason in a comment, because the next
reader will otherwise fix the four and miss the point.

**Risk.** The `awk` accumulator emits no trailing newline, which is what the surrounding `$(...)`
already discards. Behavior with zero input lines is identical: empty. **Verify:** T2 for the
resolver line, plus the three-address stub in R10.

### R6 — F-017, warn when a guest's config cannot be read

**Before,** lines 1042 to 1045 and the matching lines 1072 to 1075:

```
    CTROWS=""
    for id in $CTIDS; do
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
```

**After:**

```
    CTROWS=""; ctskip=0
    for id in $CTIDS; do
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      # `pct list` already said this VMID exists, so a config that reads back
      # empty is a present-and-permitted collector returning nothing, not an
      # absent container. Counted here and warned once after the loop: a
      # degraded pmxcfs that answers `list` from cache and times out on every
      # `config` would otherwise delete the whole table and still exit 0.
      [ -z "$CFG" ] && { ctskip=$((ctskip + 1)); continue; }
```

and immediately after the `done` at line 1057, before the `if [ -n "$CTROWS" ]`:

```
    [ "$ctskip" -gt 0 ] && warn "\`pct config\` returned nothing for $ctskip of the container(s) \`pct list\` reported — those containers are missing from the LXC table."
```

Apply the identical change to the VM loop with `vmskip` and `qm config`.

**Risk.** None to control flow. Both loops are `for` loops in the main shell, so `warn` mutates
the real accumulator. A host where one container is destroyed between `list` and `config` now
warns once, correctly, and exits 1. **Verify:** the T5 case in R10, and `rc_agrees`.

### R7 — F-027, take guest status from the list you already have

**Rationale:** halves the per-guest call count and removes 280 s from F-004's dominant term on a
28-guest host.

**Before,** lines 1041 to 1046:

```
    CTIDS=$(printf '%s\n' "$PCTRAW" | awk 'NR>1{print $1}')
    CTROWS=""
    for id in $CTIDS; do
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && continue
      st=$(tmo 10 pct status "$id" 2>/dev/null | awk '{print $2}')
```

**After:**

```
    # VMID and status in one pass. `pct list` prints `VMID Status Lock Name`, so
    # asking `pct status` per container is a second pmxcfs round trip for data
    # already in hand — the same N+1 C-023 removed from docker inspect. Column
    # order is not a documented interface, so the status is located by header
    # position rather than assumed, and an empty parse falls back to the old
    # per-container call.
    CTSTCOL=$(printf '%s\n' "$PCTRAW" | awk 'NR==1{for(i=1;i<=NF;i++) if(tolower($i)=="status"){print i; exit}}')
    CTIDS=$(printf '%s\n' "$PCTRAW" | awk 'NR>1{print $1}')
    CTROWS=""; ctskip=0
    for id in $CTIDS; do
      CFG=$(tmo 10 pct config "$id" 2>/dev/null || true)
      [ -z "$CFG" ] && { ctskip=$((ctskip + 1)); continue; }
      st=$(printf '%s\n' "$PCTRAW" | awk -v id="$id" -v c="${CTSTCOL:-0}" 'c>0 && $1==id{print $c; exit}')
      [ -z "$st" ] && st=$(tmo 10 pct status "$id" 2>/dev/null | awk '{print $2}')
```

The VM loop takes the same shape against `QMRAW`, whose header names the column `STATUS`.

**Risk.** Higher than the others, which is why F-027 is LOW rather than a recommendation I press.
A Proxmox release that renames or reorders the column makes `CTSTCOL` empty, and the fallback
then restores today's behavior exactly. Take R6 first and R7 only if F-004 matters to you.
**Verify:** T5 must still show the right status for both a running and a stopped guest, and the
fallback needs a fixture whose `pct list` header omits `Status`.

### R8 — F-008, anchor the `lsblk -P` field matcher

**Before,** line 460:

```
  fld() { printf '%s' "$2" | sed -n "s/.*[[:space:]]\{0,\}$1=\"\([^\"]*\)\".*/\1/p"; }
```

**After:**

```
  # The key is anchored to start-of-line or a preceding space on purpose. The
  # old pattern led with a greedy `.*` and made the space optional, so it
  # matched the LAST key ENDING in the name asked for: add KNAME to the -o list
  # and `fld NAME` returns KNAME's value, silently naming the wrong device in
  # every row and sending every smartctl probe at the wrong node. Measured.
  # Same class of trap as the -P capture itself; do not "simplify" it back.
  fld() { printf '%s' "$2" | sed -n "s/^\(.*[[:space:]]\)\{0,1\}$1=\"\([^\"]*\)\".*/\2/p"; }
```

**Risk.** None for the seven columns in use, which I checked against a real `lsblk -P` line.
**Verify:** T6's existing device-row assertion, after adding `KNAME` to the fixture stub.

### R9 — F-009, fall back to `/proc/meminfo`

**Before,** lines 244 to 249:

```
FREE=""
have free && FREE=$("${TMO[@]}" free -h 2>/dev/null)
RAMTOTAL=$(printf '%s\n' "$FREE" | awk '/^Mem:/{print $2}')
if have free && [ -z "$RAMTOTAL" ]; then
  warn '`free` is installed but reported no total memory — RAM fields are empty.'
fi
```

**After:**

```
FREE=""
have free && FREE=$(${TMO[@]+"${TMO[@]}"} free -h 2>/dev/null)
RAMTOTAL=$(printf '%s\n' "$FREE" | awk '/^Mem:/{print $2}')
# BusyBox `free` has no -h, so on a musl host the call above answers nothing and
# the tool is not at fault. /proc/meminfo is a plain read and always there — the
# same fallback the CPU model already takes to /proc/cpuinfo above. Warn only
# when BOTH are silent, or every Alpine host reports a broken collector.
if [ -z "$RAMTOTAL" ] && [ -r /proc/meminfo ]; then
  RAMTOTAL=$(awk '/^MemTotal:/{printf "%.0fGi", $2/1048576; exit}' /proc/meminfo 2>/dev/null)
fi
if have free && [ -z "$RAMTOTAL" ]; then
  warn '`free` is installed but reported no total memory, and /proc/meminfo did not answer either — RAM fields are empty.'
fi
```

**Risk.** The fallback rounds to whole GiB, so a host without `free` reports `94Gi` where `free
-h` would say `94Gi` too but a 500 MiB container would report `0Gi`. Use `%.1f` if that matters.
The `Snapshot` rows at lines 346 to 347 still blank on the same host, which is cosmetic and
deliberately left alone here. **Verify:** the T8 stub in R10.

### R10 — the tests that hold all of the above

Not a code refactor, but it belongs here because none of the fixes above are safe without them.
The cases are specified in section 16.

### The one-line edits, not worth a full entry each

| ID | Line | Edit |
|---|---|---|
| F-005 | 253, 886 | prefix both with `${TMO[@]+"${TMO[@]}"}` |
| F-006 | 535 to 537 | capture `smartctl --scan` once into `SCAN`, test the variable |
| F-010 | 195 to 197 | add `v=${v//$'\r'/}` to `yk()` beside the existing substitutions |
| F-011 | 409 | add `&& tolower(name) !~ /keymap\|keyboard/` |
| F-012 | 442, 893 | add the `esc()` from line 673 to the DIMM awk, route the Displays row through `row()` |
| F-016 | 1001 | add `IPMI_SEL_LINES=15` to the constants block, use `tail -n "$IPMI_SEL_LINES"` |
| F-018 | 1106 | capture the status, warn only on 124, or add a comment saying the timeout case is folded into the gate deliberately |
| F-019 | 1145 | `CNAMES_ALL=$(printf '%s\n' "$DPSRAW" \| cut -f1)` |
| F-025 | 1008 | add the two-line comment recording the never-warns judgment |
| F-026 | 737 | append `[[:space:]]` to the exclusion alternation |
| F-020 | 44 to 97 | `readonly` on the thirteen constants |
| F-021 | nine sites | `printf` for the `--- x ---` separators |
| F-022 | 299, 307 | capture `date` once |
| F-023 | 733 to 775 | capture the section, print the fence only when non-empty |
| F-024 | 714 | give `g()` the file as `$2` |

---

## 14. Prioritized action list

| ID | Risk | Line(s) | Issue | Recommended fix | Effort |
|---|---|---|---|---|---|
| F-001 | CRITICAL | 570, 573, 576 | Vendor RAID CLI writes a log file into the working directory | Append `nolog`, R1, plus the T1 assertion | S |
| F-002 | HIGH | 966 | `upower -e` activates `upowerd` over D-Bus | Field test first, then gate on `systemctl is-active` or drop the probe | S |
| F-003 | HIGH | 319 | `pveversion` unwrapped against a FUSE mount | `tmo 10`, R3 | S |
| F-007 | HIGH | 144 to 145, 24 sites | Empty array under `set -u` aborts below bash 4.4 | `${TMO[@]+"${TMO[@]}"}`, R2 | S |
| F-004 | MEDIUM | 504, 609, 1044, 1074 | No aggregate deadline, about 20 minutes arithmetic worst case | `SECONDS` bound in the two unbounded loops, R4 and R7 | M |
| F-008 | MEDIUM | 460 | `fld()` returns the wrong column if a suffix-sharing key is added | Anchor the pattern, R8 | S |
| F-009 | MEDIUM | 245 to 249 | BusyBox `free` rejects `-h`, producing a false warning | `/proc/meminfo` fallback, R9 | S |
| F-013 | MEDIUM | 608 to 614 | Megaraid probe finds nothing above base device ID 9 | Arm the miss counter after the first hit, bound by time, R4 | M |
| F-014 | MEDIUM | 728, 795, 812, 942, 960, 966, 1078, 1079 | `paste -d` cycles delimiters, so three items join as `a,b c` | `awk` accumulator, R5 | M |
| F-015 | MEDIUM | 744 to 746 | `findmnt --real` absent below util-linux 2.28, false warning on RHEL 7 | Probe and fall back, or qualify the README matrix | S |
| F-017 | MEDIUM | 1044, 1074 | A failing guest config drops the guest, or the whole table, silently | Count and warn once, R6 | S |
| F-005 | LOW | 253, 886 | Two tools outside the timeout convention | Wrap both | S |
| F-006 | LOW | 535, 537 | `smartctl --scan` runs twice | Capture once | S |
| F-010 | LOW | 194 to 199 | `yk()` does not strip CR | One substitution | S |
| F-011 | LOW | 409 | `vconsole.keymap` over-redacted | Exclude the two safe names | S |
| F-012 | LOW | 442, 893 | Two tables built without `row()` or `esc()` | Route both through the helpers | S |
| F-016 | LOW | 1001 | `tail -15` is an unnamed truncation constant | Add `IPMI_SEL_LINES` | S |
| F-018 | LOW | 1106 | Docker gate cannot tell a refusal from a timeout | Warn on 124 only, or comment the choice | S |
| F-019 | LOW | 1118, 1145 | `docker ps -a` runs twice | `cut -f1` from the first capture | S |
| F-025 | LOW | 1008 | The racadm never-warns judgment is undocumented | Two-line comment | S |
| F-026 | LOW | 737 | `df` exclusion filter is an unanchored prefix match | Append `[[:space:]]` | S |
| F-027 | LOW | 1046, 1076 | `pct status` and `qm status` re-ask for list data | Parse the list by header position with a fallback, R7 | M |
| F-020 | NITPICK | 44 to 97 | Constants are not `readonly` | Optional | S |
| F-021 | NITPICK | nine sites | `echo` for separators where the file elsewhere uses `printf --` | Optional | S |
| F-022 | NITPICK | 299, 307 | Two `date` calls can straddle midnight | Optional | S |
| F-023 | NITPICK | 733 to 775 | Filesystems section prints its fence unconditionally | Optional | S |
| F-024 | NITPICK | 714 | `g()` closes over the loop variable | Optional | S |

---

## 15. Engineering scorecard

### Architecture — 4 / 5

The gather-then-emit split at lines 209 to 302 is correct, and the alternative of buffering the
whole report would have cost the property that a killed run still leaves readable output. The
`have` plus `$TMO` plus `2>/dev/null` triple is a real extension contract rather than a habit, and
`row`, `kv`, `yk` and `cap` mean every escaping rule lives in one place, which is why C-004 and
FR-005 were both one-site fixes. The point comes off for the read-only boundary stopping at the
verb: F-001 at line 570 and F-002 at line 966 are both dependencies doing something no banned-verb
list describes, and `CLAUDE.md` predicted that class in prose without the code catching two
instances of it.

**A 5 for this script** looks like the same structure with the dependency-behavior question asked
at every call site, and with a written rule that a new tool is admitted only after someone states
what it reads, writes and activates at startup.

### Readability and maintainability — 4 / 5

The comment discipline is the best thing in the file. Lines 264 to 267, 429 to 431, 786 to 792 and
1152 to 1158 each record a measurement and the bug it prevents, and I found no comment that
restated its code and none that was wrong. Naming is terse but consistently scoped, and no
function exceeds ten lines. The point comes off for the RAID region at lines 544 to 637, which is
the one place complexity has accumulated past comfort, and for three constructs whose fragility is
undocumented: `fld` at line 460, the `df` emptiness test at line 739 and the racadm silence at
line 1008.

**A 5** looks like the megaraid probe extracted into `megaraid_probe()` and those three comments
written.

### Robustness, hangs and timeouts — 3 / 5

The gate is real and applied almost everywhere: I found no hardcoded `timeout N` anywhere in the
file, which means C-003 landed completely, and 21 of the 24 external tool sites carry the wrapper.
`smartctl -n standby` at line 504 declines to wake a sleeping disk, which is a stronger property
than the rule requires. Three things hold the score down. Line 319 runs `pveversion` bare against
pmxcfs, which is the highest-consequence unwrapped call in the file because it precedes every
section. Nothing bounds the run as a whole, and the arithmetic worst case is about 20 minutes.
And the empty-array expansion at line 1106 turns the documented no-`timeout` configuration into an
abort on older bash.

**A 5** looks like every external call wrapped without exception, one `SECONDS` budget bounding
the two open-ended loops, and the two uninterruptible `/sys` reads named in a comment so the next
hang is diagnosed rather than re-reviewed.

### Error handling — 4 / 5

The warn-or-silent judgment is the hardest thing in this project and it is right almost
everywhere. The three tests I most expected to be wrong are all correct and all commented: the
record count at line 432 rather than emptiness, the raw-versus-filtered split at lines 554 and
837, and the prefix comparison at line 1151. No `warn` call is reachable from a subshell, which I
verified across all 21 sites. Points come off for two collectors that warn on a rejected flag
rather than a failure, at lines 248 and 746, and for the guest loops at lines 1044 and 1074, which
can delete a whole table and still exit 0.

**A 5** looks like every emptiness test keyed on something that indicates the fact, the way the
memory section already is, and no path where a table disappears without a warning.

### Security — 3 / 5

Nothing is executed. No `eval`, no `source`, no backtick, no variable in command position, and
five separate shell-sourceable files parsed rather than sourced, of which `/etc/os-release` at
line 219 is the one that would have run as root on every host. The redaction policy is audited in
both directions and I found one over-redaction and no leaks. The score is 3 rather than 5 because
a security review has to score the invariant the product sells, and F-001 writes a file on a
production host while F-002 starts a daemon on one.

**A 5** looks like both of those closed, plus one line in the README about `sudo` and `secure_path`
next to the existing invocation guidance.

### Performance — 4 / 5

Correctly weighted for what this is. A measured full run here took 0.41 s and forked 181
processes, and on a real host the wall clock belongs to hardware, not shell. A-008 and C-023 both
removed the duplication that mattered. The remaining items are two duplicate tool invocations at
lines 535 and 1145 and one N+1 against pmxcfs at lines 1046 and 1076, none of which a user would
notice on a healthy host.

**A 5** looks like those three removed, and nothing else. Do not optimize the `awk` forks.

### Portability — 3 / 5

Quoting, `[ ]` over `[[ ]]`, `case` over `[[ =~ ]]`, no `grep -P`, no `stat`, no GNU `sed` flags,
and every glob loop guarded against an empty expansion. That is the discipline of someone who has
been bitten. The score is 3 because the stated floor is not met in two directions at once:
`"${TMO[@]}"` needs bash 4.4 against a claimed 3.0, and three collectors call a GNU-only or
procps-only flag and then read empty output as failure, which turns RHEL 7 and Alpine into hosts
that warn about tools that are working.

**A 5** looks like the bash floor honored, and every flag-dependent collector probing once and
falling back, so the warnings block only ever names a tool that actually failed.

### Idiomatic style — 4 / 5

`local` in every helper that needs it, `local out` split from its assignment in `cap()` so the
exit status is not masked, `printf` for everything with a format, arithmetic in `$(( ))`, no
`let`, no useless `cat` outside three sites that carry the measurement explaining them. The one
unquoted expansion that needs a directive has one, scoped to its line. Points come off for nine
`echo` separators against the file's own `printf --` habit, no `readonly` on the constants, and
two helpers that read an enclosing variable instead of taking a parameter.

**A 5** is those three closed. This dimension is already close.

### Overall — 3.6 / 5

**What that means plainly.** This is a well-engineered script with an unusually good written record
of why it is shaped the way it is, and it is one edit away from being shippable. The findings
below CRITICAL are the ordinary residue of a 1,200-line collector, and several of them exist
because the project's own standards are higher than most, so a missing comment or an unwrapped
call stands out as a defect where elsewhere it would be normal.

**The single change that would most improve it** is not F-001, which is a two-word fix. It is to
write the rule F-001 broke into the process: **before a dependency is admitted, state what it
reads, what it writes and what it activates at startup, and put the answer in the ledger.**
`CLAUDE.md` already says the first of those three for configs. `fastfetch` was caught by the read
half. `storcli` writes and `upower` activates, and neither half existed as a question, so neither
was asked. One line added to the `/adjudicate` procedure closes the whole class rather than the
two instances I happened to find.

---

## 16. Testing recommendations

The suite is good and I am not proposing to replace it. T3's premise, that the defect class is
hangs rather than errors, is correct and is why F-003 and F-004 exist in this review at all.
`rc_agrees` is the right invariant. Everything below is a case in the existing idiom: a stub
binary on `PATH`, plus an assertion on the resulting report, named by the test it belongs beside.

### One gap in the harness itself, before the cases

**T8's `minbin` includes `timeout`** (line 297 of `tests/run.sh`). So the empty-`TMO` fallback,
which is the entire reason C-003 exists, is never exercised by any test. Removing `timeout` from
that symlink list would cover the unwrapped path on every run, and it is a one-word change. This
is also the cheapest partial guard for F-007: it will not reproduce the abort on bash 5, but it
proves the fallback path completes and reaches its footer.

### Cases, one per finding at MEDIUM or above

| Finding | Smallest test | Goes beside |
|---|---|---|
| F-001 | A static assertion, not a stub: `grep -n 'RCLI".*show' hw-inventory.sh \| grep -qv nolog` must find nothing. Add it to T1's read-only block, next to the banned-verb grep, since T1 already owns "the script does not write". Optionally also make `fixtures/percbin/perccli64` fail unless its argv contains `nolog`, which makes T6 assert it dynamically. | T1 |
| F-002 | **Cannot be tested on a general-purpose host.** It needs `upower` installed, systemd, and a system bus with `upowerd` stopped. Field test, exactly: `systemctl is-active upower; bash hw-inventory.sh >/dev/null; systemctl is-active upower`. Smallest answer that settles it: whether the second `is-active` differs from the first. | FIELD-TESTS |
| F-003 | A `pvebin` stub whose `pveversion` runs `sleep 30`, run under an outer `timeout 60`. Assert the report reaches `End of report`. Today it will not. This is T3's shape applied to one binary. | T3 |
| F-004 | After R4 and R7 land, a stub set where ten guests each hang for the full `tmo 10`, asserting the run completes inside the budget. Before those land there is nothing meaningful to assert, because the current behavior is correct-but-slow rather than wrong. | T3 |
| F-007 | Two parts. Cheap and immediate: drop `timeout` from T8's `minbin` list, which exercises the fallback on any bash. Complete: a CI matrix job on an image with bash 4.2 or 4.3, running the suite. That is a workflow change rather than a suite change, and it is the only way to reproduce the abort. | T8, plus `.github/workflows/` |
| F-008 | Add `KNAME="sdz"` to the `lsblk` line in `fixtures/percbin`. T6's existing assertion, `grep -q '^\| /dev/sdb \| 3.6T \| FIXTURE-DISK-A \|'`, then fails on the unfixed script and passes on the fixed one. No new assertion needed, which is the cheapest possible coverage. | T6 |
| F-009 | A `free` stub that writes a usage error to stderr and exits 1 on `-h`. Assert the warnings block does not name `free`, and that the frontmatter `ram:` field is populated from `/proc/meminfo`. Both halves matter, exactly as T8 asserts both halves of the warning contract. | T8 |
| F-013 | A T6 variant whose `smartctl` stub answers only at `megaraid,12` through `megaraid,15`. Assert `megaraid,12` appears and `No drives answered` does not. I verified this fails on the current script and I built the stub to do it, so the case is known to discriminate. Keep the existing IDs 0, 1, 8, 9 case as well: it covers the after-first-hit half that R4 must not break. | T6 |
| F-014 | An `ip` stub emitting three IPv4 addresses on one interface, and a `resolv.conf` fixture with three nameservers. Assert the rendered cell contains `, ` twice. The resolver half needs the runner to rewrite the path the way T4 already rewrites `/var/local/emhttp`, so the interface half is the cheaper of the two and covers the same defect. | T2 or a new T19 |
| F-015 | A `findmnt` stub that exits 1 with "unrecognized option" whenever `--real` appears in its argv, and succeeds otherwise. Assert no warning names `findmnt` and that the mount table is present. | T8 |
| F-017 | Extend `fixtures/mockbin`: `pct list` reports two VMIDs, `pct config` succeeds for one and returns nothing for the other. Assert the warnings block names `pct config`, assert the surviving container still has a row, and assert `rc_agrees`. This is the test that would have caught the whole-table-disappears case. | T5 |

### Findings below MEDIUM that are worth a cheap assertion anyway

F-012 fits inside T15 as one more assertion, a display name containing `|` rendering escaped, next
to the four binding conditions it already checks. F-026 fits inside T2 as a `df` stub emitting a
filesystem named `nonessential`. F-011 fits inside T9's over-redaction half, which already asserts
that the target name survives, as one more line asserting `vconsole.keymap=us` survives.

### What cannot be tested here, stated plainly

Four things need a host this repository's development machine is not, and each is a question
rather than a report, in the form `docs/FIELD-TESTS.md` uses.

1. **F-002, the UPower activation.** Command and answer given in the table above.
2. **F-001, the StorCLI default.** On any host with `perccli64` or `storcli64`: run
   `perccli64 /call show >/dev/null` from a directory you own and list the directory before and
   after. Smallest answer: whether a new file appeared, and its name.
3. **F-013's prevalence.** On any host with a MegaRAID or PERC controller:
   `perccli64 /call/eall/sall show nolog | grep -i DID`. Smallest answer: the lowest device ID
   the controller reports. If it is ever 10 or higher in your estate, raise F-013 to HIGH.
4. **The BusyBox flag questions in section 12.** On an Alpine host: `df -hT >/dev/null 2>&1; echo
   $?` and `ip -o link show >/dev/null 2>&1; echo $?`. Smallest answer: the two exit codes. Each
   non-zero answer is another instance of F-009's class.

### One structural suggestion, offered and not pressed

Nine of the eleven cases above are "a stub rejects a flag, or answers at an unexpected offset, and
the script must not call that a failure". That is one shape. A single helper in `tests/run.sh`
taking a tool name, a stub body and an expected warning-or-silence verdict would let each new case
be three lines instead of fifteen. That is a change to the harness rather than to the idiom, and
it is worth doing only if you take more than half the cases above. If you take two or three,
write them long.

---

*End of review. Findings F-001 through F-027. One CRITICAL, three HIGH, seven MEDIUM, eleven LOW,
five NITPICK.*
