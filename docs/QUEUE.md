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

---

## Remaining

- **FR-004** — fill manufacturer/model/motherboard/BIOS from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged;
  those files are world-readable while serials are not. Today an unprivileged run
  emits `model: null` with the value sitting in a readable file. Accepted with
  binding conditions.

**FR-004 is the only item left, and what blocks it is an answer, not effort.**
FT-006 wants the unprivileged-LXC half before the code is written; the
whitebox-desktop half was answered on this machine on 2026-09-07. Everything
else accepted has been implemented — v6, below.

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
  available that stats as 0 and still reads non-empty. Unproven off this host
  class: the headless case, where the section must stay silent (**FT-003**), and
  the `strings` fallback against real panel EDID rather than the fixture
  (**FT-004**).
- **FR-002** — UPS detection, sysfs `idVendor` as the primary signal, with
  apcupsd config, `apcaccess`, UPower and `power_supply` layered on top of it.
  T16 covers both directions, and the negative half runs under T8's stripped
  `PATH` so it does not depend on what is installed on whoever's machine runs
  the suite. **The `power_supply` and `apcaccess` rows are unverified against a
  live daemon** — this host has the UPS attached with neither apcupsd nor NUT
  installed, which is precisely why sysfs is the gate. Confirm those two rows
  on a host running apcupsd (**FT-001**); the no-UPS-at-all case is **FT-002**.
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
