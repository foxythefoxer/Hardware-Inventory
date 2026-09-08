# Prior art — what other hardware-inventory tools do

A survey of comparable projects on GitHub, run 2026-09-08, and the ideas worth
taking from them. **Nothing here is adjudicated.** An entry is a candidate with
its source attached, parked so a later session can weigh it without repeating
the search.

This file is deliberately not `QUEUE.md`, which holds only *accepted* work, and
not `DISPOSITIONS.md`, which holds verdicts. An item leaves here by being
`/adjudicate`d — accepted into `QUEUE.md` with a `C-`/`FR-` id, rejected into
`DISPOSITIONS.md`, or deleted as not worth an id. Until then it is a lead, not a
plan.

**Every entry names the repository and the file it came from**, so the external
source can be re-read rather than trusted from this summary. Line numbers are
not recorded on purpose — those repositories move and ours does not track them.

---

## Where these came from

| Repository | What it is | Why it was worth reading |
|---|---|---|
| [linuxhw/hw-probe](https://github.com/linuxhw/hw-probe) | 927★, Perl, one 559KB file. Probes hardware, uploads to linux-hardware.org | The mature prior art. Same problem, ten years of it |
| [smxi/inxi](https://github.com/smxi/inxi) | 1281★, Perl. The system-info tool packaged by most distributions | The default answer to "just use an existing tool" |
| [loayai/yet-another-hardware-info](https://github.com/loayai/yet-another-hardware-info) | 27★, one 997-line bash file (`yahi.sh`) | The only true peer: single-file bash, same collectors, root-optional |
| [glpi-project/glpi-agent](https://github.com/glpi-project/glpi-agent) · [fusioninventory/fusioninventory-agent](https://github.com/fusioninventory/fusioninventory-agent) | 485★ / 268★, Perl | The enterprise shape: an agent whose point is reporting to a server |
| [pulpul-s/HWall](https://github.com/pulpul-s/HWall) | 84★, Rust, split into `collect/` modules | What this looks like when someone rewrites it as a program |
| [unraid/webgui](https://github.com/unraid/webgui) | 253★, the official Unraid web UI | **Authoritative source** for what `emhttp` writes into `/var/local/emhttp/*.ini` |
| [ruaan-deysel/unraid-management-agent](https://github.com/ruaan-deysel/unraid-management-agent) | 53★, Go | An independent `disks.ini` parser *with tests*, i.e. fixture shapes for a host class this repo cannot run on |
| [FugginOld/Unraid-HBAviewer](https://github.com/FugginOld/Unraid-HBAviewer) | 6★, PHP + bash | Tests a SMART-reading shell script with `PATH` stubs, the same way `tests/run.sh` does |

**What does not exist, which is worth knowing before anyone proposes replacing
this script with something off the shelf:** nothing found emits Markdown with
YAML frontmatter for a notes vault; nothing found has a read-only *contract*
enforced by hooks and CI rather than by habit. The field is three shapes —
agents that phone home, probes that upload, and one-shot bash reporters with no
tests at all.

---

## Candidates

### PA-001 — a systemd service and timer for the unattended sweep

- **Source:** `periodic/hw-probe.service` and `periodic/hw-probe.timer` in
  [linuxhw/hw-probe](https://github.com/linuxhw/hw-probe/tree/master/periodic).
- **What they do:** the unit sets `ProtectSystem=full`, `Nice=19`,
  `IOSchedulingClass=idle`, `IOSchedulingPriority=7` and `StandardOutput=null`;
  the timer sets `OnCalendar=monthly`, `AccuracySec=12h`, `Persistent=true` and
  `OnBootSec=7min`. Twelve lines between them.
- **Why it bears on this repo:** [`CLAUDE.md`](../CLAUDE.md) grounds the
  read-only rule in a goal — running unattended, on a schedule, with no human
  confirming each run. That goal currently has no artifact. `ProtectSystem=full`
  makes `/usr`, `/boot` and `/etc` read-only *to the unit*, which is
  kernel-enforced and sits underneath our source-level guarantee rather than
  restating it. `Persistent=true` catches up a sweep a host slept through;
  `AccuracySec=12h` stops a fleet waking at the same instant.
- **What not to copy:** their `ConditionVirtualization=false` skips guests. This
  script has Proxmox LXC and VM tables and is meant to run *inside* them.
- **The open question, which is why this is not already in the queue:** whether a
  unit file belongs in a repository that is currently one script plus its tests,
  or in the operator's own configuration. Shipping one means shipping a path,
  an output convention and a schedule, none of which this repo has an opinion on
  yet.

### PA-002 — selective collector suppression, and what it says about C-031

- **Source:** the "Disable logs" section of hw-probe's `README.md` —
  `-disable A,B,C` names collectors to skip.
- **Why it bears on this repo:** C-031 (splitting the file into `section_*()`
  functions) is **deferred, not rejected**, in
  [`.claude/rules/collectors.md`](../.claude/rules/collectors.md), explicitly
  "not worth the churn until `--skip` / section selection is actually wanted."
  This is the first outside evidence that a mature tool in this space wanted it.
- **Why it does not settle C-031 on its own:** hw-probe collects far more than
  this script does, and its stated motivation is upload size — a constraint this
  repo does not have, because nothing is uploaded. Evidence toward the deferral
  expiring, not proof that it has.

### PA-003 — stubs that record their argv, so tests assert what was *called*

- **Source:** `tests/read_smart_test.sh` in
  [FugginOld/Unraid-HBAviewer](https://github.com/FugginOld/Unraid-HBAviewer).
  Their `smartctl` stub appends `"$*"` to a temp file before answering, and the
  assertions run against that file rather than against the script's output. They
  note the same subshell trap this repo hit in G-002: the args must be read back
  from the file after the command substitution exits.
- **Why it bears on this repo:** T1 greps `hw-inventory.sh` for banned verbs
  after stripping comments and quoted strings. That is a *static* check on the
  source, and it cannot see a verb assembled at runtime, nor what was actually
  handed to `perccli` / `storcli` / `MegaCLI` once the invocation is built from
  variables. An argv-recording stub around those three would enforce the "allow
  only `show`-class verbs" convention dynamically — the convention is currently
  held by a comment and a reviewer's eyes.
- **Cost:** low. T6 already stubs `smartctl`; this is an assertion shape, not a
  new fixture. The natural home is beside T6.

### PA-004 — `/usr/sbin` and `/sbin` fallback when `command -v` misses

- **Source:** `check_dependency()` in `yahi.sh`
  ([loayai/yet-another-hardware-info](https://github.com/loayai/yet-another-hardware-info)).
  After `command -v` fails it tries `/usr/sbin/$cmd` then `/sbin/$cmd`.
- **Why it bears on this repo:** `have()` is `command -v` alone. Under the
  documented `sudo bash hw-inventory.sh`, Debian's `secure_path` already
  contains both directories, and `ip`'s absence prints a visible line in the
  report rather than vanishing — so **no hole is known**. The residual case is
  an unprivileged run on a distribution that keeps `sbin` out of a user's
  `PATH`, where `zpool` would read as absent; by standing policy `zpool` never
  warns, so that loss would be silent.
- **Recorded because it is a real difference, not because it is a bug.** Filed
  so the next session does not rediscover it and mistake it for one.
- **What not to copy:** they assign through `eval "$var=\"$path\""`. Use a
  nameref or a plain conditional.

### PA-005 — Unraid `disks.ini` slot vocabulary this repo has never seen

- **Source:** `daemon/services/collectors/array_test.go` in
  [ruaan-deysel/unraid-management-agent](https://github.com/ruaan-deysel/unraid-management-agent),
  whose table-driven test enumerates parity-slot states. The authoritative
  source for the file format itself is
  [unraid/webgui](https://github.com/unraid/webgui) — read that before changing
  the parser, not this summary.
- **The vocabulary:** `DISK_OK`, `DISK_NP` (not present), `DISK_DSBL`
  (disabled), `DISK_NP_DSBL` (both). The two `NP` states carry `device=""`.
  [`tests/fixtures/unraid/emhttp/disks.ini`](../tests/fixtures/unraid/emhttp/disks.ini)
  is `DISK_OK` in every slot, so no degraded array state has ever run through
  the parser.
- **Measured here, 2026-09-08:** the awk table builder returns early on
  `dev == "" && id == ""`, so a slot with both fields empty is dropped from the
  Array slots table entirely — no row, no warning, exit `0`. A host with a
  kicked-out parity disk would read as a host that has no parity slot, which is
  the exact failure the exit-code contract exists to prevent.
- **Why this is a field test and not yet a bug:** whether the case is reachable
  depends on whether `emhttp` retains `id=` for a disk it has disabled. If it
  does, `id != ""`, the guard passes, and the row renders correctly with a `—`
  device. That question cannot be answered on this host class — **FT-009**.
- **One non-finding, recorded so it is not "fixed":** their fixtures use
  unquoted `[parity]` section headers where ours uses `["parity"]`. The parser's
  `gsub(/[\["\]]/,"",sec)` strips both. Do not change either file to match the
  other.

### PA-006 — exit code as a health signal (the counterexample)

- **Source:** the "Exit Codes" section of `yahi.sh`'s `README.md` — `0` for
  success, `2` for "critical hardware issues detected (e.g. disk failures, high
  temperatures, RAID degradation)".
- **Why it is filed:** it is a worked example of the design our exit-code
  contract refuses. Theirs collapses *collection failed* and *hardware is
  unhealthy* into one channel, so a caller cannot tell "smartctl could not run"
  from "the disk is dying". Nothing to implement. Filed so the next "why not
  exit 2 when a disk is failing?" has a named counterexample attached rather
  than being re-argued from first principles.

### PA-007 — the read-only claim that a flag contradicts

- **Source:** two projects, same drift. `yahi.sh`'s README states the script
  "only reads information and does not modify system configuration"; its `-t`
  flag writes a 256MB test file per disk and runs a 1GB RAM write test.
  hw-probe splits it more honestly — `-all` reads, `-check` runs `glxgears`,
  `hdparm`, `dd` and `memtester` behind a separate flag — and its README says so.
- **Why it is filed:** it is the evidence for the "not read-only by default"
  clause in [`CLAUDE.md`](../CLAUDE.md). Both projects that added benchmarking
  ended up with a gap between what the documentation promises and what a flag
  does; the more careful of the two closed it by separating the verbs, not by
  removing them. Nothing to implement — this is the citation for a rule that
  already exists.

### PA-008 — salted-hash identity decoration

- **Source:** the "Privacy" section of hw-probe's `README.md`: a 32-byte prefix
  of a salted SHA512 over MAC addresses and serial numbers, with UUIDs hashed
  the same way but reformatted to stay UUID-shaped so logs remain readable.
  Their own hedge, verbatim: "Be aware that this may fail in certain edge cases."
- **Why it bears on this repo, and where it does not:** **not** for the report.
  Serials, MACs and IPs are what this script exists to emit, and the report
  lands on the operator's own disk. The technique is only interesting if
  something ever needs to correlate runs across the estate inside an artifact
  that gets *committed* — a fleet-level diff, or a fixture derived from a real
  host. A stable hash gives "same disk as last month" without publishing which
  disk.
- **What stays as it is:** fixtures use the RFC 5737 and RFC 7042 documentation
  ranges. That is stricter than hashing, because a reader can tell a
  documentation address from a live one at a glance and cannot tell a hash from
  anything. Do not replace it.

### PA-009 — collectors as separate modules (HWall), and why it is not a lead

- **Source:** [pulpul-s/HWall](https://github.com/pulpul-s/HWall) splits
  collection into `crates/hwall-core/src/collect/*.rs` — one file per subsystem.
- **Filed as a non-lead.** It is a Rust binary and a live sensor monitor, so the
  structure is a consequence of the language and the use case rather than an
  argument about this one. It appears here only so a future survey does not
  chase it twice. The related-but-real question is C-031 (PA-002).

---

## Explicitly not learned from

The rejected-proposals list in
[`.claude/rules/collectors.md`](../.claude/rules/collectors.md) already settles
one whole category this survey would otherwise reopen: **a tool that reads the
same file is not a second opinion.** `inxi`, `hwinfo` and `neofetch` all read
`/etc/os-release`, `/proc/meminfo` and the same SMBIOS tables `dmidecode`
decodes. None of them is a cross-check, and the search did not turn up one that
would be. That verdict stands without re-measuring.
