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

# When an exit-code assertion fails, the one useful fact is WHICH collector
# warned — the script writes it into the report, and a bare "exit 1" throws it
# away. That is exactly how three CI failures stayed unattributed: T8 dumped its
# warnings block and was diagnosable from the log, T2 and T12 did not and were
# not, on a runner nobody can log into. Every failure branch that turns on the
# exit code calls this.
dumpwarn() { sed -n '/^## Collection warnings/,/^_/p' "$1" | sed 's/^/        /'; }

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

# The version is written twice: the header comment, and the `collector:`
# frontmatter field a vault files the report under. A code review flagged that
# pair as undetectably driftable — a stale `collector:` misfiles every report
# and nothing else in the suite reads it. Now one of them going stale is a
# failing test, not an archaeology problem six months later.
HDRV=$(sed -n 's/^# hw-inventory\.sh \(v[0-9][0-9]*\) .*/\1/p' "$SCRIPT")
FMV=$(sed -n "s/^printf 'collector: hw-inventory\.sh \(v[0-9][0-9]*\).*/\1/p" "$SCRIPT")
if [ -n "$HDRV" ] && [ "$HDRV" = "$FMV" ]; then
  ok "version agrees in both places ($HDRV)"
else
  bad "version mismatch: header '$HDRV', frontmatter '$FMV'"
fi

# ----------------------------------------------------------------- T2 clean --
head_ "T2  Clean run on an ordinary host"

bash "$SCRIPT" > "$TMP/clean.md" 2> "$TMP/clean.err"; RC=$?
if [ $RC -eq 0 ]; then ok "exits 0"; else bad "exit $RC — a collector on this host warned:"; dumpwarn "$TMP/clean.md"; fi
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
# `strings` is in the list but `edid-decode` deliberately is not: T15 reuses
# this PATH to exercise the EDID fallback, which is otherwise only ever tested
# on machines that happen to lack edid-decode.
for u in bash sh uname hostname date id awk gawk sed grep cat head tail wc ls \
         paste basename timeout sort tr cut strings readlink; do
  p=$(command -v "$u" 2>/dev/null) && ln -sf "$p" "$TMP/minbin/$u"
done

PATH="$TMP/minbin" bash "$SCRIPT" > "$TMP/m.md" 2>"$TMP/m.err"; RC=$?
if [ $RC -eq 0 ]; then ok "exits 0 when tools are merely absent"; else bad "exit $RC — absent tools must not warn:"; dumpwarn "$TMP/m.md"; fi
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

# ------------------------------------------------------- T12 empty docker ----
# The other half of T11's stub, which always answers with 105 containers. A
# daemon that answers `docker info` with zero containers is past the section
# gate and healthy, so it must produce a complete report and exit 0 — but it
# leaves CNAMES empty, which once left DNET unset and killed the script under
# `set -u` at the emptiness test. That failure is the silently-incomplete
# report the exit-code contract exists to prevent: truncated mid-section, no
# footer, no warnings block, and still exit 1, so a caller checking only $?
# could not tell it from an honest incomplete collection.
head_ "T12  Docker daemon with zero containers"

mkdir -p "$TMP/emptydocker"
cat > "$TMP/emptydocker/docker" << 'EMPTYEOF'
#!/bin/sh
case "$1" in
  info) exit 0 ;;
  version) echo "Docker 28.0.0" ;;
  # Real docker prints the table header even with nothing to list, and prints
  # nothing at all for the bare --format form. Both are reproduced: the header
  # is exactly the "prints a banner with no records" shape that makes an
  # emptiness test the wrong check elsewhere in this script.
  ps)
    if printf '%s' "$*" | grep -q 'table'; then
      printf 'NAMES     IMAGE     STATUS    PORTS\n'
    fi
    ;;
  # Never reached while the CNAMES guard holds. If a later change drops it,
  # `docker inspect` runs with no container arguments — a usage error on real
  # docker. Detect that from the report, not stderr (T11's lesson: the script
  # runs inspect under 2>/dev/null, so stderr is invisible to the test).
  inspect)
    shift
    while [ "$1" = "-f" ]; do shift 2; done
    [ $# -eq 0 ] && echo "/INSPECT-CALLED-WITH-NO-CONTAINERS|bogus=1 "
    ;;
esac
EMPTYEOF
chmod +x "$TMP/emptydocker/docker"

PATH="$TMP/emptydocker:$PATH" bash "$SCRIPT" > "$TMP/ed.md" 2>"$TMP/ed.err"; RC=$?

[ ! -s "$TMP/ed.err" ] && ok "stderr empty (no unbound-variable abort)" \
  || { bad "stderr not empty:"; sed 's/^/        /' "$TMP/ed.err"; }
grep -q 'End of report' "$TMP/ed.md" && ok "report reaches its footer" || bad "report truncated before the footer"
if [ $RC -eq 0 ]; then
  ok "exits 0 — zero containers is healthy, not a warning"
else
  bad "exit $RC — expected 0; the warnings below say which collector, and it may be an unrelated one:"
  dumpwarn "$TMP/ed.md"
fi
# Note this fires on ANY warning, not only a docker one — it is coupled to
# whatever else happens to be installed on the host running the suite. Read the
# dump above before blaming the docker section.
if grep -q '^## Collection warnings' "$TMP/ed.md"; then
  bad "zero containers produced a warning"
else
  ok "no warning for zero containers"
fi
# The gate passed, so the section must still be present: a test that merely
# checked for a complete report would also pass if Docker were skipped entirely.
grep -q '^### Docker' "$TMP/ed.md" && ok "Docker section still emitted" || bad "Docker section missing"
grep -q 'INSPECT-CALLED-WITH-NO-CONTAINERS' "$TMP/ed.md" \
  && bad "docker inspect was called with no container arguments" \
  || ok "docker inspect not called without containers"
# Section-output convention: absent hardware never leaves a bare table header.
grep -q 'Container networks' "$TMP/ed.md" \
  && bad "empty container-networks table header emitted" || ok "no bare container-networks header"

# --------------------------------------------------------- T13 hook: verbs ---
# The read-only rule now has an enforcement layer as well as its prose, and a
# hook that is present and inert looks exactly like a hook that works. So it is
# tested from both sides: a write verb must be refused, and every read-class verb
# the script actually uses must survive. The pass half is the important one —
# an over-eager matcher that blocks `zpool list` gets switched off within a day,
# and then nothing is enforcing anything.
head_ "T13  Read-only hook (.claude/hooks/no-write-verbs.sh)"

HOOK="$HERE/../.claude/hooks/no-write-verbs.sh"
if ! command -v jq >/dev/null 2>&1; then
  printf '  \033[33mSKIP\033[0m  jq not installed\n'
elif [ ! -r "$HOOK" ]; then
  bad "hook missing: $HOOK"
else
  # try <expected-exit> <label> <command>
  try() {
    printf '%s' "$3" | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}' \
      | bash "$HOOK" >/dev/null 2>&1
    R=$?
    [ "$R" -eq "$1" ] && ok "$2" || bad "$2 — exit $R, expected $1"
  }

  try 2 'blocks mdcmd'                 'mdcmd status'
  try 2 'blocks zpool scrub'           'zpool scrub tank'
  try 2 'blocks a docker write verb'   'docker run -it alpine sh'
  try 2 'blocks pct stop'              'pct stop 202'
  try 2 'blocks smartctl -t'           'smartctl -t short /dev/sda'
  try 2 'blocks modprobe'              'modprobe ipmi_si'
  try 2 'blocks ddcutil'               'ddcutil detect'
  try 2 'blocks mount'                 'mount /dev/sdb1 /mnt'
  try 2 'blocks a package manager'     'pacman -S shellcheck'
  try 2 'blocks ipmitool chassis'      'ipmitool chassis power status'
  # Command position, not bare word: the verb must still be caught when it is
  # not the first thing on the line.
  try 2 'catches it behind sudo'       'sudo mdcmd status'
  try 2 'catches it after a pipe'      'echo hi | zpool import -a'
  try 2 'catches it after a semicolon' 'ls /tmp; docker rm -f c1'
  try 2 'catches it in a subshell'     '(cd /tmp && docker pull alpine)'

  # Everything hw-inventory.sh actually runs.
  try 0 'allows zpool list'            'zpool list -H -o name,size,health'
  try 0 'allows docker inspect'        'docker inspect -f "{{.Name}}" c1'
  try 0 'allows pct list'              'pct list'
  try 0 'allows qm list'               'qm list'
  try 0 'allows btrfs filesystem show' 'btrfs filesystem show'
  try 0 'allows findmnt'               'findmnt -rno TARGET,SOURCE'
  try 0 'allows smartctl -H -A'        'smartctl -H -A -n standby /dev/sda'
  try 0 'allows ipmitool sel list'     'ipmitool sel list last 20'
  try 0 'allows storcli show'          'storcli64 /c0 show all'
  try 0 'allows mountpoint'            'mountpoint -q /mnt'
  # A verb named in order to reject it is documentation, not an invocation —
  # the same reason T1 strips comments before its own banned-verb grep.
  try 0 'allows the mdcmd comment'     '# mdcmd is not used: it writes /proc/mdcmd'
  try 0 'allows a verb as an argument' 'grep -rn "mdcmd" docs/ README.md'
fi

# ---------------------------------------------------- T14 hook: leak shapes ---
# The publishing rule's mechanical half. Two commits in this repo's history
# exist only to repair leaks of exactly these shapes, and both were caught by a
# human reading the file afterwards.
#
# Every address and MAC below is ASSEMBLED FROM OCTETS, never written whole.
# That is not decoration: this file is committed to the public repo the hook
# guards, and a literal private-range address here would be the very thing the
# pre-commit hook refuses to accept. The test data cannot be a copy of what the
# rule forbids.
head_ "T14  Publishing hook (.claude/hooks/no-estate-identity.sh)"

LHOOK="$HERE/../.claude/hooks/no-estate-identity.sh"
if ! command -v jq >/dev/null 2>&1; then
  printf '  \033[33mSKIP\033[0m  jq not installed\n'
elif [ ! -r "$LHOOK" ]; then
  bad "hook missing: $LHOOK"
else
  # CI-002. The refusal is asserted unconditionally, against a COPY of the hook
  # in a temp tree with no pattern list beside it, so the absence is synthetic
  # rather than a property of whoever runs the suite. It used to live in the
  # skip branch, which meant it ran only where the list was missing — never on
  # the maintainer's machine, and, once CI was given a list, nowhere at all.
  # This is the hook's single most important property: refusing to run is what
  # stops it from being present and inert.
  mkdir -p "$TMP/inerthook/hooks"
  cp "$LHOOK" "$TMP/inerthook/hooks/"
  printf '%s' 'x' | jq -Rs '{tool_name:"Write",tool_input:{content:.}}' \
    | bash "$TMP/inerthook/hooks/no-estate-identity.sh" --hook >/dev/null 2>&1
  [ $? -eq 2 ] && ok "refuses to run when the private list is absent" \
                || bad "ran without a private list — an inert hook looks like a working one"
fi

if ! command -v jq >/dev/null 2>&1 || [ ! -r "$LHOOK" ]; then
  : # already reported above
elif [ ! -r "$HERE/../.claude/private-patterns.local" ]; then
  # The list is gitignored by design, so a fresh clone that has not run the
  # README's setup step legitimately lacks it. CI now copies the example into
  # place — see the workflow — because everything below tests the BUILT-IN
  # shapes and the tracked-file sweep, none of which read the private list's
  # contents. Skipping them there left the publishing rule's only enforcement
  # unverified on every push, which is the same shape of gap as CI-001.
  printf '  \033[33mSKIP\033[0m  no private-patterns.local (run the README setup step)\n'
else
  # A list that exists but holds no patterns is the one state that looks exactly
  # like protection and is not: the hook starts, the built-in shapes run, and
  # the names, hostnames and vault this file exists to catch are unguarded. It
  # is also reachable by accident — an agent session in this repo overwrote the
  # local list with the example by misfiring a `cp`, and nothing noticed, which
  # is precisely why this check exists. In CI that state is deliberate, so it is
  # a note there and a failure everywhere else.
  # `grep -c` exits 1 on a count of zero, so the fallback is an assignment, not
  # an `|| echo 0` — that appends a second line and `[` then refuses the pair.
  PATCOUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$HERE/../.claude/private-patterns.local" 2>/dev/null) || PATCOUNT=0
  if [ "$PATCOUNT" -gt 0 ]; then
    ok "private list holds $PATCOUNT pattern(s)"
  elif [ -n "${CI:-}" ]; then
    printf '  \033[33mNOTE\033[0m  private list is the example copy (0 patterns) — expected in CI\n'
  else
    bad "private list has 0 patterns — built-in shapes still run, but names and hostnames are NOT protected"
  fi

  P1=10; P2=192.168; P3=172.20; P4=100.101      # RFC 1918 x3, then CGNAT
  # One octet per variable, the device half included. Writing the last three
  # octets together would itself be an OUI-shaped triple, and the hook rejects
  # one — as it did on the commit that added this test, and again on the edit
  # that tried to explain why in a comment quoting the offending form. That is
  # the shortest available proof that the matcher is not inert.
  H1=3c; H2=ec; H3=ef; H4=1a; H5=2b; H6=3c
  OUI="$H1:$H2:$H3"; MAC="$OUI:$H4:$H5:$H6"

  ltry() { # ltry <expected-exit> <label> <text>
    printf '%s' "$3" | jq -Rs '{tool_name:"Write",tool_input:{content:.}}' \
      | bash "$LHOOK" --hook >/dev/null 2>&1
    R=$?
    [ "$R" -eq "$1" ] && ok "$2" || bad "$2 — exit $R, expected $1"
  }

  ltry 2 'blocks an RFC 1918 /8 address'   "answers on $P1.0.4.17 today"
  ltry 2 'blocks an RFC 1918 /16 address'  "gateway is $P2.1.1"
  ltry 2 'blocks an RFC 1918 /12 address'  "bridge sits on $P3.0.9"
  ltry 2 'blocks CGNAT / tailnet space'    "reachable at $P4.7.9"
  ltry 2 'blocks a real MAC'               "link/ether $MAC"
  ltry 2 'blocks a bare vendor OUI'        "prefix $OUI is a real card"
  ltry 2 'scans a Bash command too'        "gh issue comment 1 -b 'on $P2.0.30'"

  # The pass half. Fixtures are REQUIRED to use these ranges, so a hook that
  # rejects them makes the rule unfollowable — this is the over-eager direction,
  # and it is the one that gets a hook switched off.
  ltry 0 'allows RFC 5737 TEST-NET-1'      'fixture address 192.0.2.15'
  ltry 0 'allows RFC 5737 TEST-NET-2'      'iSCSI target at 198.51.100.5:3260'
  ltry 0 'allows RFC 5737 TEST-NET-3'      'bridge=203.0.113.1'
  ltry 0 'allows an RFC 7042 doc MAC'      'link/ether 00:00:5e:00:53:af brd ff:ff:ff:ff:ff:ff'
  ltry 0 'allows the broadcast MAC'        'brd ff:ff:ff:ff:ff:ff'
  ltry 0 'allows a clock time'             'finished at 10:24:31 after 12:00:05'
  ltry 0 'allows the GitHub handle'        'published by foxythefoxer under MIT'
  ltry 0 'allows a host named by class'    'measured on a Proxmox LXC and an Unraid box'
  ltry 0 'allows a hardware model'         'VX2768-2KP on DP-1, edid 128 bytes, mode 0444'
  ltry 0 'allows a loopback address'       'listening on 127.0.0.1:8080'

  # commit-msg mode: the publishing rule names commit messages explicitly, and
  # a pre-commit hook runs before there is one.
  printf 'Fix the probe\n\nSeen on %s.0.4.14 last night.\n' "$P1" > "$TMP/msg"
  bash "$LHOOK" --file "$TMP/msg" >/dev/null 2>&1
  [ $? -eq 2 ] && ok "blocks a commit message carrying an address" || bad "commit-msg mode did not block"
  printf 'Fix the probe\n\nMeasured on a Proxmox LXC.\n' > "$TMP/msg"
  bash "$LHOOK" --file "$TMP/msg" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "passes a commit message naming a host class" || bad "clean commit message was blocked"

  # Every tracked file must pass. This is the regression test that matters: the
  # fixtures are full of documentation-range addresses and MACs on purpose, and
  # a matcher that flags them makes the whole repo uncommittable.
  LEAKY=0
  for f in $(cd "$HERE/.." && git ls-files 2>/dev/null); do
    printf '%s' "$(cat "$HERE/../$f")" | jq -Rs '{tool_name:"Write",tool_input:{content:.}}' \
      | bash "$LHOOK" --hook >/dev/null 2>&1 || { LEAKY=$((LEAKY+1)); echo "        flagged: $f"; }
  done
  [ "$LEAKY" -eq 0 ] && ok "no tracked file trips the matcher" || bad "$LEAKY tracked file(s) flagged"
fi

# ------------------------------------------------------------ T15 displays ---
# FR-001. The three conditions that came out of adjudicating it are exactly the
# three that a naive implementation gets wrong, so each is asserted separately:
# a zero-STAT-but-non-empty edid must produce a row, a Writeback connector must
# not, and the section must never warn.
#
# The fixture EDID is synthetic, not a dump of a real panel: a report's serials
# belong on the operator's disk, never in this repo. It is a valid 1.3 blob, so
# `edid-decode` parses it where installed and `strings` recovers the same two
# strings where it is not — CI has neither guaranteed, hence assertions that
# hold either way.
head_ "T15  Display detection via DRM EDID"

sed -e "s#/sys/class/drm#$FIX/drm#g" "$SCRIPT" > "$TMP/drm.sh"
bash "$TMP/drm.sh" > "$TMP/d.md" 2>"$TMP/d.err"

# Binary read through a shell variable is the trap here: a raw EDID captured in
# a command substitution makes bash write "ignored null byte in input" to
# stderr, which T2 would only catch on a machine that has a monitor attached.
[ ! -s "$TMP/d.err" ] && ok "stderr empty (no NUL-byte warning from the EDID read)" \
  || { bad "stderr not empty:"; sed 's/^/        /' "$TMP/d.err"; }
# Never warns — asserted against the warnings block, NOT against the exit code.
# An unrelated collector failing on whatever host runs this (a CI runner with no
# real block devices, say) would fail an `exit 0` assertion for reasons that have
# nothing to do with displays, and a test that red-lines on someone else's
# problem gets ignored. T2 and T8 own the exit-code contract.
sed -n '/^## Collection warnings/,$p' "$TMP/d.md" | grep -qiE 'edid|display|drm|monitor' \
  && bad "the display section produced a warning" || ok "display section never warns"
grep -q '^| card1-DP-1 |' "$TMP/d.md" && ok "connector row emitted" || bad "connector row missing"
grep -q 'TESTMON-27' "$TMP/d.md" && ok "product name recovered" || bad "product name missing"
grep -q 'SN0123456789' "$TMP/d.md" && ok "panel serial recovered" || bad "panel serial missing"
grep -q 'card1-DP-2' "$TMP/d.md" \
  && bad "disconnected connector (0-byte edid) produced a row" || ok "0-byte edid produces no row"
# The stat-0 trap, and the only assertion here that a plain file cannot make:
# EVERY real edid attribute reports `stat -c%s` = 0, including the ones handing
# back a full 256 bytes, so a `[ -s ]` gate skips every monitor on the host. A
# committed fixture cannot reproduce that — a 128-byte file has a 128-byte stat
# — so card1-DP-8/edid is a symlink to a procfs file, which is the one thing
# available that stats as 0 and still reads non-empty. Its contents are not an
# EDID and are not meant to be: the assertion is that the ROW EXISTS AT ALL.
# Without this case the size-gate defect passes the whole suite, which is how
# it was found here.
grep -q '^| card1-DP-8 |' "$TMP/d.md" \
  && ok "stat-0 but non-empty edid still produces a row" \
  || bad "gated on file size, not bytes read — every real monitor would be skipped"
# Excluded BY NAME, and the fixture proves it: card1-Writeback-1 holds the same
# valid EDID as card1-DP-1, so an emptiness filter alone would let it through.
grep -q 'Writeback' "$TMP/d.md" \
  && bad "Writeback connector emitted as a physical display" || ok "Writeback connector excluded"

# The `strings` fallback, forced. Without this the two parser paths are each
# tested only on hosts that happen to lack the other tool — this machine has
# edid-decode and CI does not, so neither run covers both. $TMP/minbin is T8's
# stripped PATH, which carries `strings` and deliberately not `edid-decode`.
PATH="$TMP/minbin" bash "$TMP/drm.sh" > "$TMP/dnodec.md" 2>"$TMP/dnodec.err"
[ ! -s "$TMP/dnodec.err" ] && ok "fallback: stderr empty" \
  || { bad "fallback: stderr not empty:"; sed 's/^/        /' "$TMP/dnodec.err"; }
grep -q 'TESTMON-27' "$TMP/dnodec.md" && grep -q 'SN0123456789' "$TMP/dnodec.md" \
  && ok "fallback: strings recovers name and serial without edid-decode" \
  || bad "fallback: strings path lost the name or the serial"
grep -q 'edid-decode` is not installed' "$TMP/dnodec.md" \
  && ok "fallback: report says the two values are not separated" || bad "fallback: no note that the column is raw EDID text"

# ----------------------------------------------------------------- T16 UPS ---
# FR-002. The load-bearing condition is that the sysfs idVendor read is the
# PRIMARY signal, not a fallback: the fixture supplies only sysfs, and no
# apcupsd/NUT/power_supply state exists on the runner, so a row can only come
# from the file read. The negative half matters as much — most hosts have no
# UPS, and a section that printed "none detected" would break the standing
# rule that a section prints only when it has something to say.
head_ "T16  UPS data-connection detection"

sed -e "s#/sys/bus/usb/devices#$FIX/usb#g" \
    -e "s#/etc/apcupsd/apcupsd.conf#$FIX/apcupsd/apcupsd.conf#g" "$SCRIPT" > "$TMP/usb.sh"
bash "$TMP/usb.sh" > "$TMP/ups.md" 2>"$TMP/ups.err"

[ ! -s "$TMP/ups.err" ] && ok "stderr empty" || { bad "stderr not empty:"; sed 's/^/        /' "$TMP/ups.err"; }
# Same reasoning as T15: the warnings block, not the exit code. Upper-case UPS
# on purpose, so the pattern does not match "groups" in an unrelated warning.
sed -n '/^## Collection warnings/,$p' "$TMP/ups.md" | grep -qE 'UPS|apcupsd|apcaccess|upower|power_supply' \
  && bad "the UPS section produced a warning" || ok "UPS section never warns"
grep -q '^### UPS' "$TMP/ups.md" && ok "section emitted from the sysfs read alone" || bad "no UPS section"
grep -q 'FIXTURE-UPS-1500' "$TMP/ups.md" && ok "device product name read" || bad "product name missing"
grep -q '0764:0601' "$TMP/ups.md" && ok "vendor:product IDs read" || bad "USB IDs missing"
grep -q 'driver usbhid' "$TMP/ups.md" && ok "bound interface driver resolved" || bad "driver not resolved"
# The whitelist is the whole filter. A keyboard on the same bus must not become
# a UPS row, or the section reports every USB device on the host.
grep -q 'FIXTURE-KEYBOARD' "$TMP/ups.md" \
  && bad "a non-UPS USB device was reported as a UPS" || ok "non-UPS vendor ID filtered out"

# The second signal: configured intent, readable whether or not the daemon is
# running. Whitelisted keys, so the same assertion T4 makes about var.ini's
# csrf_token applies here — this file is parsed, never dumped.
grep -q 'CANARY_APCUPSD_MUST_NOT_LEAK' "$TMP/ups.md" \
  && bad "SECRET LEAK: a non-whitelisted apcupsd.conf key appeared in output" \
  || ok "non-whitelisted apcupsd.conf keys not emitted"
grep -q 'UPSCABLE=usb' "$TMP/ups.md" && ok "apcupsd config read" || bad "apcupsd config missing"

# Nothing attached, nothing installed: no section at all. $TMP/minbin is T8's
# stripped PATH, reused so that upower and apcaccess are genuinely absent, and
# the config path is pointed at nothing — without both, this half passes or
# fails depending on what happens to be installed on whoever's machine runs it.
sed -e "s#/sys/bus/usb/devices#$TMP/no-such-usb#g" \
    -e "s#/etc/apcupsd/apcupsd.conf#$TMP/no-such-apcupsd.conf#g" "$SCRIPT" > "$TMP/noups.sh"
PATH="$TMP/minbin" bash "$TMP/noups.sh" > "$TMP/noups.md" 2>/dev/null
grep -q '^### UPS' "$TMP/noups.md" \
  && bad "UPS section printed with no UPS present" || ok "silent when no UPS is detected"

# ------------------------------------------------------------------ T17 PCI --
# CI-001. This reproduces a host class no machine here is: a VM whose NIC and
# disks are paravirtual, so `lspci -nnk` prints a full listing that matches none
# of the section's device-class keywords. That is absent hardware, which the
# contract says is silent — but the warning was gated on the FILTERED output, so
# the script called the host broken and exited 1. Every CI run this workflow has
# ever made was red for that reason, and the failures landed on T2 and T12,
# which look like docker and displays problems and are not.
head_ "T17  PCI section on a host with no matching devices"

mkdir -p "$TMP/pcibin"
cat > "$TMP/pcibin/lspci" << 'PCIEOF'
#!/bin/sh
# A Hyper-V/KVM-shaped guest: bridges and a PIIX4 only. Nothing in this listing
# matches vga|ethernet|raid|sata|non-volatile|serial attached, which is the
# whole point — the bus enumerated fine, the host simply has none of them.
cat << 'INNER'
00:00.0 Host bridge [0600]: Intel Corporation 440BX/ZX/DX [8086:7192]
00:07.0 ISA bridge [0601]: Intel Corporation 82371AB/EB/MB PIIX4 ISA [8086:7110]
00:07.3 Bridge [0680]: Intel Corporation 82371AB/EB/MB PIIX4 ACPI [8086:7113]
INNER
PCIEOF
chmod +x "$TMP/pcibin/lspci"

PATH="$TMP/pcibin:$PATH" bash "$SCRIPT" > "$TMP/pci.md" 2>/dev/null; RC=$?
if [ $RC -eq 0 ]; then
  ok "exits 0 — no matching PCI devices is absent hardware, not a failure"
else
  bad "exit $RC — a filtered-empty PCI list must not warn:"; dumpwarn "$TMP/pci.md"
fi
grep -q 'lspci -nnk' "$TMP/pci.md" \
  && bad "warned about lspci -nnk although it returned a full listing" \
  || ok "no lspci warning when the filter simply matched nothing"
# Section-output convention: no bare heading, and no empty code fence either —
# the fence is why T2's empty-table-header check never caught this.
grep -q '^### Notable PCI devices' "$TMP/pci.md" \
  && bad "PCI section emitted with no devices to list" || ok "PCI section omitted, not left empty"

# The other direction, and the reason the warning exists at all: plain `lspci`
# answers, `-nnk` does not. That IS a present-and-permitted tool returning
# nothing, so it must warn and exit 1. Without this half, deleting the warning
# outright would pass the test above.
cat > "$TMP/pcibin/lspci" << 'PCIEOF'
#!/bin/sh
for a in "$@"; do case "$a" in -*k*) exit 0 ;; esac; done
echo "00:1f.6 Ethernet controller [0200]: Intel Corporation I219-V [8086:15b8]"
PCIEOF
chmod +x "$TMP/pcibin/lspci"

PATH="$TMP/pcibin:$PATH" bash "$SCRIPT" > "$TMP/pci2.md" 2>/dev/null; RC=$?
[ $RC -eq 1 ] && ok "exits 1 when lspci -nnk alone returns nothing" || bad "exit $RC — expected 1"
grep -q 'lspci -nnk' "$TMP/pci2.md" \
  && ok "warning names lspci -nnk" || bad "no warning although -nnk returned nothing"

# ---------------------------------------------------------------- summary ----
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
