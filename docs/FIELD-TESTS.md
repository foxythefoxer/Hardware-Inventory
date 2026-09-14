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

**Round two came back on 2026-09-13, collected against `v11` — the tip of `main`,
so there is no version gap to judge these answers across.** Five entries closed,
two re-checks came back still-unanswerable for the same reason as last time, one
census came back partial, and **eight entries were found defective as written**.
Three of those are the serious kind: the instruction could not produce the answer
it asked for, and in FT-012's case the entry's own **Send back** would have
recorded the exact opposite of the truth — an argument for deleting a gate that
works. Two answers surfaced defects rather than answers and were filed as issues
#7 and #8, per this file's own rule.

The lesson round two adds to round one's is one level up from the precondition
rule: **an entry that measures a gated code path must ask for the ungated call
as well, and must state its pass criterion as an outcome rather than as the one
branch the filer had in mind.** Both rules are below. FT-012 and FT-013 are the
worked examples, and FT-012 is now the second entry here to have been defective
in two different ways across two rounds.

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

**Ask for the mechanism separately from the gate.** FT-012 asked whether
`upower -e` activates a stopped `upowerd`, and asked it by running the whole
script with the daemon stopped — but the shipped gate is `have upower && have
systemctl && systemctl is-active --quiet upower` sitting *in front of* the
`upower -e` call, so a stopped daemon guarantees the call is never made. The
block returns `inactive` twice on every host, at every version since the gate
landed, whatever the mechanism does. **A gated path needs two measurements, and
they answer different questions:** run the shipped script to measure what the
gate prevents, and call the gated tool directly to measure the thing the gate
exists for. Neither substitutes for the other, and an entry that asks for one
while interpreting it as the other is the precondition trap one level up — a
null result for want of a question rather than for want of a thing.

**State the pass criterion as an outcome, not as the branch that produces it.**
FT-013's pass was "the two counts read `1` and `1`", where the second count was
a `(needs root)` row that only prints on hosts where `dmidecode` is *absent* —
so a container that happens to have it installed returns a **false failure**,
and that entry's **Send back** told the operator to escalate it immediately. What
actually proved the gate held was the em dashes in the identity rows, which hold
whichever branch fires. Ask what a pass *looks like*; do not describe the one
code path you had in mind. The corollary for any entry that counts table rows:
`row()` emits `| value | value |` but the separator prints as `|---|---|` with no
space after the pipe, so `grep -c '^| '` counts the header and the data rows and
**never** the separator — entries + 1 is the pass, and FT-010 shipped a round
asking for entries + 2, where a clean pass looked like a missing row.

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

**"Not needed" is not the same instruction as "must not be sent", and an entry
that means the second must say the second.** FT-004 asked whether each display
row carried a legible make and model, noting that "the strings themselves are not
needed" — true, and on the one-panel laptop of round one it cost nothing. On a
host with an external monitor the same row carries an unlabelled **serial
number**, because without `edid-decode` the descriptor bytes cannot be told
apart. A caveat phrased as a convenience gets dropped by an operator who cannot
see why it is there, and the one host class where it matters is the class that was
never available to the filer. Same for a narrowed glob: FT-010's `file` command
was narrowed to one representative to stop a share *list* crossing, and the one
filename that survived was still a share name, which is user content.

Nothing you send is committed verbatim. What lands in this repo is the verdict
with the machine dropped: *"confirmed on a host running apcupsd — the MODEL and
STATUS rows populate, no warning"*. Never the model string, never the hostname.

If the answer shows a bug, that is an ordinary finding: `/adjudicate` it, and it
gets an ID in [`DISPOSITIONS.md`](DISPOSITIONS.md) like any other.

---

## Open

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
  sas, one nvme" is the whole answer, and **an empty `TRAN` is a valid value, not
  a failed command** — see the correction below), the megaraid row count, and
  whether the "No drives answered" line is present. A count above zero with that
  line absent is the pass.

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
# `-i` is not optional: without an operating-mode option smartctl only OPENS the
# device and prints "Use 'smartctl -a' ...", so both counts read 0 on a working
# controller and the pair stops discriminating anything (correction, round two).
smartctl -i -d megaraid,0 "/dev/$MRTGT" | grep -cE '^(Device Model|Product|Serial Number):'
smartctl -i -d megaraid,0 /dev/bus/0    | grep -cE '^(Device Model|Product|Serial Number):'
```

**Send back:** the `TRAN` values (no `NAME`s — "one sas, one nvme" is the answer,
and two blanks is also an answer), the `--scan` lines with any serials or WWNs
cut, and the two counts. `0` then non-zero confirms hypothesis 3 and makes this a
script bug; both `0` means the passthrough is refusing this caller entirely and
the cause is elsewhere. The likely fix if it is 3 — deriving the target from
`smartctl --scan`, which already proposes the right node — is not being written
until this comes back, because it would replace a working code path on a guess.

**Hypothesis 3 is refuted, 2026-09-13, `v11` — and the finding went to issue #7.**
The measurement and the diagnosis are on the issue; it awaits a verdict there
rather than here, so **this entry stays open until that lands** and whoever runs
it next runs the text above. What belongs here is that the target-node
hypothesis this entry was built to test is **wrong**: on that host the
passthrough works from every node tried. All three forms — `-d megaraid,0` on
the probe's own target, on `/dev/bus/0`, and `-d sat+megaraid,0` — return "ATA
device successfully opened" at exit `0`, and `--scan` enumerates all eight
drives. The probe is not picking the wrong device.

- **Correction, and it is why the refutation nearly did not happen: the
  discriminating pair did not discriminate.** Both lines ran `smartctl -d
  megaraid,0 <node>` with no operating-mode option, so smartctl only opens the
  device and prints "Use 'smartctl -a' ... to print SMART information" — **both
  counts come back `0` on a perfectly working controller**, for want of a question
  rather than for want of a drive. This entry read both-`0` as "the passthrough is
  refusing this caller entirely and the cause is elsewhere", which on this
  evidence would have been a false negative pointing away from the real defect.
  `-i` is now in both lines. It was caught only because the operator dumped the
  full output instead of trusting the count.
- **Correction: the `TRAN` example read as an expectation.** Both disks on that
  host report **empty** transport and there is no NVMe at all. Empty `TRAN` is
  normal for controller-backed virtual disks — it is exactly what the probe's own
  filter treats as eligible — but an operator who gets two blanks where the entry
  showed "one sas, one nvme" may reasonably conclude the command failed. Both
  **Send back** lines now say so.
- One secondary observation, not worth an entry of its own: `-n standby` is inert
  through that controller, which answers "CHECK POWER MODE not implemented,
  ignoring -n option". Not a defect — the standby guard simply does nothing on
  that path.

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
- **Re-checked 2026-09-13 and still unanswerable there.** `command -v perccli64 storcli64
  MegaCli64` returns nothing on the only host in that estate with a real controller, exactly
  as in round one, and the `v11` report's RAID section says so in its own words: *"No vendor
  CLI found."* Recorded as a re-check rather than as a new answer because the blocker is a
  fact about that estate today, not a permanent exclusion — **two negative rounds are not
  unanswerability, and this entry is not abandoned.**

### FT-014 — does the `findmnt` fallback populate the table on util-linux 2.23? (R2-008)

- **Needs:** RHEL 7 or CentOS 7, or anything else shipping util-linux below 2.28.
  `findmnt --version` says.
- **Why not here:** this host runs util-linux 2.42.3, where `--real` works, so the
  first branch always wins and the fallback is never reached on any run or in any
  test. A stub can only prove that our own `if` fires — it cannot prove the older
  binary accepts `-t no...` and returns the same four columns, which is the whole
  question. The README's matrix lists RHEL as **Full** support and the script warned
  it had no mounted filesystems.
- **Run:**
  ```bash
  findmnt --version                                       # precondition: below 2.28?
  findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS | wc -l  # expected: 0, and an error
  findmnt -t nosquashfs,notmpfs,nodevtmpfs,nooverlay -o TARGET,SOURCE,FSTYPE,OPTIONS | wc -l
  ```
  If the first line reports 2.28 or newer, stop — this host cannot answer it, and
  both commands will simply work.
- **Run as:** unprivileged. Neither form needs root.
- **Send back:** the version and the two counts. `0` then a number above 1 is the
  pass and confirms both halves — that `--real` really is what failed, and that the
  fallback really does recover the table. Two non-zero counts mean `--real` works
  there after all and the finding's premise is wrong on this distribution, which is
  worth knowing and needs no report. **No report, and no mount table** — the counts
  are the answer; a mount table is estate topology.
- **A partial census, 2026-09-13 — data, not a verdict.** Two hosts measured, both far above
  the threshold: util-linux **2.41** on a Dell PowerEdge and **2.41.3** on a Fedora 44
  laptop. Two other hosts in that round closed their sittings without recording theirs, so
  the census is incomplete and is reported as incomplete rather than rounded to "this estate
  cannot answer it".
- **The two missing versions are not being chased, and that is the verdict on the census.**
  This entry needs util-linux *below* 2.28 — RHEL/CentOS 7 or equivalent — and two more
  numbers above 2.28 cannot turn an incomplete "nothing here is old enough" into an answer.
  Completing the set would cost someone two trips to two machines to leave this entry exactly
  where it sits, which is the thing the header warns against. The two measured versions are
  recorded so the next round does not re-measure the same hosts.

### FT-015 — what device ID does a real controller number its drives from? (R2-009)

- **Needs:** any host with a hardware RAID controller and its vendor CLI —
  `perccli64` or `storcli64`. The same host class as FT-011.
- **Why not here:** no controller in reach, so the fix is measured against a stub
  that answers wherever it is told to. The stub proves the probe *can* find drives
  based at 12; it says nothing about whether any controller actually numbers them
  that way. **This is the difference between MEDIUM and HIGH**, and it is the one
  thing that would change the rating rather than the fix.
- **Run:**
  ```bash
  perccli64 /call/eall/sall show nolog 2>/dev/null | grep -i DID | head -20
  # or, on Broadcom:
  storcli64 /call/eall/sall show nolog 2>/dev/null | grep -i DID | head -20
  ```
- **Run as:** root. The vendor CLI needs it.
- **Send back:** **the lowest DID only** — one number. Nothing else from that output
  is wanted and most of it is estate identity: the listing carries enclosure IDs,
  slot numbers and drive serials. If the lowest is 0 through 9, the old bound was
  finding drives on this controller and the finding stays MEDIUM. If it is 10 or
  higher, this array was invisible before v11 and the finding was HIGH.
- **Worth pairing with FT-011**, which needs the same binary on the same host and
  asks for one directory listing.
- **Re-checked 2026-09-13 with FT-011 and blocked by the same fact:** no `perccli64`,
  `storcli64` or `MegaCli64` on the one host in that estate with a real controller. R2-009
  stays MEDIUM on the stub, and the entry stays open rather than abandoned — it needs a host
  where the controller *and* its CLI are both already present.

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
- **Re-run at `v11`, 2026-09-13, same host class** — a Dell PowerEdge, **BMC yes**
  (iDRAC), **hardware RAID yes** (LSI MegaRAID SAS 2208). The resident checkout
  moved `v7` → `v11` cleanly and `git describe --tags` confirmed the pin before
  anything ran.
  - Suite: **166 passed, 0 failed.** This is **the first real-hardware run since
    CI-005's fix, and the machine that produced that failure now agrees with CI** —
    which is the check that the fix was a fix and not a test tuned to a runner.
  - Script exit `1`, **13** sections — the same count the `v7` run gave, so no
    section was gained or lost between the tags on that host. Warnings block naming
    exactly one collector: `pct list` empty as root, the same known local condition
    round one reported, tracked on the operator's side and not a script defect.
  - **166 is not a shortfall against this host's 210, and the gap is measured,
    not assumed.** The suite `SKIP`s whole blocks for tools the runner lacks —
    ShellCheck (T7), the two `jq`-gated hook tests, and T14's half that needs the
    `private-patterns.local` from the README setup step a resident checkout has
    probably never run. Measured here at `v11` by mirroring every tool *except*
    `shellcheck` and `jq` onto a clean `PATH`: **210 passed with them, 159 passed
    without, 0 failed either way** — so those two binaries alone gate 51
    assertions. A field answer's pass/fail line is the signal; **its count is a
    fact about the host's toolchain**, and counts are comparable neither forward
    across tags nor sideways across hosts. Say "0 failed", not "166".
  - **Nothing to close, by design.** Two outings, two findings it alone could
    produce: CI-005 in round one, and in round two the confirmation that no runner
    could give.
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

**Round two, returned 2026-09-13 from the same estate, collected against `v11` —
which was the tip of `main` at the time and still is.** The pin, the code that
ran and the code in this repo are one commit (`c11ea81`), re-fetched before the
return was written, so round one's version-gap argument has no round-two
equivalent and nothing below needs re-running. That is also what let FT-010
satisfy its own "re-target at current `main`" instruction without a second
checkout. Every `Run` block was executed as written first; where a block could
not produce its own answer, what actually settles the question was run second and
**both results were reported, because the difference between them is the
correction.** Four entries below therefore carry a verdict *and* a defect in the
instruction that produced it.

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

### FT-004 — answered, both halves. The Displays section appears unprivileged, and the fallback survives a second vendor's EDID.

Round one answered the fallback's *quality* from a root run on a Fedora 44 KDE
laptop with one internal eDP panel (`v7`). Round two closed the half that was
left, on the same host class with an external DisplayPort monitor attached:
`v11`, **unprivileged, no sudo anywhere in the test**. Precondition confirmed
both times — `command -v edid-decode` found nothing, so the `strings` path is
what ran.

- `grep -c '^### Displays'` → **1**. **The section appears without root**, so the
  EDID files are world-readable on that distribution and the root-only case this
  entry was opened to rule out does not arise there. Exit `0`, with no
  `## Collection warnings` section at all.
  - **One narrowing on the reasoning that came with that**, because it would
    misinform the next entry otherwise: the return explained the clean exit as
    "an unprivileged run never attempts the root-gated collectors and so has
    nothing to warn about". The first half is right and the second does not
    follow. Most of the script's warn sites are not root-gated at all — `lscpu`,
    `lsblk`, `df`, `findmnt`, `ip` and `lspci` each warn when present, permitted
    and empty, and CI-004 exists precisely because an unprivileged `lspci` that
    enumerates nothing warns *correctly* and once failed a test about Docker.
    **Exit `0` with no warnings block is a fact about that laptop, not a property
    of unprivileged runs.** It is still the right answer here; only the
    generalisation is wrong.
- **Two connector rows**, one internal eDP and one external DP, each carrying a
  recognisable make and model; no empty row and no control characters. Round one
  proved the fallback against one panel, which could not establish that it
  survives a *second* vendor's descriptor layout. It does.

The **trailing padding space** on the eDP model value is round one's artefact and
the not-a-bug verdict on it stands unchanged: it lands inside a Markdown table
cell where it renders identically either way, and the fallback's contract is that
it does not separate the descriptor fields.

**A reading note, because the count and the rows prove different things.** The
heading prints whenever any connector yields EDID bytes, and a row is emitted as
`(EDID present, not parsed)` even where the parse recovers nothing — so `1`
proves the unprivileged *read* succeeded, which is this entry's actual question,
but would not by itself have shown the fallback recovered anything. Both halves
came back clean here, so it closes either way; recorded so a later round does not
read the count as proof of the rows.

**Correction, and this one is a publishing matter: the `Send back` asked for less
care than the data needs.** The external monitor's row carries a **serial number**
in its raw text, unlabelled and ahead of the model, because without a parser the
descriptor bytes cannot be told apart — the script says exactly that in the
section's own footnote. Round one's single eDP row carried no serial, so this was
the first run where the Displays section is genuinely unsafe to paste. "The
strings themselves are not needed" was doing real work by accident; **an operator
with one internal panel would never discover why**, which is how a caveat that
holds by luck becomes a leak on the next host. Were this entry still open the
line would now read *must not be sent*; it is closing, so the correction is
recorded here instead — and the rule it generalises to is in *Never send the
whole report* above.

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

### FT-009 — answered. `emhttp` blanks both fields, so the silent drop is reachable on a healthy array.

Measured 2026-09-13 on an Unraid host with a configured **dual-parity** array,
`v11`, one root run — Unraid's console is root, which this entry's **Run as** line
says is enough.

**`emhttp` does not keep `id=` for a slot with no disk in it: it blanks `device`
and `id` both.** Five slots came back `status=DISK_NP` with both fields empty and
`emit()`'s early return fired on every one. So **the drop is reachable on an
ordinary healthy array**, not only on a degraded one — which is what this entry
was opened to find out, and it resolves PA-005 in the direction that makes it a
defect rather than a fixture gap.

- `grep -c '^\['` → **13** sections; the Array slots row count → **9**, i.e.
  eight slots plus the header against this entry's stated pass of 14. Collector
  exit **`0`**, no warning, nothing in the report saying five rows are missing.
- The guard is `if (dev == "" && id == "") return` and it never consults
  `status`, which is read for display only. The report prints `Disks missing`,
  `Disks invalid` and `Disks disabled` from `var.ini` immediately above that
  table, so **a slot dropped this way leaves the report contradicting its own
  counters.** The guard's intent is right — five `DISK_NP` rows would be noise —
  and it is keyed on the wrong field.
- The `parity2` half of the question is moot on this host: dual parity, so
  `parity2` is populated and there was no empty parity slot to observe.

**Filed as issue #8 rather than returned as a verdict**, which is this file's own
rule working. How that judgment moved is worth keeping, because the reasoning
outlasts the outcome: the return was first read as an ordinary answered field
test on the grounds that the *harmful* case cannot be produced without degrading
an array. What moved it was the half that does not depend on that case — five of
thirteen slots dropped on a healthy array while the counters directly above read
`Disks missing: 0`. **Severity was the thing in doubt; validity never was.**

**The remaining half is unanswerable by construction, not pending.** Whether a
disk `emhttp` has *lost* — `DISK_DSBL`, `DISK_INVALID` — also comes back with a
blank `id` cannot be measured on that host, and that is not a host-class gap like
FT-011 and FT-015: it needs a **fault**, not a host, and no estate should
manufacture one on a live array to answer a field test. It also cannot change
anything. The answered half already establishes the drop is reachable, and the
fix under adjudication in #8 — keying the guard on `status` rather than on
`device`+`id` — makes `emhttp`'s retention of `id` irrelevant in either
direction. Same shape as FT-006: no further measurement can move it, so it
closes rather than sitting open waiting for a degraded array nobody should
produce.

### FT-010 — answered. The fix renders the Shares table on the host that filed issue #2.

Round one answered the `.ini` half from a `file` run alone. Round two ran the
script, on the same Unraid host, at `v11` — which is what "re-target at current
`main`" asked for, since `v11` *is* the tip of `main`. Root, one run, the same
run that answered FT-009.

- Exit **`0`**. `cr-lines-above` → **empty**: not one CR anywhere in the report.
- Shares table rows → **11** against **10** configured shares. Every share
  present and the table renders — **the headline question, and the part a fixture
  could not answer.** FR-005's fix works on the host that broke.
- `file` corroborates round one exactly: the representative `.cfg` and
  `ident.cfg` are `ASCII text, with CRLF line terminators`; every
  `/var/local/emhttp/*.ini` is plain `ASCII text` (one empty, one flagged for very
  long lines), none with CRLF. **The Array slots `awk` block is correct as shipped
  without a CR-strip guard**, and the second DOS-formatted input this entry was
  opened to rule out does not exist there.

**Correction, arithmetic: the pass was shares + 1, not shares + 2.** `row()`
emits `| value | value |` while the separator prints as `|---|---|` with no space
after the pipe, so `grep -c '^| '` counts the header and the data rows and never
the separator. **11 against 10 is the pass, and as the entry read it looked like a
row short** — the next operator would have re-run the sitting or filed a bug
against a working fix. FT-009 states the same arithmetic correctly as sections + 1,
which is what makes this a slip rather than a misunderstanding. The general form
is now in *Filing a request* above.

**Correction, publishing: the narrowed `file` glob still published a share name.**
Round one replaced `shares/*.cfg` with one representative to stop a share *list*
crossing, and that was the right change — but the filename that survives is still
a share name, and share names are user content. The operator redacted it; the
formats were the whole answer and carried it without the name. Noted because the
same half-fix looks complete to the next reader, and the general form is now in
*Never send the whole report* above.

### FT-012 — answered. `upower -e` does activate a stopped `upowerd`, and the R2-002 gate is load-bearing.

Measured 2026-09-13 on a Fedora 44 KDE laptop with `upower` installed and a
graphical session, `v11`, unprivileged apart from the stop and the start.
Precondition met both halves: `command -v upower` present, and
`systemctl list-unit-files 'upower*' | grep -c upower` → 1.

**Stopped the daemon, confirmed `inactive`, called `upower -e` directly (exit
`0`), and `is-active` then read `active`.** Restored and confirmed `active`. So
R2-002's inference is now a measurement, and **the gate cannot be dropped**:
removing it reintroduces a query that changes the host it is inventorying.
Corroboration, since R2-002 rested on reading a service file rather than on a
measurement: `/usr/share/dbus-1/system-services/org.freedesktop.UPower.service`
is present there, so the activation path the fix was reasoned from is the one
that fired.

**The entry's own `Run` block could not have produced that answer, and its `Send
back` would have recorded the opposite of it.** The shipped gate is `have upower
&& have systemctl && systemctl is-active --quiet upower` sitting *in front of*
`upower -e`, so stopping the daemon guarantees the call is never made: the block
returns `inactive` then `inactive` on every host, at every version since R2-002,
regardless of what the mechanism does. The operator ran it as written first and
got exactly that, then ran the direct call. Read against this entry's **Send
back**, `inactive` twice with `upower` installed meant *"v8 activated nothing on
this version and the gate is cheap insurance rather than a fix"* — **an argument
for deleting a gate that works, manufactured by the instruction rather than by
the host.** Two measurements were wanted and they answer different questions: the
gated collector run measures the gate's effectiveness (`inactive` twice is a real
pass worth keeping), and a direct `upower -e` between the two reads measures the
mechanism the gate exists for (`inactive` then `active` is the confirmation). The
entry performed the first while interpreting it as the second. The rule is now in
*Filing a request* above; **this entry is its worked example, and it is the second
round in a row that FT-012 has been found defective in a new way** — which is the
argument for that rule being written down rather than remembered.

**The `Needs` line also named the wrong class**, and would have sent the next
operator on a repeat of round one's void run: no server in that estate has
`upower` installed at all, which is why round one gained the precondition. The
answerable class is the inverse — **a desktop with the daemon stopped
deliberately.**

Two things offered before they were asked for, and neither bears on the answer:
the machine was on battery with no adapter attached, and D-Bus activation happens
at bus-connect, *before* any device enumeration — so the result is independent of
power source and of whether any power device exists at all. That is what makes it
generalise to the headless hosts the gate actually protects. That host prints no
`### UPS` section in either run, having no UPS to enumerate.

### FT-013 — answered. The shipped container gate holds in a real unprivileged LXC.

Measured 2026-09-13 on an unprivileged Debian LXC on a Proxmox node — the class
this entry asked for, and the class that answered FT-006 — reached by `pct exec`,
i.e. root inside the container, which the **Run as** line names as the same case.
`v11`. Precondition met: `systemd-detect-virt -c` printed a container type and
exited `0`.

**Every DMI row in `### Identity` came back `—`: Manufacturer, Model, Service tag
/ serial, Motherboard, BIOS. Nothing of the node's identity reached the
container's report**, which is the whole question. `model:` is null, `Platform`
reads `lxc`, exit `1`, and the warnings block names `dmidecode` and `dmidecode -t
memory` — both correct for an LXC under the "unknown, not none" contract. FR-004
ships verified on the class it was gated for.

**What proves the gate held is the em dashes, not the missing row — and the
stated pass of `1` and `1` was wrong.** `v11` has three identity branches, not
two: root-with-`dmidecode`, the DMI-sysfs fallback, and the `(needs root)` row.
`dmidecode` is installed in that container and `pct exec` is root, so the
**first** branch fired and the `(needs root)` row this entry greps for never
printed there at all. So the stated pass is branch-dependent and returns a **false
failure on a container that has `dmidecode` installed**, which is not exotic: it
arrives as a dependency of ordinary packages.

**Sharpening that diagnosis one step, because it changes which line was at
fault.** The `(needs root)` row does not appear only where `dmidecode` is absent —
it appears whenever the root-with-`dmidecode` branch does not fire *and* the sysfs
fallback does not either. Inside a container the fallback never fires by design,
so an **unprivileged** run there prints that row even with `dmidecode` installed,
and the stated pass of `1` and `1` would have been **correct for the run the `Run
as` line asks for in its first word**. What produced the false failure was the
same line's second sentence — "root inside an unprivileged LXC is the same case
for this purpose" — which is true of `dmidecode` failing and false of which
identity branch renders. **The two lines were individually defensible and
inconsistent with each other**, which is harder to catch than a plain wrong
criterion and is the better reason to state a pass as an outcome: an
outcome-shaped criterion would have survived either reading of `Run as`. Worse, the **Send back** told the operator that a
`0` meant the container had filed the node's identity as its own and was worth an
immediate `/adjudicate`. **A manufactured escalation, and the inverse of FT-012's
defect** — one entry would have hidden a real finding, this one would have
invented a false one, from the same root cause of describing a code path instead
of an outcome.

What makes the em dashes conclusive rather than merely consistent: `DMI_SYSFS` is
populated *above* the identity table, so had the fallback fired, the first branch
would have printed the node's values into those same five rows. FT-006 already
established that this container's `/sys/devices/virtual/dmi/id/` is readable and
populated **with the node's values** — so there was something there to leak, and
it did not leak.

**The branch-independent criterion, recorded rather than re-run.** The answer is
already in and no second sitting is wanted; this is for whoever re-asks the
question on a new container class. A pass is `model:` null **and** no `###
Identity` row carrying a vendor string — whether that shows as five `—` rows or
as the single `(needs root)` row depends only on whether `dmidecode` happens to be
installed, and neither is the defect:

```bash
bash hw-inventory.sh > "$HOME/hw.md"
grep -c '^model: null' "$HOME/hw.md"                                   # expect 1
sed -n '/^### Identity/,/^###[^#]/p' "$HOME/hw.md" \
  | grep -cE '^\| (Manufacturer|Model|Motherboard|BIOS) \| [^—(]'      # expect 0
```

The second count excludes both `—` and any `(needs root …)` string, so it reads
`0` under every branch that has not leaked and non-zero the moment a vendor string
reaches an identity row. **Checked before being written here, against all three
branch shapes** — five em dashes, the `(needs root)` row, and a synthetic leak
where the fallback printed a node's board into those rows: `0`, `0`, `4`. The
first draft of it ended the `sed` range at `/^$/`, which terminates on the blank
line directly below the heading and so never reaches the table — it read `0` on
the leak too, i.e. it was a criterion that passed everything. The range anchor is
`/^###[^#]/`, the same one FT-004's `Run` block uses, and it also keeps a `Model`
row in a later section from being counted.
