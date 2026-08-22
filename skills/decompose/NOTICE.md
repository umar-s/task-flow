# NOTICE

The decomposition methodology in this skill's `references/` — the SPIDR
splitting axes (`splitting.md`), the edge-case probe taxonomy
(`edge-probe.md`), the planning thinking-models (`thinking-models.md`), the
task field model (`task-schema.md`), and the plan-QA checks
(`qa-checklist.md`) — is adapted from **Open GSD** (`@opengsd/gsd-core`),
© 2026, distributed upstream under the MIT License.

Nothing in those files is copied verbatim from the upstream source. The
material has been reworded and restructured to fit this plugin's own task
model: a flat epic → tasks → `depends_on` graph instead of GSD's
story/phase workflow, an optional `story_points` annotation instead of a
hard SP gate, and no interactive confirm/reject loop — decisions here are
made by whichever skill or workflow reads this reference, not by a
conversational back-and-forth with the end user.

Three conventions added in 1.10.0 — the draft's out-of-scope table, the
revision loop's convergence guard and the optional duplicate search before a
tracker push — follow the shape of the corresponding conventions in
`gstack` (`spec`, `plan-ceo-review`, `spec --dedupe`) as recorded in
`docs/audits/2026-08-21-dmitriy-toolkit-v3-audit.md`; the wording here is
this plugin's own and no text was taken from that source.

This plugin (`task-flow`) is itself licensed under the MIT License. See the
`LICENSE` file at the repository root for the full text.
