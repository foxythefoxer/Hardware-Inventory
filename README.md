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
controller, no BMC and no hypervisor simply produces a shorter report.

---

## Requirements

**Required:** `bash` (3.0+), and the coreutils/util-linux basics — `awk`, `sed`, `grep`,
`timeout`.

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
systemd units.

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

One known gap: the kernel command line is emitted verbatim, and on some systems it can
carry secrets (`rd.luks.key`, iSCSI credentials). Check that section before sharing.
See F-009 below.

---

## Known limitations

Open findings from a code review, kept honest rather than hidden. None can damage a
machine; all affect the completeness or fidelity of the report.

| ID | Impact |
|---|---|
| F-025 / F-026 | Errors are suppressed and the script always exits `0`. A host where collection systematically fails produces a report that **looks complete and is empty**. No debug switch yet. |
| F-003 | 26 call sites hardcode `timeout N` instead of using the `$TMO` fallback. On a system without coreutils `timeout`, several sections blank silently. |
| F-012 | The "physical devices" table doesn't filter on `TYPE=="disk"`, so `md*`, `dm-*` and ZFS zvols can appear there. On a Proxmox host with `local-zfs`, every VM disk shows up as a phantom drive. |
| F-014 | 22 fixed `head -N` truncation points with no marker when a limit is hit. A large disk shelf can be cut off mid-table. |
| F-001 | No `LC_ALL=C`. Under a non-English locale, translated `lscpu`/`free` labels leave CPU and RAM fields empty. |
| F-009 | `/proc/cmdline` emitted verbatim; may contain secrets. |
| F-020 | The `racadm` block isn't root-gated and has no heading, so its output can land under the wrong section. |
| F-011 | A DIMM with no Part Number line is dropped from the table while still counted in the slot total. |
| F-016 | The megaraid probe targets the first non-NVMe disk, which on some hosts is a USB boot device. |

**Deliberate non-goals**, so they aren't re-reported: no `set -e` (a best-effort
collector must survive absent tools), no `set -o pipefail` (24 pipelines end in `head`,
which raises SIGPIPE and would poison every exit status), no POSIX `sh` support (the
shebang declares bash).

---

## Repository layout

```
hw-inventory.sh      the script
README.md            this file
CLAUDE.md            maintainer decisions, read by Claude Code at session start
docs/reviews/        independent code reviews and the prompt used to generate them
docs/prompts/        prompts for ingesting output into an Obsidian vault
```

---

## Contributing

Two rules, both non-negotiable:

1. **No change may introduce a write.** If a feature seems to require one, it doesn't
   get built — find the read-only path or leave the data uncollected. `mdcmd` vs the
   emhttp `.ini` files is the worked example.
2. **New sections must degrade silently.** Guard on `have <tool>`, wrap in a timeout,
   redirect stderr, and produce nothing rather than an error when the hardware or tool
   is absent.

Before opening a PR, run the failure test: make every external tool fail or hang, and
confirm the script still completes and reaches its footer. Bugs in this project have
historically been hangs, not errors — errors are already handled.

---

## License

MIT — see [LICENSE](LICENSE).
