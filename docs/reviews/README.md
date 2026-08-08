# Code reviews

Independent reviews of `hw-inventory.sh` v4, kept here as provenance for the
**Known limitations** table in the top-level README and to give the `F-0NN` finding
IDs referenced there something to point at.

## Read this first

- **These are AI-generated and unedited.** Three models were given the same prompt
  (`code-review-prompt-template.md`) and the script, with **zero context** about the
  target environment, the design constraints, or what had already been decided.
- **Finding IDs are per-reviewer and do not correspond across documents.** Claude's
  F-001 is a locale issue; Grok's F-001 is brace expansion; GPT's F-001 is loop
  iteration. Cross-reference by line number, not by ID.
- **Not all findings were accepted.** Several were rejected outright — including one
  recommended by two of the three reviewers that would break the script. See
  [DISPOSITIONS.md](DISPOSITIONS.md) before acting on anything in here.

**If you are about to open a PR based on one of these reviews, read DISPOSITIONS.md
first.** It records which findings were accepted, which were rejected, and why.

## Contents

| File | What it is |
|---|---|
| `DISPOSITIONS.md` | Maintainer response — accept / reject / defer per finding |
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
