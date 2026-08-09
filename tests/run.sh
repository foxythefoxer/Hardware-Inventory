#!/usr/bin/env bash
# tests/run.sh — verify hw-inventory.sh. Run from anywhere:
#
#   bash tests/run.sh
#
# Read-only, like the thing it tests. Creates nothing outside a temp dir it
# removes on exit. Exits 0 if every test passes, 1 otherwise.
#
# The tests exist because every real bug in this project has been a HANG, not an
# error. Errors are already handled by design; T3 is the one that has caught a
# live defect. Do not delete it to make the suite faster.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${1:-$HERE/../hw-inventory.sh}"
FIX="$HERE/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ -r "$SCRIPT" ] || { echo "cannot read $SCRIPT"; exit 1; }
echo "Testing: $SCRIPT"
[ "$(id -u)" -eq 0 ] || echo "Running as $(id -un) — root-only tests will be skipped."

# ---------------------------------------------------------------- T1 syntax --
head_ "T1  Syntax and read-only contract"

bash -n "$SCRIPT" 2>/dev/null && ok "parses under bash -n" || bad "bash -n failed"

# Banned verbs. Comments AND quoted-string contents are stripped first: a word
# like "mount" inside a printf format string is data, not a command, and the
# header comment deliberately names every verb the script does not use.
BANNED='\b(rm|mv|cp|mkdir|rmdir|touch|tee|dd|truncate|chmod|chown|mkfs|mount|umount|modprobe|swapon|crontab|useradd|iptables|parted|fdisk|wipefs|mdcmd)\b|smartctl[^|]*[[:space:]]-t[[:space:]]|zpool[[:space:]]+(create|destroy|import|export|scrub)|btrfs[[:space:]]+(balance|scrub|device)|docker[[:space:]]+(run|exec|rm|start|stop|pull|build)|(pct|qm)[[:space:]]+(start|stop|set|create|destroy|clone|enter|exec)|ipmitool[^|]*(chassis|sel clear|mc reset|raw)|(storcli|perccli|megacli)[^|]*(add|delete|set |start )'
strip() { sed -e "s/#.*//" -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g' "$SCRIPT"; }
if strip | grep -nEq "$BANNED"; then
  bad "banned verb found:"; strip | grep -nE "$BANNED" | sed 's/^/        /'
else
  ok "no state-changing verbs"
fi

# /dev/null, /dev/stdout and /dev/stderr are sinks, not writes.
if grep -nE '[^0-9&]>[[:space:]]*/(proc|sys|dev)/' "$SCRIPT" \
     | grep -vE '/dev/(null|stdout|stderr)' | grep -q .; then
  bad "writes to /proc, /sys or /dev"
else
  ok "no writes to /proc, /sys, /dev"
fi

grep -qE '\bset -e|\bset -o pipefail' "$SCRIPT" \
  && bad "set -e / pipefail present (see docs/reviews/DISPOSITIONS.md)" \
  || ok "set -e and pipefail correctly absent"

# ----------------------------------------------------------------- T2 clean --
head_ "T2  Clean run on an ordinary host"

bash "$SCRIPT" > "$TMP/clean.md" 2> "$TMP/clean.err"; RC=$?
[ $RC -eq 0 ] && ok "exits 0" || bad "exit $RC"
[ ! -s "$TMP/clean.err" ] && ok "stderr empty" || { bad "stderr not empty:"; sed 's/^/        /' "$TMP/clean.err"; }
grep -q 'End of report' "$TMP/clean.md" && ok "reaches footer" || bad "no footer"

# A table header with no rows under it means a section printed its shape but
# collected nothing — the exact silent-empty failure the suite guards against.
awk '/^\|---/{getline n; if (n !~ /^\|/) {print NR; exit}}' "$TMP/clean.md" | grep -q . \
  && bad "empty table header found" || ok "no empty table headers"

# Frontmatter must be valid YAML or every downstream consumer breaks.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP/clean.md" <<'PY' && ok "frontmatter parses as YAML" || bad "frontmatter is not valid YAML"
import sys
try: import yaml
except ImportError: sys.exit(0)
t = open(sys.argv[1]).read()
sys.exit(0 if isinstance(yaml.safe_load(t.split('---')[1]), dict) else 1)
PY
fi

# --------------------------------------------------------------- T3 hostile --
head_ "T3  Hostile environment (every tool fails; lspci hangs)"

S=$(date +%s)
PATH="$FIX/badbin:$PATH" timeout 180 bash "$SCRIPT" > "$TMP/h.md" 2>"$TMP/h.err"; RC=$?
E=$(( $(date +%s) - S ))

# Since C-025/C-026 this must exit 1, not 0. Every tool here is present and
# failing, which is precisely the case that must not read as a complete report.
# 124 still means it HUNG — that is the defect class this test was written for,
# and the reason the distinction below is spelled out rather than `-ne 0`.
if [ $RC -eq 124 ]; then
  bad "exit 124 — it HUNG, find the unguarded command"
elif [ $RC -eq 1 ]; then
  ok "exits 1 (collection warnings) with everything broken"
else
  bad "exit $RC — expected 1, every tool is broken so the report cannot be complete"
fi
[ "$E" -lt 90 ] && ok "finishes promptly (${E}s)" || bad "took ${E}s — a timeout guard is missing"
grep -q 'End of report' "$TMP/h.md" && ok "still reaches footer" || bad "no footer"
grep -q '^## Collection warnings' "$TMP/h.md" \
  && ok "names the failed collectors" || bad "no warnings section despite everything failing"

# --------------------------------------------------------------- T4 unraid ---
head_ "T4  Unraid array parsing"

sed -e "s#/var/local/emhttp#$FIX/unraid/emhttp#g" \
    -e "s#/boot/config/shares#$FIX/unraid/shares#g" "$SCRIPT" > "$TMP/unraid.sh"
bash "$TMP/unraid.sh" > "$TMP/u.md" 2>/dev/null

grep -q 'CANARY_TOKEN_MUST_NOT_LEAK' "$TMP/u.md" \
  && bad "SECRET LEAK: csrf_token from var.ini appeared in output" \
  || ok "csrf_token not leaked"

for slot in parity disk1 cache flash; do
  grep -q "^| $slot |" "$TMP/u.md" && ok "slot '$slot' parsed" || bad "slot '$slot' missing"
done
grep -q '7.28 TB' "$TMP/u.md" && ok "KB->TB conversion correct" || bad "size conversion wrong"
grep -q '78% used' "$TMP/u.md" && ok "fill percentage correct" || bad "fill percentage wrong"
grep -q 'STARTED' "$TMP/u.md" && ok "array state read" || bad "array state missing"
grep -q 'prefer' "$TMP/u.md" && ok "share cache policy read" || bad "share policy missing"

# -------------------------------------------------------------- T5 proxmox ---
head_ "T5  Proxmox LXC and VM parsing"

PATH="$FIX/mockbin:$PATH" bash "$SCRIPT" > "$TMP/p.md" 2>/dev/null
grep -q '^| 202 | ct-dns01' "$TMP/p.md"   && ok "LXC row parsed" || bad "LXC row missing"
grep -q '^| 301 | vm-proxy01' "$TMP/p.md" && ok "VM row parsed"  || bad "VM row missing"
grep -q '198.51.100.4/24' "$TMP/p.md"         && ok "LXC IP extracted from net0" || bad "LXC IP missing"
grep -qE '^\| 202 .*\| yes \|' "$TMP/p.md" && ok "unprivileged flag mapped to yes" || bad "unprivileged flag wrong"
grep -q 'media=cdrom' "$TMP/p.md"         && bad "cdrom leaked into VM disk list" || ok "cdrom excluded from disks"

# ----------------------------------------------------------------- T6 perc ---
head_ "T6  PERC / MegaRAID with sparse device IDs"

PATH="$FIX/percbin:$PATH" bash "$SCRIPT" > "$TMP/r.md" 2>/dev/null
grep -q 'PERC H310' "$TMP/r.md" && ok "controller detected" || bad "controller not detected"

# The script only probes SMART as root, by design. Without root there is
# nothing to assert here, so skip rather than report a false failure.
if [ "$(id -u)" -ne 0 ]; then
  printf '  \033[33mSKIP\033[0m  drive probe needs root (run: sudo bash tests/run.sh)\n'
else
  for n in 0 1 8 9; do
    grep -q "megaraid,$n" "$TMP/r.md" && ok "drive at sparse ID $n found" || bad "drive at ID $n missed"
  done
  grep -q 'megaraid,20' "$TMP/r.md" && bad "probe ran past the miss threshold" || ok "probe stopped after miss threshold"
fi

# ----------------------------------------------------------- T7 shellcheck ---
head_ "T7  ShellCheck (skipped if not installed)"

if command -v shellcheck >/dev/null 2>&1; then
  N=$(shellcheck -S warning -f gcc "$SCRIPT" 2>/dev/null | grep -c .)
  [ "$N" -eq 0 ] && ok "zero errors and warnings" \
                 || { bad "$N error/warning findings"; shellcheck -S warning -f gcc "$SCRIPT" | head -10 | sed 's/^/        /'; }
else
  printf '  \033[33mSKIP\033[0m  shellcheck not installed\n'
fi

# ------------------------------------------------------------- T8 warnings ---
# The C-025/C-026 contract, and specifically the judgment call in it: a tool
# that is PRESENT and fails is a warning; a tool that is ABSENT is not. Both
# halves are asserted, because an accumulator that warns about absent hardware
# would make every minimal host look broken and train everyone to ignore it.
head_ "T8  Collection warnings and exit code"

# --- one tool present and failing ---
mkdir -p "$TMP/onebad"
printf '#!/bin/sh\nexit 1\n' > "$TMP/onebad/lscpu"
chmod +x "$TMP/onebad/lscpu"

PATH="$TMP/onebad:$PATH" bash "$SCRIPT" > "$TMP/w.md" 2>"$TMP/w.err"; RC=$?
[ $RC -eq 1 ] && ok "exits 1 when a present tool fails" || bad "exit $RC — expected 1"
grep -q '^## Collection warnings' "$TMP/w.md" \
  && ok "emits ## Collection warnings" || bad "no warnings section"
grep -q 'lscpu' "$TMP/w.md" && ok "warning names the failed tool" || bad "warning does not name lscpu"
grep -q 'End of report' "$TMP/w.md" && ok "still writes the full report" || bad "no footer"
[ ! -s "$TMP/w.err" ] && ok "stderr still empty" || bad "stderr not empty"

# --- tools absent, not failing ---
# A PATH holding only generic utilities: every hardware tool is genuinely
# missing, which is a minimal container or a stripped host, not a broken one.
mkdir -p "$TMP/minbin"
# bash and sh are in the list because the PATH= prefix below also governs how
# `bash` itself is resolved — without them the run dies at 127 before starting.
for u in bash sh uname hostname date id awk gawk sed grep cat head tail wc ls \
         paste basename timeout sort tr cut; do
  p=$(command -v "$u" 2>/dev/null) && ln -sf "$p" "$TMP/minbin/$u"
done

PATH="$TMP/minbin" bash "$SCRIPT" > "$TMP/m.md" 2>"$TMP/m.err"; RC=$?
[ $RC -eq 0 ] && ok "exits 0 when tools are merely absent" \
              || { bad "exit $RC — absent tools must not warn:"; \
                   sed -n '/^## Collection warnings/,/^_/p' "$TMP/m.md" | sed 's/^/        /'; }
grep -q '^## Collection warnings' "$TMP/m.md" \
  && bad "absent tools produced warnings" || ok "no warnings for absent tools"
grep -q 'End of report' "$TMP/m.md" && ok "still writes the full report" || bad "no footer"

# -------------------------------------------------------------- T9 cmdline ---
# C-009. Both halves matter: a leaked secret is the obvious failure, but
# over-redacting is a real one too — a kernel command line with the target and
# initiator scrubbed out stops being useful as inventory.
head_ "T9  Kernel command line redaction"

sed -e "s#/proc/cmdline#$FIX/cmdline/cmdline.txt#g" "$SCRIPT" > "$TMP/cmdline.sh"
bash "$TMP/cmdline.sh" > "$TMP/k.md" 2>/dev/null

# CHAP secrets *and* CHAP usernames: a username is half of a credential pair,
# not merely identifying, so it is redacted with the rest.
for s in ChapPass111 RevPass222 SuperSecret333 chapuser1 revuser1; do
  grep -q "$s" "$TMP/k.md" && bad "SECRET LEAK: $s appears in output" || ok "redacted: $s"
done

grep -q 'iscsi:REDACTED@198.51.100.5:3260' "$TMP/k.md" \
  && ok "iSCSI host and port still visible" || bad "host/port lost, or creds not redacted"
grep -q 'iqn.2001-04.com.example:target0' "$TMP/k.md" \
  && ok "iSCSI target name preserved" || bad "target name lost"
grep -q 'rd.iscsi.password=REDACTED' "$TMP/k.md" \
  && ok "name-based redaction still applies" || bad "rd.iscsi.password not redacted"
grep -q 'rd.iscsi.initiator=iqn.1994-05' "$TMP/k.md" \
  && ok "non-secret iscsi params untouched" || bad "over-redacted rd.iscsi.initiator"

# ---------------------------------------------------------------- summary ----
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
