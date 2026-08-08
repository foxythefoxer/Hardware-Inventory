# Tests

```bash
bash tests/run.sh
```

Exits 0 if everything passes, 1 otherwise. Read-only, like the script it tests.
No dependencies beyond bash and coreutils; ShellCheck is used if present, skipped if not.

| Test | Checks |
|---|---|
| T1 | Syntax; no state-changing verbs; no writes to `/proc`, `/sys`, `/dev`; `set -e`/`pipefail` still absent |
| T2 | Clean run: exit 0, empty stderr, reaches footer, no empty table headers, valid YAML frontmatter |
| T3 | **Hostile run** — every external tool fails and `lspci` hangs. Must still complete promptly |
| T4 | Unraid array parsing against fixtures, including a canary that `csrf_token` never leaks |
| T5 | Proxmox LXC/VM config parsing against mock `pct`/`qm` |
| T6 | PERC/MegaRAID probe finds drives at sparse IDs and stops after the miss threshold |
| T7 | ShellCheck: zero errors and warnings |

## T3 is the important one

Every real bug in this project's history has been a **hang**, not an error. Errors are
already handled by design — `have` guards, `|| true`, suppressed stderr. A missing
`timeout` wrapper is invisible to reading and to every other test here.

T3 caught exactly that once already: an unguarded `lspci` froze the script for 240s.
If T3 reports exit 124, a command somewhere lost its timeout guard.

Do not delete T3 to make the suite faster. It takes ~20 seconds and that is the point.

## Adding fixtures

`fixtures/mockbin` and `fixtures/percbin` are stub binaries placed on `PATH`.
`fixtures/unraid` holds `.ini` files; the runner rewrites the script's hardcoded
`/var/local/emhttp` and `/boot/config/shares` paths into a temp copy rather than
requiring the script to grow a test-only override.

To test hardware you don't own, add a stub that emits its real output format. That is
how Unraid, Proxmox and PERC support were all developed without the hardware present.
