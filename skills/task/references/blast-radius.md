# Blast radius: who else depends on what you are about to change (phase 3)

Loaded in phase 3, before the execution plan. The plan's file list is only as
honest as this search.

## The rule that matters

**An empty result is a claim, not a finding.** "No other callers", "nothing
imports this", "the field is unused" — each is a statement about your search,
not about the codebase, until it survives a second, differently-shaped search.
A tool that returned nothing may have been pointed at the wrong ref, may not
index the language, may not see strings.

So every "nothing found" carries three things:
1. **two searches in different namespaces**, not two tools over the same one —
   `grep` and `rg` on the same working tree is one search. The namespaces are:
   code · config and templates · data and migrations · consumers outside this
   repo. Cover the two that can plausibly hold a consumer of this thing;
2. **the named source of evidence** — which command, on which revision;
3. **the named blind spots** — what these searches cannot see.

## Search the shapes, not just the symbol

For a changed function, endpoint, field, config key, enum value or event name,
run at least two of:

| Shape | Search |
|---|---|
| direct use | the symbol itself, whole-word: `git grep -nw '<name>'` |
| re-export / alias | `git grep -n "as <name>\|from '.*<module>'"`, barrel files (`index.*`) |
| string reference | the *string* form: route paths, `getattr`/`__getattr__`, `send('<event>')`, DI keys, template names |
| dynamic import | `import(`, `require(`, `importlib`, reflection, service locators |
| config & data | env var names, YAML/JSON keys, feature flags, DB values that store the enum |
| outside the repo | other services, mobile clients, dashboards, saved queries — the consumers git cannot see |

For an **enum or status value**: read (do not grep) every consumer of a
neighbouring value. Code that switches on `PENDING` and `DONE` is exactly where
a new `CANCELLED` silently falls through.

## Write it down like this

```
Blast radius (DoD-3, seam: OrderService.total):
  callers in repo: 4 (`git grep -nw total_for_order` @ 3f2a1c9) — src/api/orders.py:88, …
  string/dynamic:  1 (`git grep -n "'total_for_order'"`) — src/jobs/registry.yaml:12
  outside repo:    unknown — the billing service reads the same table (no access);
                   flagged for the ticket, not verified here
  blind spots:     reflection in src/plugins/* (dynamic dispatch by name);
                   no search covers a consumer that builds the name at runtime
```

Three lines and a named unknown beat "checked, nothing found" every time.

## Choosing the test seam (same phase, same question)

The radius tells you what the change can break; the seam decides where you can
*see* it break. Pick the **highest practical level that still proves
user-observable behaviour**, preferring an existing seam over a new one and a
real boundary (route, DB, queue) over a deep mock. A mock-shaped seam that stays
green while the real path is broken is exactly the failure this step prevents.
Record the chosen seam in the plan, next to the radius that motivated it.
Escalate the choice to the user only when it changes a contract, the cost of the
work, or how much the result can be trusted.

## When the radius is bigger than the plan

If the search turns up consumers the ticket never mentioned — another service,
a public contract, a stored value — that is a **tier event**, not a footnote:
re-read the tier line (a tier only moves up), and add the Reversibility section
to the spec if the change has become one-way. Say it out loud in the plan
rather than absorbing it silently: a plan that quietly grew is the plan the
reviewer cannot check.
