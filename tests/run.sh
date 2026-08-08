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

[ $RC -eq 0 ] && ok "completes (exit 0) with everything broken" \
              || bad "exit $RC — 124 means it HUNG, find the unguarded command"
[ "$E" -lt 90 ] && ok "finishes promptly (${E}s)" || bad "took ${E}s — a timeout guard is missing"
grep -q 'End of report' "$TMP/h.md" && ok "still reaches footer" || bad "no footer"

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

# ---------------------------------------------------------------- summary ----
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
