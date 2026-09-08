# Field tests — questions this host cannot answer

Every change here is written and verified on one machine. That machine is one
host class out of several: bare metal with monitors on DisplayPort, a UPS on USB
with no daemon talking to it, no ZFS zvols, no BMC, no hardware RAID — and no
sudo, because agent sessions cannot answer an interactive password prompt, so
every run here is unprivileged and the root half of the script is only ever
*simulated*. A branch this machine cannot reach is **not** verified by a green
suite, and the suite will never say so — it passes just as loudly.

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
- **Run as** — root, unprivileged, or both. Never leave this to be inferred; see
  below, it is the line that gets forgotten.
- **Send back** — the smallest thing that settles it. Yes/no wherever it can be.

**Ask for an answer, not a report.** "Does a `### UPS` section appear, and do the
warnings mention `apcaccess`?" is two words back. A pasted report is estate
identity sitting in a session transcript waiting to be quoted into a commit — see
the publishing rule in [`CLAUDE.md`](../CLAUDE.md).

## Running one (the operator)

Commands below are bash; from fish, `bash -c '...'`. All are reads.

**Run it both ways, and say which one each answer came from.** Root is not a
detail of how you invoked it — it changes what the script can collect at all.
`dmidecode` (model, DIMM layout), SMART health, `pct`/`qm` and IPMI are
root-gated, and the report says *"not run as root, some fields incomplete"* in
its header when they were skipped. An answer that does not say which run it came
from cannot distinguish "this host lacks the hardware" from "that collector never
ran", which is the one distinction this whole script is built around.

```bash
bash hw-inventory.sh      > "$HOME/hw-user.md"; echo "unprivileged exit=$?"
sudo bash hw-inventory.sh > "$HOME/hw-root.md"; echo "root exit=$?"
```

Each entry's **Run as** line says whether both are actually wanted. Where it says
one, the other adds nothing and is not worth your time; where it says both, the
*difference* between the two runs is the answer. Same for the suite itself:
`bash tests/run.sh` skips T6's drive probe, `sudo bash tests/run.sh` is the only
thing that runs it, and CI has always run both — badly, until CI-001.

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
- **Run as:** **both.** No part of the UPS section is root-gated, but
  `/etc/apcupsd/apcupsd.conf` is read through `[ -r ]` and its mode varies by
  distribution — if the `apcupsd config` row appears only under `sudo`, that is
  itself the finding, and it means the row cannot be trusted on an ordinary run.
- **Send back:** which `Signal` rows appear (row labels only, values redacted),
  the exit code, and whether the warnings block mentions the UPS section at all.
  Both runs, marked.

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
- **Run as:** unprivileged is enough. Nothing in this section is root-gated, so a
  root run answers the same question twice.
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
- **Run as:** unprivileged. EDID is a world-readable sysfs file, so root changes
  nothing here.
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
- **Run as:** unprivileged first. If the Displays section is missing entirely as
  an ordinary user, re-run with `sudo` — a section that appears only under root
  means the EDID files are not world-readable on that distribution, which is a
  finding in itself and not what this entry set out to ask.
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
- **Run as:** unprivileged answers this one — `lsblk` needs no privilege. Send
  the root run too if it is no trouble: on a Proxmox host that pass also
  exercises `pct`/`qm`, `dmidecode` and SMART, none of which any machine here can
  reach, and FT-007 is the standing request for exactly that.
- **Send back:** that `zd*` devices exist at all (otherwise the test proves
  nothing), and the count from the second command — it must be `0`.

### FT-006 — DMI files without root (FR-004, before implementing it)

- **Needs:** two answers, from two classes: an **unprivileged Proxmox LXC**, and a
  **normal user shell on a whitebox desktop**.
- **Why not here:** FR-004 proposes filling model and motherboard from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged. This
  machine is bare metal, where that directory always exists — the case that
  decides whether the feature needs a gate or has a silent hole is a container,
  which may have no such directory at all. Answer this **before** the
  implementation, not after.
- **Run:**
  ```bash
  ls /sys/devices/virtual/dmi/id/ 2>&1 | head -20
  bash -c 'for f in sys_vendor product_name board_name bios_version; do
    test -r /sys/devices/virtual/dmi/id/$f && echo "$f readable" || echo "$f NOT readable"
  done'
  ```
- **Run as:** **unprivileged, and it matters more here than anywhere.** The whole
  question is what a non-root run can see; a `sudo` answer to FT-006 is not a
  weaker answer, it is an answer to a different question.
- **Send back:** the listing (or the error, if the directory is absent — that is
  the answer for an LXC) and the four readable/not lines, per host class. Values
  are not wanted, only whether they can be read.
- **Half answered, 2026-09-07, on the development host** (whitebox desktop, bare
  metal, ordinary user shell — the "normal user shell on a whitebox desktop"
  class this entry asks for, which is what this machine already is):
  the directory exists and all four of `sys_vendor`, `product_name`,
  `board_name`, `bios_version` are readable unprivileged, mode `0444`. But
  `product_serial`, `board_serial`, `chassis_serial` and `product_uuid` are mode
  `0400 root:root` and **not** readable. So the FR-004 fallback can fill model,
  motherboard and BIOS without root, and can never fill a serial that way — the
  serial rows stay root-gated on `dmidecode` no matter what this feature does.
  **Still open: the unprivileged LXC half**, which is the one that decides
  whether FR-004 needs a gate for a missing directory.

### FT-008 — the megaraid probe target, on a host with a controller (C-016)

- **Needs:** a host with a PERC/MegaRAID controller and drives behind it. An
  Unraid host is the ideal one, because its USB boot key is the device the fix
  is about; any host whose first non-NVMe disk is a USB stick will do.
- **Why not here:** no RAID controller and no Unraid. The probe now picks its
  target by `TRAN`, skipping `usb` and `nvme`, and that choice has only ever run
  against a fixture that says what it was asked about. What a fixture cannot
  tell you is what `lsblk` reports for a real controller-attached drive — if
  those come back with `TRAN="usb"` on some enclosure, the filter would skip the
  one disk it needs.
- **Run:**
  ```bash
  lsblk -dn -P -o NAME,TYPE,TRAN
  sudo bash hw-inventory.sh > "$HOME/hw-root.md"; echo "exit=$?"
  grep -c '^| megaraid,' "$HOME/hw-root.md"
  grep -c 'No drives answered' "$HOME/hw-root.md"
  ```
- **Run as:** **root for the script** — the probe is root-gated and an
  unprivileged run skips it entirely, so a non-root answer says nothing. The
  `lsblk` line needs no privilege.
- **Send back:** the `TRAN` values only (`NAME` is not wanted — "one usb, three
  sas, one nvme" is the whole answer), the megaraid row count, and whether the
  "No drives answered" line is present. A count above zero with that line absent
  is the pass.

### FT-009 — does `emhttp` keep `id=` for a slot with no disk in it? (PA-005)

- **Needs:** any Unraid host with a configured array. It does **not** need a
  degraded array — the interesting slot is an *unassigned* one, and a host with
  single parity already has an empty `parity2` slot if emhttp writes sections
  for unassigned slots at all. That is half the question.
- **Why not here:** no Unraid. The Array slots table is built by the one awk
  block in the script, and its `emit()` returns early when `device` and `id` are
  **both** empty. Measured on 2026-09-08 against a synthetic slot with both
  empty: the row is dropped silently — no row, no warning, exit `0`. A host
  whose parity disk had been kicked out would then read as a host that has no
  parity slot, which is precisely the reading the exit-code contract exists to
  prevent. Whether that is reachable turns on whether emhttp retains the `id=`
  of a disk it has disabled or lost. If it does, `id != ""`, the guard passes,
  and the row renders correctly with a `—` in the Device column — no bug, and
  the fixture just gains a case. If it does not, the drop is real.
  An independent parser's tests
  ([ruaan-deysel/unraid-management-agent](https://github.com/ruaan-deysel/unraid-management-agent),
  `daemon/services/collectors/array_test.go`) enumerate `DISK_NP`, `DISK_DSBL`
  and `DISK_NP_DSBL` with `device=""`, but carry no `id` field either way, so
  they do not settle it. See [`PRIOR-ART.md`](PRIOR-ART.md) PA-005.
- **Run:**
  ```bash
  awk -F= '
    /^\[/ { s=$0; gsub(/[\["\]]/,"",s); next }
    /^(status|device|id)=/ {
      v=$0; sub(/^[^=]*=/,"",v); gsub(/"/,"",v)
      if ($1=="status") printf "%s status=%s\n", s, v
      else printf "%s %s=%s\n", s, $1, (v==""?"EMPTY":"present")
    }
  ' /var/local/emhttp/disks.ini
  grep -c '^\[' /var/local/emhttp/disks.ini
  bash hw-inventory.sh > "$HOME/hw.md"; echo "exit=$?"
  sed -n '/^#### Array slots/,/^_Slot names/p' "$HOME/hw.md" | grep -c '^| '
  ```
- **Run as:** one run is enough — Unraid's console is root, and nothing in this
  section is root-gated anyway. If you happen to have a non-root shell, say
  whether `/var/local/emhttp/disks.ini` is readable from it; that is a bonus
  answer, not the question.
- **Send back:** the first command's output **verbatim — it is already safe**,
  which is why it is shaped that way: slot names are Unraid roles (`parity`,
  `disk1`, `cache`, `flash`), status values are emhttp's own vocabulary, and
  `device` and `id` are reduced to `EMPTY`/`present` so no serial or node name
  leaves the host. Then the two counts and the exit code. The table count
  includes its header row, so **sections + 1** is the pass; anything lower means
  a slot was dropped, and the first command says which.

### FT-007 — the root half, on hardware that has any (standing)

- **Needs:** any host you can `sudo` on, and ideally one with a BMC, a
  PERC/MegaRAID controller, or DIMM slots `dmidecode` can enumerate.
- **Why not here:** agent sessions on the development host have no sudo — it
  needs an interactive password no session can supply — so the entire root half
  of this script has only ever been exercised by *simulating* `is_root() { true; }`
  against a copy. CI runs as root and covers the stubs and fixtures; what it
  cannot cover is real IPMI, a real RAID controller, and real DIMM records, since
  a runner has none of them. That is what this asks for.
- **Run:**
  ```bash
  sudo bash tests/run.sh 2>&1 | tail -3
  sudo bash hw-inventory.sh > "$HOME/hw-root.md"; echo "exit=$?"
  grep -c '^### ' "$HOME/hw-root.md"; sed -n '/^## Collection warnings/,$p' "$HOME/hw-root.md"
  ```
- **Run as:** root, by definition. The unprivileged pass is what every other
  entry already covers.
- **Send back:** the suite's pass/fail line, the script's exit code, the section
  count, and the warnings block verbatim — it names tools, not machines, which is
  why it is the one part of a report that is always safe to paste. Say what the
  host class is: BMC or not, hardware RAID or not.
- **Standing, not one-shot.** Re-run it after any change to a root-gated
  collector. It is the only check that touches real privileged hardware.

---

## Answered

Nothing yet. An answered request moves here as one line — the verdict and the
host class, with the machine dropped — so the same question is not asked twice.
