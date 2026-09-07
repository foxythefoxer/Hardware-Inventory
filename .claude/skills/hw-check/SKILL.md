---
name: hw-check
description: Verify a change to hw-inventory.sh before committing — write an adversarial stub for what changed, run it, then run the full suite and separate a regression this change caused from a failure that was already there. Use after editing hw-inventory.sh or tests/run.sh, before any commit or PR.
---

# Verify a change to hw-inventory.sh

<!-- This exists because "run the tests and add a case for what you changed" was
     prose in an always-loaded file, and prose is a hope. The phases below make
     it a procedure, and phase 1 is the one that was actually being skipped:
     every previous session ran the suite, and the suite only ever contained
     cases somebody had already thought to write. -->

**The thesis of this test suite: errors are already handled, hangs are the real
risk.** Three static code reviews of this script missed its one real defect
because none of them ran it. So the question is never "does my change work on a
healthy host" — it is "what does my change do when the tool it calls misbehaves".

Do not skip phase 1 because the change looks small. A one-line change to an
assignment is what produced the T12 bug: `DNET` was set inside a guard and
tested outside it, so a *healthy* docker with zero containers killed the script
under `set -u`.

## Phase 0 — establish the baseline first

```bash
bash tests/run.sh 2>&1 | tail -3
```

Record the pass/fail counts **before** touching anything, or you cannot tell a
regression from a failure that was already there. If the baseline is already
red, say so and stop — fixing someone else's failure inside your change makes
both untraceable.

## Phase 1 — write an adversarial stub for what you changed

Identify every external tool your change calls, then write a stub for it in a
scratch directory and put that directory first on `PATH`. Four shapes, and the
last two are the ones that get missed:

| Shape | Stub | What it must not do |
|---|---|---|
| **Fails** | `exit 1` | Truncate the report, or warn about a tool that is merely absent |
| **Hangs** | `sleep 300` | Exceed its timeout — exit `124` from the suite means it hung |
| **Succeeds, returns nothing** | `exit 0` with no output | Leave a variable unset (`set -u` aborts), or emit a bare table header |
| **Returns a banner but no records** | print a header, no rows | Pass an emptiness test that should have failed |

The third row is T12 and the fourth is the `dmidecode -t memory` trap, where the
tool prints to stdout even when it cannot read `/dev/mem` — so the check keys off
the record count, not emptiness. **When a tool's output gates an assignment, test
the empty answer, not just the failing one.** The pattern to copy is `DMIMEM=""`
initialised above its own root gate.

If your change adds a `cap()` site, add a fifth: a stub **over** the limit and
one **under** it. The under-limit case is the one that catches a marker leaking
onto a section that should have stayed untouched.

Run each stub against the script directly and read the output before writing any
assertion:

```bash
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$D/<tool>"; chmod +x "$D/<tool>"
PATH="$D:$PATH" timeout 180 bash hw-inventory.sh > "$D/out.md" 2> "$D/err"; echo "exit=$?"
grep -c '' "$D/err"; grep -q 'End of report' "$D/out.md" && echo footer-ok
```

`exit=124` is a hang. Fix it before going further; nothing else matters.

## Phase 2 — promote the stub into `tests/run.sh`

A scratch stub that proved a bug and then evaporated is a bug that comes back.
Add the case as a new `T<n>` block, following the shape already there: `head_`
for the banner, `ok`/`bad` for assertions, a comment saying **why** the case
exists rather than what it does.

Two rules the existing tests learned the hard way:

- **Assert against the rendered report, not stderr.** The script correctly runs
  several commands under `2>/dev/null`, so a stub writing to stderr is checking a
  channel the script itself discards. A draft of T11 did exactly this and passed
  against the bug it was written to catch.
- **Confirm the test fails without the fix.** Reintroduce the defect
  deliberately, watch the new assertion go red, then restore. A test that has
  never failed has not been tested.

Assert both directions wherever the change involves a judgment call — a warning
that must fire *and* a case that must stay silent, a value redacted *and* a value
preserved. Over-redaction and over-warning are real failures too.

## Phase 3 — the full suite

```bash
bash tests/run.sh
sudo bash tests/run.sh   # when you can: T6's drive probe skips otherwise
```

Then compare against phase 0:

- **More failures than the baseline** → your change caused them. Fix, do not
  document.
- **The same failures** → pre-existing. Say so explicitly in the report and
  leave them; do not fold someone else's failure into your commit.
- **T3 exits `124`** → it hung. That is this suite's whole reason for existing.
- **T7 skipped** → shellcheck is absent locally. CI runs it on every push, so
  this is a local gap, not an unverified baseline.

Some paths are only reachable as root — `dmidecode`, SMART, `pct`/`qm`, IPMI.
Where sudo is unavailable, simulating `is_root() { true; }` against a *copy* of
the script exercises those branches; that is how the `dmidecode` banner problem
was found.

## Phase 4 — clean up, then state a verdict

Remove every scratch directory and stub, **including on failure**. The suite
itself creates nothing outside a `mktemp -d` it removes on `EXIT`; a verification
run that leaves debris behind is worse than the script it is testing.

End with one line, not a narrative:

```
PASS — 109 passed, 0 failed (baseline 109/0). T7 skipped locally, runs in CI.
FAIL — 108 passed, 1 failed. T12 regressed: <what and where>.
```

If anything is unverified — a branch that needs root, a condition that needs a
host class you do not have — name it in the verdict rather than letting a green
line imply coverage that does not exist.
