# hw-inventory.sh

A read-only hardware inventory script for Linux homelabs. Run it on a host, get a
Markdown report on stdout describing that machine — CPU, memory, disks, SMART health,
network, RAID controller, BMC, virtualisation guests and containers.

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
| `mount` / `umount` / `mkfs` / package managers | Never. |

Two further behaviours worth knowing:

- **Spun-down disks stay spun down.** SMART is queried with `-n standby`, so a sleeping
  array disk is reported as `(standby — not woken)` rather than woken to answer.
- **No temp files, no locks.** Re-running is safe. Concurrent runs are safe.

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
tags: [homelab, inventory, hardware]
---
```

Sections, each emitted only when it applies: Identity · Snapshot (volatile) · CPU ·
Boot and kernel parameters · Memory and DIMMs · Storage devices · SMART health ·
RAID controller · Unraid array, slots and shares · Filesystems and pools · Network
interfaces · PCI devices · BMC / IPMI · Proxmox LXC and VM tables · Docker · Failed
systemd units · Collection warnings (only when something failed — see
[Exit codes](#exit-codes)).

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

**Fixed since that review**, listed because the IDs still appear in
[docs/reviews/](docs/reviews/):

| ID | Was | Now |
|---|---|---|
| C-025 / C-026 | Errors suppressed everywhere and always exits `0`; a systematically broken host produced a report that looked complete and was empty. | Collectors that were present and permitted but returned nothing are named under `## Collection warnings`, and the script exits `1`. See [Exit codes](#exit-codes). |
| C-003 | 26 sites hardcoded `timeout N`, bypassing the `$TMO` fallback; without coreutils `timeout` several sections blanked silently. | Every site routes through the same `have timeout` gate, so a host without `timeout` runs the commands unwrapped instead of failing them. |
| C-012 | The "physical devices" table filtered by name only, so `md*`, `dm-*` and ZFS zvols appeared as phantom drives — one per VM disk on a Proxmox host with `local-zfs`. | Filtered on `TYPE=="disk"` plus a `zd[0-9]` name exclusion, since zvols report `TYPE=disk` too. |
| C-001 | No `LC_ALL=C`; a non-English locale left CPU and RAM fields empty. | `export LC_ALL=C` at the top. |
| C-009 | `/proc/cmdline` emitted verbatim; could carry secrets. | Redacted by parameter name (`password`, `secret`, `token`, `key` — covering `rd.luks.key`) and, since the follow-up, by value for credentials embedded inside dracut's `netroot=iscsi:…@…` form. Names are kept. A filter, not a proof — see the identifying-information note above. |
| C-020 | The `racadm` block was not root-gated and had no heading, so its output landed under the previous section. | Gated on root, with its own `###` heading. |
| C-011 | A DIMM with no `Part Number` line was dropped from the table but still counted in the slot total. | Rows are emitted at the record boundary, so every populated slot appears. |
| C-014 | 23 fixed `head -N` truncation points (the review says 22 — off by one, verified against the file) with no marker when a limit was hit. | Every one is now a named constant consumed through `cap()`, which appends a `--- truncated at N ... ---` marker when the limit is actually hit, and nothing at all otherwise. |

**Deliberate non-goals**, so they aren't re-reported: no `set -e` (a best-effort
collector must survive absent tools), no `set -o pipefail` (23 pipelines end in `head`,
22 of which terminate there — the dmidecode wrapper pipes `head`'s output on into `sed` —
either way `head` raises SIGPIPE and would poison the exit status), no POSIX `sh` support
(the shebang declares bash).

Also deliberate: **`zpool` and `btrfs` returning nothing is never a warning.** Those
packages are routinely installed on hosts that use neither filesystem, where an empty
listing is the correct answer. `df`, `findmnt`, `lsblk`, `lscpu` and `ip` do warn, being
facts every working host has.

---

## Repository layout

```
hw-inventory.sh      the script
README.md            this file
CLAUDE.md            maintainer decisions, read by Claude Code at session start
tests/run.sh         the test suite — bash tests/run.sh
tests/fixtures/      failing/hanging tool stubs, Unraid, Proxmox and cmdline mocks
docs/reviews/        independent code reviews and the prompt used to generate them
docs/prompts/        prompts for ingesting output into an Obsidian vault
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

Before opening a PR:

```bash
bash tests/run.sh      # all tests must pass; add one for what you changed
```

The suite makes every external tool fail or hang and confirms the script still completes,
reaches its footer, and exits `1` rather than `124`. Bugs in this project have
historically been hangs, not errors — errors are already handled.

`warn` may only be called from the main shell. Pipeline bodies and command substitutions
run in subshells, so a `warn` inside one is silently lost; capture the pipeline into a
variable and test it outside, as the storage and network tables do.

---

## License

MIT — see [LICENSE](LICENSE).
