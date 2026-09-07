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

---

## Remaining

- **C-016** — the megaraid probe targets the first non-NVMe disk, which on Unraid
  is often the USB boot device.
- **C-004** (LOW) — escape `|` in Markdown table cells. Most pipe-bearing output
  already sits inside code fences.
- **C-005** — `/etc/os-release` is sourced, which executes it as root.
- **FR-001** — monitor detection via DRM EDID, read from
  `/sys/class/drm/card*-*/edid`. Displays are the one category of attached
  hardware the script cannot see, and sysfs reads work headless where `xrandr`
  needs a session. Accepted with binding conditions.
- **FR-002** — UPS data-connection detection. Accepted with changes, the
  load-bearing one being that the primary signal is a sysfs read of `idVendor`
  rather than `lsusb`, and that `/sys/class/power_supply` cannot be the gate.
- **FR-004** — fill manufacturer/model/motherboard/BIOS from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged;
  those files are world-readable while serials are not. Today an unprivileged run
  emits `model: null` with the value sitting in a readable file. Accepted with
  binding conditions.

- **A-007** — hoist the `lsblk -P` call and derive `DISKS` from it. Deferred into
  C-016, which changes that same path; doing them separately means the same
  reasoning twice.
- **A-008** — capture `free -h` and `lscpu` once instead of re-invoking them six
  times between them. Same shape as the `DMIMEM` capture already in the file.
- **A-009** — micro-simplifications as one batch: the `CNAMES_TRUNCATED`
  bookkeeping, `cap()`'s `total`, and `$(<file)`/`$EUID`/`${f##*/}` for six
  forks. Cleanup, not correctness — every site works today.

**Read the ledger entry before implementing any of these FRs.** For an
accepted-with-changes item the conditions **are** the acceptance, and the summary
line above is deliberately not a substitute for them — an index line that
enumerates a condition set is the long form in miniature and drifts exactly as
the long form does, which is why these lines do not try. Each was written against
a real host, and FR-004 marks the conditions that could not be verified here;
confirm those on a Proxmox LXC and a whitebox board rather than shipping them on
reasoning alone.

---

## Done — do not re-implement

Verified against the file and covered by `tests/run.sh` where testable.

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
  `local-zfs` host.
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
