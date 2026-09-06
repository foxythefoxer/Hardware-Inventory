# Maintainer dispositions

Every proposal about `hw-inventory.sh` that has been adjudicated, with the reasoning that
produced the verdict. Two streams share this ledger, told apart by ID prefix:

- **`C-` Claude Opus 5, `G-` Grok 4.5, `O-` GPT-5.5** — findings from the three code
  reviews in [`reviews/`](reviews/). A closed set: one prompt, three models, 2026-08-06.
  Numbering does not correspond across those documents, which is why the prefixes exist.
- **`FR-`** — requests submitted from outside the review cycle, filed as GitHub issues by a
  session working in a private notes vault. Open-ended; new ones land here.

`CLAUDE.md` is loaded into every session, so it carries only the one-line verdict per ID
and points here. This file is opened when the reasoning is actually wanted. **Write the
full adjudication here, then the index line there — never the paragraph in both places.**
That duplication is what this split exists to stop.

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

| ID | Finding | Status |
|---|---|---|
| C-025 / C-026 | Errors suppressed at 82 sites, always exits `0`, no debug switch. A systemically broken host and a bare host produce identical output. | **Done — `4c1602d`.** Promoted to top priority; both reviewers who raised it rated it MEDIUM. This output is consumed as machine-readable ground truth, so a silently empty section does not produce no answer — it produces a confident wrong one. Implemented narrowly: a warning means the tool was present, permitted, and still returned nothing. Absent tools stay silent. Exits 1 with a `## Collection warnings` block; the report is still written in full first. Changed the caller contract — T3 previously asserted exit 0 with every tool broken and now asserts 1, still distinguishing 124 (hung). |
| C-003 | 26 call sites hardcode `timeout N`, bypassing the `$TMO` fallback built for systems without coreutils `timeout`. | **Done — `fa84efe`.** Verified: 26 hardcoded vs 23 `$TMO`. Maintainer's own bug. Severity reduced HIGH→MEDIUM — `timeout` is present on all supported platforms — but the inconsistency defeated a deliberate guard. `TMO` became an array and a `tmo N cmd...` function covers the sites needing a non-default duration; both run the command unwrapped when `timeout` is absent. |
| C-012 | "Physical devices" table lacks the `TYPE=="disk"` filter applied elsewhere, so `md*`/`dm-*` appear. | **Done — `d12fafa`, then `de745a8`.** Extended, and the extension was the load-bearing half: the reviewer missed that ZFS zvols report `TYPE=disk`, so the `TYPE` filter alone (`d12fafa`) did not exclude them and every VM disk on a `local-zfs` host would still have become a phantom `/dev/zdN` row drawing its own wasted `smartctl` probe. `de745a8` added a `zd[0-9]` name exclusion to both the `DISKS` variable and the device table. Still not verified against real zvols. |
| C-014 | 22 fixed `head -N` truncations (actually 23 — see below), 13 magic numbers, no marker when a limit is hit. | **Done — `03f4cf7`.** This bug class had recurred three times. 17 named constants, grouped by what they cap (not one per call site — several sites share a purpose, e.g. df+findmnt), consumed through a `cap()` helper that appends a marker only when a limit is actually hit and adds nothing on untruncated or empty input. `cap()` never calls `warn()`: truncation is real data arriving incomplete, not a collector failure. One site (`CNAMES`, word-split into `docker inspect` arguments) cannot use `cap()`'s inline marker without corrupting the argument list, and defers its marker to after the block instead. Covered by T10/T11, both verified against reintroduced versions of the bugs they guard against. |
| C-020 | `racadm` block not root-gated and has no `###` heading; output lands under the previous section. | **Done — `af2a682`.** Verified. Maintainer's bug. Gated on `is_root` and given its own `###` heading. |
| C-023 | N+1: up to 100 serial `docker inspect` calls. | **Done — `13f37b6`.** One call over all containers, using `{{.Name}}` to map results back since docker applies the template once per object in argument order. No test coverage for this path; verified by hand against a stub docker. |
| C-009 | `/proc/cmdline` emitted verbatim; may carry `rd.luks.key` or iSCSI credentials. | **Done — `5a343b7`, completed in `6378cb6`.** Genuine gap in an otherwise deliberate redaction policy. `5a343b7` redacted by parameter **name** (`password`, `secret`, `token`, `key`; `rd.luks.key` falls out of the generic `key` match) — which covered only half of what this very finding names. The iSCSI credentials it also lists live *inside* a value, under the innocuous name `netroot`, so no name match could ever see them; `6378cb6` added a value pass replacing everything between `iscsi:` and `@`, CHAP usernames included, keeping host, port, LUN and target. Covered by T9, verified to fail without the fix. Names are kept throughout. Still a filter, not a proof. |
| C-004 | Markdown table cells unescaped; a literal `\|` corrupts the table. | **Accepted, downgraded to LOW.** Most pipe-bearing output already sits inside code fences. Narrow exposure, cheap fix. |
| C-011 | A DIMM with no Part Number line is dropped from the table but still counted in the slot total. | **Done — `187e16e`.** Rows are emitted at the record boundary rather than on the `Part Number:` line, so every populated slot appears. Verified against a synthetic `dmidecode -t memory` fixture. |
| C-001 | No `LC_ALL=C`. | **Done — `8f1d960`.** Verified harmless to the em-dash sentinel and awk `%.2f`. |
| C-005 | Sourcing `/etc/os-release` executes it as root. | **Accepted.** Was already known; good that it resurfaced independently. |
| C-016 | MegaRAID probe targets the first non-NVMe disk, which on Unraid is often the USB boot device. | **Accepted, LOW.** |
| G-002 | Pipeline bodies run in subshells; variable mutations would be lost. | **Done — `4c1602d`, documented in `75d4261`.** No longer theoretical: the warning accumulator is global state, so a `warn` inside a pipeline body would be silently lost. The storage and network row loops now capture their pipeline and test it outside; the rule is recorded in CLAUDE.md and at the `warn()` definition. |
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

## Verified reviewer claims

Checked against ShellCheck 0.10.0 and the file itself:

- **"Zero errors and zero warnings on the default ruleset"** (Claude) — **correct** when
  checked. 24 findings, all severity `note`. The 22 `SC2016` hits are false positives
  from single-quoted awk programs where `$2`/`$10` are awk fields, not shell variables.
  **Not re-verified since the C-025/C-026 work** — ShellCheck was not installed in that
  environment, and `tests/run.sh` skips T7 when it is missing. Re-run before trusting it.
- **"107 masked return values" under `-o all`** (Claude) — **exactly correct.**
- **26 hardcoded `timeout` sites** — **correct.** All routed through the gate in
  `fa84efe`; the count is now 0.
- **`racadm` not root-gated** — **correct.** Fixed in `af2a682`.
- **ZFS zvol behaviour** — **still unverified.** No zvols available in the test
  environment. The fix shipped in `de745a8` on reasoning alone (zvols report
  `TYPE=disk`, so the name exclusion is what does the work). Confirm on a Proxmox host
  with `local-zfs` before and after.
- **"22 `head -N` truncation points"** (all three reviews) — **off by one.** The actual
  count is **23**, and has been since the first commit. Fixed in `03f4cf7`.
- **C-009's own wording was the better spec.** It named "`rd.luks.key` **or iSCSI
  credentials**", and the first fix (`5a343b7`) only handled the first. Re-reading the
  finding text after implementing would have caught it two commits earlier — worth doing
  for anything still open here.
