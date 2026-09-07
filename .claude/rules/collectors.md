---
paths:
  - "hw-inventory.sh"
  - "tests/**"
  - "docs/DISPOSITIONS.md"
---

# Working on the collectors

<!--
WHY THIS FILE IS PATH-SCOPED, and the gap that leaves.

`paths:` frontmatter means this file does not load at launch. It loads when one
of the three globs above is read. Verified on this machine, 2026-09-07, Claude
Code 2.1.263: a rules file with `paths:` was absent from a fresh session's
context and present immediately after a matching file was read, while an
unscoped rules file in the same directory loaded at launch as usual.

Of the last 34 commits here, 18 touched no code — documentation and adjudication
work that paid for all of this on every session and used none of it.

THE OBJECTION, and the answer, because it matters: "Rejected proposals only work
if they load BEFORE a session proposes something." They do. Any proposal about
this repo requires reading hw-inventory.sh, tests/, or the ledger first, and
this file loads on that read — strictly earlier than the moment of proposing.

THE GAP IS REAL, and stated rather than hidden: a session that reads only
README.md and proposes from that will not have seen the rejections below. The
mitigations are that README.md points at the ledger and says several plausible
changes have been evaluated and declined, and that `set -o pipefail` and `set -e`
are caught by T1 regardless of what anyone believes. A proposal that survives to
an edit meets this file on the way.
-->

## The exit-code contract

The script exits `0` when collection is complete and `1` when it is not, having
written the report in full either way and ended it with a `## Collection
warnings` block naming what failed. Callers may rely on this.

**The judgment call, which is the whole feature:** a warning means the tool was
**present, permitted, and still returned nothing.** Silence is for things a host
genuinely lacks.

- Tool not installed → silent. A minimal host is not a broken one.
- Tool needs root and the run is unprivileged → silent. The header already says so.
- Tool present, permitted, no output → `warn`.

Judgments already made, so they don't get relitigated:

- **`zpool` and `btrfs` never warn.** `zfsutils` and `btrfs-progs` are routinely
  installed as dependencies on hosts that use neither filesystem, where an empty
  listing is the correct answer. A warning there would fire on ordinary ext4
  machines and train readers to skip the section. `df`, `findmnt`, `lsblk`,
  `lscpu` and `ip` *do* warn — they describe facts every working host has. Both
  sites carry a comment saying so.
- **`pvecm` never warns.** `pvecm status` fails on a standalone node that was
  never joined to a cluster, which is a normal Proxmox install.
- **`docker info` failing is the section gate, not a warning.** Installed docker
  with a stopped daemon, or a user outside the `docker` group, is legitimate.
- **An empty `systemctl --failed`, zero containers and zero VMs are healthy**,
  not warnings. Where a tool prints a header even with nothing to report
  (`pct list`, `qm list`), test the raw output for emptiness rather than the
  parsed row count.
- **Test the thing that actually indicates failure, not just emptiness.**
  `dmidecode -t memory` prints a banner to stdout even when it cannot read
  `/dev/mem`, so that check keys off the `Memory Device` record count. An
  emptiness test there never fires.

`warn` **must only be called from the main shell.** Pipeline bodies and command
substitutions are subshells and their mutations are lost (G-002) — no longer a
theoretical fragility now that a global accumulator exists. The storage and
network row loops capture their pipeline into a variable and test it outside;
follow that pattern.

---

## Conventions

- Comments explain **why**, not what. The `lsblk -P` comment exists specifically
  so a future maintainer doesn't "simplify" it back into a column-shift bug.
  Keep that habit.
- Guard every external tool with `have`, a timeout, and `2>/dev/null`. The
  timeout is `"${TMO[@]}"`, or `tmo N cmd...` where the 10s default is wrong;
  both run the command unwrapped when `timeout` is absent, which is the entire
  point of the gate (C-003). Never hardcode `timeout N` — that bypasses it.
- When adding a vendor CLI, allow only `show`-class verbs and say so in a
  comment.
- Whitelist keys when parsing config files rather than dumping them. Unraid's
  `var.ini` contains a `csrf_token`; `ipmitool lan print` contains an SNMP
  community string. Both are filtered deliberately — extend that policy, don't
  work around it.
- **Fixtures use the documentation ranges**: RFC 5737 `192.0.2.0/24`,
  `198.51.100.0/24`, `203.0.113.0/24` for addresses, RFC 7042
  `00:00:5E:00:53:00`–`FF` for MACs. Never a private-range address or a real
  OUI — a reader cannot tell those from a live one, and neither can a scanner.
  `.claude/hooks/no-estate-identity.sh` refuses the wrong ones, but meeting the
  rule here is cheaper than meeting it as a blocked commit.
- Serials, MACs and IPs **are** emitted on purpose; that's the point of an
  inventory. Secrets are not. The line is "identifying" vs "authenticating."
  Worked example: an iSCSI CHAP **username** is redacted, because it is half of
  a credential pair rather than a name for a thing — while the target IQN, host
  and port beside it are kept. When a value is arguably both, ask which side it
  is doing work on.
- Section output is captured to a variable and printed only if non-empty, so
  absent hardware never leaves a bare table header. Row loops that are pipeline
  bodies must be captured too — both to keep that property and because `warn`
  cannot run inside one.
- Warning text names the tool and says what is missing as a result, so a reader
  who never opens the script can act on it. "`lsblk` is installed but listed no
  block devices — the storage and SMART sections are empty as a result", not
  "lsblk failed".
- A `head -N` that can genuinely truncate real output goes through `cap()` with a
  named constant, not a bare number — see the constants block near the top.
  `cap()` is not `warn()`: truncation is real data arriving incomplete, not a
  collector failing, and it never touches `WARNCOUNT` or the exit code. Before
  piping something through `cap()`, check whether its output is later word-split
  into another command's arguments (as `CNAMES` is, into `docker inspect`'s) — an
  inline marker there becomes a bogus argument instead of a footnote. That site
  reads the full list, caps it with plain `head`, and defers its marker to after
  the block instead.

---

## Rejected proposals — do not re-suggest

Evaluated and declined. Reopening one requires new evidence, not a fresh opinion.
Below is the verdict and the single fact that settles it; the measurements and
the full argument are in [`docs/DISPOSITIONS.md`](../../docs/DISPOSITIONS.md)
under the same ID.

- **`set -o pipefail`** (G-003, O). Would break the script. 23 pipelines end in
  `head -N`, which exits early and SIGPIPEs upstream: measured exit `141` with
  it, `0` without. Also incompatible with the exit-code contract above — you
  cannot have both a meaningful exit code and a `pipefail` that reports failure
  on every successful pipeline.
- **`set -e` / `set -eE`** (O). This is a best-effort collector and most commands
  are *expected* to fail (`dmidecode` unprivileged, `zpool` off ZFS, `pct` off
  Proxmox), so it truncates the report at the first absent tool. `have` / `$TMO`
  / `|| true` handle those explicitly. `set -u` alone is deliberate.
- **Removing brace expansion `{0..31}`** (G-001). Line 1 declares `bash`; numeric
  ranges have worked since bash 3.0 (2004). `seq` would add a coreutils
  dependency to remove a bash dependency from a bash script.
- **Converting whitespace-split lists to arrays** (O-001) — rejected as a
  *priority*, not as an edit. Device names from `lsblk` and VMIDs from `pct list`
  are whitespace-free by construction. Harmless to do; not a correctness fix, and
  not to be sold as one.
- **A `fastfetch` cross-check** (FR-003, issue #1). Two facts settle it. It
  breaks the read-only rule invisibly — a bare `fastfetch` executes `command`
  modules out of the host's `config.jsonc`, verified by watching it create a
  file. And it is not a second source: its `MemTotal` is byte-identical to
  `/proc/meminfo`, its OS fields come from `/etc/os-release`, its model from the
  same SMBIOS table `dmidecode` decodes. **A tool that reads the same file is not
  a second opinion** — apply that to the next cross-check proposal (`neofetch`,
  `inxi`, `hwinfo`) without re-measuring. The real gap it surfaced is FR-004.
- **Replacing the `TMO` array with `tmo()`** (A-004). Both are outputs of C-003,
  introduced together; collapsing them re-opens an adjudicated design at 21 sites.
- **One `smart_fields()` helper for the two SMART loops** (A-005). Only 3 of ~8
  parses are identical — the `poh` and `tmp` fallbacks read ATA and SCSI
  spellings on purpose.
- **Deleting `docs/reviews/`** (A-002). The stale line numbers were real; the fix
  was a freeze header on each file, since the `C-`/`G-`/`O-` IDs are only
  meaningful because those documents are what they point at.
- **Generating the `badbin` stubs from a loop** (A-006) — rejected as a priority,
  not as an edit. It touches T3's fixture to change no behaviour.
- **Splitting the file into `section_*()` functions** (C-031) — deferred, not
  rejected. Real improvement, but it restructures a working one-shot reporter;
  not worth the churn until `--skip` / section selection is actually wanted.

---

## Testing

**Errors are already handled; hangs are the real risk.** Every genuine bug found
in this project so far has been a hang, not an error — three static code reviews
missed the one real defect because none of them ran the script.

Before any PR: **`bash tests/run.sh`, all passing**, plus a new case for what you
changed. `/hw-check` is that as a procedure, including the adversarial-stub phase
that this instruction alone never actually produced.

**CI runs the suite on every push and pull request** that touches
`hw-inventory.sh`, `tests/`, `.claude/hooks/` or the workflow itself, twice:
unprivileged, then as root. That settles two things this file used to apologise
for. ShellCheck (T7) skipped on the maintainer's host because installing it
needed an interactive sudo password no agent session has, so the baseline went
unverified through the whole C-025/C-026 work; an Ubuntu runner ships it, so it
now runs every time. And T6's megaraid drive probe is root-gated and had never
run outside a `sudo` invocation nobody was making. The baseline to hold is **zero
errors, zero warnings** on shellcheck's default ruleset.

What the suite covers, and why each case is shaped the way it is:

1. **T3 hostile.** Stubs on `PATH` that exit non-zero, one that `sleep`s. The
   script must complete, reach its footer, and exit `1` — `124` means it hung,
   which is the defect class this test exists for. Do not delete it to make the
   suite faster.
2. **T2 clean.** Zero stderr, no empty table headers, valid YAML frontmatter,
   exit `0`.
3. **T4/T5/T6 mock fixtures** for hardware you don't have: Unraid
   `disks.ini`/`var.ini`, `pct`/`qm` config output, and a `smartctl` answering on
   sparse `megaraid,N` IDs.
4. **T8 warning contract.** Both halves: a present-and-failing tool exits `1` and
   is named; a `PATH` where the tools are merely absent still exits `0` and warns
   about nothing. The second half is the one that catches over-eager warnings.
5. **T9 cmdline redaction.** Also both halves: secrets and CHAP usernames gone,
   and the target name, initiator and `rd.iscsi.firmware` still present.
   Over-redaction is a real failure too — a command line scrubbed of its target
   is no longer useful as inventory.
6. **T10/T11 output caps.** T10 is the general case: a stub over a limit gets the
   `--- truncated ---` marker and nothing past it; a stub under the limit is
   byte-for-byte what a bare `head -N` would have produced, marker included (i.e.
   not included) — this second half is what catches a marker leaking onto an
   untruncated section. T11 is the CNAMES edge case: a marker must never reach
   `docker inspect`'s argument list, and must land after the container-networks
   table, not inside it. Both were run against deliberately reintroduced versions
   of the bugs they guard against — a stderr-based first draft of T11 did not
   fail without the fix, since the script correctly runs `docker inspect` under
   `2>/dev/null` and the test was checking a channel the script itself discards.
7. **T12 the empty-collection case.** A `docker info` that answers with zero
   containers is past the section gate and healthy, so it must reach the footer
   and exit `0`. It did neither: `DNET` was assigned only inside the
   `[ -n "$CNAMES" ]` guard and tested outside it, so `set -u` killed the script
   mid-section — no footer, no warnings block, and still exit `1`, which a caller
   cannot tell from an honest incomplete collection. T11's stub always answers
   with 105 containers, which is why nothing caught it. **When a tool's output
   gates an assignment, test the empty answer, not just the failing one** — the
   pattern to copy is `DMIMEM=""` initialised above its own root gate.
8. **T13/T14 the enforcement hooks.** Both assert their pass half as loudly as
   their block half: a matcher that refuses `zpool list` or a documentation-range
   MAC gets switched off within a day, and then nothing is enforcing anything.
   T14 also runs every tracked file through the leak matcher.
9. `bash -n` (T1) and ShellCheck (T7). T1 also greps the script for banned verbs
   and for `set -e`/`pipefail`, stripping comments and quoted strings first — the
   header comment deliberately names every verb the script does not use.

Some paths are only reachable as root (`dmidecode`, SMART, `pct`/`qm`, IPMI).
Where sudo isn't available, simulating `is_root() { true; }` against a copy
exercises the branches; it found the `dmidecode` banner problem noted above.
