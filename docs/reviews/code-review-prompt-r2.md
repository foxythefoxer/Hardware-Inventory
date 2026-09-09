# Code review prompt — round 2 (`R2-`)

The prompt for the **second** review round of `hw-inventory.sh`. Round one's prompt is
[`code-review-prompt-r1.md`](code-review-prompt-r1.md), kept because the `C-`/`G-`/`O-`
findings point back at what it produced; it is not the one to use.

Written for a **web session with manual file uploads** — no repository access, no ability
to run anything. Everything the reviewer knows, you upload.

---

## 1. What to upload

Upload the files, then paste the fenced prompt below. Order matters only in that the
script should be first.

### Required — the review is not valid without these

| File | Why |
|---|---|
| `hw-inventory.sh` | The target. ~1,200 lines. |
| `CLAUDE.md` | The read-only rule and the publishing rule, in their authoritative form. |
| `.claude/rules/collectors.md` | The exit-code contract, the conventions, and the **rejected-proposals list**. Highest value per byte in the repo — it is what stops the reviewer re-proposing `set -o pipefail`. |

### Strongly recommended

| File | Why |
|---|---|
| `docs/DISPOSITIONS.md` | The measurements behind every verdict. Large (~57 KB), and the reason a rejection sticks. |
| `docs/QUEUE.md` | What is accepted and **not yet done**, so the reviewer doesn't file `FR-004` again as a fresh finding. |
| `README.md` | The read-only contract, the platform-support matrix and the exit-code contract in operator-facing form. Settles §12 without guesswork. |

### Include if the session's budget allows

| File | Why |
|---|---|
| `tests/run.sh` | ~49 KB. Lets §16 name a case in the existing suite's idiom instead of recommending you adopt bats-core over an 18-case suite that already runs twice in CI. |
| `tests/README.md` | 1.4 KB. The cheap substitute for the above if the budget is tight — it states the hang thesis and what T3 is for. |

### Do not upload, and why

- **`docs/reviews/*` — the R1 reviews.** Withheld deliberately. A reviewer given R1's
  findings audits R1 instead of the script, and re-reports its accepted items as new. The
  part of R1 worth carrying forward is the rejection list, which is already in
  `.claude/rules/collectors.md` with the fact that settles each one — that prevents the
  waste without the anchoring.
- **`docs/PRIOR-ART.md`.** Explicitly unadjudicated leads. Uploading it invites the
  reviewer to argue for them, which is a separate decision on a separate channel.
- **`docs/FIELD-TESTS.md`.** Questions that only another host class can answer. Nothing in
  it is reviewable from source.
- **A generated report. Ever.** A report is nothing but hostnames, serials and MACs. The
  script is generic and belongs in public; its output does not. If the reviewer asks for
  sample output, give it a hand-written one in the documentation ranges.

---

## 2. How to run it

**One model or several.** The self-identification block and the filename convention keep
several models' outputs from colliding, as they did in R1. Findings are numbered
`F-001…` *within each document* — that numbering is provenance, not identity, and the
ledger assigns the real `R2-NNN` id at adjudication. See §4.

**Split the turns.** The script is ~1,200 lines, four times the length at which models
begin silently truncating the walkthrough. Ask for Document 1 in one turn and Document 2
in the next; if Document 2 still comes back short, ask for §1–8 then §9–16. The prompt
tells the reviewer to announce where it stopped rather than trail off, but a turn budget
it can actually meet is the better fix.

**Then adjudicate.** Every finding goes through `/adjudicate` under an `R2-` id, whether
accepted or rejected. A finding nobody wrote a verdict for gets re-proposed next round.

---

## 3. The prompt

Everything the reviewer needs is inside the fence. Copy all of it.

```
# ROLE

You are a senior staff engineer conducting a formal code review. Write the review you
would actually hand to a colleague: rigorous, specific, and explanatory. The author is
competent and this script has already been through one review round and a repository
audit — your job is not to list defects, it is to explain the engineering reasoning
behind every judgment.

For every significant design decision, say whether it is good or problematic AND WHY.
Affirm the good ones explicitly; a review that only lists problems teaches nothing about
what to keep doing. Do not flatter and do not manufacture praise, but do not stay silent
on correct choices either.

# WHAT YOU HAVE BEEN GIVEN

You have the script and the repository's own instruction files. Read them before you
review. They are not background material — they are the record of what has already been
decided about this code, and a finding that contradicts one without new evidence is a
finding the maintainer has to reject in writing.

  hw-inventory.sh              The target.
  CLAUDE.md                    The rules that govern all changes here.
  .claude/rules/collectors.md  The exit-code contract, the conventions every collector
                               follows, and the list of proposals already rejected.
  docs/DISPOSITIONS.md         The full adjudication ledger: every verdict with the
                               measurement that produced it.
  docs/QUEUE.md                Accepted work not yet implemented.
  README.md                    Operator-facing contract, platform matrix, exit codes.
  tests/run.sh, tests/README.md  The existing test suite, if supplied.

If a file named above was not supplied, say so in Document 2 §1 and state which of your
findings you could not check against it.

# HARD CONSTRAINTS ON WHAT YOU MAY RECOMMEND

Three constraints bind this script. A recommendation that violates one is not a finding,
it is noise, and it costs the maintainer a written rejection.

These constrain your RECOMMENDATIONS, never your FINDINGS. A read-only violation already
present in the script is a CRITICAL finding and you should report it as one.

## 1. The script is read-only. Every command it runs must be a query.

Not "read-only by default", not "read-only unless the user asks". This is the reason the
script can run unattended against production hosts without a human confirming each run;
a write-capable version would need that human every time.

Do not recommend any write. That includes, and is not limited to: creating a temp file
(`mktemp`, lock files, caches, state or output directories), writing a log file,
`smartctl -t`, `zpool scrub|import`, `btrfs balance|scrub`, `docker run|exec`, `mount`,
`systemctl start|stop`, `mdcmd`, and any package operation.

**The ban covers a dependency's config, not just its verb.** Before recommending any new
tool, state what it reads at startup and whether that file can execute. Worked precedent:
`fastfetch` was proposed as a cross-check and rejected because a bare invocation executes
`command` modules out of the host's `config.jsonc`. A flag that suppresses this is not
sufficient on its own — it moves the guarantee from this script's source into a third
party's release notes.

If a finding appears to require a write, say so and stop there. The correct answer is a
read-only path, or leaving the data uncollected.

## 2. Several proposals are already adjudicated, with measurements.

`.claude/rules/collectors.md` carries the rejection list; `docs/DISPOSITIONS.md` carries
the evidence. Do not re-propose anything on it. If you believe one is wrong you must
produce **new evidence** — a measurement, not a better argument — and file it as a single
finding naming the id and the measurement that overturns it.

Two that R1 reviewers recommended and that are wrong for this script specifically:
`set -o pipefail` measures exit `141` here, because 23 pipelines end in `head -N` which
exits early and SIGPIPEs upstream; and `set -e` truncates the report at the first absent
tool, which is the normal case for a best-effort collector where most commands are
*expected* to fail.

## 3. This repository is public and your output will be committed to it.

Do not write a hostname, IP or MAC address, serial number, real name, email address or
network topology into either document, including inside an example. Identify a host by
class — "a Proxmox LXC", "a whitebox AM5 desktop".

The script **emits** serials, MACs and IPs by design; that is the product. Writing one
into a report on the operator's own disk is the point of the tool, committing one here is
disclosure. If you need to show sample output, invent it in the documentation ranges:
RFC 5737 `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` for addresses, RFC 7042
`00:00:5E:00:53:00`–`FF` for MACs.

# SELF-IDENTIFICATION (REQUIRED)

Before producing output, state your identity in this exact format:

  VENDOR: <the organization that made you, e.g. Anthropic, OpenAI, xAI, Google, Meta>
  MODEL:  <your specific model name and version, as precisely as you know it>

Use lowercase-hyphenated slugs of these values in every output filename. If you are not
certain of your exact version string, use the most specific identifier you are confident
in and append `-unverified` to the model slug. Never invent a version number.

# OUTPUT: TWO SEPARATE FILES

Produce EXACTLY two Markdown documents.

Filename pattern (use literally, substituting the bracketed parts):

  code-review-summary--r2--[vendor-slug]--[model-slug]--[YYYY-MM-DD].md
  code-review-detailed--r2--[vendor-slug]--[model-slug]--[YYYY-MM-DD].md

  - vendor-slug / model-slug from SELF-IDENTIFICATION (lowercase, hyphens only)
  - date in ISO 8601; if you cannot determine today's date, use `undated` rather than guess

If you can write files, write both and report the paths. If you cannot, output each
document in its own fenced code block with the exact filename on the line immediately
before the fence. Do not merge them into one document under any circumstances.

# ANCHOR YOUR LINE NUMBERS TO A COMMIT

Both documents must carry, in the header, the **commit SHA the review was performed
against**. It is given in the INPUT block at the bottom of this prompt; copy it verbatim.

This is not bookkeeping. R1's reviews were performed against a 651-line script that is now
~1,200 lines, and every line number in them is stale by construction — usable to
understand why a finding was raised, useless for locating code. A SHA in the header makes
a review age into a historical document instead of a misleading one.

Every finding, observation, refactor and scorecard rationale in BOTH documents must cite
the line number(s) it refers to. Not just the walkthrough — everywhere. A claim without a
line reference is not reviewable and should not appear. Quote the lines you are citing.

# FINDING IDS AND RISK LEVELS

Number your findings `F-001`, `F-002`, … in the order they appear in the DETAILED
document; the SUMMARY references the same ids. Never reuse or renumber one.

These ids are **document-local provenance, not identity.** The repository's ledger will
assign each accepted or rejected finding a permanent `R2-NNN` id and record your vendor,
model and original `F-` number beside it. So do not attempt to coordinate your numbering
with anything, and do not skip numbers to leave room.

Every finding gets exactly one risk level. Use these strictly; do not inflate.

  CRITICAL — Data loss, security compromise, silent corruption, or a violation of the
             read-only rule. Ship-blocking. Must include a concrete scenario in which the
             damage actually occurs.
  HIGH     — Incorrect behavior, crashes, hangs, or failure under realistic conditions.
  MEDIUM   — Works today but is fragile, non-portable, or will cause maintenance pain.
  LOW      — Minor correctness or clarity improvement worth doing.
  NITPICK  — Style, preference, polish. Explicitly optional; the author may decline.
             Cap these at five. If you have more, the extras are not worth the attention.

If a level has zero findings, write "None." rather than manufacturing one.

# DOCUMENT 1 — CONDENSED REVIEW (code-review-summary--r2--...)

Target length: 1-2 pages, for someone who has five minutes.

  1. Header: target, commit SHA, reviewer vendor + model, date, LOC, shell/runtime.
  2. VERDICT — one of `Approve`, `Approve with comments`, `Request changes`, `Reject`,
     followed by 2-4 sentences of justification.
  3. ENGINEERING SCORECARD table, 1-5 per dimension with a one-line rationale citing lines:
       Architecture | Readability & Maintainability | Robustness (hangs & timeouts) |
       Error Handling | Security | Performance | Portability | Idiomatic Style
     Any dimension may be `N/A` with a one-sentence justification. Give an overall score
     and say plainly what it means.
  4. TOP FINDINGS table: ID | Risk | Line(s) | One-line description.
     Every CRITICAL and HIGH. Add MEDIUM/LOW only if the table stays under ~15 rows.
     Never list NITPICKs here.
  5. TOP 3 ACTIONS — highest-leverage changes, in the order they should be done.
  6. WHAT THIS CODE DOES WELL — 2-4 specific decisions that were correct, with line
     numbers and a sentence on why each is the right call. Not generic praise.

No code blocks longer than 3 lines in this document.

# DOCUMENT 2 — EXTENSIVE ENGINEERING REVIEW (code-review-detailed--r2--...)

Sections in this exact order.

  ## 1. Overview & Context
     What the code does, entry points, invocation model, external dependencies and their
     assumed versions, required privileges, target runtime. List every assumption you had
     to make because neither the code nor the supplied documents told you, and name any
     document from the WHAT YOU HAVE BEEN GIVEN list that was not supplied.

  ## 2. Architecture Review
     The shape of the program, not its lines:
       - Overall structure and control flow; is the decomposition sound?
       - Separation of concerns; data flow; what is global and why
       - Configuration strategy: args vs env vars vs hardcoded constants
       - Idempotency and re-runnability
       - Failure model: fail fast, fail soft, or fail silently — and is that right here?
       - Extension points: what happens when the next collector is added?
     For each decision, state whether it was the right call and why. Where you disagree,
     name the alternative design and its concrete tradeoff — do not assert a preference.
     Include a short bulleted or ASCII flow diagram of the execution path.

  ## 3. Blocking-Call Audit
     READ THIS FRAMING FIRST. Three static reviews of this script produced roughly 3,500
     lines of analysis and did not surface one instance of the only defect class that has
     ever actually broken it. **Every real bug in this project's history has been a HANG,
     not an error.** Errors are handled by design — `have` guards, `2>/dev/null`,
     `|| true` — so a review that audits error handling and stops has audited the part
     that already works.

     You cannot see a hang by reading. You CAN see a missing guard. Build this table, one
     row per invocation of an external binary, covering every one in the file:

       Line(s) | Command | `have` guarded? | Timeout wrapper | Can it block? | Verdict

     The script's convention is `have <tool>` plus either `"${TMO[@]}"` (the 10s default)
     or `tmo N cmd...` where that duration is wrong. Both run the command unwrapped when
     coreutils `timeout` is absent, which is the entire point of the gate. **A hardcoded
     `timeout N` bypasses the fallback and is a finding** — that was a real defect at 26
     call sites.

     Flag specifically anything touching: a network mount (`df`, `findmnt`, `pvesm`), a
     storage backend that can stop answering (`smartctl`, the vendor RAID CLIs, `zpool`),
     a hardware bus (`lspci`, `ipmitool`, `dmidecode`), or a daemon socket (`docker`,
     `systemctl`, `apcaccess`). An unguarded `lspci` once froze this script for 240s.

     Where you cannot tell whether a command can block, say so and name the condition
     under which it would.

  ## 4. Section-by-Section Walkthrough
     THE SCRIPT IS ~1,200 LINES. This is the section models truncate first, and a
     walkthrough that quietly skips the last 400 lines is worse than one that stops
     honestly, because nobody can tell which happened. If you run out of room, STOP at a
     region boundary and end the section with:

       WALKTHROUGH INCOMPLETE — covered through line N; resume at line N+1.

     Work in the script's own regions: the named-constants block, the helpers, the gather
     stage, then one `###` section per subsystem. Use those boundaries, not arbitrary line
     windows. Format:

       ### Lines X-Y — <region>
       **What it does:** ...
       **Assessment:** Good / Acceptable / Problematic — and WHY, in engineering terms
       **Finding:** F-0NN [RISK]   (omit if none)
       **Recommendation:** ...     (omit if none)

     If a region is correct, one line saying so and why is the complete entry. Do not pad
     correct code to look thorough.

  ## 5. Readability & Maintainability
     Judge it as "a stranger opens this file in six months." Naming, function length,
     nesting depth, magic numbers and strings, comment coverage (missing, misleading and
     redundant are all three defects), dead code, duplication, hidden coupling, and how
     discoverable the tuning knobs are. Give a cyclomatic-complexity read on the most
     complex region and say whether it needs splitting.

     Note that this repo's convention is that comments explain **why**, not what, and
     several exist specifically to stop a future maintainer "simplifying" a construct back
     into a bug. Judge a comment against that standard before calling it redundant.

  ## 6. Shell Idiom Review
       - Shebang correctness; does it match the features used?
       - `set -u` is deliberate and `-e`/`pipefail` are adjudicated — see the constraints.
         Assess whether `set -u` is used correctly, i.e. every variable that is
         conditionally assigned is initialised before its guard.
       - Quoting discipline; word splitting and glob exposure
       - `[[ ]]` vs `[ ]`; arithmetic contexts
       - Arrays vs whitespace-split strings for lists and argument building
       - `local` in functions; `readonly` for constants
       - `printf` vs `echo` for anything non-trivial
       - Subprocess cost; useless use of cat/grep/echo
       - Safe iteration over filenames
       - Exit codes: meaningful, distinct, documented
       - Minimum bash version any construct you recommend would require
     For each, say whether the script follows the practice, cite lines, and explain the
     concrete failure the practice exists to prevent.

  ## 7. Error Handling & the Exit-Code Contract
     The script has a specific, documented contract, stated in
     `.claude/rules/collectors.md`. Read it before writing this section. In summary: the
     report is written in full either way; exit `0` means collection complete, exit `1`
     means one or more collectors failed and the report ends with a `## Collection
     warnings` block naming them. The judgment at its centre is that a warning means the
     tool was **present, permitted, and still returned nothing** — a tool that is absent,
     or that needs root on an unprivileged run, is silent, because a minimal host is not a
     broken one.

     Audit against that contract, not against a generic one:
       - Does every collector's warn/silent decision match the rule? Name any that warns
         where it should be silent (this fires on ordinary healthy hosts and trains
         readers to skip the section) or is silent where it should warn (this reports a
         confident wrong answer as ground truth, which is the worse direction).
       - Does anything test for *emptiness* where emptiness is not the failure signal?
       - `warn` mutates a global and must only be called from the main shell — pipeline
         bodies and command substitutions are subshells and lose the mutation. Find every
         `warn` reachable from inside one.
       - Table: Line(s) | Operation | Can it fail? | Detected? | Handled? | Consequence
       - Partial-failure state: if it dies at line N, is the report still well-formed?
       - Silent failure paths, enumerated explicitly. This is the most dangerous category
         for a tool whose output is consumed as ground truth.

  ## 8. Static Analysis
     ShellCheck runs in CI on every push with a **zero errors, zero warnings** baseline on
     the default ruleset, so assume the obvious codes are already clean. Report only what
     that ruleset would MISS, or a place where a `disable` directive is hiding a real
     problem. Table: Code | Line | Severity | Message | Fix. Cite real SC codes; if you do
     not know a real one, write `[no-rule-id]` — never fabricate one.

  ## 9. Edge Cases & Failure Modes
     Concrete scenarios: trigger condition -> resulting behavior -> fix. At minimum:
     a tool present but returning empty output; a tool returning malformed output; output
     that hits a `cap()` limit exactly at the boundary; filenames and device model strings
     containing spaces, `|`, CR, or unicode; unset variables under `set -u` where the
     assignment is inside a conditional; empty glob expansion; a `/sys` attribute that
     exists but reads empty; CRLF input from a FAT32 mount; unexpected locale.
     Separate CONFIRMED issues from SUSPECTED ones you could not verify from the code
     alone. Never present a guess as a fact.

  ## 10. Performance
     This is a one-shot reporter, not a hot path, so weight this section accordingly and
     say so if there is nothing worth changing. Where there is: subprocess counts inside
     loops, repeated invocation of the same expensive tool, N+1 patterns against a daemon.
     Label each optimization MEASURED-OBVIOUS or SPECULATIVE, and give the command that
     would confirm or refute it.

  ## 11. Security Review
     Input validation and sanitization; injection surfaces, including any place host
     output becomes part of a command; secret handling; file permissions; TOCTOU; unsafe
     `eval` or dynamic execution; anything that would execute a file the script means only
     to read; privilege boundaries and whether root is required where it is used.

     Two things specific to this script:
       - Its **redaction policy** is that identifying values (serials, MACs, IPs, target
         names) are emitted on purpose and authenticating values (passwords, tokens, CHAP
         usernames, SNMP community strings, CSRF tokens) are filtered. Audit both
         directions: a secret that reaches the report, AND over-redaction that strips a
         value the inventory needs. Both are defects.
       - Any file the script parses that could instead be *executed* by a plausible
         "simpler" implementation.
     Cite CWE ids where a recognized classification applies.

  ## 12. Portability Review
     **Scope: Linux only.** This script reads `/sys`, `/proc`, `lsblk`, `ip` and
     `dmidecode`; macOS and BSD are out of scope by design and a matrix row for them is
     noise. The stated support matrix is in `README.md` — audit the code against it rather
     than inventing your own.

     Cover: glibc vs musl/Alpine, WSL's limited `/sys`, and the named distributions.
     Then enumerate specific blockers with their portable replacement: GNU vs BusyBox flag
     differences (`sed`, `date`, `stat`, `readlink`, `grep -P`, `df`, `lsblk`), hardcoded
     paths and assumed binaries, assumed `$PATH`, and the minimum bash version any
     construct requires. The stated floor is bash 3.0.

  ## 13. Suggested Refactors
     Re-read the HARD CONSTRAINTS before writing this section — it is where a read-only
     violation is most likely to enter. For each substantive refactor:
       - Rationale: which dimension it improves and why the churn is justified
       - Before: the current code, quoted exactly, with line numbers
       - After: complete, runnable replacement — not pseudocode, no `...` elisions
       - Risk of the change and how to verify it did not break anything
     Refactored code must itself pass every standard in this review, including the
     `have` + timeout convention and the read-only rule.

  ## 14. Prioritized Action List
     One table sorted CRITICAL -> HIGH -> MEDIUM -> LOW -> NITPICK:
     ID | Risk | Line(s) | Issue | Recommended Fix | Effort (S/M/L)

  ## 15. Engineering Scorecard
     The same dimensions as Document 1, expanded: the 1-5 score, 2-3 sentences citing
     specific line numbers, and what a 5 would look like for this specific script. Close
     with the single change that would most improve it.

  ## 16. Testing Recommendations
     A test suite already exists — `tests/run.sh`, run twice in CI (unprivileged, then as
     root) on every push. If it was supplied, read it first. **Do not recommend replacing
     it with a framework;** recommend cases in its existing idiom, which is a stub binary
     placed on `PATH` plus assertions on the resulting report.

     For each finding you raised at MEDIUM or above, name the smallest test that would
     have caught it, and say which existing test it belongs next to. Where a finding
     cannot be tested on a general-purpose Linux host — it needs ZFS zvols, a UPS daemon,
     a BMC, an unprivileged container — say so explicitly and state the exact command and
     the smallest answer that would settle it, rather than proposing a test that cannot
     run.

# RULES OF ENGAGEMENT

- Ground every finding in the actual submitted code, with line numbers. Quote the lines.
- Explain WHY, always. "Quote "$var" on line 42" is incomplete; say what breaks without it.
- If you cannot determine something from what you were given, say "cannot determine from
  the provided material" and state what you would need. Never guess silently.
- Do not report a bug you are not reasonably confident exists — use the SUSPECTED bucket.
- Do not soften findings to be agreeable; do not manufacture findings to look thorough.
- A finding that contradicts the supplied instruction files needs new evidence, not a
  fresh opinion. Say which document you are contradicting and what measurement overturns it.
- Keep both documents consistent. No finding may contradict its counterpart.
- Preserve the author's evident intent. Suggest improvements, do not redesign the project.

# INPUT

Target:              hw-inventory.sh
Commit SHA:          [FILL IN — the SHA you are reviewing; goes in both document headers]
Language / runtime:  bash, floor of 3.0, developed against bash 5.x
Intended environment: run manually or from cron, as root where possible and unprivileged
                     otherwise; the script degrades rather than failing when unprivileged
Target platforms:    Linux only. Unraid, Proxmox VE, Arch, Fedora/RHEL, Debian/Ubuntu
                     supported; Alpine/musl and WSL degraded; macOS/BSD out of scope.
Already known imperfect: see docs/QUEUE.md for accepted-but-unimplemented work, and
                     "Known limitations" in README.md.

The files are attached.
```

---

## 4. What happens to the output

Both documents are committed to `docs/reviews/` unedited, the same way R1's were — they
are the provenance the `R2-` ids point back at, and editing them destroys that.

Then every finding is adjudicated under an **`R2-` id**, one namespace for the whole
round regardless of how many models ran it. The reviewer's own `F-NNN` is recorded inside
the ledger entry alongside its vendor and model, as provenance.

This is deliberate, and it is the correction of an R1 mistake. R1 filed three models'
findings under three per-model prefixes, which had to be renumbered afterwards (`86e6c05`)
and left `C-`/`G-`/`O-` as a closed set that cannot grow. A prefix names a **channel**;
the model is a column in the ledger, not a namespace of its own. See "Pick the ID prefix"
in `/adjudicate`.

---

## 5. What changed from R1

R1's prompt was written for a 651-line script in a repository with no ledger, no exit-code
contract and no test suite, and it was pasted with its entire `INPUT` block left blank.
Structure survived; the context did not.

- **HARD CONSTRAINTS is new**, and is the section that pays for the rewrite. R1 never
  mentioned the read-only rule, and its shell-practices checklist actively asked for a
  `mktemp` recommendation — a write, in the one script that must not write.
- **The rejection list is now supplied.** R1 gave the models zero context deliberately.
  That bought independence when there was nothing to be independent *of*; today it buys a
  re-argument of `set -o pipefail`, which two of the three R1 reviewers recommended and
  which measures exit `141` here.
- **§3 Blocking-Call Audit is new and promoted near the front**, against the one defect
  class that has ever broken this script and that R1 missed entirely.
- **The walkthrough has a length protocol.** R1's advice about long scripts was in a usage
  note *below* the fence, where nobody pasting the prompt would ever read it.
- **A commit SHA is mandatory in both headers.** R1 mandated line numbers everywhere and
  never mandated the anchor that makes them mean anything; its documents are now stale by
  ~550 lines.
- **§7 is written against the actual exit-code contract**, not a generic "does the exit
  code communicate failure".
- **§16 aims at the existing suite** instead of recommending bats-core over an 18-case
  suite that already runs twice in CI. **§8 assumes ShellCheck is clean**, because it is,
  on every push. **§12 is Linux-scoped**, dropping a macOS/BSD matrix that could only ever
  come back "Broken".
- **Finding ids are declared document-local**, so nothing has to be renumbered later.
- **The upload manifest above is new**, and is the part that makes any of this reach the
  reviewer in a web session.
