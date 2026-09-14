# Changelog

Every released version is a git tag, and a tag never moves — `v7` points at the
commit that minted it and keeps pointing there after `main` moves on. Between
releases the script header carries the number the open batch *will* ship as, so
`main` is that number unreleased; `git describe --tags` is what separates a
release from the road to one.

**Mint on the re-fetch, not on the merge.** A number is cut when there is a
reason to tell the estate to pull, and everything landed since ships under it
together. A commit that alters the emitted report is not by itself a reason to
cut a version — see v8/v9 below for what happens when it's treated as one.

What changed in each version is also the *Done* list in
[`docs/QUEUE.md`](docs/QUEUE.md). The version is written three times in the
script — the header comment, the version `printf`, and the opening fence — and
T1 fails unless all three agree.

Pin a sweep so a month of reports can't straddle a bump:

```bash
git -C /opt/hw-inventory fetch --tags
git -C /opt/hw-inventory checkout v7     # detached HEAD, deliberately
sudo bash /opt/hw-inventory/hw-inventory.sh > "$(hostname)-$(date +%F).md"
```

---

## v12

`FR-008` and `FR-009`, the two defects that came back from field-test round two
as findings rather than answers — both measured against `v11` itself, which is
what earns the number here rather than the merge.

`FR-008` (issue #7): the `-d megaraid,N` probe required `Device Model` /
`Product` / `Serial Number` before counting a hit, and asked `smartctl` only for
`-H -A`, which produces none of them. Every ID missed, and the section then
*asserted* the controller was empty — "No drives answered … may be in HBA/IT
mode" — on a host with eight healthy drives behind an LSI SAS 2208. Third time
this one probe has produced that same false sentence (C-016, R2-009). `-i`
added; the SAS serial extractor case-folded with it, since smartctl spells it
`Serial number:` for SCSI and a SAS drive was landing a blank serial in a table
that exists to report serials.

`FR-009` (issue #8): the Unraid Array slots guard dropped a slot on blank
`device`+`id` rather than on status, taking five of thirteen slots on a healthy
dual-parity array — silently, at exit `0`, while `Disks missing: 0` printed in
the table directly above it. Keyed on `status == "DISK_NP"` now, so an empty
slot stays suppressed and a lost one renders.

Report-changing for two host classes that **had both already filed reports under
`v11`**, which is the distinction v8/v9 below got wrong: those two changed
nothing on any host that had been run, and these change what the estate is
currently holding.

The durable fix is in the fixtures. Both megaraid stubs printed identity fields
whatever options they were handed — they modelled the script's own gate instead
of the tool — so the probe passed at every ID in CI and missed at every ID on
hardware. They now answer only what they are asked, and T6/T21 fail if the flag
is ever dropped again.

## v11

`R2-003`: without `timeout` on `PATH`, the empty wrapper array aborted the
script under `set -u` on any bash below 4.4 — the fallback for minimal hosts
was exactly what broke them. The two sentences describing the requirement used
to contradict each other for that reason. Fixed, and the test suite now runs
the script with no `timeout` on `PATH` at all, which it had never once done.
Full measurement in `docs/DISPOSITIONS.md` under `R2-003`.

## v8, v9 — the drift this changelog exists to prevent

Left standing rather than rewritten, as a worked example of the minting rule
above. v8 was R2-001 — `nolog` on the three RAID-CLI calls, so a `show` verb
stops writing `storcli.log` into the working directory — and v9 was R2-002,
the UPower probe gated on a daemon already running. Both are real fixes to the
read-only guarantee and both deserved to ship. But **neither changed the
emitted report on any host that had been run**: no estate host has a RAID CLI
installed at all (`FT-011`), and the UPower gate stops a daemon being
activated rather than altering a section. Two numbers for two states nothing
ever filed a report under is the noise v5's entry below argues against — three
versions later, against the same rule. The tags stay, because a tag never
moves and that includes one that should not have been cut.

## v7

`FR-005`, the first defect a real Unraid host found rather than a review:
`/boot` is the FAT32 flash device, so its `.cfg` files are CRLF, and the CR
rode through `$(...)` into the Shares table and the flash-identity line —
Markdown honours it as a line break, so each row ended after its first cell
and the table stopped being a table. Report-changing for exactly one host
class, which is what a version number is for.

## v6

The queue batch: `C-005` (os-release parsed, not sourced), `C-016` + `A-007`
(one `lsblk -P` capture, and a megaraid probe that skips the USB boot key),
`A-008`, `A-009` and `C-004` (`|` escaped in every table cell). Two of those
change the report — an Unraid host gets drive rows where it got "no drives
answered", and any cell containing a pipe stops shifting the columns after it.

## v5

Displays, UPS, and the `CI-001` PCI fix. That last one changed the report too
— on a host whose PCI devices match none of the section's classes, a section
and a spurious warning both disappear, and the exit code goes from `1` to `0`
— and it still didn't earn a number of its own, because no report had ever
been produced by a v5 without it. A version number describes what a consumer
can be holding, not what the repository did; two numbers for a state nothing
ever ran is noise in every vault that files by this field. v5 was tagged and
fetchable before this batch, so this one was v6.
