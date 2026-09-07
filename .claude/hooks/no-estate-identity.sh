#!/usr/bin/env bash
# Refuse to write or commit estate identity into this public repository.
#
# Two commits in this repo's own history exist only to repair leaks of exactly
# this kind — d5c6c65 "Stop leaking estate identity into a public repo" and
# 5f7893d "Narrow the issue-text rule; bar the maintainer's own name". Both were
# caught by a human reading the file afterwards, which is not a control. These
# are shapes a matcher can see, so a matcher sees them now.
#
# THREE MODES, because a PreToolUse hook only sees what an agent writes:
#
#   --hook     PreToolUse. Reads the tool payload as JSON on stdin and scans the
#              content of a Write, the new text of an Edit, and the whole Bash
#              command — the last one because `gh issue comment -b "..."` is how
#              a verdict gets posted, and the issue tracker is public surface
#              whose replies are this session's to leak.
#   --staged   git pre-commit. Scans the added lines of the staged diff. This is
#              the one that covers a hand-edit, which no PreToolUse hook sees.
#   --file F   git commit-msg. The publishing rule names commit messages
#              explicitly, and a pre-commit hook cannot see the message.
#
# WHAT IT CANNOT DO. It matches shapes, not judgment. The prose rule in the
# always-loaded instructions is not redundant with this and must not be deleted
# as though it were: no matcher can see a description of network topology, a
# named private vault, or a real name it has not been told about. That is why
# the private list below exists, and why it is required rather than optional.
#
# A NOTE ON THE ESCAPING, so nobody "simplifies" it into a self-match: every
# address pattern below is written with escaped dots and bracket classes, so the
# script's own source does not contain a string its own regexes match. Replace
# `10\.[0-9]{1,3}` with a literal address in a comment and this hook starts
# refusing to let anyone edit it.

set -u

MODE="${1:---hook}"
HERE=$(cd "$(dirname "$0")" && pwd)
PRIVATE="$HERE/../private-patterns.local"

# (c) A hook that is present and inert looks exactly like a hook that is working.
# The private list holds the patterns that cannot live in a published file — the
# maintainer's own name is the load-bearing one, and this script is committed —
# so a fresh clone has no copy of it. That must be loud, not silent.
if [ ! -r "$PRIVATE" ]; then
  cat >&2 <<EOF
no-estate-identity: the private pattern list is missing, so leak detection is
NOT running. This is a hard failure on purpose — a hook that quietly does
nothing is worse than no hook, because it looks like protection.

  expected: .claude/private-patterns.local   (gitignored, never committed)
  create it: cp .claude/private-patterns.example .claude/private-patterns.local
             then add the names and hostnames this repo must never publish.

The file is local-only by construction: the publishing rule bars the
maintainer's own name from this repository, and this script is committed to it.
EOF
  exit 2
fi

# --- gather the text to scan --------------------------------------------------
case "$MODE" in
  --hook)
    command -v jq >/dev/null 2>&1 || {
      echo "no-estate-identity: jq is required for --hook mode and is not installed." >&2
      exit 2
    }
    INPUT=$(cat)
    TEXT=$(jq -r '[.tool_input.content?, .tool_input.new_string?, .tool_input.command?]
                  | map(select(type == "string")) | join("\n")' <<<"$INPUT" 2>/dev/null)
    WHERE="this $(jq -r '.tool_name // "tool"' <<<"$INPUT") call"
    ;;
  --staged)
    # Added lines only. A diff that removes a leaked address must not be blocked
    # by the address it is removing — that is precisely the repair commit.
    TEXT=$(git diff --cached --unified=0 | sed -n 's/^+//p')
    WHERE="the staged changes"
    ;;
  --file)
    TEXT=$(cat "${2:?--file needs a path}")
    WHERE="the commit message"
    ;;
  *)
    echo "no-estate-identity: unknown mode '$MODE'" >&2; exit 2 ;;
esac

[ -n "${TEXT:-}" ] || exit 0

# Blank the documentation ranges first: RFC 5737 addresses are not matched by the
# private-range patterns anyway, but RFC 7042 MACs would be caught by any general
# MAC shape, and they are the ones fixtures are *required* to use.
#
# The broadcast and all-zero MACs go with them. They identify nothing, and they
# sit on the same `ip link` line as every real MAC — so leaving them in means the
# hook rejects the exact fixture the publishing rule tells you to write.
SCAN=$(printf '%s\n' "$TEXT" \
  | sed -E -e 's/00[:-]00[:-]5[Ee][:-]00[:-]53[:-][0-9A-Fa-f]{2}/DOC-MAC/g' \
           -e 's/00[:-]00[:-]5[Ee]/DOC-OUI/g' \
           -e 's/([Ff]{2}[:-]){5}[Ff]{2}/BROADCAST-MAC/g' \
           -e 's/(00[:-]){5}00/NULL-MAC/g')

FOUND=""
look() { # look <regex> <what it is> [<regex the match must ALSO contain>]
  local hits
  hits=$(printf '%s\n' "$SCAN" | grep -oEi "$1" | head -5) || return 0
  [ -n "${3:-}" ] && hits=$(printf '%s\n' "$hits" | grep -E "$3")
  [ -n "$hits" ] && FOUND="${FOUND}
  $2
$(printf '%s\n' "$hits" | sed -e 's/^[^0-9A-Za-z]*//' -e 's/[^0-9A-Za-z]*$//' -e 's/^/      /')"
  return 0
}

OCT='[0-9]{1,3}'
look "(^|[^0-9.])(10\.$OCT\.$OCT\.$OCT|192\.168\.$OCT\.$OCT|172\.(1[6-9]|2[0-9]|3[01])\.$OCT\.$OCT)([^0-9.]|$)" \
     "an RFC 1918 private address. Fixtures use RFC 5737: 192.0.2.x, 198.51.100.x, 203.0.113.x."
look "(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.$OCT\.$OCT([^0-9.]|$)" \
     "a 100.64/10 address — CGNAT space, which is where a tailnet lives."
look "(^|[^0-9A-Fa-f:-])([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}([^0-9A-Fa-f:-]|$)" \
     "a MAC address outside the RFC 7042 documentation range 00:00:5E:00:53:00-FF."
# Bare OUI: three colon-separated octets, at least one of which contains a hex
# letter — which a clock time cannot. A time of day passes; a vendor prefix does
# not. The letter requirement is the whole pattern: without it this flags every
# timestamp in every log paste, which is how a hook gets switched off. It is the
# weakest matcher here and deliberately not stricter.
#
# No example of either form is written out here, for the same reason the address
# patterns above are escaped: a comment quoting a vendor prefix makes this file
# fail its own check. It did, once.
look "(^|[^0-9A-Fa-f:-])([0-9A-Fa-f]{2}:){2}[0-9A-Fa-f]{2}([^0-9A-Fa-f:-]|$)" \
     "an OUI-shaped hex triple. If it is a vendor prefix it is estate identity; if it is a timestamp, reword it." \
     '[A-Fa-f]'
# An empty alternation is the trap here: `grep -E ""` matches every line, so a
# pattern file holding nothing but comments would block all work rather than
# none of it. Test for emptiness before using it, not after.
PRIVATE_RE=$(grep -vE '^[[:space:]]*(#|$)' "$PRIVATE" | paste -sd'|' -)
if [ -n "$PRIVATE_RE" ]; then
  look "$PRIVATE_RE" \
     "a string from the private pattern list — a name, hostname or label this repo must never publish."
fi

[ -n "$FOUND" ] || exit 0

cat >&2 <<EOF
Blocked by the publishing rule: $WHERE contains estate identity.
$FOUND

This repository is public. Everything committed is published — the ledger, the
fixtures, the commit messages and the issue replies. Serials, MACs and IPs are
exactly what hw-inventory.sh exists to EMIT; the distinction is where the data
lands. Writing a host's identity into a report on the operator's own disk is the
product. Committing it here is disclosure.

  - Identify a host by CLASS: "a Proxmox LXC", "a whitebox AM5 desktop".
  - Keep the measurement, drop the machine. Byte counts, file modes, timings and
    hardware models carry the argument and are all publishable.
  - Fixtures use the documentation ranges, RFC 5737 and RFC 7042, so that a
    reader — or a scanner — can tell them apart from a live address.

If this is a false positive, a human can decide: \`git commit --no-verify\` for a
commit, or say so here for a tool call. Do not edit the pattern list to get past
it.
EOF
exit 2
