# Checkpoint: handing this task to the next session

Loaded when a phase boundary meets a context boundary — the user asks for a new
session or `/compact`, or you can see the transcript will not survive to phase 8.
A checkpoint is not a status report: it is the minimum a fresh session needs to
continue **without re-deriving decisions**, and it lives on disk, next to the
spec, because that is what survives.

Write `<TASK-ID>.state.md` beside the spec (never as a ticket comment — the
ticket is the customer's channel, not scratch space; and never anything that
holds a secret, a token or personal data).

```markdown
# <TASK-ID> — state @ <UTC time>
phase: 5 (TDD implement), next: 6 (code review dispatch)
tier: T2 · reversibility: one-way (migration) · type: feature
branch: feature/DEV-475-order-total   base: develop @ 3f2a1c9
spec: docs/specs/DEV-475.md            checkpoint written by: session 2

## Baseline (the numbers a fresh run must reproduce)
tests 47/47 · diff-coverage 31/31 · repro: `make check` (node 20.11.1)

## Seam
OrderService.total_for_order — src/services/order.py:88

## Decisions that are settled (do not re-litigate)
- rounding moved to the money type, not the service (spec §4)
- no new endpoint: the existing one gains a field (ticket comment #3)

## Open questions
- billing service reads the same table — consumer unverified (spec §3)

## Volatile facts (re-check before relying on them)
- ⚠ VERIFY `gh pr view 214 --json state,mergeStateStatus` — MR state as of the
  time above; CI may have moved
- ⏱ TTL 1h: staging deploy at 12:40 UTC; the URL below may point at older code
- ⚠ VERIFY `git log --oneline develop -1` — base moved twice today
```

## Rules

- **Every fact that can rot carries how to re-check it.** A sha, a pipeline
  state, a deploy URL, a queue depth: `⚠ VERIFY <command>` or `⏱ TTL <window>`.
  A fresh session treats an unmarked volatile fact as false.
- **Decisions are copied, not summarised.** "We decided rounding lives in the
  money type" plus where it is written. A summary that loses the *why* invites
  the next session to decide differently and call it a fix.
- **The checkpoint never replaces the spec.** It points at it. If a decision is
  worth keeping, it belongs in the spec; the checkpoint carries the pointer.
- **On resume:** read the spec, then the checkpoint, then re-run the marked
  verifications *before* trusting anything they cover — and say in one line
  which facts you re-verified and which you dropped as stale.
- **The state file stays out of the task's diff.** It carries the author's
  reasoning, the previous verdict's sha and the premortem edges in the author's
  words — exactly what a clean-context reviewer must not receive — and it is
  never scanned by the gate's scan-at-sink. Keep it in the artifact directory
  outside the commit (`git check-ignore -v` tells you what the repo already
  thinks; add it to the project's ignore list if it does not), and delete it
  when the task closes. Никогда не пиши в него секреты, токены или PII.
- **On resume, validate before you trust.** Compare the recorded branch and
  base with `git rev-parse --abbrev-ref HEAD` and `git rev-parse HEAD`:
  - branch and HEAD match → continue from the recorded phase;
  - HEAD moved → every sha-bearing verdict in the file (`review @ …`) is void:
    phases 6/6b are re-run on the delta, and the baseline numbers are re-taken;
  - branch differs, or the file names another task → the file is a note, not a
    checkpoint. Say so and start from phase 0.
  Say in one line which facts you re-verified and which you dropped as stale.
