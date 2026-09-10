# Code review R2, condensed

| Field | Value |
|---|---|
| Target | `hw-inventory.sh` v7 |
| Commit SHA | `34ca470a0f454abd4b1a85a3b979cda200f2d4ed` — filled in at filing, per the instruction this cell carried. The reviewer was handed the file and not the SHA; the working tree was clean at this commit and its `hw-inventory.sh` is the 1,205-line file that was attached. Nothing else in this document is edited. |
| Reviewer vendor | Anthropic |
| Reviewer model | Claude Opus 5 |
| Date | 2026-09-09 |
| LOC | 1,205 lines (`wc -l`) |
| Shell / runtime | bash, `#!/usr/bin/env bash` (line 1), `set -u` and `export LC_ALL=C` (lines 29 to 30). Stated floor bash 3.0, developed on bash 5.x. Linux only. |

---

## Verdict

**Request changes.**

One finding blocks the ship, and only one. F-001: lines 570, 573 and 576 call `perccli64` or
`storcli64` with no `nolog` keyword. That CLI family writes a command log into the current
working directory by default. The MegaCLI branch three lines below passes `-NoLog` at lines
581 and 584 for exactly that reason, so the file already contains the counter-example to
itself. A write on a production host breaks the invariant the whole design rests on, and the
cron use case is the reason that invariant exists.

The rest of the script is careful work. The error model, the redaction policy and the
subshell discipline around `warn` are all correct, and the comments earn their space. Six
findings sit at HIGH or come from measurements I took here rather than from reading, so read
the detailed document before you dismiss anything as cosmetic.

---

## Engineering scorecard

| Dimension | Score | Rationale |
|---|---|---|
| Architecture | 4 / 5 | Gather-then-emit split (lines 209 to 285, then 287 onward) is right for a one-shot reporter, and `have` plus `$TMO` plus `2>/dev/null` is a real extension contract. The read-only boundary stops at the verb and does not cover what a dependency does on its own (F-001, F-002). |
| Readability and maintainability | 4 / 5 | Comments explain why, not what, and several of them (lines 269 to 271, 429 to 431, 1152 to 1158) exist to stop a future maintainer reintroducing a fixed bug. `fld()` at line 460 is the one construct whose fragility no comment records (F-008). |
| Robustness (hangs and timeouts) | 3 / 5 | The `TMO` and `tmo()` gate covers 21 of 24 external tool sites, and no hardcoded `timeout N` survives. `pveversion` runs bare at line 319 against a FUSE filesystem (F-003), and no aggregate deadline bounds the run (F-004). |
| Error handling | 4 / 5 | The warn-or-stay-silent rule holds at every site I checked, and no `warn` call sits inside a subshell. Two collectors return nothing and say nothing: `pct config` and `qm config` at lines 1044 and 1074 (F-017). |
| Security | 3 / 5 | Redaction runs in both directions and `/etc/os-release` is parsed rather than sourced (lines 215 to 224), which closes a root-level execution path. F-001 puts a write on a production host, and F-002 starts a daemon. |
| Performance | 4 / 5 | Not a hot path, and A-008 already removed the expensive duplication. Two round trips remain: `smartctl --scan` at lines 535 and 537 (F-006) and `docker ps -a` at lines 1118 and 1145 (F-019). |
| Portability | 3 / 5 | Quoting and `[ ]` usage hold to the bash 3.0 floor, but `"${TMO[@]}"` breaks it (F-007), `free -h` breaks on BusyBox (F-009) and `findmnt --real` breaks below util-linux 2.28 (F-015). |
| Idiomatic style | 4 / 5 | `printf` over `echo` almost everywhere, `local` in every helper that needs it, `case` instead of `[[ =~ ]]`, no useless `cat` outside the three sites documented at lines 786 to 792. |

**Overall: 3.6 / 5.** This is a well-engineered script with one ship-blocker and a portability
floor it does not actually meet. Nothing here suggests a redesign. Fix F-001, then work down
the HIGH list.

---

## Top findings

| ID | Risk | Line(s) | Description |
|---|---|---|---|
| F-001 | CRITICAL | 570, 573, 576 | `perccli64` / `storcli64` run without `nolog`, so the CLI writes a log file into the working directory. MegaCLI at 581 and 584 already passes `-NoLog`. |
| F-002 | HIGH | 966 | `upower -e` is a D-Bus activatable call. On a host where `upowerd` is not running, it starts the daemon. Contradicts `docs/DISPOSITIONS.md` FR-002. |
| F-003 | HIGH | 319 | `pveversion` runs with no timeout wrapper, against `/etc/pve`, which is a FUSE mount that can stop answering. The same binary is wrapped at line 1021. |
| F-007 | HIGH | 144 to 145, 1106 | `"${TMO[@]}"` with an empty `TMO` aborts under `set -u` on bash below 4.4. At line 1106 that abort happens in the main shell and truncates the report. |
| F-004 | MEDIUM | 504, 609, 1044, 1074 | No aggregate deadline. Per-call budgets sum to about 20 minutes on a Proxmox host with 12 disks and 28 guests, plus 192 s where a RAID controller is present. |
| F-008 | MEDIUM | 460 | `fld()` matches an unanchored greedy pattern. Adding a column whose name ends with an existing key returns the wrong field. Measured with `KNAME`. |
| F-009 | MEDIUM | 245 to 249 | BusyBox `free` rejects `-h`, so an Alpine host warns and exits 1 while `/proc/meminfo` sits readable. CPU already has that fallback at line 241. |
| F-013 | MEDIUM | 608 to 614 | The megaraid probe finds no drive at all when the lowest controller device ID is 10 or higher. Measured: base ID 9 finds three drives, base ID 10 finds none. |
| F-014 | MEDIUM | 728, 795, 812, 942, 960, 966, 1078, 1079 | `paste -sd', '` cycles its delimiter list. Three or more items join as `a,b c`. Three resolvers are the common case. |
| F-015 | MEDIUM | 744 to 746 | `findmnt --real` did not exist before util-linux 2.28, so on RHEL 7 the mount table is empty and the script raises a false warning. |
| F-017 | MEDIUM | 1044 to 1045, 1074 to 1075 | A failing `pct config` or `qm config` drops the guest with no warning. If every call fails, the whole table disappears and the script still exits 0. |

Eleven LOW and five NITPICK findings appear in the detailed document.

---

## Top 3 actions

1. **Add `nolog` to the three perccli / storcli calls (F-001).** Verify first on a host that
   has the binary: run it from a directory you own and list that directory afterward. Then
   add the keyword, and extend T1's banned pattern so a future call without it fails the
   suite. This is the only ship-blocker.
2. **Wrap `pveversion` at line 319 and expand `"${TMO[@]}"` safely (F-003, F-007).** Both are
   one-line edits to the gate the script already treats as load-bearing. `"${TMO[@]}"`
   becomes `${TMO[@]+"${TMO[@]}"}`, which is a no-op on bash 4.4 and later and stops the
   script dying at line 1106 on anything older.
3. **Settle F-002 with a field test, not an argument.** On a host with `upower` installed and
   `upowerd` stopped, run `systemctl is-active upower`, run the script, run it again. If the
   answer changes from `inactive` to `active`, the FR-002 line calling `upower -e` a read is
   wrong and the probe needs a gate or needs removing.

---

## What this code does well

**`cap()` is built on `head -n $((n+1))` rather than a read loop (lines 125 to 134).** The
comment at lines 104 to 109 states why, and the reason is correct: `head` holds the read end
of the pipe, so it closes early and a slow producer still takes SIGPIPE. A `while read` loop
would drain the producer instead. The whole `set -o pipefail` rejection depends on that
behavior, and the code and the comment agree about it.

**`/etc/os-release` is parsed as `KEY=value` instead of sourced (lines 215 to 224).** Sourcing
a shell fragment as root on every run is a code-execution path in a script that otherwise only
reads. The `osr()` anchor `^KEY=` cannot match `ID_LIKE` or `VERSION_ID`, and a `$(...)` in a
value stays literal text. T18 turns exactly that lever, so the fix cannot silently regress.

**Pipeline row loops are captured into a variable and tested outside (lines 464 to 472, 784 to
800).** This is one decision serving two purposes at once. It keeps `warn` in the main shell,
where its mutation survives, and it stops a table header printing above zero rows. The
comments at both sites name the second purpose as well as the first.

**MegaCLI is invoked with `-NoLog` (lines 581 and 584).** That flag exists only to stop the
tool writing `MegaSAS.log` into the working directory. Passing it shows the author already
understands that a vendor CLI can write without being asked to. F-001 is that same
understanding failing to reach the perccli branch eleven lines above it.
