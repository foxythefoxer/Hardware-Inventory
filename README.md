# hw-inventory.sh

A read-only hardware inventory script for Linux homelabs. Run it on a host, get a
Markdown report on stdout describing that machine — CPU, memory, disks, SMART health,
network, RAID controller, BMC, attached displays, UPS, virtualisation guests and
containers.

Single file. No dependencies beyond tools you already have. Nothing is installed,
nothing is written, nothing leaves the box.

```bash
sudo bash hw-inventory.sh > "$(hostname)-$(date +%F).md"
```

---

## The read-only contract

This is the script's central promise, and it is the reason to trust it on a production
NAS or hypervisor:

**Every command is a query. The script writes nothing, mutates nothing, and sends nothing.**

It's also what makes the script safe to eventually run unattended — a cron job, a
scheduled sweep, anything without a human confirming each run — since nothing it does
ever needs confirming in the first place.

Concretely, the following are deliberately absent:

| Not used | Why it would have been tempting |
|---|---|
| `smartctl -t` | Self-tests are the obvious way to check a disk. `-H -A` reads existing data instead. |
| `mdcmd status` | The natural way to read Unraid array state — but it works by *writing* a command into `/proc/mdcmd`. State is read from emhttp's `.ini` files instead. |
| `zpool scrub` / `import` | Only `list` and `status -x`. |
| `btrfs balance` / `scrub` / `device` | Only `filesystem show`. |
| `docker run` / `exec` / `pull` | Only `ps`, `version` and `inspect`. |
| `pct` / `qm` start, stop, set, destroy | Only `list`, `config`, `status`. |
| `perccli` / `storcli` / `megacli` write verbs | Only `show`, `-LDInfo`, `-PDList`. |
| `ipmitool chassis power`, `sel clear`, `mc reset` | Only `mc info`, `lan print`, `sdr`, `sel list`. |
| `modprobe` | If the IPMI modules aren't loaded, the script says so and moves on rather than loading them. |
| `ddcutil` | The tool for talking to a monitor. But DDC/CI is bidirectional over `i2c-dev`, so "querying" a display writes to it. EDID is read from `/sys/class/drm/*/edid` instead, which also works headless. |
| `lsusb -v` | The obvious way to find a UPS on the bus. `-v` issues USB control transfers to the device; `/sys/bus/usb/devices/*/idVendor` is the descriptor the kernel already cached. |
| `mount` / `umount` / `mkfs` / package managers | Never. |
| General system-info tools (`fastfetch`, `neofetch`, `inxi`) | The obvious way to cross-check the collected facts. But `fastfetch` executes `command` modules out of the host's own `config.jsonc`, so a bare call with no flags can write — and it reads the same `/proc` and sysfs files this script does, so it is a second parser, not a second source. |

Three further behaviours worth knowing:

- **Spun-down disks stay spun down.** SMART is queried with `-n standby`, so a sleeping
  array disk is reported as `(standby — not woken)` rather than woken to answer.
- **No temp files, no locks.** Re-running is safe. Concurrent runs are safe.
- **The promise covers what a dependency does at startup, not just what it is asked to
  do.** That is why the last row above is a category rather than a command, and part of
  why the script has no dependencies beyond tools you already have.

---

## Platform support

| Platform | Status | Notes |
|---|---|---|
| Unraid | Full | Array state, per-slot disks, share cache policy, Docker |
| Proxmox VE | Full | LXC + VM configs, storage, cluster, PERC, iDRAC |
| Arch / CachyOS | Full | Minus enterprise-only sections |
| Fedora / RHEL | Full | Minus enterprise-only sections |
| Debian / Ubuntu | Expected to work | Same code paths as Proxmox minus the PVE tools |
| Alpine / musl | Degraded | Requires `bash`; some tools absent |
| WSL | Degraded | Limited hardware visibility through `/sys` |
| macOS / BSD | Not supported | Linux-specific by design (`/sys`, `lsblk`, `ip`) |

Sections that don't apply to a host are skipped silently. A machine with no RAID
controller, no BMC and no hypervisor simply produces a shorter report. A section that is
empty because a tool was present and *failed* is a different thing, and is reported —
see [Exit codes](#exit-codes).

---

## Requirements

**Required:** `bash` (3.0+), and the coreutils/util-linux basics — `awk`, `sed`, `grep`.

`timeout` is strongly recommended but no longer required: without it, commands that
would have been wrapped simply run unwrapped, so a hung tool can stall the run.

**Optional.** Each unlocks a section; each is detected before use and skipped if absent:

| Tool | Adds |
|---|---|
| `dmidecode` | System model, service tag, BIOS, DIMM layout |
| `smartctl` (smartmontools) | Disk health, power-on hours, wear |
| `lsblk`, `lspci`, `lscpu` | Disks, PCI devices with bound drivers, CPU topology |
| `ipmitool` | BMC / iDRAC / iLO info, sensors, system event log |
| `perccli64` / `storcli64` / `megacli` | Hardware RAID array topology |
| `zfsutils` / `btrfs-progs` | Pool and filesystem detail |
| `docker` | Container inventory with networks and IPs |
| `edid-decode` | Monitor vendor, model and panel serial as separate fields. Displays are detected without it — `strings` recovers the same two values unlabelled, and the connector is listed either way |

Install the common ones:

```bash
# Debian / Proxmox / Ubuntu
sudo apt install dmidecode smartmontools pciutils

# Fedora / RHEL
sudo dnf install dmidecode smartmontools pciutils

# Arch / CachyOS
sudo pacman -S --needed dmidecode smartmontools pciutils
```

Unraid ships everything needed already.

---

## Usage

Output goes to **stdout**. The script never creates a file — redirecting is your call.

```bash
# bash — Proxmox, Fedora, Debian, Unraid
cd ~/inventory
sudo bash hw-inventory.sh > "$(hostname)-$(date +%F).md"
```

```fish
# fish
cd ~/inventory
sudo bash hw-inventory.sh > (hostname)-(date +%F).md
```

```bash
# watch it scroll and capture at once
sudo bash hw-inventory.sh | tee "$(hostname)-$(date +%F).md"
```

Run with `bash`, not `./`, so the shebang and your login shell can't disagree.

**Run as root.** Without it, `dmidecode` and SMART return nothing and the report is
marked `**not run as root**, some fields incomplete` in its header.

Three things that catch people out:

- **The redirect runs as you, not as root.** Your shell opens the output file before
  `sudo` starts, so the file is owned by you. `sudo bash hw-inventory.sh > /root/out.md`
  fails with permission denied — use `| sudo tee` if you need a root-owned path.
- **On Unraid, `/root` and `/tmp` are RAM.** Write to a share instead, or lose the file
  on reboot.
- **PERC and SMART sections can take a minute.** The megaraid probe walks device IDs and
  each sleeping disk gets a short timeout. `tee` beats a bare redirect there.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Collection complete. |
| `1` | Report written in full, but one or more collectors failed. The report ends with a `## Collection warnings` block naming them. |

**A non-zero exit does not mean the report is missing** — it is always written first, in
full. It means part of it is unknown rather than absent, and the difference matters: a
disk table that is empty because `lsblk` failed reads identically to one that is empty
because the host has no disks, and if you feed this to an LLM or a diff, the silent
version becomes a confident wrong answer.

What counts as a failure is deliberately narrow — the tool was **present, permitted, and
still returned nothing**:

- A tool that isn't installed is silent. A minimal host is not a broken one.
- A tool needing root when you didn't use `sudo` is silent; the header already says the
  run was unprivileged.
- Zero containers, zero failed systemd units, and no cluster on a standalone Proxmox
  node are all healthy states, not warnings.

```bash
sudo bash hw-inventory.sh > host.md || echo "incomplete — see Collection warnings"
```

---

## Output

A Markdown document with YAML frontmatter, suitable for a notes vault or for feeding to
an LLM as machine context:

```yaml
---
host: "example-host"
os: "Debian GNU/Linux 13 (trixie)"
kernel: "6.17.9-1-pve"
platform: "bare-metal"
cpu: "Intel(R) Xeon(R) CPU E5-2470 v2 @ 2.40GHz"
ram: "94Gi"
collected: 2026-08-06
collector: hw-inventory.sh v7
tags: [homelab, inventory, hardware]
---
```

Sections, each emitted only when it applies: Identity · Snapshot (volatile) · CPU ·
Boot and kernel parameters · Memory and DIMMs · Storage devices · SMART health ·
RAID controller · Unraid array, slots and shares · Filesystems and pools · Network
interfaces · Displays · UPS · PCI devices · BMC / IPMI · Proxmox LXC and VM tables ·
Docker · Failed systemd units · Collection warnings (only when something failed — see
[Exit codes](#exit-codes)).

### Version

`collector:` is the version a vault files the report under, and it is the only
place the version appears in the output. **It moves when the emitted report
changes for some class of host, and only once per state the world has seen.**

**v7** is FR-005, the first defect a real Unraid host found rather than a review:
`/boot` is the FAT32 flash device, so its `.cfg` files are CRLF, and the CR rode
through `$(...)` into the Shares table and the flash-identity line — Markdown
honours it as a line break, so each row ended after its first cell and the table
stopped being a table. Report-changing for exactly one host class, which is what
a number is for.

**v6** is the queue batch: C-005 (os-release parsed, not sourced), C-016 +
A-007 (one `lsblk -P` capture, and a megaraid probe that skips the USB boot
key), A-008, A-009 and C-004 (`|` escaped in every table cell). Two of those
change the report — an Unraid host gets drive rows where it got "no drives
answered", and any cell containing a pipe stops shifting the columns after it.

**v5** was Displays, UPS, and the CI-001 PCI fix. That last one changed the
report too — on a host whose PCI devices match none of the section's classes, a
section and a spurious warning both disappear, and the exit code goes from `1`
to `0` — and it still did not earn a number of its own, because no report had
ever been produced by a v5 without it. A version number describes what a
consumer can be holding, not what the repository did; two numbers for a state
nothing ever ran is noise in every vault that files by this field. v5 was
tagged and fetchable before this batch, so this one is v6.

What changed in each version is the *Done* list in
[`docs/QUEUE.md`](docs/QUEUE.md). The version is written twice in the script —
the header comment and that `printf` — and T1 fails if the two ever disagree,
which is how a stale `collector:` misfiling every report gets caught.

**Every version is also a git tag, and a tag never moves.** `v7` points at the
commit that minted it and keeps pointing there after `main` has moved on. A
change that alters the report earns `v8` and its own tag, never a re-cut `v7` —
a host that already fetched would go on running the old one and say `v7` either
way. Docs, tests and hooks change under a tag without minting one; the collector
is what the tag is for.

Pin a sweep so a month of reports cannot straddle a bump:

```bash
git -C /opt/hw-inventory fetch --tags
git -C /opt/hw-inventory checkout v7     # detached HEAD, deliberately
sudo bash /opt/hw-inventory/hw-inventory.sh > "$(hostname)-$(date +%F).md"
```

`git -C /opt/hw-inventory describe --tags` says what a host will run before the
sweep starts; `collector:` in the report says what it ran.

### Diffing two runs

Volatile fields are grouped under `### Snapshot` so they can be excluded:

```bash
diff <(sed '/^### Snapshot/,/^$/d' old.md) \
     <(sed '/^### Snapshot/,/^$/d' new.md)
```

What's left is real change: a disk that vanished, a DIMM no longer detected, a link
renegotiated slower, an array slot that left `DISK_OK`.

---

## ⚠️ The output contains identifying information

By design, a complete inventory includes:

- System serial number / Dell service tag
- Disk serial numbers
- MAC addresses and internal IP addresses
- BMC / iDRAC network configuration
- Container and VM names, and their addresses

That's exactly what makes it useful for your own records — serials tell you which
physical disk to pull, MACs feed DHCP reservations.

**Do not paste raw output into a public issue, forum post, or pastebin.** If you're
reporting a bug here, redact serials and addresses first, or send only the section that
demonstrates the problem.

The kernel command line used to be emitted verbatim, which on some systems leaks secrets.
Two things are redacted now, with parameter names kept in both cases:

- **By name** — any parameter whose name contains `password`, `secret`, `token` or `key`.
  This covers `rd.luks.key` and `rd.iscsi.password`.
- **By value** — credentials embedded *inside* a value, where no name match can see them.
  dracut's iSCSI root is the known case, and its parameter is innocuously called
  `netroot`:

  ```
  netroot=iscsi:user:pass:rev_user:rev_pass@host:port:...:targetname
  → netroot=iscsi:REDACTED@host:port:...:targetname
  ```

  Everything between `iscsi:` and `@` goes, including the CHAP usernames — a username is
  half of a credential pair, not merely identifying. Host, port, LUN and target name stay,
  since that is the part worth inventorying.

**This is a filter, not a proof.** It catches the forms known to appear here, not every
way a secret can be written on a kernel command line. Glance at the section before
sharing a report.

---

## Known limitations

Open findings from a code review, kept honest rather than hidden. None can damage a
machine; all affect the completeness or fidelity of the report.

| ID | Impact |
|---|---|
| C-016 | The megaraid probe targets the first non-NVMe disk, which on some hosts is a USB boot device. |

Findings already fixed, and proposals deliberately **rejected** — `set -e`,
`set -o pipefail`, and others — are recorded once, with the measurements behind each
verdict, in [`docs/DISPOSITIONS.md`](docs/DISPOSITIONS.md). They were summarised here
too until that second copy drifted from the ledger, so the ledger is now the only
statement of them. **Read it before opening a PR**: several plausible-looking changes
have been evaluated and declined, one of which would break the script.

Also deliberate: **`zpool` and `btrfs` returning nothing is never a warning.** Those
packages are routinely installed on hosts that use neither filesystem, where an empty
listing is the correct answer. `df`, `findmnt`, `lsblk`, `lscpu` and `ip` do warn, being
facts every working host has.

---

## Repository layout

```
hw-inventory.sh      the script
README.md            this file
CLAUDE.md            the two rules that govern everything, read at session start
tests/run.sh         the test suite — bash tests/run.sh
tests/fixtures/      failing/hanging tool stubs, Unraid, Proxmox and cmdline mocks
docs/DISPOSITIONS.md accept/reject/defer ledger — every adjudicated proposal, with reasons
docs/QUEUE.md        accepted work not yet done, and what is already done
docs/FIELD-TESTS.md  what needs running on a host class the development machine isn't
docs/PRIOR-ART.md    what comparable tools do, and unadjudicated leads taken from them
docs/reviews/        independent code reviews and the prompt used to generate them
docs/prompts/        prompts for ingesting output into an Obsidian vault
.claude/rules/       conventions, the exit-code contract and rejected proposals
.claude/hooks/       enforcement — banned verbs, and estate identity in writes and commits
.claude/skills/      /adjudicate (record a verdict) and /hw-check (verify a change)
.githooks/           pre-commit and commit-msg wrappers around the same leak scanner
.github/workflows/   CI: the suite on every push, unprivileged and as root
```

---

## Contributing

Two rules, both non-negotiable:

1. **No change may introduce a write.** If a feature seems to require one, it doesn't
   get built — find the read-only path or leave the data uncollected. `mdcmd` vs the
   emhttp `.ini` files is the worked example.
2. **New sections must degrade silently when the tool is absent** — guard on
   `have <tool>`, wrap in a timeout, redirect stderr — **and warn when it is present and
   fails.** Silence is for hardware a host doesn't have; a tool that was there, had the
   privileges it needed, and returned nothing calls `warn`. Getting that line wrong in
   either direction is the bug: warn too eagerly and every minimal host looks broken,
   warn too little and an empty section reads as fact.

Set up a fresh clone once. Neither step is automatic, and the second one is not
optional — the leak hook refuses to run without its pattern list rather than
running inertly, because a hook that quietly does nothing looks exactly like a
hook that works:

```bash
git config core.hooksPath .githooks                                 # pre-commit + commit-msg
cp .claude/private-patterns.example .claude/private-patterns.local  # then fill it in
```

**Run that second command once, and never again.** It overwrites the list you
filled in, and the result — a file that exists with no patterns in it — is the
one state that looks exactly like protection and is not: the hook starts, the
built-in address and MAC shapes still fire, and the names and hostnames it was
told to catch are unguarded. The file is gitignored, so git cannot get it back.
`bash tests/run.sh` fails on an empty list for that reason (T14); CI copies the
example in deliberately and prints a note instead.

Before opening a PR:

```bash
bash tests/run.sh      # all tests must pass; add one for what you changed
```

CI runs the same suite on every push and pull request, unprivileged and again as
root — the root pass is the only place the megaraid drive probe is exercised, and
the runner is the only place ShellCheck is guaranteed present.

**A green suite says nothing about the host classes you don't have.** This script is
developed on one machine, and a condition that machine cannot reach — no ZFS zvols, no
UPS daemon, never unprivileged, monitors always attached — is unverified no matter how
many tests pass. Those go in [`docs/FIELD-TESTS.md`](docs/FIELD-TESTS.md) as a command
and the answer wanted, to be run on a host that *is* the right class. Ask a question,
never for a report: a report is estate identity, and this repo is public.

The suite makes every external tool fail or hang and confirms the script still completes,
reaches its footer, and exits `1` rather than `124`. Bugs in this project have
historically been hangs, not errors — errors are already handled.

`warn` may only be called from the main shell. Pipeline bodies and command substitutions
run in subshells, so a `warn` inside one is silently lost; capture the pipeline into a
variable and test it outside, as the storage and network tables do.

---

## License

MIT — see [LICENSE](LICENSE).
