#!/usr/bin/env bash
# PreToolUse hook: refuse to run a state-changing command from a session working
# on this repo.
#
# WHY THIS EXISTS, and what it does NOT cover.
#
# The read-only rule is a rule about hw-inventory.sh, and T1 in tests/run.sh
# already greps the script itself for banned verbs on every CI run. That half is
# mechanised. The half nothing checked is the session: an agent reasoning about
# whether `mdcmd status` is safe can simply run it on the host to find out, and
# the answer arrives after the write. This hook closes that, and only that.
#
# So it matches the Bash tool's command, not file content. Content is deliberately
# out of scope: T1 covers the one file where a verb would be a defect, and every
# other occurrence in this repo — the ban list, the README table, the ledger — is
# documentation naming a verb in order to reject it. A content matcher would have
# to be argued out of blocking its own rule book.
#
# Verbs are matched in COMMAND POSITION only: after the start of the command or a
# `;` `&` `|` `(` `)` `{` `}`, with sudo/env/timeout-style prefixes stripped. A
# verb inside an argument — `grep 'mdcmd' docs/` — is data, and passes. Comments
# are stripped first, for the same reason T1 strips them: the header comment in
# hw-inventory.sh deliberately names every verb the script does not use.
#
# Blocking is exit 2 with the reason on stderr; that is the PreToolUse contract.

set -u

command -v jq >/dev/null 2>&1 || {
  echo "no-write-verbs: jq is required for this hook and is not installed." >&2
  exit 2
}

INPUT=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$INPUT")" = "Bash" ] || exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[ -n "$CMD" ] || exit 0

# One command fragment per line, with the noise words that can precede a verb
# removed, so every pattern below can anchor on ^ and mean "in command position".
NORM=$(printf '%s\n' "$CMD" \
  | sed -e 's/#.*//' -e 's/[;&|(){}]/\n/g' \
  | sed -E -e 's/^[[:space:]]+//' \
           -e ':a' -e 's/^(sudo|doas|command|env|nice|nohup|time|xargs|exec)[[:space:]]+//' -e 'ta' \
           -e 's/^timeout[[:space:]]+-?[a-z]*[[:space:]]*[0-9]+[a-z]?[[:space:]]+//')

# Each entry is verb-pair plus a plain-English reason, because a hook that only
# says "blocked" teaches nothing and gets disabled. Read-class verbs are absent
# from every pattern on purpose: `zpool list`, `docker inspect`, `pct list`,
# `qm list`, `btrfs filesystem show` and `ipmitool sdr` are what the script uses.
check() {
  grep -qE "$1" <<<"$NORM" && {
    cat >&2 <<EOF
Blocked by the read-only rule: $2

  command: $CMD

This script is read-only — every command must be a query. Not "read-only by
default": the reason hw-inventory.sh can be automated at all is that nothing it
does needs a human confirming it against a production host. A session working on
it inherits that.

If you need the data, find the read-only path or leave it uncollected. The worked
example is Unraid array state: mdcmd status is the obvious call, but it works by
writing a command string into /proc/mdcmd, so the script parses emhttp's .ini
files instead. Same data, no write.

If this is a false positive — the verb is an argument, not an invocation — say so
and the human can run it.
EOF
    exit 2
  }
  return 0
}

check '^mdcmd\b' \
  'mdcmd writes a command string into /proc/mdcmd. There is no read-only mdcmd.'
check '^modprobe\b' \
  'modprobe loads a kernel module. If the IPMI modules are absent, the report says so.'
check '^ddcutil\b' \
  'DDC/CI is bidirectional over i2c-dev, so querying a monitor writes to it. EDID comes from sysfs.'
check '^u?mount\b' \
  'mount/umount changes the mount table. findmnt and df read it.'
check '^smartctl\b.*[[:space:]]-t([[:space:]]|$)' \
  'smartctl -t starts a self-test. -H -A reads the data already there.'
check '^zpool[[:space:]]+(scrub|import|export|create|destroy|add|remove|attach|detach|replace|offline|online|clear|set|upgrade|initialize|trim|labelclear)\b' \
  'that zpool verb changes pool state. Only list and status -x are used.'
check '^btrfs[[:space:]]+(balance|scrub|device|property[[:space:]]+set|filesystem[[:space:]]+(resize|label|defragment|defrag))\b' \
  'that btrfs verb changes the filesystem. Only filesystem show is used.'
check '^docker[[:space:]]+(run|exec|rm|rmi|pull|push|start|stop|restart|kill|build|create|commit|prune|update|rename|import|load|login)\b' \
  'that docker verb changes container or image state. Only ps, version and inspect are used.'
check '^(pct|qm)[[:space:]]+(start|stop|shutdown|set|create|destroy|clone|enter|exec|reboot|reset|resize|migrate|restore|rollback|snapshot|delsnapshot|template|unlock|suspend|resume|push|pull|mount|unmount|move_disk|move-disk|disk)\b' \
  'that pct/qm verb changes a guest. Only list, config and status are used.'
check '^(perccli|perccli64|storcli|storcli64|megacli|MegaCli|MegaCli64)\b.*([[:space:]]|/)(add|del|delete|set|start|stop|create|import|erase|insert|flash|locate|spinup|spindown)\b' \
  'that is a write verb on a RAID controller CLI. Only show-class verbs are allowed.'

# The one write on this list that no verb pattern can express, because the verb
# is not the problem (R2-001). This CLI family writes a command log into the
# working directory on every invocation unless told not to, so `show` — the
# read verb — still writes. Checking for the absence of the suppressing keyword
# is the only shape that catches it, which is why the guard is inverted here.
# A nolog anywhere in the command excuses the whole command: NORM has already
# split it into fragments and pairing them up buys nothing a session guard
# needs. T1 is the precise gate, against the script itself.
#
# The trailing [-/] is required, not decoration. Every other pattern here names
# a verb after the binary; this one cannot, so without that argument it matches
# a bare word — and NORM splits on `|`, which promotes the `megacli` inside a
# grep alternation to command position. That fired on this repo's own tooling
# the first time it ran. A real invocation always carries /cx or -Flag; a
# mention never does, and a matcher that refuses ordinary work gets switched
# off, which is the failure this whole file is trying not to have.
grep -qiE '(^|[[:space:]])-?no-?log([[:space:]]|$)' <<<"$NORM" \
  || check '^(perccli|perccli64|storcli|storcli64|megacli|MegaCli|MegaCli64)\b[[:space:]]+[-/]' \
       'a RAID controller CLI writes a command log into the working directory unless told not to, so even its show verbs write. Pass nolog (storcli/perccli) or -NoLog (MegaCLI).'
check '^ipmitool\b.*\b(chassis|raw|power|mc[[:space:]]+reset|sel[[:space:]]+clear|user[[:space:]]+set|lan[[:space:]]+set|sol[[:space:]]+(activate|set))\b' \
  'that ipmitool verb changes BMC or chassis state. Only mc info, lan print, sdr and sel list are used.'
check '^(apt|apt-get|aptitude)[[:space:]]+.*\b(install|remove|purge|upgrade|full-upgrade|dist-upgrade|autoremove)\b|^(dnf|yum|zypper)[[:space:]]+.*\b(install|remove|erase|upgrade|update)\b|^pacman[[:space:]]+-[A-Za-z]*[SRU]|^(apk|emerge|snap|flatpak)[[:space:]]+.*\b(add|install|remove|del)\b' \
  'no package manager. The script depends on tools you already have; installing one to satisfy it changes the host.'

exit 0
