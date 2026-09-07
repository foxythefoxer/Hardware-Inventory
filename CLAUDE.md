# Maintainer notes for `hw-inventory.sh`
<!--
This file is loaded into EVERY session. It was 362 lines; most of that was
justification for rules rather than the rules themselves, paid for on every
session including the ones that never touch the script — of the last 34 commits,
18 touched no code at all.

Two things carry the bulk now, and neither loses anything:

  - HTML comments like this one are stripped before any of this reaches the
    model's context, and stay visible when a human opens the file. Verified by
    test, 2026-09-06. Reasoning and provenance are therefore free here, and
    belong here rather than in prose.

  - `.claude/rules/collectors.md` carries `paths:` frontmatter, so it loads when
    hw-inventory.sh, tests/ or the ledger is read rather than at launch.
    Verified on this machine, 2026-09-07, Claude Code 2.1.263, with an unscoped
    rules file as the control.

WHAT STAYED, and the test for it: a rule stays here if it must hold before any
file is opened, or if no hook can check it. The read-only principle generalises
to cases the ban list does not name. The config clause is the part a matcher
cannot see — it is what caught fastfetch. The publishing principle covers issue
replies and judgment about topology, which no shape-matcher sees.

Nothing was deleted. Everything below points at where it went.
-->
Read this before proposing any change. Two rules govern everything here; the table at the bottom routes the rest.

---

## The one inviolable rule

**This script is read-only. Every command must be a query.**

Not "read-only by default." Not "read-only unless the user asks." A change that
introduces a write is rejected regardless of how useful the data would be. If a
feature appears to require a write, the answer is to find the read-only path or
to leave the data uncollected.

This is the design's whole point, not a safety property incidental to it: the
script was built read-only from the start so it could eventually run unattended —
a cron job, a scheduled sweep — without a human confirming each run against
production hosts first. A write-capable script would need that human in the loop
every time; this one doesn't, by construction. **A change that introduces a write
doesn't just add risk, it breaks the reason the script can be automated at all.**
<!-- The worked example, kept for a human: Unraid array state. `mdcmd status` is
     the obvious call, but it works by writing a command string into
     /proc/mdcmd, so the script parses emhttp's .ini files instead. Same data,
     no write. That is the shape of every correct answer here. -->
**The ban covers the tool's config, not just its verb.** A banned-verb list can
only describe commands this script writes; it cannot see a tool whose behaviour
is defined by a file on the host. Before adding any dependency, ask what it reads
at startup and whether that can execute. A flag that suppresses it is not
sufficient on its own: it moves the read-only guarantee from this script's source
into a third party's release notes.
<!-- Measured, and the reason that clause exists: `fastfetch` auto-loads
     config.jsonc from five search paths — /etc/fastfetch/ among them — and its
     `command` module runs an arbitrary shell string. A bare `fastfetch` with no
     flags created a file on this host, and would do it as root under the
     documented sudo invocation (FR-003). `-c none` does close it, which is
     precisely why the flag is not enough: the guarantee moves off-repo.

     This clause is the half no hook can enforce. `.claude/hooks/no-write-verbs.sh`
     matches verbs in command position; it cannot read a third party's config
     loader. Do not treat the hook as a replacement for this paragraph. -->
The banned verbs themselves are enforced rather than recited: by
`.claude/hooks/no-write-verbs.sh` in a session, and by T1 against the script on
every CI run.
<!-- `ddcutil` is on that list for a reason worth keeping: DDC/CI is
     bidirectional over i2c-dev, so *querying* a monitor writes to it. That is
     why FR-001 reads EDID out of sysfs instead. -->

---

## This repo is public; its inputs are not

`foxythefoxer/Hardware-Inventory` is a public GitHub repository. Everything
committed is published — this file, the ledger, the fixtures, the commit
messages, and the replies posted to issues.

**Never commit estate identity.** No hostnames, IP or MAC addresses, network
topology, tailnet addresses, real names or email addresses. This is not a secrets
rule; serials, MACs and IPs are precisely what the script exists to *emit*. It is
a publishing rule, and the distinction is where the data lands: writing a host's
identity into a report on the operator's own disk is the product, committing it
here is disclosure. **"Real names" includes the maintainer's own** — say
`foxythefoxer`, a handle already public by construction.

The test that settles the cases in between: **`hw-inventory.sh` is generic and
belongs here; its reports are nothing but hostnames, serials and MACs, and never
do.** Never commit a sample report or paste one into a review or a fixture.
Identify a host by class — "a Proxmox LXC", "a whitebox AM5 desktop". Keep the
measurement, drop the machine.

`.claude/hooks/no-estate-identity.sh` blocks the *shapes* on writes, commits and
commit messages. **It is not a substitute for this section:** no matcher sees a
description of topology, a named private vault, or a name it was never told.
<!-- Provenance, for a human: requests arrive as issues filed by a session
     working in a private notes vault documenting a real homelab (FR-003 was
     issue #1), and dispositions get argued from measurements taken on real
     hosts. That session has rules keeping estate detail inside the vault. This
     one is the receiving end, and had none — hence this section.

     Fixtures use the documentation ranges: RFC 5737 for addresses, RFC 7042
     00:00:5E:00:53:00–FF for MACs. Never a private-range address or a real OUI —
     a reader cannot tell those from a live one, and neither can a scanner. T9's
     iSCSI fixture carried a live address until 2026-09-05, which is what that
     rule exists to prevent, and two commits in this history exist only to repair
     leaks of exactly this kind.

     The name rule is the one that slips through, because it looks like ordinary
     attribution rather than data. A private vault addressing its owner by first
     name is correct there and wrong the moment the sentence is copied out. -->
---

## Where everything else lives

| What | Where | Loaded when |
|---|---|---|
| Exit-code contract · Conventions · Rejected proposals · Testing | [`.claude/rules/collectors.md`](.claude/rules/collectors.md) | `hw-inventory.sh`, `tests/**` or the ledger is read |
| Accepted work not yet done, and what's already done | [`docs/QUEUE.md`](docs/QUEUE.md) | You open it |
| Every verdict, with its measurements | [`docs/DISPOSITIONS.md`](docs/DISPOSITIONS.md) | You open it |
| Recording a new verdict, and replying to the issue | `/adjudicate` | You invoke it |
| Verifying a change before committing | `/hw-check` | You invoke it |
| The banned-verb list · leak shapes | `.claude/hooks/` | Every matching tool call, and `git commit` |

**`docs/QUEUE.md` is the only record that an accepted request is still
outstanding.** The filing session stops at submission by design and deletes
accepted items from its own backlog once adjudicated, so nothing outside this
repo will notice if that queue rots.

A fresh clone needs two one-time steps before the git-side hooks do anything —
see **Contributing** in the README.
