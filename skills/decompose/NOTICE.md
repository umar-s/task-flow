# NOTICE

The splitting logic in `references/splitting.md` — the five SPIDR axes, the
capability-level trigger signals, and the task-level size signals — is
adapted from **Open GSD** (`@opengsd/gsd-core`), © 2026, distributed upstream
under the MIT License.

Nothing in that file is copied verbatim from the upstream source. The
material has been reworded and restructured to fit this plugin's own task
model: a flat epic → tasks → `depends_on` graph instead of GSD's
story/phase workflow, an optional `story_points` annotation instead of a
hard SP gate, and no interactive confirm/reject loop — decisions here are
made by whichever skill or workflow reads this reference, not by a
conversational back-and-forth with the end user.

This plugin (`task-flow`) is itself licensed under the MIT License. See the
`LICENSE` file at the repository root for the full text.
