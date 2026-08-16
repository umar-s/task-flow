# NOTICE

`references/implementation-integrity.md` — the phase-5 discipline covering the
red-suite baseline, RED-means-you-watched-it-fail, the anti-gaming rules, the
mutation check and the "numbers, not adjectives" reporting rule — is adapted
from **old-coder** (`AmazingAng/old-coder`, commit `01f8fe9`, 2026-08-15),
© 2026 amazingang, distributed upstream under the MIT License. The
negative-control rule in the `ci-gate` skill ("prove a home-grown checker can
fail before trusting its pass") comes from the same source.

Nothing is copied verbatim. The material has been reworded and re-scoped to fit
this plugin's trust model, which differs from the upstream one in a way worth
stating: old-coder replaces line-by-line review with a self-run gauntlet and a
self-authored evidence report, so the party being checked holds every control.
Here those mechanics sit *under* an independently-dispatched code review, a
conditional security review and a deterministic CI gate — they raise the floor
the implementer stands on, and they are never the thing that authorises a
merge.

Consequently the upstream SPEC/EVIDENCE artifacts, the tier-gated gauntlet
tooling matrix, and the independent-verifier protocol are deliberately not
imported: this flow already has a tracked ticket as its contract, a phase-6
reviewer with clean-context independence, and phase 8's non-gameable gate.

This plugin (`task-flow`) is itself licensed under the MIT License. See the
`LICENSE` file at the repository root for the full text.
