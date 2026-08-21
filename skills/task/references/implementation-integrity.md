# Implementation integrity — the phase-5 floor under "tests are green"

Load this in phase 5, before writing the first test. Phase 6's reviewer and
phase 8's deterministic gate both start from the assumption that the suite
means something; this file is what makes that assumption true. Everything here
is about the *implementer's own* discipline — it does not replace the
independent review, and the independent review cannot recover it after the
fact.

Adapted from the evidence-first practice in `AmazingAng/old-coder` (MIT — see
`../NOTICE.md`), narrowed to what a supervised, independently-reviewed flow
actually needs.

## 1. Baseline before the first edit

On a repo that is not already green, record the **pre-existing failures
verbatim** — which tests, which errors — before touching anything. From then on
the bar is **zero NEW failures**, not "all green": a suite that was red in three
places yesterday tells you nothing about your change unless you wrote down
which three.

Fixing unrelated pre-existing failures is scope creep. Surface them (a
follow-up ticket, a line in the close comment) rather than silently folding
them into this task's diff, where they hide the change under review.

## 2. RED means you watched it fail

**The type of ticket decides what the first red test is:**
- **bug** — the first red test *reproduces the ticket's Actual*, and its
  assertion is the ticket's Expected. A bug fixed without a test that failed on
  the reported symptom is a fix for a bug you inferred, not the one reported.
- **refactor** — characterisation tests first (they pin today's behaviour,
  including the parts nobody likes), and the mutation check of §4 is mandatory:
  behaviour preservation is the whole DoD, and only a killed mutant shows it.
- **feature** — as below.

- Run each new test and **watch it fail** before writing the implementation. A
  test you never saw fail proves nothing — it may be asserting nothing at all.
- If the module doesn't exist yet, stub it so the test fails on the assertion,
  not on the import. A collection error is a weaker RED.
- Related behaviours may share one RED run, as long as each new assertion was
  individually observed failing.
- **A new test that passes immediately is a claim, not a result.** Either it is
  vacuous (fix it), or the behaviour already existed. Prove which: break the
  implementation with a one-off throwaway mutant, watch the test go red,
  restore. Then keep the test as regression armour and say in the close comment
  that it covered pre-existing behaviour.

## 3. Anti-gaming rules (absolute)

The suite is only worth what it cannot be talked out of. These have no
exceptions and no "just this once":

1. **Never weaken a test to reach green.** No broadened assertion, no added
   skip, no raised tolerance, no deleted case. A test that looks wrong is a
   *spec* conversation — raise it, don't bury it.
2. **Never edit a test and the implementation in the same step to reach
   green.** Change one, run, then the other. Simultaneous edits are how you
   redefine correctness to match your bug without noticing.
3. **Never mock the unit under test**, and never mock so much that the test
   only exercises mocks. Mock boundaries — network, clock, filesystem, third
   party — not the logic you are being paid to prove. (This is the phase-3 seam
   decision showing up again at the keyboard.)
4. **Never chase a coverage number.** Coverage detects untested code; it is not
   a target. A test written only to touch lines, asserting nothing meaningful,
   is worse than no test — it converts a known gap into a false green.
5. **Never report a check you did not run.** "Skipped: no mutation tool for
   this language, did the manual pass instead" costs nothing. An invented
   result costs the whole flow its meaning.

## 4. Mutation check on the changed logic

Green tests prove the code passes the tests. They do not prove the tests would
notice if the code were wrong. Before phase 6, spend a few minutes proving they
would:

- **Prefer the project's mutation tool** when one exists (Infection, Stryker,
  mutmut, cargo-mutants, PIT, …) — it generates mutants from the syntax tree
  and cannot silently skip one.
- **Scope it by the diff. Always.** A whole-repo mutation run on anything
  monolith-sized is not a gate, it is a weekend: cost scales with mutants ×
  suite runtime, and both are large there. Point the tool at the changed files
  or the module that owns them — `infection --filter=<changed files>
  --only-covered`, `stryker run --mutate <changed files>`,
  `mutmut run "pkg.module*"`, `cargo mutants --file`, PIT `targetClasses`. If
  even the scoped run is too slow for CI, run it locally on the diff before
  opening the MR and put the number in the close comment: this is a phase-5
  discipline, not a pipeline job. On a legacy module with no coverage to start
  from, mutate only the new code — an old file's survivors are a backlog item,
  not this task's blocker.
- No tool for this language? Do it by hand: introduce **3–5 plausible bugs**,
  one at a time, in the logic that matters most —
  - flip a comparison (`<` → `<=`, `==` → `!=`)
  - off-by-one a bound or slice index
  - delete one branch of a conditional, or remove an early return
  - swap `and`/`or`, negate a boolean
  - return a constant (`0`, `null`, `""`) instead of the computed value

  Run the suite after each. **Every mutant must make at least one test fail.**
  A survivor is a missing or vacuous assertion: add the test that kills it,
  then continue. Restore between mutants and verify with `git diff` that
  nothing survived the restore — eyeballing is how a mutant ships.
- Report it as `N/N killed`, with the survivors you deliberately accepted and
  why (a mutant semantically equivalent to the original cannot be killed and
  must not be "fixed" by a meaningless test).

Scale this: skip it on a trivial-tier change and say so; on a high-stakes tier
(money, auth, data loss, concurrency, migrations, public API) it is not
optional, and the mutants should be drawn from the premortem's failure modes
rather than from this generic list.

**Where invariants exist, generate the cases instead of choosing them.**
Parsing, serialization, money arithmetic, ordering, retries and idempotence all
carry properties (round-trip, commutativity, bounds, "applying it twice changes
nothing") — express those with a property-based library (fast-check, hypothesis,
proptest, jqwik) and let it hunt the boundary. That is precisely the class of
case a premortem cannot enumerate, because enumerating it is the hard part. One
property with a shrinking counterexample is worth more than five hand-picked
inputs. Pair one-sided invariants with their opposite bound: "never exceeds the
limit" passes happily on a function that always returns zero.

## 5. Suite health

Every number you are about to report rests on the suite being deterministic. If
the project supports it, run the suite in **randomized order** at least once
(`pytest-randomly`, `vitest --sequence.shuffle`, `go test -shuffle=on`, …). An
order-dependent or flaky suite does not "mostly work" — it makes every result
after it unfalsifiable, and it will be your explanation for a failure that was
actually real.

## 6. Numbers, not adjectives

What phase 7 and phase 8 report must be:

- **Produced on the project's own toolchain.** Before the baseline, resolve the
  version the repo pins (`.nvmrc`, `.node-version`, `.python-version`,
  `.tool-versions`, `composer.json` platform) and activate it; numbers from a
  different runtime are not evidence for this repo, and a `node_modules` higher
  up the tree can make them worse than useless (`require.resolve` must point
  inside the clone). Report it as a **comparison**, not a printout —
  `node: pin 20.11.1 · actual 20.11.1 (match)`. A mismatch is not evidence:
  activate the pinned version and rerun, or, if you cannot after a named
  attempt, the run is `BLOCKED` on the toolchain rather than green on the
  wrong one.
- **From one final fresh run, executed after the last code edit.** Mid-task
  numbers are stale the moment you touch a file again. Rerun, then report.
- **Actual values, pasted.** "47 passed, 0 failed; 31/31 changed lines covered;
  5/5 mutants killed; suite green in randomized order (seed 4113)" — never
  "tests look good", never "coverage is fine".
- **Explicit about what was skipped**, with the reason, on the same line as
  everything that ran. A check nobody ran and nobody mentioned reads exactly
  like a check that passed.
- **Reproducible from the repo, not from the conversation.** Name the one
  command that regenerates what you cite — `make check`, `composer gate`,
  `npm run verify`, or the literal sequence if the project has no entry point.
  A number nobody else can regenerate is a claim; a number with the command
  behind it is evidence. If the mutation pass was manual, the script that
  applied the mutants belongs in the repo as well — a mutant list that lived in
  `/tmp` makes the score unauditable the moment the session ends.

- **Free of secrets and PII.** Never open `.env` or a secret store to make an
  authed call — use the mechanism that does not reveal the value — and keep
  tokens, keys and personal data out of the evidence line and the close comment
  (test users by role, not by name). The gate's `ci/scan-text.sh` scans the text
  you are about to post; use it when the repo has it.
- **Anchored to the reviewed commit, by command, not by memory.** Take the sha
  from the reviewer's `Reviewed:` line the moment the report arrives (write it
  into the state file if a session hand-over is possible), then:
  ```bash
  git merge-base --is-ancestor <review-sha> HEAD || echo "re-reviewed: required"
  git diff --quiet <review-sha>..HEAD && echo "re-reviewed: n/a (no code since)"
  git rev-list --count --no-merges <review-sha>..HEAD    # code commits since
  ```
  A merge of the integration branch (phase 8's "run on the merged state") adds
  commits that are not yours: report `merge only` when
  `git diff <review-sha>..HEAD` is empty, and `re-reviewed: yes|no` — never a
  bare count that reads as if someone had judged it.
- **Led by the terminal status.** The close comment and the skill's answer both
  start with one of `DONE | DONE_WITH_CONCERNS | BLOCKED | MERGED_NOT_LIVE |
  ABANDONED` plus a one-line reason, followed by the `DoD-n → PASS | FAIL |
  PARTIAL` grading with a `file:line` or command per item. A human skims the
  first line; a runner parses it. The status is **derived, not chosen**:

  | Condition | Status |
  |---|---|
  | merged, deployed, every `DoD-n` PASS, no check skipped | `DONE` |
  | merged and live, but a Required accepted by the risk owner (recorded on the MR), a check skipped with a reason, or a `DoD-n` not PASS | `DONE_WITH_CONCERNS` |
  | merged, not running (deploy failed, never triggered, health check failed) | `MERGED_NOT_LIVE` |
  | not merged; the blocker is named and not yours to clear | `BLOCKED` |
  | work stopped on purpose; say what happens to the branch | `ABANDONED` |

  `DONE_WITH_CONCERNS` is not a self-issued pass: the concern it names is
  something the risk owner accepted or the ticket now carries as a follow-up —
  an unresolved Required or a mandatory check you simply did not run is not a
  concern, it is unfinished work.
  The landing detail (`landing: deployed | deployed-with-concerns | not-live |
  reverted`) is a separate field, so a grep for one vocabulary can never pass
  for the other.

A step you got wrong and then fixed is a normal part of a task and costs
nothing to admit. A step you quietly weakened is the only unrecoverable one.
