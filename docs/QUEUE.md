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

**Nothing.** FR-004 went in on 2026-09-12 and was the last accepted item; every
verdict in [`DISPOSITIONS.md`](DISPOSITIONS.md) is now either implemented, below,
or rejected.

That is not "nothing left to do", and the difference matters more now than it did
when this list was full. Three bodies of work sit outside this file by design,
and an empty **Remaining** is exactly when they get forgotten:

- ~~**Code review round two is unadjudicated below its CRITICAL.**~~ **Closed
  2026-09-12.** All 27 findings have a verdict: 23 accepted and implemented as
  `R2-001` … `R2-023`, 4 declined and written into
  [`collectors.md`](../.claude/rules/collectors.md) so they are not
  re-proposed. This bullet stays, struck through, because the *class* is what
  matters and it will recur: a review round that lands as one large document
  produces a backlog no file tracks until someone adjudicates it, and this one
  sat at 2 of 27 for three days. The next round wants its findings ruled on as
  they are read, not filed whole.
- [`PRIOR-ART.md`](PRIOR-ART.md) holds leads that have never been adjudicated
  either.
- Open entries in [`FIELD-TESTS.md`](FIELD-TESTS.md) are answers this repo is
  still waiting on from host classes this machine is not. **Round two returned
  2026-09-13 and closed five** — FT-004, FT-009, FT-010, FT-012 and FT-013 — so
  FR-004's container gate and R2-002's UPower gate are now measured on real
  hardware rather than inferred, and FR-005's fix is confirmed on the host that
  filed issue #2. **FT-008 closed 2026-09-14 with FR-008** — its target-node
  hypothesis was refuted and the defect it actually surfaced is fixed, so nothing
  is left to run on it. **Still open: FT-011, FT-014, FT-015**, plus standing
  FT-007. FT-015 remains the one that would change a rating rather than a fix: if
  a real controller numbers its drives from 10 or higher, R2-009 was a HIGH — and
  two rounds have now failed to reach it, because a controller is not enough and
  the vendor CLI has to already be installed.
- ~~**Two field answers came back as defects rather than answers and are filed as
  issues #7 and #8, unadjudicated.**~~ **Closed 2026-09-14.** Both accepted and
  implemented as FR-008 and FR-009, below, in v12. This bullet stays, struck
  through, because the *class* is worth keeping visible: a field test can come
  back as a defect rather than an answer, and when it does there is nothing in
  `FIELD-TESTS.md` to hold it — it becomes an issue, and issues are only tracked
  here once adjudicated. These two sat for a day in exactly that gap.

**An unadjudicated review round rots the same way this queue does, and has less
holding it up** — a queue item is at least visible in one line here, while a
finding nobody ruled on is 150,000 bytes into a document whose own README says
not to act on it without reading the ledger first. **R2 is the worked example
and it is now closed:** it sat at 2 of 27 adjudicated while this file said
"Remaining: nothing", which was true of the queue and false of the repo. Four of
the 25 that were still open turned out to be defects a running host would hit —
one hang, one total loss of a healthy array, one false warning on Alpine, one
silent omission from the filesystem table. **Rule the findings as you read them.
A round filed whole is a backlog no file tracks.**

**Read the ledger entry before implementing any accepted FR.** For an
accepted-with-changes item the conditions **are** the acceptance, and a summary
line here is deliberately not a substitute for them — an index line that
enumerates a condition set is the long form in miniature and drifts exactly as
the long form does, which is why these lines do not try. Each was written against
a real host; where a condition could not be verified here, the entry marks it and
it wants answering on the right host class *before* the implementation, not
after.

---

## Done — do not re-implement

Verified against the file and covered by `tests/run.sh` where testable.

- **FR-008** — `-i` added to the `-d megaraid,N` probe's `smartctl` call, which
  gated on identity fields that `-H -A` does not produce, so a healthy eight-drive
  array was reported as *"No drives answered"*. Issue #7. The SCSI/SAS serial
  extractor is case-folded with it — the 7.5 binary prints `Serial number:` for
  SAS and `Serial Number:` for ATA and NVMe, so a SAS drive cleared the gate on
  `Product:` and landed a blank serial. **The stubs were the real hole and are
  fixed at the source**: both megaraid stubs printed identity whatever options
  they were handed, modelling the gate rather than the tool, so T6 and T21 now
  fail if the flag is dropped again. T24 is new for the SAS spelling. v12.
- **FR-009** — the Array slots `emit()` guard keyed on `status == "DISK_NP"`
  instead of on blank `device`+`id`, which dropped five of thirteen slots on a
  healthy dual-parity array while the counters directly above read
  `Disks missing: 0`. Issue #8. Matching one status exactly is the design: any
  other state now renders rather than vanishing. The fixture gained both a slot
  that must stay suppressed and a lost slot that must render, because an
  assertion on either alone passes against a guard that drops everything or one
  that drops nothing. v12.
- **FR-004** — manufacturer, model, motherboard and BIOS filled from
  `/sys/devices/virtual/dmi/id/` when `dmidecode` is absent or unprivileged, so
  `model:` is no longer null on every unprivileged run with the value sitting in
  a `0444` file. Serials are not: they are `0400`, and the **Service tag /
  serial** row says it needs root rather than showing an em dash a reader would
  take for "this host has none". **Skipped inside containers** — an LXC sees the
  host's DMI, and FT-006 proved that gate load-bearing rather than
  precautionary — and skipped where `systemd-detect-virt` is absent, since the
  question cannot be answered there. Placeholder strings
  (`To Be Filled By O.E.M.` and friends) read as unknown. T19 holds every
  condition, all three host shapes. **FT-013 confirmed the gate on a real
  unprivileged LXC on 2026-09-13** — every DMI row `—`, `model:` null, nothing of
  the node's identity in the container's report — so this no longer rests on a
  stubbed `systemd-detect-virt`. v10.
- **FR-007** — the report wrapped in `<!-- hw-inventory:begin/end -->` comment fences and
  its `## <hostname>` heading replaced with the fixed `## Hardware inventory`, so a
  consumer pasting the report into a hand-written document has a heading-level-agnostic
  boundary and no longer a title that collides with the document's own. Issue #5. v10.
- **R2-012 … R2-023** — the LOW/NITPICK batch, twelve of sixteen accepted, v11.
  Two tables that built rows outside `row()`/`esc()` routed through them —
  C-004's entry claimed there was one and there were two. `key` no longer
  redacts `vconsole.keymap` on every dracut host, with `rd.luks.key` asserted
  still-redacted so the exclusion cannot widen unnoticed. The `df` filter
  anchored: unanchored it silently dropped any filesystem whose name begins
  with `none`, `overlay` or `tmpfs`. `docker ps -a` and `smartctl --scan` each
  run once instead of twice. One timestamp feeds the fence and `collected:`, so
  the two machine-read date fields cannot disagree. Plus `yk()` stripping CR,
  `IPMI_SEL_LINES`, `g()` taking its file as an argument, two more tools inside
  the timeout convention, and comments recording the racadm and docker-gate
  judgments. **Four declined** — `F-020`, `F-021`, `F-023`, `F-027` — with
  `F-023` the one worth knowing: capturing that section to fix its fence would
  put four `warn` calls in a subshell and lose them.
- **R2-005 … R2-011** — all seven R2 MEDIUMs, v11. `fld()`'s key anchored, so a
  future `lsblk` column that merely ends with an existing key can no longer make
  the device table name the wrong device (T6's fixture grew `KNAME`, and its
  existing row assertion catches it). `free -h` falls back to `/proc/meminfo`,
  so BusyBox rejecting a flag is no longer reported as a broken collector.
  `paste -sd` replaced by `joinby` at eight sites — it cycles delimiters, so
  three items joined as `a,b c`, **and two items silently used only the first
  delimiter**, which the review had cleared as safe. `findmnt --real` falls back
  for util-linux below 2.28 (**FT-014**). The megaraid probe arms its miss
  counter only after the first hit — a controller numbering drives from 10 lost
  its entire array *and the report said so* (**FT-015**). The two guest loops
  and the probe are bounded by `RUN_BUDGET_S` / `MEGARAID_PROBE_S`, and warn
  when they cut. A failing `pct`/`qm config` is counted and warned once instead
  of dropping guests in silence. T21 and T22 are new; all five fixes with
  behaviour changes were mutation-verified.
- **R2-003** — all 24 `"${TMO[@]}"` expansions changed to the empty-array-safe
  `${TMO[@]+"${TMO[@]}"}`. Below bash 4.4 the bare form is an unbound variable
  under `set -u` when the array is empty — which is precisely the host with no
  `timeout` installed, the one the fallback exists for. Two sites are in the
  main shell, where that abort truncates the report instead of emptying one
  capture; the second of them was added by FR-004 four months *after* the review
  named the first. T1 greps for the bare form (comments stripped — it failed on
  the comment that names it before it failed on any code), and **T20 runs the
  script with no `timeout` on `PATH` at all**, which no test in this suite had
  ever done. Not reproducible here: bash 5.3.15.
- **R2-004** — `pveversion` on the Identity line wrapped in `tmo 10`. It read
  `/etc/pve` unwrapped — pmxcfs, a FUSE mount that blocks rather than fails when
  the node loses quorum — while the same binary was already wrapped 700 lines
  below. It is the earliest collector in the file, so it stalled the run before
  any section printed. The check is a fixture edit, not a new test:
  `badbin/pveversion` exited 1 for every call, and an error is not how a wedged
  FUSE mount fails, so T3 never saw it. It now sleeps on the bare call.
  Mutation-verified: unwrapped RC=124 with no footer, wrapped RC=1 complete.
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
  the broken output, since the break lands after it. **FT-010 confirmed it on the
  host that filed it, 2026-09-13 at `v11`:** exit `0`, not one CR anywhere in the
  report, and all ten shares present in the table. It also answered the one thing
  a fixture cannot — `/var/local/emhttp/*.ini` really are LF, so the awk table is
  correct as shipped without a CR guard.
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
  fields are not separated). **FT-004 closed on 2026-09-13**: the section appears
  on an *unprivileged* run, so the EDID files are world-readable on that
  distribution and the root-only case does not arise there — and the fallback
  recovers a legible make and model from a second vendor's EDID (an external DP
  monitor) as well as from the laptop's own panel. One publishing note came with
  it: an external monitor's row carries an unlabelled **serial number** ahead of
  the model, since without a parser the descriptor bytes cannot be told apart, so
  the Displays section must never be pasted into this repo.
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
