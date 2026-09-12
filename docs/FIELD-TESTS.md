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

**Round one came back on 2026-09-09 and the channel works.** Seven entries are
answered, two came back partial and stayed open, one entry was found *defective as
written* (FT-012, an ambiguous instruction that would have recorded a false
measurement), and one answer found a defect in the test suite that no CI runner
could ever produce (CI-005, via FT-007). Three things follow for whoever files the
next entry.

An answer that arrives partial is the normal case, not a failure — it is why each
entry says the *smallest* thing that settles it, so a half-answer is still worth
having. **An answer can also be wrong**: two came back measuring something other
than what the entry asked (`test -r` as root, `is-active` on an absent unit), and
both were caught only because the operator said which run each came from. And
**a partial answer can still close an entry** — FT-006 did, because the half that
came back decided the design and no measurement of the missing half could have
changed the verdict. Ask what the answer is *for* before asking for the rest of
it; an entry kept open at 90% costs someone a trip to a machine for nothing.

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

**Add a precondition wherever an absent tool and a negative result look the same.**
FT-012 asked for `systemctl is-active upower` before and after, and read `inactive`
twice as "the script activated nothing" — but `is-active` says `inactive` for a
unit that does not exist, so on a host without upower the entry would have
manufactured a measurement out of an absence. FT-004 has the same rule inverted:
confirm `edid-decode` is *missing* first, or the run tests the wrong path. Both
directions are the same instruction — **state what must be true for the answer to
mean anything, and put it in the `Run` block as its own command**, not in prose an
operator reads after the fact. A wrong answer from a host class this repo cannot
reach is not correctable here; nobody can go back and check.

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
- **The fallback's quality is answered, 2026-09-09** on a Fedora 44 KDE laptop
  with one internal eDP panel, `v7`, **root run**. Precondition confirmed first:
  `command -v edid-decode` found nothing, so the `strings` path is what ran. The
  one connector row carries a legible panel model — not a raw `strings` dump — no
  row was empty, and no control characters appeared. So the fallback survives a
  real panel's EDID, which the committed 128-byte fixture could not establish.
  - One artefact, and the verdict on it: a **trailing padding space** on the model
    value. That is an EDID descriptor artefact carried through by design — the
    fallback's whole contract is that it does not separate the fields, and the
    report says so in the section. It lands inside a Markdown table cell where it
    renders identically either way, so **it is not being trimmed**: a `sed` to
    strip it would be a change to a collector to alter nothing a reader can see.
    Recorded here so the next session does not rediscover it as a bug.
- **Still open: the unprivileged run, which is the only thing left.** The entry
  asks for unprivileged *first* precisely because a section that appears only
  under root means the EDID files are not world-readable on that distribution.
  Only the root run was made, so that is untested and this answer is **not**
  evidence that EDID is world-readable there. One command settles it, and the
  section either appears or it does not:
  ```bash
  bash hw-inventory.sh | grep -c '^### Displays'
  ```

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

**Now a measured fail, not a hypothetical — raised in priority, 2026-09-09.** This
entry was not run, but a `v7` root report collected for FT-007 on a qualifying
host (BMC, LSI MegaRAID SAS 2208, `megaraid_sas`, drives behind it) contains the
answer to two of its three questions:

- `smartctl --scan` in that report enumerates **eight** megaraid device specs,
  `megaraid_disk_00` through `_07`.
- `grep -c '^| megaraid,'` → **`0`**, and the report prints `_No drives answered
  -d megaraid,N._`

Against this entry's stated pass — a count above zero with that line absent —
**that is the fail.** The probe found nothing on a controller whose drives
`smartctl` itself can see and name. The `-d megaraid,N` block is byte-identical
between `v7` and `v9`, so the evidence applies to the current code.

**What it is not yet:** a diagnosed bug. Three explanations were on the table and
the evidence moves them:

1. *Controller in HBA/IT mode* — the fallback text's first guess, now the weakest.
   In IT mode `--scan` reports drives as ordinary SCSI devices, not as
   `megaraid_disk_NN`; it reported the latter.
2. *Needs `-d cciss,N`* — the second guess, and `--scan` proposing `megaraid`
   argues against it.
3. **The target node** — the leading hypothesis, and it is the same *class* of
   defect as C-016 rather than a new one. `--scan` proposes `/dev/bus/0` as the
   passthrough node; the probe instead picks the first non-USB, non-NVMe disk from
   `lsblk` and runs `-d megaraid,$n /dev/$MRTGT`. If that block device does not
   route through the controller — a boot disk on the onboard AHCI controller would
   not — then every one of the 32 IDs misses, the `misses >= 10` break fires, and
   the output is exactly what was seen. **C-016's comment names only the Unraid
   USB-key case; on this evidence the same symptom has a second cause, on a host
   that is not Unraid and whose first non-USB disk is not a boot key.**

**The one thing to send, and it discriminates all three.** Read-only, root, and it
needs no report:

```bash
lsblk -dn -P -o NAME,TYPE,TRAN                      # what the probe picks from
smartctl --scan | head -3                           # what smartctl proposes
# Does ID 0 answer on smartctl's node but not on the probe's?
MRTGT=$(lsblk -dn -P -o NAME,TYPE,TRAN | grep -Ev 'NAME="nvme|TRAN="(usb|nvme)"' \
  | sed -n 's/^NAME="\([^"]*\)".*/\1/p' | head -1); echo "probe would pick: $MRTGT"
smartctl -d megaraid,0 "/dev/$MRTGT" | grep -cE '^(Device Model|Product|Serial Number):'
smartctl -d megaraid,0 /dev/bus/0    | grep -cE '^(Device Model|Product|Serial Number):'
```

**Send back:** the `TRAN` values (no `NAME`s — "one sas, one nvme" is the answer),
the `--scan` lines with any serials or WWNs cut, and the two counts. `0` then
non-zero confirms hypothesis 3 and makes this a script bug; both `0` means the
passthrough is refusing this caller entirely and the cause is elsewhere. The
likely fix if it is 3 — deriving the target from `smartctl --scan`, which already
proposes the right node — is not being written until this comes back, because it
would replace a working code path on a guess.

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
- **Answerable, and expected: 2026-09-09.** An estate has the host class (Unraid,
  configured array, single parity) and this was out of round one's scope only
  because the round was planned from a revision of this file that predated the
  entry. Nothing is blocking it — do not read its age as unanswerability.

### FT-010 — does the fix actually render the Shares table on the host that broke? (FR-005)

- **Needs:** the Unraid host that filed issue #2, running current `main`.
- **Why not here:** no flash device. FR-005 was reproduced and fixed against a
  CRLF fixture — the corruption reproduced byte-identically to the issue, and
  reverting the fix turns T4's two new cases red — but a fixture is a model of
  the file, not the file. What it cannot rule out is a *second* DOS-formatted
  input in that section that this repo has no sample of: `disks.ini` and
  `var.ini` are assumed LF because `/var/local/emhttp` is tmpfs, and the awk
  table that reads them carries no CR guard on that assumption.
- **Run:**
  ```bash
  git -C /opt/hw-inventory fetch --tags && git -C /opt/hw-inventory checkout main
  bash /opt/hw-inventory/hw-inventory.sh > "$HOME/hw.md"; echo "exit=$?"
  # Any CR left anywhere in the report, and where:
  grep -n $'\r' "$HOME/hw.md" | cut -d: -f1 | tr '\n' ' '; echo "cr-lines-above"
  # Do the two tables have the same number of rows as they have entries?
  sed -n '/^#### Shares/,/^_.shareUseCache/p' "$HOME/hw.md" | grep -c '^| '
  ls /boot/config/shares/*.cfg | wc -l
  # And are the source files CRLF as assumed? One representative share, not the
  # glob: `shares/*.cfg` expands to one path per configured share, and share
  # names are user content.
  file "$(ls /boot/config/shares/*.cfg | head -1)" /boot/config/ident.cfg /var/local/emhttp/*.ini \
    | sed 's#.*/##'
  ```
- **Run as:** one run, root — Unraid's console is root and this section is not
  root-gated either way.
- **Send back:** four short things, no report. (1) The exit code. (2) The
  `cr-lines-above` list — **empty is the pass**. (3) The two counts: shares + 2
  (header and separator) should equal the row count. (4) The `file` output,
  which is the part a fixture cannot answer — it says whether the `.ini` files
  really are LF, or whether the awk table needs the guard too. **Only the last
  of the four is safe to paste as-is**, and only in the narrowed form above; the
  original glob would have published a share list, which is why the command
  changed rather than the caveat.
- **The `.ini` assumption is answered, and it holds: 2026-09-09**, live `file` run
  on an Unraid host. `/boot/config/shares/*.cfg` and `/boot/config/ident.cfg` are
  **ASCII text with CRLF line terminators**; every `/var/local/emhttp/*.ini` is
  **ASCII text with no CRLF** (one empty, one flagged "very long lines", neither
  with a CR). So `/var/local/emhttp` is not the CRLF flash device that Shares and
  the flash-identity line read from, and **the Array slots `awk` block is correct
  as shipped without a CR-strip guard** — the second DOS-formatted input this
  entry was opened to rule out does not exist on this host.
- **Still open: the rest of the entry, which is its headline question.** The
  answer above came from a `file` run alone — the script was never run, so there
  is no exit code, no `cr-lines-above` list and no row-count comparison, and
  **whether the shipped fix actually renders the Shares table on the host that
  filed issue #2 remains unconfirmed.** That is the confirmation the fixture
  cannot give. Re-target it at current `main` rather than `v7`: the Shares,
  `ident.cfg` and `disks.ini` parsers are byte-identical from `v7` through `v9`,
  so checking out an old tag buys nothing.

### FT-011 — does the RAID CLI write a log, and does it take `nolog`? (R2-001)

- **Needs:** a host with `perccli64` or `storcli64` installed. A controller behind it is
  ideal but not required — the question is about the tool, not the array.
- **Why not here:** neither binary exists on any host in reach. R2-001 shipped on the
  vendor documentation for two facts that nothing here can measure: that the CLI writes
  `storcli.log` / `perccli.log` into the working directory without the keyword, and that
  `nolog` is accepted on the three command forms the script actually uses. If some version
  rejects it, those commands fail and the RAID section empties and warns — a degradation
  rather than a violation, but one nobody would attribute to a one-word fix six months on.
- **This is the one entry here that is not purely a read, and deliberately so.** It makes
  an empty scratch directory to give the tool somewhere harmless to write, because seeing
  whether it writes *is* the question. Nothing touches the controller: every command below
  is a `show`.
- **Run:**
  ```bash
  cd "$(mktemp -d)" && ls -A; echo "--- empty above ---"
  storcli64 /call show nolog >/dev/null 2>&1; echo "nolog exit=$?"
  ls -A; echo "--- after the nolog run ---"
  storcli64 /call show >/dev/null 2>&1;       echo "bare  exit=$?"
  ls -A; echo "--- after the bare run ---"
  # And the other two forms the script uses, keyword accepted or not:
  storcli64 /call/vall show nolog      >/dev/null 2>&1; echo "vall  nolog exit=$?"
  storcli64 /call/eall/sall show nolog >/dev/null 2>&1; echo "sall  nolog exit=$?"
  ```
  Substitute `perccli64` throughout on a Dell host; it is the same tool rebadged, and an
  answer from either settles it.
- **Run as:** **root.** These CLIs need it to reach the controller, and an unprivileged run
  can fail before it gets far enough to write anything, which would answer the question
  wrongly rather than not at all.
- **Send back:** the four exit codes, and the filenames that appeared — filenames only,
  not contents, and a log from a RAID CLI is one of the few files here whose *name* is the
  whole answer. Three things settle it: `nolog exit=0` with the directory still empty, a
  file appearing after the bare run, and the last two exits matching the first. If the
  directory is empty after **both** runs, say so — that means this fix was a no-op on this
  version and the entry should say which version.
- **One estate cannot answer it, 2026-09-09.** `command -v perccli64 storcli64 MegaCli64`
  returns nothing on the only host there with a real MegaRAID controller, and that host's
  distribution does not ship any of the three. Installing a vendor CLI onto a production
  host to answer a field test was declined, correctly — this entry is not worth a package
  install. **So a real controller is not sufficient to close this; the CLI has to already be
  there.** R2-001 stays shipped on vendor documentation until an estate has both, and that
  is an acceptable resting place: the failure mode if some version rejects `nolog` is an
  empty RAID section that warns, not a violation.

### FT-012 — does `upower -e` start the daemon it queries? (R2-002)

- **Needs:** a host with `upower` installed, systemd, a system bus, and `upowerd`
  **stopped**. A headless server or VM is the likely class; a desktop has it running.
- **Why not here:** `upowerd` runs on the development host, so the activation is inferred
  from UPower's D-Bus service file rather than measured. R2-002 already gated the probe —
  the gate is safe whichever way this comes back — so this confirms the mechanism for the
  record, and says whether the gate could ever be dropped again.
- **Run:**
  ```bash
  # Precondition, and the test is VOID without it: `is-active` answers `inactive`
  # for a unit that does not exist, so an absent upower is indistinguishable from
  # a stopped one. Both must print something before the rest means anything.
  command -v upower || echo "upower ABSENT — stop here, this host cannot answer it"
  systemctl list-unit-files 'upower*' | grep -c upower
  systemctl is-active upower; echo "--- before ---"
  bash hw-inventory.sh >/dev/null 2>&1
  systemctl is-active upower; echo "--- after ---"
  ```
  If they differ, stop the daemon again (`sudo systemctl stop upower`) and re-run with the
  v8 tag checked out to confirm it is the script and not something else on the host.
- **Run as:** unprivileged is enough and is the more honest test — nothing in the UPS
  section is root-gated, and D-Bus activation does not need root.
- **Send back:** the precondition result, then the two words. `inactive` then `active` means
  the finding is confirmed and the gate is load-bearing; `inactive` twice **with upower
  installed** means v8 activated nothing on this version and the gate is cheap insurance
  rather than a fix. Either answer is useful and neither needs a report.
- **Precondition added 2026-09-09, and this entry was defective without it.** A headless
  server was tried and returned `command -v upower` → nothing, `systemctl is-active upower`
  → `inactive`. Read against the original **Send back**, `inactive` twice would have been
  logged as "v8 activated nothing on this version" when the truth was that **the tool is not
  installed and nothing was activatable** — the entry would have manufactured a measurement
  out of an absence. That is FT-004's precondition, inverted: FT-004 must confirm
  `edid-decode` is *missing* before its answer means anything, and this one must confirm
  `upower` is *present*. Caught by the operator running it; a host class this repo cannot
  reach is exactly where an ambiguous instruction becomes a false record.

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
- **First real run, 2026-09-09, `v7`:** a Dell PowerEdge server — **BMC yes**
  (iDRAC), **hardware RAID yes** (LSI MegaRAID SAS 2208, `megaraid_sas`),
  partially populated DIMM slots `dmidecode` enumerates, a readable service tag.
  Script exit `1`, **13** sections, warnings block naming exactly one collector
  (`pct list` empty as root — a known local condition on that host, tracked
  elsewhere, not a script defect). Suite: **107 passed, 1 failed**.
  - **The one failure was a suite defect, not a script defect**, and it was filed
    as issue #4 rather than returned as an answer — which is this file's own rule
    working. Adjudicated as **CI-005**: T10's under-cap assertion grepped the
    whole report for `--- truncated` while stubbing only `systemctl`, so any of
    `cap()`'s ~20 other sites truncating *correctly* on a host with a real
    controller and a populated BMC failed a test about systemd. Fixed and
    reproduced without that hardware. The issue's own uncertainty — which site
    actually fired — turned out not to matter.
  - **This entry found a defect no runner could produce, on its first outing.**
    That is the argument for it being standing: CI has no BMC and no RAID
    controller, so this class of failure is invisible to it by construction.
  - Counts are not comparable forward: `tests/run.sh` gained ~90 lines between
    `v7` and `v9`, and 158 is the current figure on the development host class.
  - **Does not close.** It closes by its own terms, never.

---

## Answered

An answered request moves here as the verdict and the host class, with the
machine dropped, so the same question is not asked twice.

**Round one, returned 2026-09-09 from one estate, collected against the `v7`
tag** while this repo was at `v9`. Whether that gap invalidates an answer was
settled by diff rather than by argument: every collector these answers touch —
the DRM/EDID reads, `/sys/class/power_supply`, the `apcupsd.conf` read, the
Unraid `shares`/`ident`/`disks.ini` parsers, `lsblk`, and the `-d megaraid,N`
probe — is **byte-identical between `v7` and `v9`**. Only the RAID CLI
invocations (R2-001) and the UPower branch (R2-002) moved, and no answer below
rests on either. **Nothing here needs re-running at `v9`.** This file also did
not change between those tags except to gain FT-011 and FT-012, so every answer
was collected against the entry text as it still reads.

### FT-001 — answered. UPS rows from a live daemon, and the predicted failure did not happen.

Confirmed on an Unraid host running `apcupsd` against a USB-attached UPS, both
runs, same session. Root: three `Signal` rows — `USB device`, `apcupsd config`,
`apcaccess`. Unprivileged: the same minus `apcaccess`. No warning about the UPS
section either way, exit `0` both (the root code inferred from the contract, not
captured).

**The `[ -r ]` concern this entry was opened on is closed the other way:** the
`apcupsd config` row **survives an unprivileged run** on this distribution, so
the row can be trusted on an ordinary run. The row that dropped was `apcaccess`,
gated by neither privilege nor file mode but by `have apcaccess` plus a TCP query
to the daemon's NIS port. Which of the two failed was not measured — the run used
`su -s /bin/bash nobody -c`, so a reduced `PATH` and a daemon refusing the caller
are both live explanations — and **it does not need to be**: the script's
behaviour is identical and correct in both cases (no row, no warning, because a
tool that is absent or a query that returns nothing is silence, not failure). No
follow-up filed.

No `UPower` row appeared even at `v7`, where that branch was ungated: this class
has no systemd, so `have systemctl` also fails it at `v9`, for a second reason.

### FT-002 — answered. Absent hardware is silent.

A KVM guest with no USB bus: `### UPS` count `0`, no `## Collection warnings`
block at all, exit `0` (inferred from the contract). Delivered from a root run
where the entry asked for unprivileged, which the entry's own **Run as** line
permits — nothing in the section is root-gated.

### FT-002b — answered. A laptop battery is not a UPS, and neither is a USB-C PD source.

Filed and answered together, from a laptop with an internal battery:
`/sys/class/power_supply/` holds `AC`, `BAT0` and two `ucsi-source-psy-USBC000:*`
USB-C PD source entries, and `### UPS` count is **`0`**.

This is the false-positive shape FT-002 could not catch: every host class listed
there is negative because the directory is *empty*, which says nothing about a
populated one. The gate is `grep -lx UPS */type` — an exact type match, not the
directory's existence and not the `idVendor` read alone, which is why two
plausible non-UPS supplies and a battery all miss it.

**Now a fixture, not a standing request** (T16's negative half, CI-005's commit):
that half was reading `/sys/class/power_supply` off whatever host ran the suite,
where it happens to be empty. The committed suite passed a mutation that reports
every `power_supply` entry as a UPS signal; with the fixture staged, it fails.
The measurement is what said the code was right; the fixture is what keeps it.

### FT-003 — answered, both halves, the second one negative.

A bare-metal server with a discrete GPU installed, driver unbound, nothing
plugged in: `/sys/class/drm/` lists `card0`, `card0-VGA-1`, `version`, and
`### Displays` count is **`0`**. Exit `1` with a warnings block naming exactly one
collector (`pct list` empty — a known local condition on that host, tracked
elsewhere), and nothing about displays.

**That run is the interesting case, not the boring one.** A connector node with
no EDID behind it is precisely what this entry asked for; only the *virtual* GPU
variant went unmet, and FT-003b is why. A KVM guest cannot supply "a DRM node and
no EDID" — QEMU's virtual display presents a synthetic EDID. Reaching that
variant needs a guest with its display device removed, which is a configuration
change rather than a read; not worth a request, since the physical run already
exercised the branch.

### FT-003b — answered. A QEMU virtual display is not a headless host.

A KVM guest with a QEMU virtual display device lists `card0`, `card0-Virtual-1`,
`version` and renders **one** `### Displays` row, no warnings. The `-Virtual-1`
suffix is the tell. Not a bug — there is a display device, and the row is
correct — but two things follow: **this host class can never answer a negative
display test**, and a row in a guest report is synthetic rather than a monitor
someone forgot about. No fixture: the connector parses identically to the
committed EDID fixtures, so there is nothing here a test could hold still.

### FT-005 — answered. The `zd[0-9]` exclusion holds against real zvols.

A Proxmox host with `local-zfs` and both guest disks on it: `lsblk` shows `zd0`,
`zd16`, `zd32`, and `### Storage — physical devices` contains **`0`** matches for
`zd[0-9]`. First run against real zvols rather than the reasoning that
`TYPE=="disk"` alone would not catch them (C-012). Root run, which the entry
invited as a bonus; that same pass is what produced the FT-007 material.

### FT-006 — answered, both halves. **FR-004 is unblocked, and its container gate is load-bearing.**

The desktop half was answered on this machine on 2026-09-07: `sys_vendor`,
`product_name`, `board_name` and `bios_version` readable unprivileged at `0444`;
`product_serial`, `board_serial`, `chassis_serial` and `product_uuid` at `0400
root:root` and not. So the fallback can fill model, motherboard and BIOS without
root and can never fill a serial that way.

The LXC half, 2026-09-09, on an unprivileged Debian LXC on a Proxmox host:
**`/sys/devices/virtual/dmi/id/` exists in the container and lists the same field
set as bare metal.** Reached by `pct exec`, i.e. root inside the container — sound
for this question, because a directory's existence does not turn on the caller's
privilege. From the same run, `dmidecode` failed entirely there, both system
identity and memory.

**Read against FR-004's conditions, that is the opposite of a clean bill, and it
is the more useful answer.** The entry was framed as "does the feature need a gate
for a *missing* directory" — it does not. But FR-004's binding condition is the
other one: *skip the fallback inside containers, because an LXC generally sees the
host's sysfs and a naive read would report the Proxmox node's motherboard as the
container's own, in the machine-readable `model:` field.* That condition was
marked **unverified — no container available in this environment**. It is now
verified in the direction that makes the gate mandatory: the directory is there,
it is populated, and `dmidecode` is not available to contradict it, so **a
container is exactly where the fallback would fire and exactly where it must not.**
`systemd-detect-virt -c` is the gate, not `PLATFORM != bare-metal`.

**The unanswered remainder is moot, and is not being re-asked.** The LXC
readability check was run as `test -r` under `pct exec`, which returns true for a
`0400 root:root` file and so measures nothing about an ordinary user — a real
defect in that answer. It no longer matters: the container gate means the fallback
never runs in a container, so whether an unprivileged container caller can read
those files cannot change any line of the implementation. Nor can the one question
genuinely left open — whether the container sees the host's DMI *values* or
synthetic ones — because the verdict is "skip" either way: the host's values are
wrong, and synthetic ones are meaningless. **No further measurement can move this,
which is why it closes rather than staying open at 90%.**
