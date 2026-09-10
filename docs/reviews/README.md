# Code reviews

Independent reviews of `hw-inventory.sh`, kept here as provenance: they are what the
`C-`, `G-` and `O-` IDs (round one, v4) and the `R2-` IDs (round two, v7) in
[`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) point back at. (R1's were originally filed as
per-reviewer `F-0NN` IDs; `86e6c05` unified them to the one-letter-per-reviewer scheme the
ledger uses. The documents themselves still say `F-`. R2 keeps `F-` inside the document by
design and maps to `R2-` in the ledger — see §4 of the R2 prompt.)

## Read this first

- **Each round is frozen at the commit in its own header**, and only R2 has one that was
  filled in. R1 is `bc32386`, a 651-line script; R2 is `34ca470`, 1,205 lines. Line numbers
  are stale the moment the file moves and are not corrected;
  each file carries a header saying so. Use them to understand *why* a finding was
  raised, never to locate code.
- **These are AI-generated and unedited.** Three models were given the same prompt
  (`code-review-prompt-r1.md`) and the script, with **zero context** about the
  target environment, the design constraints, or what had already been decided. That was
  deliberate, and it bought independence when there was nothing yet to be independent
  *of*. It does not any more: two of the three recommended `set -o pipefail`, which
  measures exit `141` against this script. `code-review-prompt-r2.md` supplies the
  rejection list for exactly that reason.
- **Finding IDs are per-reviewer and do not correspond across documents.** Claude's
  F-001 is a locale issue; Grok's F-001 is brace expansion; GPT's F-001 is loop
  iteration. The old advice here was to cross-reference by line number instead — that
  stopped working when the script outgrew these documents. Cross-reference through the
  ledger, which is what its `C-`/`G-`/`O-` prefixes exist for.
- **Not all findings were accepted.** Several were rejected outright — including one
  recommended by two of the three reviewers that would break the script. See
  [`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) before acting on anything in here.

**If you are about to open a PR based on one of these reviews, read
[`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) first.** It records which findings were
accepted, which were rejected, and why. It sits one level up rather than in this folder
because it is the ledger for every adjudicated proposal, these reviews included but not
only them.

## Contents

| File | What it is |
|---|---|
| `code-review-*--r2--anthropic--claude-opus-5--*` | **Round two**, one reviewer, against v7 at `34ca470`. Summary + detailed, 27 findings: 1 CRITICAL, 3 HIGH, 7 MEDIUM, 11 LOW, 5 NITPICK |
| `code-review-prompt-r2.md` | The prompt that produced the round-two documents above. Includes the upload manifest for a web session with no repository access |
| `code-review-prompt-r1.md` | The prompt given to all three round-one models below. Superseded; kept because those documents are what it produced |
| `code-review-summary--anthropic--claude-opus-5--*` | Summary + detailed, 35 findings |
| `code-review-summary--xai--grok-4-5--*` | Summary + detailed, 7 findings |
| `code-review-summary--openai--gpt-5-5--*` | Summary + detailed, 3 findings |

A second round files under one `R2-` prefix for the whole round, not one per model — see
§4 of the R2 prompt, and "Pick the ID prefix" in `/adjudicate`.

## What the exercise was worth

Mixed, and worth being specific about.

The reviews found one genuine defect the maintainer had introduced (a fallback that was
built and then bypassed at 26 call sites) and one real correctness bug in table
filtering. Both are in the accepted list.

They also demonstrated the limits of static review. **None of the three ran the script.**
Every real bug found in this project's history has been a hang rather than an error —
including the one that was caught, by an execution test, before these reviews were
commissioned. Three reviewers and roughly 3,500 lines of analysis did not surface that
class of problem at all, because you cannot see a hang by reading.

Scores also ran inverse to rigor: the most thorough review scored the code lowest
(3.3/5), the least thorough scored it highest (4.75/5). A reviewer that finds nothing
and awards high marks is not providing signal.
