---
name: adjudicate
description: Record a verdict on a proposal about hw-inventory.sh — a code-review finding, a feature request filed as a GitHub issue, or an audit finding. Use when accepting, rejecting or deferring any proposed change, when writing a disposition into docs/DISPOSITIONS.md, or when replying to a feature-request issue with a verdict.
---

# Adjudicate a proposal

<!-- This is a skill rather than a rule in the always-loaded instructions because
     it is a procedure invoked at a moment, not a constraint that has to hold
     continuously. It used to be the preamble of CLAUDE.md, loaded into every
     session — including the ~53% of sessions here that are documentation work
     and never adjudicate anything. -->

## Where the verdict goes

Two files, one line each of overlap.

- **`docs/DISPOSITIONS.md`** — the full adjudication: the measurement, the
  binding conditions, what was checked against a real host, what could not be.
- **The always-loaded instructions** — one index line: the verdict and the
  single fact that settles it.

**Never write the paragraph in both places.** The always-loaded file is loaded
into every session; the ledger is opened when the reasoning is actually wanted.
That split is the entire reason the ledger exists — a second copy of a verdict
is a copy that drifts, and it has, three times.

## Pick the ID prefix

**A prefix names a channel. Never a model, never a person.** Numbers are assigned
here, at adjudication, in the order verdicts are written — a reviewer's own
`F-001` is *provenance*, recorded inside the entry beside its vendor and model,
not the id. One channel, one namespace, forever.

The reason is that channels repeat and models do not persist. A rejection filed
under a model's name stops being findable by the next model, and then it gets
re-proposed and re-argued. `C-`/`G-`/`O-` are the counter-example and the lesson:
three models reviewed on one day under three per-model prefixes, which then had
to be renumbered wholesale (`86e6c05`) and left a namespace that can never grow.

| Prefix | Channel |
|---|---|
| `R2-` | The **second code-review round** — one namespace for the whole round however many models run it. `docs/reviews/code-review-prompt-r2.md` is the prompt and the upload manifest. Open-ended: `R3-` for the round after. |
| `FR-` | A request from outside the review cycle, filed as a GitHub issue. Open-ended. |
| `A-` | A whole-repo audit run against the working tree. Open-ended. |
| `CI-` | A finding from the suite running on a GitHub runner. A separate channel because it is a separate host class — nobody read the code to find these, the code ran somewhere that is not this machine and disagreed. Open-ended. |
| `C-` `G-` `O-` | **Closed.** The three round-one reviews in `docs/reviews/` — Claude, Grok, GPT, 2026-08-06. Numbering does not correspond across them, which is why three prefixes exist. Do not add to these; a new review round is `R2-`. |

Adding a channel is a one-line addition to this table plus one to the stream list
at the top of `docs/DISPOSITIONS.md`. Do not reach for a per-model prefix again.

## The rule that keeps breaking

**An index line never enumerates a numbered condition set.**

"Accepted with four binding conditions (a; b; c; d)" is the long form in
miniature, and it drifts exactly as the long form does. Both known cases were
this shape: one index line silently swapped a ledger condition for a sentence
from its preamble, and another said "four" where the ledger listed five —
dropping the one an implementer most needs. Both survived until someone compared
the two files by hand, which is not a control.

State the verdict and the single fact that settles it. The conditions live in
the ledger. For an accepted-with-changes item **the conditions are the
acceptance**, so a summary that omits them is not a shorter version of the
verdict, it is a different one.

## Steps

1. **Check it is not already adjudicated.** Search `docs/DISPOSITIONS.md` for
   the proposal, not just its ID. Reopening a rejection requires new evidence,
   not a fresh opinion.
2. **Write the full entry in `docs/DISPOSITIONS.md`** under its ID. Name the
   measurement — byte counts, exit codes, file modes, timings, hardware models.
   Mark claims **verified** only where you checked the actual file rather than
   reasoning about it, and say explicitly which conditions could *not* be
   verified here and on what host class they still need confirming.
3. **Add one index line** to the always-loaded instructions: verdict plus the
   single settling fact. Under "Agreed work queue" in `docs/QUEUE.md` if it is
   accepted and outstanding; under "Rejected proposals" in
   `.claude/rules/collectors.md` if declined.
4. **If it came in as an issue, reply there** — see below — and only then close.

## The evidence rule

**Name the measurement, not the machine.**

An adjudication is auditable only if it says what was actually checked, so keep
the numbers and the hardware models: a monitor model anyone can buy is not
estate identity. A hostname is a machine on someone's LAN. Where a claim needs
its host identified at all, identify it by class — "a Proxmox LXC", "a whitebox
AM5 desktop", "the Unraid box".

A hostname sat in one FR entry from the day it was written until someone noticed.

## Replying to the issue

The tracker is public surface and **the verdict comment is written by this
session** — a leak there is this session's to make, not the filer's. Everything
in the publishing rule applies to issue text unchanged, plus one thing files do
not tempt you into:

**Do not name the private notes vault or any of its notes.** The filing agent
and its brief may be named — those identify an agent, not an estate. The vault's
name and its filenames carry its internal structure, and a citation like "per
`some-decisions-note.md`, 2026-09-05 entry" reads as courtesy inside the vault
and as disclosure outside it. Quote the measurement, exactly as the ledger does.

**Write it right the first time.** Editing an issue afterwards does not reliably
remove anything — GitHub keeps the prior revision in the edit history.

## After an acceptance

Nothing tracks a request home. The filing session records that it submitted one
and what the verdict was, then stops by design: it does not check whether this
repo implemented anything, and it deletes accepted items from its own backlog
once adjudicated.

`docs/QUEUE.md` is therefore the **only** record that an accepted request is
still outstanding. Nothing outside this repo will notice if it rots.
