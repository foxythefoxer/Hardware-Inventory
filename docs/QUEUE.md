# Agreed work queue

Accepted proposals not yet implemented, and implemented ones recorded so they are
not re-done. The reasoning behind every verdict is in
[`DISPOSITIONS.md`](DISPOSITIONS.md) under the same ID; `/adjudicate` is the
procedure for adding to either file.

**This file is the only record that an accepted request is still outstanding.**
The session that files feature requests records that it submitted one and what
the verdict was, then stops by design — it does not track whether this repo
implemented anything, and it deletes accepted items from its own backlog once
adjudicated. Nothing outside this repo will notice if this list rots.

Work that is *done* but proven on only one host class is not tracked here — it is
in [`FIELD-TESTS.md`](FIELD-TESTS.md), with the command to run and the answer
wanted. The notes below name the `FT-` id where one exists.

Ideas taken from other projects and **not yet adjudicated** are not tracked here
either — they are in [`PRIOR-ART.md`](PRIOR-ART.md) with their source repository
attached. "Nothing left in this file" therefore does not mean "nothing left to
consider"; it means nothing left that has been agreed to.

---

## Remaining

- **FR-004** — fill manufacturer/model/motherboard/BIOS from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged;
  those files are world-readable while serials are not. Today an unprivileged run
  emits `model: null` with the value sitting in a readable file. Accepted with
  binding conditions.

**FR-004 is the only item left, and as of 2026-09-09 nothing blocks it but
effort.** FT-006 is answered on both halves and is closed: the whitebox-desktop
half on this machine on 2026-09-07 (`0444` on the four fields, `0400` on the
serials), the unprivileged-LXC half from the estate on 2026-09-09.

**The LXC answer makes the container gate mandatory rather than precautionary,
so implement that condition first.** `/sys/devices/virtual/dmi/id/` **exists and
is populated inside an unprivileged LXC**, and `dmidecode` fails there — so a
container is precisely where the fallback would fire, and precisely where it must
not, or every container on a Proxmox node reports the node's motherboard as its
own in the machine-readable `model:` field. The condition was written
**unverified** for want of a container; it is now verified in the direction that
makes it load-bearing. Gate on `systemd-detect-virt -c`, not on
`PLATFORM != bare-metal` — a real VM's SMBIOS identity is legitimate inventory.

Two of FR-004's conditions remain unverified and neither is a blocker: the
placeholder-string filter (`To Be Filled By O.E.M.` and friends — this board
fills its DMI properly), and whether a container sees the host's DMI *values* or
synthetic ones, which cannot change the verdict because the gate skips both.
Everything else accepted has been implemented — v7, below.

**Read the ledger entry before implementing any of these FRs.** FR-004 is the
one left; the note below applies to it, and applied to FR-001 and FR-002 when
they were still here. For an
accepted-with-changes item the conditions **are** the acceptance, and the summary
line above is deliberately not a substitute for them — an index line that
enumerates a condition set is the long form in miniature and drifts exactly as
the long form does, which is why these lines do not try. Each was written against
a real host, and FR-004 marks the conditions that could not be verified here;
confirm those on a Proxmox LXC and a whitebox board rather than shipping them on
reasoning alone — **FT-006**, and it wants answering *before* the implementation,
not after.

---

## Done — do not re-implement

Verified against the file and covered by `tests/run.sh` where testable.

- **R2-001** — `nolog` passed to the three `perccli`/`storcli` calls, which otherwise
  write `storcli.log` into the working directory: a `show` verb that writes, which is why
  no banned-verb list could see it. T1 greps for the keyword instead of a verb, and T13's
  case asserting the hole was correct is inverted. **FT-011** confirms the keyword is
  accepted on a host that actually has the binary. v8.
- **FR-006** — the Docker container list rendered as a real Markdown table
  through `row()`, same as every other multi-row section; was a code-fenced
  dump of `docker ps -a`'s raw columns. Issue #3. Its cap moved from `cap()`'s
  inline marker to a deferred footnote, since the marker would otherwise land
  inside a table row.
- **FR-005** — the CR from Unraid's FAT32 `/boot` stripped in `row()` and in the
  `ident.cfg` awk, which is why the Shares table rendered as one cell per line.
  Issue #2, the first defect a real host found rather than a review. T4's two new
  cases anchor a whole row `^...$` — a `grep` for the first cell passes against
  the broken output, since the break lands after it. **FT-010** wants v7 confirmed
  on the host that filed it, and asks the one thing a fixture cannot: whether
  `/var/local/emhttp/*.ini` really are LF, as the awk table's missing guard assumes.
- **C-005** — `/etc/os-release` parsed as `KEY=value` instead of sourced, which
  executed it as root on every run. T18 turns on a command substitution in
  `PRETTY_NAME`: sourced it collapses, parsed it stays literal.
- **C-016 + A-007** — one `lsblk -P` capture feeds the device table, the disk
  list and the megaraid probe, and that probe now picks its target by `TRAN`,
  excluding `usb` and `nvme` — on Unraid the first non-NVMe disk is the USB boot
  key, and probing it reports "no drives answered" on a host whose array is
  fine. T6's fixture is that layout and its smartctl stub names the node it was
  asked about; the root half of it only runs under `sudo` or in CI.
- **C-004** — `|` escaped in every table cell, through one `row()` helper that
  `kv()` also calls, plus an `esc()` in the one table built in awk. The
  container-networks table is exempt on purpose: `|` is its own field separator
  there. T4 and T6 assert the escape and the resulting cell count.
- **A-008** — `lscpu` and `free -h` captured once at the gather stage and parsed
  from text six times. Report byte-identical on this host.
- **A-009** — the micro-simplification batch, five of six. The three
  `cat /sys/class/net/…` reads in the interface loop stayed as `cat`: bash
  reports a missing file in `$(<file)` on its own stderr and `2>/dev/null`
  inside the substitution does not suppress it, so an interface class with no
  `speed` attribute would fail T2's empty-stderr assertion elsewhere. Measured;
  the reason is in a comment at the site and in the ledger.
- **FR-001** — display detection from `/sys/class/drm/card*-*/edid`, with
  `edid-decode` where installed and `strings` over the same bytes where it is
  not. All four binding conditions are held by T15, one assertion each. The
  stat-0 gate is the one that needed a fixture trick: a committed 128-byte file
  has a 128-byte `stat`, so a `[ -s ]` regression passed the whole suite until
  `card1-DP-8/edid` was made a symlink to a procfs file — the one thing
  available that stats as 0 and still reads non-empty. **Both off-host cases came
  back on 2026-09-09.** FT-003: a server with a GPU installed and nothing plugged
  into it renders no section — a connector node with no EDID behind it, which is
  the case the entry called interesting. FT-004: the `strings` fallback recovers a
  legible panel model from a real eDP panel, no empty rows and no control
  characters, with a trailing padding space that is **deliberately not trimmed**
  (it renders identically inside a table cell, and the section already says the
  fields are not separated). Still open on FT-004: whether the section survives an
  *unprivileged* run on a distribution whose EDID files may not be world-readable
  — only the root run was made.
- **FR-002** — UPS detection, sysfs `idVendor` as the primary signal, with
  apcupsd config, `apcaccess`, UPower and `power_supply` layered on top of it.
  T16 covers both directions, and the negative half runs under T8's stripped
  `PATH` so it does not depend on what is installed on whoever's machine runs
  the suite. **Verified against a live daemon on 2026-09-09** (FT-001, an Unraid
  host running apcupsd on a USB UPS): all three rows populate as root, and the
  `apcupsd config` row **survives an unprivileged run**, which was the open
  question — `/etc/apcupsd/apcupsd.conf` is read through `[ -r ]` and its mode
  varies by distribution. FT-002 confirms the silent negative on a host with
  nothing UPS-shaped, and FT-002b the harder negative: a laptop with `AC`, `BAT0`
  and two USB-C PD source entries emits no section, because the gate is
  `grep -lx UPS */type` and not the directory's existence. That last one is now
  staged as a fixture in T16's negative half, which had been reading the runner's
  own `/sys/class/power_supply`.
- **CI-005** — T10's under-cap assertion grepped the *whole report* for `---
  truncated` while stubbing only `systemctl`, so any of `cap()`'s ~20 other sites
  truncating correctly failed a test about systemd. Issue #4, reported from the
  first run of this suite on real privileged server hardware (BMC + MegaRAID);
  green on a desktop and in CI, which have neither. Reproduced here without that
  hardware by stubbing `systemctl` under its cap and `lspci` over its own.
  Scoped to `### Failed systemd units` rather than to the marker's wording, so a
  leak under any other noun still fails. **CI-004's class a fourth time** — it
  fixed the assertions that turned on `$RC` and left the ones that turn on a
  substring; the rule in `collectors.md` now covers every channel.
- **CI-004** — T2, T12 and T17 asserted `exit 0` against the *live* host, so any
  collector the runner happened to degrade failed a test about something else. The
  `v6` tag caught it: `a476d3f` was green on one runner and red on the next, on an
  unprivileged `lspci` that enumerated nothing and answered for root. The script was
  right to warn; the tests were asserting the runner's hardware. Now `rc_agrees`
  asserts the contract — a warnings block iff exit 1 — and each test's own claim is
  checked by name against that block. CI-001 fixed a cause of this and left the class.
- **CI-001** — the PCI section warned on its *filtered* output, so a guest whose NIC and
  disks are paravirtual — matching none of the section's device classes — was called
  broken. That one warning is why every CI run this workflow ever made was red, and why
  three assertions in T2 and T12 blamed docker and displays. T17 covers both directions.
  The root pass had never run either, being a later step in the same job; fixed with it.
- **CI-002** — T14 skipped its whole matcher half on every CI run for want of a
  gitignored file, leaving the publishing rule's only enforcement unverified on
  every push. CI now copies the committed example into place; everything that
  runs there tests built-in shapes, so it publishes nothing. The refusal
  assertion moved out of the skip branch — it had been running only where the
  list was missing — and a **zero-pattern list is now a failure**, written after
  a misfired `cp` in this repo replaced the real list with the example and
  nothing noticed.
- **C-025 / C-026** — warning accumulator and meaningful exit code. The
  exit-code contract in `.claude/rules/collectors.md` is the operative statement
  of it.
- **A-001** — the `set -u` crash on an empty container list. T12 is the operative
  statement of it; it is listed here so the fix is not mistaken for untested
  cleanup.
- **A-003** — four duplicated documentation blocks cut to links. The rule they
  broke is the one-line-index rule above; the `head -N` count had reached three
  copies.
- **C-003** — every hardcoded `timeout N` routed through the `have timeout` gate.
- **C-012** — physical-devices table filtered on `TYPE=="disk"` *plus* a
  `zd[0-9]` name exclusion; the `TYPE` filter alone does not catch zvols, which
  report `TYPE=disk`. Still unverified against real zvols — confirm on a
  `local-zfs` host (**FT-005**).
- **C-014** — named constants for every `head -N` limit, consumed through
  `cap()`. The rules that came out of it are under Conventions in
  `.claude/rules/collectors.md`; T10/T11 cover them.
- **C-009** — `/proc/cmdline` redacted by parameter **name** and by **value**,
  the latter for credentials embedded in dracut's
  `netroot=iscsi:user:pass:...@host` form where the name gives nothing away.
  Covered by T9. The name pass alone missed the embedded form for two commits: if
  you add another redaction, ask first whether the secret can hide in a value.
- **C-020** `racadm` root-gated under its own `###` heading · **C-023** one
  `docker inspect` over all containers instead of N+1 · **C-011** DIMM rows
  emitted at the record boundary · **C-001** `export LC_ALL=C` after `set -u`.
