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

# Same strip() as the banned-verbs check above: a comment that names
# `set -o pipefail` to explain why it's avoided (see cap() in the script)
# is documentation, not the directive itself.
if strip | grep -qE '\bset -e|\bset -o pipefail'; then
  bad "set -e / pipefail present (see docs/DISPOSITIONS.md)"
else
  ok "set -e and pipefail correctly absent"
fi

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

# ------------------------------------------------------------ T10 cap() ------
# F-014. systemctl --failed exercises cap() via SYSTEMD_FAILED_LINES=20: no
# root gate, plain fenced text, easy to script both directions with.
head_ "T10  Output-cap markers (cap())"

mkdir -p "$TMP/capbin-over" "$TMP/capbin-under"

{
  printf '#!/bin/sh\n'
  printf 'for i in $(seq 1 25); do printf "bad%%d.service loaded failed failed Bad unit %%d\\n" "$i" "$i"; done\n'
} > "$TMP/capbin-over/systemctl"
chmod +x "$TMP/capbin-over/systemctl"

{
  printf '#!/bin/sh\n'
  printf 'for i in $(seq 1 3); do printf "bad%%d.service loaded failed failed Bad unit %%d\\n" "$i" "$i"; done\n'
} > "$TMP/capbin-under/systemctl"
chmod +x "$TMP/capbin-under/systemctl"

PATH="$TMP/capbin-over:$PATH" bash "$SCRIPT" > "$TMP/cap_over.md" 2>"$TMP/cap_over.err"
PATH="$TMP/capbin-under:$PATH" bash "$SCRIPT" > "$TMP/cap_under.md" 2>"$TMP/cap_under.err"

# Over the limit: exactly 20 real lines, then the marker, and no 21st line.
grep -q 'bad20.service' "$TMP/cap_over.md" && ok "25-line stub: line 20 present" || bad "line 20 missing"
grep -q 'bad21.service' "$TMP/cap_over.md" && bad "25-line stub: line 21 leaked past the cap" || ok "25-line stub: line 21 correctly absent"
grep -q -- '--- truncated at 20 failed unit lines ---' "$TMP/cap_over.md" \
  && ok "25-line stub: truncation marker present" || bad "25-line stub: no truncation marker"
[ ! -s "$TMP/cap_over.err" ] && ok "25-line stub: stderr still empty" || bad "25-line stub: stderr not empty"

# Under the limit: this is the one that catches the empty-section regression
# — cap() must reproduce a bare `head -N` exactly when nothing is truncated,
# marker included (i.e. NOT included), or every untruncated section in the
# report grows a spurious line.
grep -q 'bad3.service' "$TMP/cap_under.md" && ok "3-line stub: real output present" || bad "3-line stub: real output missing"
grep -q -- '--- truncated' "$TMP/cap_under.md" \
  && bad "3-line stub: marker present despite no truncation" || ok "3-line stub: no marker below the cap"
UNDER_UNITS=$(grep -c '^bad[0-9]*\.service' "$TMP/cap_under.md")
[ "$UNDER_UNITS" -eq 3 ] && ok "3-line stub: byte-identical line count (3)" || bad "3-line stub: got $UNDER_UNITS lines, expected 3"

# ------------------------------------------------------- T11 CNAMES safety ---
# F-014's sharpest edge case: CNAMES is word-split into `docker inspect`
# arguments, so cap()'s inline marker cannot be used there without a marker
# line becoming a bogus container name. Assert the marker is deferred to
# after the container-networks table AND never reaches `docker inspect`.
head_ "T11  Docker container-list cap (deferred marker)"

mkdir -p "$TMP/dockerbin"
cat > "$TMP/dockerbin/docker" << 'DOCKEREOF'
#!/bin/sh
case "$1" in
  info) exit 0 ;;
  version) echo "Docker 27.0.0" ;;
  ps)
    if [ "$4" = 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' ] || printf '%s' "$*" | grep -q 'table'; then
      i=1; while [ "$i" -le 105 ]; do printf 'c%d\timg\tUp\t\n' "$i"; i=$((i+1)); done
    else
      i=1; while [ "$i" -le 105 ]; do printf 'c%d\n' "$i"; i=$((i+1)); done
    fi
    ;;
  inspect)
    shift
    while [ "$1" = "-f" ]; do shift 2; done
    # A marker word leaking in as an argument must be detectable from the
    # FINAL REPORT, not from stderr: the real script runs this whole command
    # under 2>/dev/null (correctly, per convention), so anything this stub
    # writes to stderr is invisible to the test. Emit a distinctive STDOUT
    # row instead — stdout is what flows through sed/awk into $DNET and then
    # into the report — so the hazard is caught the same way a real leak
    # would eventually surface: in the rendered Markdown.
    for name in "$@"; do
      case "$name" in
        *truncated*|*---*)
          echo "/MARKER-LEAKED-INTO-INSPECT:${name}|bogus=1 "
          continue
          ;;
      esac
      echo "/$name|bridge=198.51.100.1 "
    done
    ;;
esac
DOCKEREOF
chmod +x "$TMP/dockerbin/docker"

PATH="$TMP/dockerbin:$PATH" bash "$SCRIPT" > "$TMP/dock.md" 2>"$TMP/dock.err"

grep -q 'MARKER-LEAKED-INTO-INSPECT' "$TMP/dock.md" \
  && bad "marker text was passed to docker inspect as a container name" \
  || ok "marker text never reached docker inspect"
grep -q 'container network lookups capped at 100 containers' "$TMP/dock.md" \
  && ok "deferred marker present after the Docker section" || bad "deferred marker missing"
# The VISIBLE container table (site 813) is a normal cap() consumer — it is
# only CNAMES (818, word-split into docker inspect args) that cannot use an
# inline marker. With 105 stub containers this table legitimately truncates,
# so its own "--- truncated ---" line is expected, not a leak.
grep -q -- '--- truncated at 100 container lines ---' "$TMP/dock.md" \
  && ok "container table still gets its own inline cap() marker" || bad "container table marker missing"
# The deferred marker must come after the container-networks table, not
# inside it — the table is Markdown, and this marker would corrupt a row.
awk '/Container networks/{t=NR} /container network lookups capped/{m=NR} END{exit !(t>0 && m>0 && m>t)}' "$TMP/dock.md" \
  && ok "deferred marker placed after the container-networks table" || bad "deferred marker placed before or inside the table"

# ---------------------------------------------------------------- summary ----
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
