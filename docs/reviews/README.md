# Code reviews

Independent reviews of `hw-inventory.sh` v4, kept here as provenance: they are what the
`C-`, `G-` and `O-` IDs in [`docs/DISPOSITIONS.md`](../DISPOSITIONS.md) point back at.
(They were originally filed as per-reviewer `F-0NN` IDs; `86e6c05` unified them to the
one-letter-per-reviewer scheme the ledger uses. The documents themselves still say `F-`.)

## Read this first

- **Every one of these is frozen at commit `bc32386`, a 651-line script.** The file is
  now 990 lines. Line numbers in them are stale by construction and are not corrected;
  each file carries a header saying so. Use them to understand *why* a finding was
  raised, never to locate code.
- **These are AI-generated and unedited.** Three models were given the same prompt
  (`code-review-prompt-template.md`) and the script, with **zero context** about the
  target environment, the design constraints, or what had already been decided.
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
| `code-review-prompt-template.md` | The prompt given to all three models |
| `code-review-summary--anthropic--claude-opus-5--*` | Summary + detailed, 35 findings |
| `code-review-summary--xai--grok-4-5--*` | Summary + detailed, 7 findings |
| `code-review-summary--openai--gpt-5-5--*` | Summary + detailed, 3 findings |

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
