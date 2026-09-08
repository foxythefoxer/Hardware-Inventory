# Field tests — questions this host cannot answer

Every change here is written and verified on one machine. That machine is one
host class out of several: it has monitors on DisplayPort, a UPS on USB with no
daemon talking to it, no ZFS zvols, and every run happens as root on bare metal.
A branch that machine cannot reach is **not** verified by a green suite, and the
suite will never say so — it passes just as loudly.

This file is where a session parks the question it could not answer, and where
the operator picks up what to run elsewhere. **It is the only record of an
unverified branch.** `docs/QUEUE.md` tracks work that is not done; this tracks
work that is done but only proven on one host class.

---

## Filing a request (the session)

`/hw-check` phase 4 ends by naming anything unverified. When the reason is *"this
host is the wrong class"* rather than *"needs root"*, it goes here instead of into
a verdict that scrolls out of the terminal. An entry is an ID and four lines:

- **Needs** — what the host must have or lack. A class, never a machine.
- **Why not here** — the specific fact about the development host that blocks it.
- **Run** — exact commands, read-only, copy-pasteable.
- **Send back** — the smallest thing that settles it. Yes/no wherever it can be.

**Ask for an answer, not a report.** "Does a `### UPS` section appear, and do the
warnings mention `apcaccess`?" is two words back. A pasted report is estate
identity sitting in a session transcript waiting to be quoted into a commit — see
the publishing rule in [`CLAUDE.md`](../CLAUDE.md).

## Running one (the operator)

Commands below are bash; from fish, `bash -c '...'`. All are reads.

**Never send the whole report.** Send only what **Send back** asks for, and read
it before sending. `### Identity`, `### Network interfaces` and the `host:`
frontmatter line are never part of an answer. Where a request needs a value,
replace it with `<redacted>` — every question here is about whether a row appeared
and whether the run warned, not what the row said.

Nothing you send is committed verbatim. What lands in this repo is the verdict
with the machine dropped: *"confirmed on a host running apcupsd — the MODEL and
STATUS rows populate, no warning"*. Never the model string, never the hostname.

If the answer shows a bug, that is an ordinary finding: `/adjudicate` it, and it
gets an ID in [`DISPOSITIONS.md`](DISPOSITIONS.md) like any other.

---

## Open

### FT-001 — UPS rows sourced from a running daemon (FR-002)

- **Needs:** a host with `apcupsd` installed and running against an attached UPS.
- **Why not here:** the UPS is attached to the development host with neither
  apcupsd nor NUT installed, which is exactly why sysfs is the gate. The
  `apcaccess` and `power_supply` rows have therefore never run against a live
  daemon — only against stubs.
- **Run:**
  ```bash
  bash hw-inventory.sh > "$HOME/hw.md"; echo "exit=$?"
  sed -n '/^### UPS/,/^###[^#]/p' "$HOME/hw.md"
  ```
- **Send back:** which `Signal` rows appear (row labels only, values redacted),
  the exit code, and whether the warnings block mentions the UPS section at all.

### FT-002 — no UPS attached (FR-002, negative)

- **Needs:** any host with nothing UPS-shaped on USB — a VM, a container, a
  desktop on mains.
- **Why not here:** the development host has a UPS on the bus. The silent path is
  covered only by T16's stripped `PATH`, i.e. by an absence this suite staged.
- **Run:**
  ```bash
  bash hw-inventory.sh > "$HOME/hw.md"; echo "exit=$?"
  grep -c '^### UPS' "$HOME/hw.md"; sed -n '/^## Collection warnings/,$p' "$HOME/hw.md"
  ```
- **Send back:** the count (must be `0`), the exit code, and whether any warning
  names a UPS tool. A warning here would be the bug — absent hardware is silent.

### FT-003 — headless host (FR-001, negative)

- **Needs:** a server, VM or container with no monitor attached. A virtual GPU
  with a DRM node and no EDID is the interesting case, not a boring one.
- **Why not here:** monitors are attached here; the empty path runs only against
  fixtures.
- **Run:**
  ```bash
  ls /sys/class/drm/ 2>&1
  bash hw-inventory.sh > "$HOME/hw.md"; echo "exit=$?"
  grep -c '^### Displays' "$HOME/hw.md"; sed -n '/^## Collection warnings/,$p' "$HOME/hw.md"
  ```
- **Send back:** the `drm` listing, the count (must be `0`), the exit code, and
  whether anything warned about displays.

### FT-004 — displays without `edid-decode` (FR-001, fallback)

- **Needs:** a host with a monitor attached and `edid-decode` **not** installed.
- **Why not here:** `edid-decode` is installed on the development host, so the
  `strings` fallback only ever runs against the committed 128-byte fixture. Real
  EDID blobs from real panels are messier than that fixture.
- **Run:**
  ```bash
  command -v edid-decode || echo "edid-decode absent — good, this is the test"
  bash hw-inventory.sh > "$HOME/hw.md"
  sed -n '/^### Displays/,/^###[^#]/p' "$HOME/hw.md"
  ```
- **Send back:** whether each connector row carries a recognisable make and model
  (yes/no per row is enough — the strings themselves are not needed), and whether
  any row came out empty or full of control characters.

### FT-005 — zvols in the physical-devices table (C-012)

- **Needs:** a Proxmox host with a `local-zfs` storage and at least one guest disk
  on it, so `zd*` devices exist.
- **Why not here:** no zvols on the development host. The `zd[0-9]` exclusion has
  never seen a real one — the `TYPE=="disk"` filter alone does not catch them,
  which is the whole reason the exclusion exists.
- **Run:**
  ```bash
  lsblk -o NAME,TYPE | grep '^zd' | head
  bash hw-inventory.sh > "$HOME/hw.md"
  sed -n '/^### Storage — physical devices/,/^###[^#]/p' "$HOME/hw.md" | grep -c 'zd[0-9]'
  ```
- **Send back:** that `zd*` devices exist at all (otherwise the test proves
  nothing), and the count from the second command — it must be `0`.

### FT-006 — DMI files without root (FR-004, before implementing it)

- **Needs:** two answers, from two classes: an **unprivileged Proxmox LXC**, and a
  **normal user shell on a whitebox desktop**.
- **Why not here:** FR-004 proposes filling model and motherboard from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged. Every
  run here is root on bare metal, where those files always exist — so whether the
  feature needs a gate or has a silent hole is not observable from this machine.
  Answer this **before** the implementation, not after.
- **Run:**
  ```bash
  ls /sys/devices/virtual/dmi/id/ 2>&1 | head -20
  bash -c 'for f in sys_vendor product_name board_name bios_version; do
    test -r /sys/devices/virtual/dmi/id/$f && echo "$f readable" || echo "$f NOT readable"
  done'
  ```
- **Send back:** the listing (or the error, if the directory is absent — that is
  the answer for an LXC) and the four readable/not lines, per host class. Values
  are not wanted, only whether they can be read.

---

## Answered

Nothing yet. An answered request moves here as one line — the verdict and the
host class, with the machine dropped — so the same question is not asked twice.
