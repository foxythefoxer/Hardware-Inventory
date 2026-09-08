# Maintainer dispositions

Every proposal about `hw-inventory.sh` that has been adjudicated, with the reasoning that
produced the verdict. Two streams share this ledger, told apart by ID prefix:

- **`C-` Claude Opus 5, `G-` Grok 4.5, `O-` GPT-5.5** — findings from the three code
  reviews in [`reviews/`](reviews/). A closed set: one prompt, three models, 2026-08-06.
  Numbering does not correspond across those documents, which is why the prefixes exist.
- **`FR-`** — requests submitted from outside the review cycle, filed as GitHub issues by a
  session working in a private notes vault. Open-ended; new ones land here.
- **`CI-`** — findings from the suite running on a GitHub runner. A separate channel
  because it is a separate host class: nobody read the code to find these, the code ran
  somewhere that is not this machine and disagreed.
- **`A-`** — findings from a whole-repo audit run against the working tree, as opposed to a
  review of a snapshot or a request for a feature. Open-ended, and deliberately keyed to
  the *channel* rather than to whichever model ran it: an audit is repeatable, so the next
  run must land in the same namespace as the last one or its rejections stop being
  findable. This is why they are not `C-`/`G-`/`O-`, which name a reviewer identity in a
  closed set of three.

The instruction files carry only the one-line verdict per ID and point here; this file is
opened when the reasoning is actually wanted. **Write the full adjudication here, then the
index line there — never the paragraph in both places.** That duplication is what this
split exists to stop. The index line goes to [`QUEUE.md`](QUEUE.md) if accepted and
outstanding, or to `.claude/rules/collectors.md` if rejected; `/adjudicate` is the
procedure. Entries below that cite `CLAUDE.md` predate that split and are left as written,
the same way `reviews/` keeps its stale line numbers — they are a record of what was
argued, not a pointer to follow.

Claims marked **verified** were checked against the actual file rather than taken on
trust.

---

## Rejected — do not re-open without new evidence

### `set -o pipefail` — G-003, O top-action-3

**Rejected. This would break the script.** 23 pipelines end in `head -N`; 22 of them
terminate there (one, the dmidecode wrapper, pipes `head`'s output on into `sed`, but
still surfaces the same exit code under `pipefail` — the rightmost non-zero status in
the pipeline, not merely the last command's, is what `pipefail` reports). `head` exits
after N lines, upstream receives SIGPIPE, and under `pipefail` that surfaces as exit
141. Measured:

```
with pipefail:    exit=141
without pipefail: exit=0
```

Two of three reviewers recommended this. It is also directly incompatible with the
planned exit-code contract (C-026, accepted below) — you cannot have both a meaningful
exit code and a `pipefail` that reports failure on every successful pipeline.

Claude's review was the only one to reach the opposite conclusion, and it correctly
identified the SIGPIPE mechanism.

### `set -e` / `set -eE` — O top-action-3

**Rejected.** This is a best-effort collector. Most commands are *expected* to fail:
`dmidecode` without root, `zpool` on a non-ZFS box, `pct` off a Proxmox host. `set -e`
aborts on the first absent tool. `set -u` alone is deliberate.

### Remove brace expansion `{0..31}` — G-001

**Rejected.** Line 1 declares `#!/usr/bin/env bash`; numeric brace ranges have worked
since bash 3.0 (2004). Grok's own refactor hedges "if bash is guaranteed" — it is, by the
shebang. POSIX `sh` support is not a goal. Swapping to `seq` would add a coreutils
dependency to remove a bash dependency from a bash script.

### Whitespace-delimited iteration, rated MEDIUM — O-001

**Rejected at that severity.** Device names from `lsblk` and VMIDs from `pct list` are
whitespace-free by construction. GPT's own text concedes this is "acceptable in
practice" and then rates it MEDIUM anyway. Harmless to change; not a correctness fix.

### Em-dash sentinel `NA="—"` — G-007

**Rejected.** Verified to render correctly, including under `LC_ALL=C`.

### Locale finding rated HIGH — C-001 severity only

**Fix accepted, severity rejected.** The mechanism is real — `lscpu` and `free` are
gettext-translated. But every supported platform defaults to `en_US`/`C`, so realistic
probability is near zero. The reviewer had no deployment context. One-line fix, so it's
in the accepted queue at Tier 2, not as a HIGH.

---

## Accepted

Rows marked **Done — `hash`** are implemented and covered by `tests/run.sh`; the hash is
the commit that did it. The rest are accepted but not yet written.

**These hashes rot silently.** Every one of them dangled at some point — written before a
history rewrite and pointing at commits that no longer existed, which nothing detects,
because a wrong hash reads exactly like a right one. They were repaired by matching each
`C-` ID against the commit subjects that carry it. If you rewrite history, re-run the
check: extract every `` `xxxxxxx` `` from this file and `git cat-file -e` each one.

| ID | Finding | Status |
|---|---|---|
| C-025 / C-026 | Errors suppressed at 82 sites, always exits `0`, no debug switch. A systemically broken host and a bare host produce identical output. | **Done — `b3872ff`.** Promoted to top priority; both reviewers who raised it rated it MEDIUM. This output is consumed as machine-readable ground truth, so a silently empty section does not produce no answer — it produces a confident wrong one. Implemented narrowly: a warning means the tool was present, permitted, and still returned nothing. Absent tools stay silent. Exits 1 with a `## Collection warnings` block; the report is still written in full first. Changed the caller contract — T3 previously asserted exit 0 with every tool broken and now asserts 1, still distinguishing 124 (hung). |
| C-003 | 26 call sites hardcode `timeout N`, bypassing the `$TMO` fallback built for systems without coreutils `timeout`. | **Done — `53eece7`.** Verified: 26 hardcoded vs 23 `$TMO`. Maintainer's own bug. Severity reduced HIGH→MEDIUM — `timeout` is present on all supported platforms — but the inconsistency defeated a deliberate guard. `TMO` became an array and a `tmo N cmd...` function covers the sites needing a non-default duration; both run the command unwrapped when `timeout` is absent. |
| C-012 | "Physical devices" table lacks the `TYPE=="disk"` filter applied elsewhere, so `md*`/`dm-*` appear. | **Done — `615d554`, then `2c5f8df`.** Extended, and the extension was the load-bearing half: the reviewer missed that ZFS zvols report `TYPE=disk`, so the `TYPE` filter alone (`615d554`) did not exclude them and every VM disk on a `local-zfs` host would still have become a phantom `/dev/zdN` row drawing its own wasted `smartctl` probe. `2c5f8df` added a `zd[0-9]` name exclusion to both the `DISKS` variable and the device table. Still not verified against real zvols. |
| C-014 | 22 fixed `head -N` truncations (actually 23 — see below), 13 magic numbers, no marker when a limit is hit. | **Done — `4b92867`.** This bug class had recurred three times. 17 named constants, grouped by what they cap (not one per call site — several sites share a purpose, e.g. df+findmnt), consumed through a `cap()` helper that appends a marker only when a limit is actually hit and adds nothing on untruncated or empty input. `cap()` never calls `warn()`: truncation is real data arriving incomplete, not a collector failure. One site (`CNAMES`, word-split into `docker inspect` arguments) cannot use `cap()`'s inline marker without corrupting the argument list, and defers its marker to after the block instead. Covered by T10/T11, both verified against reintroduced versions of the bugs they guard against. |
| C-020 | `racadm` block not root-gated and has no `###` heading; output lands under the previous section. | **Done — `8a18d7d`.** Verified. Maintainer's bug. Gated on `is_root` and given its own `###` heading. |
| C-023 | N+1: up to 100 serial `docker inspect` calls. | **Done — `d503c78`.** One call over all containers, using `{{.Name}}` to map results back since docker applies the template once per object in argument order. No test coverage for this path; verified by hand against a stub docker. |
| C-009 | `/proc/cmdline` emitted verbatim; may carry `rd.luks.key` or iSCSI credentials. | **Done — `61ba374`, completed in `77d3b69`.** Genuine gap in an otherwise deliberate redaction policy. `61ba374` redacted by parameter **name** (`password`, `secret`, `token`, `key`; `rd.luks.key` falls out of the generic `key` match) — which covered only half of what this very finding names. The iSCSI credentials it also lists live *inside* a value, under the innocuous name `netroot`, so no name match could ever see them; `77d3b69` added a value pass replacing everything between `iscsi:` and `@`, CHAP usernames included, keeping host, port, LUN and target. Covered by T9, verified to fail without the fix. Names are kept throughout. Still a filter, not a proof. |
| C-004 | Markdown table cells unescaped; a literal `\|` corrupts the table. | **Done — `0abf454`.** Downgraded to LOW when accepted: most pipe-bearing output already sits inside code fences, and the cells that can carry one are the free text — an lsblk MODEL, a VM disk list, an Unraid status string. Fixed once rather than at each site: a `row()` helper takes one argument per cell and escapes each, and `kv()` is a two-cell call to it. The Unraid slot table is built in awk and escapes where values are read (`esc()`); its inner `row()` became `emit()` so the two are not confused. One deliberate exception, commented at the site: the container-networks table parses on `\|` itself, so a cell holding one drops the row rather than mangling it. Covered by T4 and T6, both asserting the escape *and* the resulting cell count, and verified to fail with the escaping removed. |
| C-011 | A DIMM with no Part Number line is dropped from the table but still counted in the slot total. | **Done — `39269ce`.** Rows are emitted at the record boundary rather than on the `Part Number:` line, so every populated slot appears. Verified against a synthetic `dmidecode -t memory` fixture. |
| C-001 | No `LC_ALL=C`. | **Done — `4774e17`.** Verified harmless to the em-dash sentinel and awk `%.2f`. |
| C-005 | Sourcing `/etc/os-release` executes it as root. | **Done — `37d38aa`.** Was already known; good that it resurfaced independently. The file is a shell fragment by specification, so `.` on it ran whatever it contained, as root, on every run, from a path this script otherwise only reads — the same class of hole that sank FR-003's `fastfetch`, in the script's own source rather than a dependency's config. Parsed as `KEY=value` with quotes stripped; `^KEY=` cannot match `ID_LIKE` or `VERSION_ID`, which is the one way a prefix parse goes wrong that sourcing never could, so T18 asserts that too. T18's fixture puts a command substitution in `PRETTY_NAME`: sourced it collapses, parsed it stays literal. Verified against the pre-fix script, which collapses it. |
| C-016 | MegaRAID probe targets the first non-NVMe disk, which on Unraid is often the USB boot device. | **Done — `0da5ab9`**, with A-007 in the same commit as that deferral required. LOW, but it is a wrong *answer*, not a missing one: `-d megaraid,N` against a USB stick answers for no ID, so the section says "no drives answered — the controller may be in HBA/IT mode" on a host whose array is right there. The target is now chosen by `TRAN`, excluding `usb` and `nvme`, and `nvme` by name as well because older util-linux leaves `TRAN` empty for it; an otherwise empty `TRAN` stays eligible, since controller-backed disks routinely report none. T6's fixture is that layout — NVMe, boot key, controller disk — and the smartctl stub reports which node it was asked about, so the report shows the target. Reverting only the selection puts `PROBED-VIA-sda` in the table; verified with `is_root` simulated, no session here having sudo. |
| G-002 | Pipeline bodies run in subshells; variable mutations would be lost. | **Done — `b3872ff`, documented in `52dff02`.** No longer theoretical: the warning accumulator is global state, so a `warn` inside a pipeline body would be silently lost. The storage and network row loops now capture their pipeline and test it outside; the rule is recorded in CLAUDE.md and at the `warn()` definition. |
| G, edge cases | Megaraid probe can skip drives at sparse IDs beyond the 10-miss threshold. | **Accepted as a documented tradeoff, not a bug.** Deliberate bound against a 32-iteration worst case. |

---

## Deferred

| ID | Finding | Reason |
|---|---|---|
| C-031 | One ~630-line top-level `main`; extract `section_*()` functions. | Real, but it restructures a working one-shot reporter. Not worth the churn until `--skip` is actually wanted. |
| C-029 | No argument parsing; `--help` prints a full report. | Pairs naturally with C-031. Same reasoning. |
| C-024 | `mapfile -t` instead of word-splitting `for` lists. | Cosmetic given the inputs. Bundle with C-031 if that happens. |

---

## Feature requests — `FR-`

Submitted from outside the review cycle. Same three verdicts as above: accepted, accepted
with changes, or rejected. "Accepted with changes" means the conditions listed **are** the
acceptance, not commentary on it — an implementation that drops one has not implemented
the request. A rejected request is recorded here at the same length as an accepted one,
because a rejection nobody can audit gets re-proposed.

### FR-001 — monitor detection via DRM EDID — accepted with changes

Displays are the one category of attached hardware the script cannot see. Read
`/sys/class/drm/card*-*/edid` — plain sysfs reads, so it works headless and over SSH,
where `xrandr` needs a session. `ddcutil` stays banned and the reason belongs in a
comment at the site, not just here: DDC/CI is bidirectional and needs `i2c-dev`, so it
writes to the monitor. Four conditions came out of checking this against a real host:

- **It must never `warn`.** A host with no connected display is not a broken host, and
  an LXC has no `/sys/class/drm` at all. Same call as `zpool`/`btrfs`, for the same
  reason — a warning here would fire on every headless server in the estate and train
  readers to skip the section.
- **Gate on bytes actually read, not on file size.** Every `edid` attribute reports
  `stat -c%s` = 0, including the three connectors on this host that return a full 256
  bytes. A `[ -s ]` test would skip every monitor that is present. This is the
  `dmidecode` banner trap again (see the exit-code contract in `CLAUDE.md`): test the
  thing that indicates the fact, not emptiness.
- **Exclude `*-Writeback-*` connectors.** They are virtual encoders, not physical
  outputs — the same class of false row as the zvols that a `TYPE=="disk"` filter alone
  did not catch (C-012).
- `edid-decode` is a parser and is fine under `have` + `$TMO` + `2>/dev/null`. Where it
  is absent, `strings` over the same bytes still recovers the product name and serial,
  which is enough for inventory. Both were **verified** against a `VX2768-2KP` on DP-1.
  The panel serial is emitted on purpose: identifying, not authenticating.

### FR-002 — UPS data-connection detection — accepted with changes

Whether a host can actually talk to its UPS is currently knowable only by asking. Three
mechanisms exist across the estate (apcupsd, UPower, nothing at all), so detection has to
be layered rather than assume a tool:

- **The primary signal is a direct sysfs read of `/sys/bus/usb/devices/*/idVendor`, not
  `lsusb`.** Same move as parsing emhttp's `.ini` instead of calling `mdcmd`: the data
  is already in a file, so read the file. `lsusb -v` in particular is out — it issues
  USB control transfers to the device instead of reading descriptors the kernel has
  already cached.
- **That path is load-bearing, not a fallback.** **Verified** here: a CyberPower
  `CP1500PFCLCDa` (`0764`) is attached and visible in sysfs with neither apcupsd nor
  NUT installed. Both daemon-based checks report nothing on this host.
- **`/sys/class/power_supply` cannot be the gate.** It is empty on that same host
  despite the UPS being attached and claimed by `usbhid`. Useful as corroboration where
  it is populated; useless as the test.
- The vendor-ID list (APC `051d`, CyberPower `0764`) is a heuristic that will go stale.
  Say so in a comment where it is defined, so whoever adds a third brand knows it is a
  whitelist and not a protocol.
- `apcaccess status` is a query to apcupsd's NIS port and is allowed, but detection must
  not depend on the daemon answering; `/etc/apcupsd/apcupsd.conf` records the configured
  intent independent of daemon state. `upower -e` / `-i` are reads and are allowed as a
  third signal, though they yield little on a headless host with no session.
- **It must never `warn`, and it stays silent when nothing is found.** Most hosts have
  no UPS. Emitting "no UPS detected" would break the standing rule that a section prints
  only if non-empty; absence of the section is the negative answer, exactly as it is for
  every other category of hardware.
- Load percentage and battery age are explicitly out of scope for the accepted item.
  Presence of a data connection is the whole deliverable.

### FR-003 — `fastfetch` cross-check — rejected

Filed as GitHub issue #1: call `fastfetch` first where present, record its output beside
the script's own values, and define a reconciliation policy for disagreements, with
fastfetch proposed as the tie-breaker. The request explicitly left the tie-breaker
direction open. All three of its load-bearing claims fail when measured; the concern
underneath it is real and is carried forward as FR-004.

**1. It breaks the read-only rule, and does it invisibly.** `fastfetch` auto-loads
`config.jsonc` from the five search paths it prints under `--list-config-paths`
(`~/.config/fastfetch/`, `~/.config/kdedefaults/fastfetch/`, `/etc/xdg/fastfetch/`,
`/etc/fastfetch/`, `~/fastfetch/`), and its `command` module executes an arbitrary shell
string. **Verified** against fastfetch 2.68.1 with a config holding one `command` module,
invoking it with no flags at all:

```
fastfetch --pipe          -> "Proof: autoloaded", and the file it was told to
                             create existed afterwards
fastfetch --pipe -c none  -> no such file; the config was not read
```

Under the documented `sudo bash hw-inventory.sh` that executes as root, out of
`/root/.config/fastfetch/` or `/etc/fastfetch/`. This is a class the banned-verb list did
not cover, because the verb is a query and the *host's config file* supplies the write —
the rule in `CLAUDE.md` was extended to name it. `-c none` does close this particular
hole, but the read-only property would then rest on auditing a third-party tool's module
set at every release rather than on reading this script, and that is the trade the
read-only-by-construction design exists to refuse. It is also the property that lets the
script run unattended.

**2. fastfetch is not an independent source.** It reads the same kernel interfaces the
script does, so it is a second *parser*, not a second *source*. **Verified** on one
whitebox AM5 desktop, all four rows read in the same run:

| Fact | Script reads | fastfetch reports | Relationship |
|---|---|---|---|
| Memory | `free` → `/proc/meminfo` `MemTotal: 31977708 kB` | `32745172992` bytes = **31977708 kB** | byte-identical, same file |
| OS | sources `/etc/os-release` | `prettyName: CachyOS`, `id: cachyos` | same file |
| Kernel | `uname -r` → `7.2.2-1-cachyos` | `7.2.2-1-cachyos` | same call |
| Model | `dmidecode` decode of SMBIOS | `/sys/.../dmi/id/product_name` = `MS-7D67` | same SMBIOS table, two decoders |

Correlated sources cannot adjudicate each other: a wrong *value* — the error class the
request wants caught — passes through both identically. What a disagreement would
actually surface is a formatting difference (`30Gi` vs `32745172992`), which makes the
requested reconciliation policy a unit-conversion table rather than a verification.
**Generalise this before evaluating the next such request:** a tool that reads the same
file is not a second opinion, whatever its name is.

**3. The proposed tie-breaker direction is backwards.** Where the two genuinely diverge
it is because this script deliberately chose the more authoritative or more specific
source. Naming fastfetch authoritative would let a terminal-banner tool overrule
`dmidecode`'s SMBIOS decode, emhttp's `.ini` array state, and the whitelisted config
parsing. And under the exit-code contract a disagreement is not a collector failure, so
it could not `warn` either — it would be a report annotation with no route to action.

Supporting, not load-bearing: runtime is not the objection (6–7 ms per run, measured over
three runs), but bulk is — the JSON is **11,890 bytes against a whole report of 8,532**,
and the majority of it is desktop-session metadata (DE, WM theme, icons, cursor, terminal
font) with no place in a server inventory. The modules that do not overlap are already
covered better by accepted work: `Display` reads the same DRM EDID as FR-001 and names
the same `VX2768-2KP` panel, and `Battery`/`PowerAdapter` read the
`/sys/class/power_supply` that FR-002 **verified** is empty on the host the UPS is
actually attached to.

### FR-004 — unprivileged system identity from DMI sysfs — accepted with changes

The genuine gap FR-003 surfaced, reachable without the dependency that sank it. An
unprivileged run currently prints `| Manufacturer / model | (needs root — install/run
dmidecode as root) |` and emits `model: null` into the frontmatter, while the values sit
in world-readable files. **Verified** on this host:

```
-r--r--r--  sys_vendor      Micro-Star International Co., Ltd.
-r--r--r--  product_name    MS-7D67
-r--r--r--  board_name      PRO X670-P WIFI (MS-7D67)
-r--r--r--  bios_version    1.A0
-r--------  product_serial  Permission denied
-r--------  board_serial    Permission denied
```

Reading `/sys/devices/virtual/dmi/id/` where `dmidecode` is absent or unprivileged is the
same move already made twice: emhttp's `.ini` instead of `mdcmd`, and FR-002's sysfs
`idVendor` instead of `lsusb -v`. It also matches what this script already does one field
over — `CPUMODEL` falls back from `lscpu` to `/proc/cpuinfo` and warns only if both fail.
DMI identity is the outlier that has no fallback. Conditions:

- **Serials stay root-gated and stay honest.** `product_serial`, `board_serial` and
  `product_uuid` are mode `-r--------`; only the freely-readable fields get filled in.
  The header's "**not run as root**, some fields incomplete" note stays correct, and the
  service-tag row must not silently become `—` as though the host had no serial.
- **Skip the fallback inside containers.** An LXC generally sees the *host's* sysfs, so a
  naive read would make every container on a Proxmox node report the node's motherboard
  as its own — and put it in the machine-readable `model:` field, which is worse than
  the null it replaces. `PLATFORM` is already computed from `systemd-detect-virt` above
  the DMI block; gate on the container case specifically (`systemd-detect-virt -c`), not
  on `PLATFORM != bare-metal`, since a real VM's SMBIOS identity is legitimate inventory.
  **Unverified** — no container available in this environment. Confirm on a Proxmox LXC
  before shipping; this is the same false-row class as C-012's zvols and FR-001's
  writeback connectors, both of which were missed by the reviewer who proposed the
  feature.
- **Filter placeholder strings.** `To Be Filled By O.E.M.`, `Default string`, `System
  Product Name`, `Not Specified`, `None` are common on whitebox boards. `dmidecode -s`
  returns them verbatim too, so the root path has the same exposure today — but the
  fallback would put them into `model:` on far more hosts. An unfilled field should read
  as unknown, not as a model name. **Unverified**: this board fills its DMI properly.
- **It must never `warn`.** Absent `/sys/devices/virtual/dmi/id` is a normal container,
  and the root path's existing warning already covers "`dmidecode` ran as root and
  returned nothing". Same call as `zpool`/`btrfs` and both prior FRs.
- The identity block's `is_root && have dmidecode` gate has to be restructured, since
  there are now three states rather than two: full identity, partial identity from
  sysfs, and nothing. Do not let the partial state print the "(needs root)" row *and*
  the values.

---

## Repository audits — `A-`

Whole-repo audits for over-engineering, run against the working tree rather than a
snapshot. The first was a `ponytail-audit` on 2026-09-06 against `5f7893d` (47 tracked
files, a 982-line script, ~4,100 lines of docs), proposing a net −3,100 lines.

Two things about that audit shape how these are adjudicated. It was **disciplined about
the existing ledger** — it explicitly declined to re-propose C-014's named constants,
G-003/O's `set -e`/`pipefail`, and C-031's section split, naming the evidence each was
settled on. That is the ledger working as designed. And its single most valuable finding
was the one it filed as *out of scope*: a real crash, found by running the script rather
than reading it, which is the same lesson `reviews/README.md` records about the three
static reviews. **An audit's line-count headline is the least reliable part of it.** Here
~3,100 of the proposed 3,300 lines were documentation deletions, of which one was right,
one was wrong, and the largest was neither — it named a real defect and the wrong remedy.

### A-001 — `DNET` unbound under `set -u` on an empty container list — accepted, done

Filed as out of scope, and the only thing in the audit that was actually broken.
**Done — `f8ff695`.** A daemon answering `docker info` with zero containers is past the
section gate and healthy, but leaves `CNAMES` empty; `DNET` was assigned only inside the
`[ -n "$CNAMES" ]` guard and tested outside it, so `set -u` aborted the script at the
test. Reproduced: report truncated mid-section, no footer, no `## Collection warnings`
block, **and still exit 1**.

That exit code is the severity. The C-025/C-026 contract exists so a caller can trust
`$?`, and here a truncated report returned the same `1` as an honest incomplete
collection — the failure mode was wearing the contract's own signal. Fixed by
initialising `DNET` above the guard, matching `DMIMEM`.

T11's docker stub always answers with 105 containers, which is why nothing caught it.
T12 covers the empty case and was verified to fail against a reintroduced version of the
bug (3 of 7 assertions), the control T10/T11 were held to. Generalised into `CLAUDE.md`:
**when a tool's output gates an assignment, test the empty answer, not just the failing
one.**

### A-002 — delete `docs/reviews/` (2,965 lines) — rejected; defect fixed another way

**Resolved by `1fcd35e`, which is not what was asked for.** The audit's diagnosis was
correct: the detailed reviews are unedited AI prose whose line references point into a
651-line script that is now 990 lines, and every actionable finding is already restated
by ID here. Its remedy — delete, cite the commit from the ledger, let git hold the
provenance — does not follow. The `C-`/`G-`/`O-` prefixes are only meaningful because
those documents are what they point back at; a reader who hits `G-003` here and wants to
know what Grok actually argued would have to know to `git log` a deleted path first.

There is a sharper reason than the one available when this was decided. "Cite the commit
from the ledger" assumes the ledger's commit citations resolve, and at the moment the
audit proposed it **every one of the twelve in this file was dangling** — see the note
under Accepted. Provenance that lives only in git needs a working pointer into git, and
the pointers had rotted without anyone noticing. That is an argument for keeping the
documents, not for leaning harder on the history.

Deletion was the right response to *stale line numbers* only if the numbers were the
value. They are not — the argument is. Each document now carries a header naming
`bc32386` (651 lines) and the current size, saying its line numbers are stale by
construction and that this ledger is authoritative. Historical rather than quietly wrong,
at a cost of six headers.

The folder README had rotted twice on its own and both were fixed in the same commit: it
still described the findings as `F-0NN`, a scheme `86e6c05` renamed, and it offered
"cross-reference by line number, not by ID" as navigation — advice that had become
exactly backwards.

### A-003 — documentation de-duplication — accepted, done

**Done — `e6e2c30`, `11d582d`, `f384ca7`, `bffcac0`.** Four separate second copies, all
drifted or drifting, all deleted in favour of a link:

The README's "Fixed since that review" table restated eight entries from this file, and
its "Deliberate non-goals" paragraph re-argued the `set -e`/`pipefail` rejections — the
third statement of a verdict `CLAUDE.md` already bars stating twice. The drift was
measurable: the `head -N` count was argued in three files at once, each carrying its own
correction of the others (this file's "22 (actually 23)", the README's "23 (the review
says 22 — off by one)", `CLAUDE.md`'s 23). `tests/README.md` listed T1–T7 for a suite
that had reached T11. `llm-ingest.md` repeated the README's `sed`/`diff` recipe verbatim,
a copy that fails silently — the stale one still runs, it just stops excluding what it
was written to exclude. Two `.gitkeep` files were holding open directories that have had
tracked content since `e0c4752`.

Kept, against the audit: the README's `zpool`/`btrfs` paragraph. It reads as duplication
but is not an adjudication record — it explains behaviour a user sees in their own
report, which is the README's job. **The test for this class: does the second copy serve
a different reader, or merely a different file?**

### A-004 — replace the `TMO` array with `tmo()` at 21 sites — rejected

`TMO=()` and `tmo N cmd...` are two spellings of one idea, and the audit is right that
they are redundant. They are also **both outputs of C-003**, introduced together in
`53eece7` as that fix: `TMO` for the 10s default, `tmo` for sites needing another
duration, and the point of having both was that neither hardcodes `timeout N`. Collapsing
them re-opens an adjudicated design across 21 call sites of a working one-shot reporter,
which is the churn C-031 was deferred over — with less payoff, since C-031 at least
unlocked `--skip`.

No new evidence, and none of the redundancy is load-bearing: both forms already run the
command unwrapped when `timeout` is absent, which is the entire guarantee.

### A-005 — one `smart_fields()` helper for the two SMART parse blocks — rejected as stated

The claim is that health/poh/ra/tmp "are parsed by near-identical programs" in the
plain-SMART and megaraid loops, written twice. **Checked line by line, and the overlap is
3 of roughly 8 parses.** Identical: `health`, the first `poh` probe, `ra`. Divergent *by
design*: the `poh` fallback reads ATA's `^Power On Hours` in one and SCSI's
`number of hours powered up` in the other; the `tmp` fallback reads `^Temperature:` versus
`^Current Drive Temperature`. The loops also emit different columns — plain has
`pe` and `wear`, megaraid has `mdl` and `ser`.

A shared helper would have to emit the superset and carry both fallback sets, i.e.
re-introduce the divergence inside itself. The duplication is two device classes that
genuinely answer differently, not one program typed twice. **Not re-open without a
measurement showing the fallbacks are interchangeable** — they are not, and that is the
whole finding.

### A-006 — generate the 19 `badbin` stubs from a loop in `run.sh` — rejected as a priority

Correct that the stubs are near-identical and that their messages are asserted on
nowhere. Rejected on where it lands: `badbin` is T3's fixture, the test `CLAUDE.md` marks
as the one that must not be weakened for speed, and every real bug in this project's
history has been the class T3 catches. Trading 19 inert files for generated ones touches
the load-bearing test to change no behaviour. Harmless in isolation; not worth doing on
its own. Bundle it with a change that already has reason to be in `run.sh`.

### A-007 — hoist the `lsblk -P` call and derive `DISKS` from it — accepted, done

Real: two `lsblk` invocations with equivalent exclusion filters, and the `-P` form
already carries everything `DISKS` needs. Deferred because it collides with **C-016**,
which is open and changes exactly this path — the megaraid probe picks its target by
walking `DISKS`, and C-016 is the finding that this picks the USB boot device on Unraid.
Refactoring the producer while its one problematic consumer is queued for change means
doing the same reasoning twice. **Do it as part of C-016 or not at all.**

**Done — `0da5ab9`, as part of C-016**, which is what the deferral asked for and the
reason it was right: the hoist is what *supplies* the fix. The probe needs the `TRAN`
column to tell a controller-attached disk from a USB boot key, and after the hoist that
column is already in hand — done separately, C-016 would have had to add a third `lsblk`
call or re-derive the same filter. The `TYPE`/`zd`/`loop` exclusions now exist once,
which is also where C-012's zvol exclusion had been duplicated.

### A-008 — capture `free -h` and `lscpu` once instead of re-invoking — accepted, done

Four `free -h` and two `lscpu` invocations, each re-parsed from scratch. Straightforward,
and the precedent is in the file: `DMIMEM` is captured once for exactly this reason, with
a comment saying the three parses that follow used to re-run `dmidecode` each. Same shape,
same fix. Not urgent — this is a one-shot reporter and the cost is a few forks, not a
hot loop. Queued in `CLAUDE.md`.

**Done — `3b07754`.** Both captures sit at the gather stage, where the frontmatter
already needed a field from each, and every later site parses that text. The two
warnings keep their meaning — `lscpu` present and empty still warns at the CPU section,
`free` present with no `Mem:` line still warns at the top — and T8's failing-tool half
covers both. The report came out byte-identical to the previous commit's on this host,
which is the whole claim a refactor like this makes.

### A-009 — micro-simplifications, as one batch — accepted, done

Three proposals of one shape, worth doing together or not at all:

- `CNAMES_TRUNCATED` currently uses four variables and a `wc -l` to learn whether `head`
  cut anything. `[ "$CNAMES" = "$CNAMES_ALL" ] || CNAMES_TRUNCATED=1` is equivalent —
  command substitution strips trailing newlines from both sides, so below the limit the
  two are byte-identical and above it one is a strict prefix. Verified by reading, not
  yet by running; T11 and T12 both cover this block.
- `cap()`'s `total` can be tested inline.
- `$(cat /sys/…)` ×6 → `$(<file)`, `$(id -u)` → `$EUID`, `basename "$f" .cfg` →
  `${f##*/}`. Bash-only, which line 1 already declares — the same argument G-001 settled.

Accepted as cleanup, explicitly **not** as correctness. Each site works today.

**Done — `e5a088c`, five of six.** The comparison, `cap()`'s `total`, `$EUID`,
`${f##*/}` and the three *guarded* sysfs reads under the kernel-parameters table all
went in. T4's share row now asserts the share name as well as the policy, because a
parameter expansion that forgets the `%.cfg` strip looks identical to one that doesn't.

**The three `cat /sys/class/net/…` reads in the interface loop stay as they are**, and
this is the part of A-009 that was wrong on paper. Measured both ways: bash reports a
missing file in `$(<file)` on its own stderr, and a `2>/dev/null` *inside* the
substitution does not suppress it (an unreadable-but-present file, such as a `speed`
attribute returning `EINVAL`, is silent — it is the missing file that is loud). Those
paths are built from an interface name discovered at runtime, so one interface class
without a `speed` attribute would fail T2's empty-stderr assertion on someone else's
host, to save three forks in a one-shot reporter. The reason is in a comment at the
site, since the next reader of this list will otherwise "finish" the batch.

---

## Continuous integration — `CI-`

Findings produced by running the suite on a GitHub runner: a host class no machine here
is, and the only channel that reports from one automatically. Kept out of `A-` because
these are not audit findings — nobody read the code to find them, the code ran somewhere
else and disagreed.

### CI-001 — the PCI section warns on filtered-empty output — accepted, done

**Every run of this workflow, from the first, was red for this one reason.** Three
assertions failed on each: T2's `exits 0`, and T12's `exit 0` and `no warning for zero
containers`, which name docker and displays and had nothing to do with either. The
warning text itself was the misdirection — it claimed `lspci -nnk` returned nothing when
the command had returned a full listing.

The condition tested the **filtered** output. `PCIOUT` is `lspci -nnk` passed through an
awk filter selecting `vga|3d controller|display|ethernet|network|raid|sata|non-volatile|
serial attached`, and the warning fired on `[ -z "$PCIOUT" ]`. A GitHub runner is a
virtualised guest whose NIC and disks are paravirtual — VMBus or virtio, not PCI — so the
bus enumerates fine and matches none of those classes. That is a host genuinely lacking
the hardware, which the exit-code contract makes **silent**: "a warning means the tool
was present, permitted, and still returned nothing." It was present, permitted, and
returned plenty.

Measured, 2026-09-08: run `34177270429`, `110 passed, 3 failed`, unprivileged pass. The
warnings block named exactly one collector. Reproduced locally with a stubbed `lspci`
printing three bridge lines and no matching class — T17's first stub — and the three
assertions go red against `6b38e32`'s script and green against the fix, which is the
control this ledger holds every test to.

The same block had a second defect of the same shape: the heading and code fence were
printed **before** the filter ran, so a host with no matching devices got an empty
```` ``` ```` block. That is the convention every other section follows and this one did
not — capture, then print only if non-empty. T2's empty-table-header check does not see
it, because a fence is not a table.

Fixed by separating the raw listing from the filtered one: `PCIRAW` gates the warning,
`PCIOUT` gates the section. T17 asserts both directions — a full listing matching nothing
must be silent and exit 0, and a `-nnk` that alone returns nothing while plain `lspci`
answers must still warn and exit 1. Without the second half, deleting the warning
outright would pass.

**Not a display, UPS or docker defect**, though the failing assertions were all in those
tests. Worth stating because that is what a bare `exit 1` in a CI log implies, and it is
what the log said for four runs. The diagnosis only became possible when `6b38e32` made
those failure branches dump the warnings block — the fix and its diagnostic are one
finding, and the diagnostic is the durable half.

**Also found, and fixed with it:** the root pass had never run. Both suites are steps in
one job, so the unprivileged failure skipped `Suite, root` on every run — T6's megaraid
drive probe and the root-gated branches have not executed in CI once, contrary to what
the workflow's own header comment claims about them. `if: ${{ !cancelled() }}` on that
step; a failure in one pass must not hide the other's result.

### CI-002 — the leak hook's own test never ran in CI — accepted, done

T14 skipped its entire matcher half on every push, printing `SKIP no
private-patterns.local (expected in a fresh clone)`. That skip was correct about
the cause and wrong about the consequence: **the only enforcement the publishing
rule has was unverified on every run**, which is CI-001's shape exactly — a check
that looks present and is not running.

The skip was avoidable. Everything below it tests the hook's **built-in** shapes
— RFC 1918, CGNAT, MAC and OUI forms, the documentation ranges that must pass,
commit-msg mode, and the sweep of every tracked file. None of them reads the
private list's contents; the hook merely refuses to start unless the file
exists. `.claude/private-patterns.example` is committed and holds only comments,
so copying it into place in CI unlocks all of it and publishes nothing.
Measured in a hook copy under a temp tree: a private-range address exits 2, RFC
5737 exits 0, a host named by class exits 0 — identical to the maintainer's
machine, where the list is populated.

What CI still cannot check is the private patterns themselves. That is by
construction — they are not in this repository, which is the point of them — and
it is stated rather than papered over.

**The refusal assertion moved out of the skip branch.** It ran only where the
list was missing, so it never ran on the maintainer's machine, and once CI was
given a list it would have run nowhere at all. It now runs unconditionally
against a copy of the hook in a temp tree with no list beside it, so the absence
is synthetic. Refusing to start is the hook's most important property: the file
it needs is gitignored, so the failure it guards against — present and inert —
is the default state of every fresh clone.

**A zero-pattern list is now a failing assertion**, and this one was written from
an incident rather than from reasoning. During this session an agent's scratch
`git clone` failed with `Invalid cross-device link`; the `&&` chain stopped at
the failure but the following `;`-separated `cp
.claude/private-patterns.example .claude/private-patterns.local` did not, and it
ran in the real working tree. The maintainer's populated list was replaced by the
example: 2,068 bytes, 0 active patterns. Nothing detected it. Not git — the file
is gitignored by design and has never been committed. Not the hook — it starts
happily, and the built-in shapes still fire, so writes kept being scanned and
kept passing. Not the suite — T14 asserted the hook's behaviour, never the list's
contents. The contents were unrecoverable: no snapshot, no editor local history,
no copy anywhere on disk.

The lesson generalises past this repo: **a security control with a data
dependency needs an assertion on the data, not only on the code.** The hook's own
header says a hook that is present and inert is worse than none, and it enforces
that for a *missing* file while an *empty* one produced exactly the state it
warns about. The count assertion fails locally and prints a note under `CI`,
where the example copy is deliberate.

### CI-003 — the root pass failed on two counts CI-002 could not have caught — accepted, done

Found by merging CI-002 to `main` **before its own CI run finished**. The branch was
green at the commit before it; the commit that landed had never been run anywhere but
this host, where neither defect is reachable. Both are root-pass-only, and the root pass
is the half no development machine here executes.

**`sudo` scrubs `$CI`, so the note became a failure.** CI-002 made a zero-pattern list a
failing assertion, downgraded to a `NOTE` when `$CI` is set — the workflow copies the
empty example into place two steps earlier, so that state is deliberate there. The root
step ran `sudo bash tests/run.sh`, and sudo drops the environment by default: the root
pass saw no `$CI`, concluded it was on the maintainer's machine, and failed on a
condition the workflow had just created on purpose. Fixed with `--preserve-env=CI`, not
`-E` — several tests work by putting stubs on `PATH`, and `-E` would carry that in too.

**T6's drive probe depended on the runner's real disk topology.** This one predates
CI-002 and was latent from the moment the root job was added. The megaraid probe picks
`MRTGT` by taking the first non-`nvme*` name in `$DISKS`, and `$DISKS` came from the
runner's *real* `lsblk` — the controller was mocked, the disk it hangs off was not. On a
runner exposing `sda` all four sparse-ID assertions pass; on an NVMe-only one `MRTGT` is
empty, the probe never runs, and the four failures read as a megaraid parsing bug. Same
image version both times, different hardware underneath — GitHub's fleet is mixed, so the
test was a coin flip on the SKU. Fixed with an `lsblk` stub in `percbin` answering both
call sites (the plain form feeds `$DISKS`, the `-P` form feeds the device table; leaving
`-P` unhandled trips the "none survived the physical-disk filter" warning on a run where
nothing is wrong).

Two lessons, and the second is the larger one:

- **A partly-mocked fixture is an untrustworthy test.** Mocking the thing under test and
  leaving its *precondition* to the host makes a green run mean "this machine had a SATA
  disk", not "the parser works". Mock the whole path or assert nothing.
- **A green tick belongs to a commit, not to a branch.** CI-002 was merged on the
  strength of the run before it. That is the same error shape as CI-001 and CI-002
  themselves — a check that looks present and is not running — committed this time by the
  person reading the check rather than by the check. **Wait for the run on the exact
  commit being merged.**

---

## Verified reviewer claims

Checked against ShellCheck 0.10.0 and the file itself:

- **"Zero errors and zero warnings on the default ruleset"** (Claude) — **correct** when
  checked. 24 findings, all severity `note`. The 22 `SC2016` hits are false positives
  from single-quoted awk programs where `$2`/`$10` are awk fields, not shell variables.
  **Not re-verified since the C-025/C-026 work** — ShellCheck was not installed in that
  environment, and `tests/run.sh` skips T7 when it is missing. Re-run before trusting it.
- **"107 masked return values" under `-o all`** (Claude) — **exactly correct.**
- **26 hardcoded `timeout` sites** — **correct.** All routed through the gate in
  `53eece7`; the count is now 0.
- **`racadm` not root-gated** — **correct.** Fixed in `8a18d7d`.
- **ZFS zvol behaviour** — **still unverified.** No zvols available in the test
  environment. The fix shipped in `2c5f8df` on reasoning alone (zvols report
  `TYPE=disk`, so the name exclusion is what does the work). Confirm on a Proxmox host
  with `local-zfs` before and after.
- **"22 `head -N` truncation points"** (all three reviews) — **off by one.** The actual
  count is **23**, and has been since the first commit. Fixed in `4b92867`.
- **C-009's own wording was the better spec.** It named "`rd.luks.key` **or iSCSI
  credentials**", and the first fix (`61ba374`) only handled the first. Re-reading the
  finding text after implementing would have caught it two commits earlier — worth doing
  for anything still open here.
