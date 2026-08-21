#!/usr/bin/env bash
# migration-guard.sh — tool-agnostic, path-based migration policy gate.
#
# Policy:
#   1) forward-only / immutability — an already-committed migration file may not
#      be modified, deleted or renamed. Only NEW migration files are allowed.
#   2) destructive DDL in a NEW migration requires an explicit approval marker
#      with a reason — `destructive: approved (<ticket or reason>)` in a
#      comment inside the same file. A bare `destructive: approved` is not
#      an approval: the parenthesised reason is what a reviewer and a
#      post-mortem can hold someone to.
#
# Config (env):
#   MIGRATION_DIRS  space-separated dir names treated as migrations
#                   (default: "migrations db/migrate db/migration prisma/migrations")
#   GATE_BASE_REF   base ref to diff against (overrides auto-detect)
#   STAGED=1        evaluate the staged index instead of a commit range
#
# Usage:
#   ci/migration-guard.sh            # CI: auto-detect base ref
#   ci/migration-guard.sh --staged   # local / pre-commit: check staged changes
#
# Exit codes: 0 ok · 1 policy violation · 2 config/infra (fails closed).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
MIGRATION_DIRS="${MIGRATION_DIRS:-migrations db/migrate db/migration prisma/migrations}"
STAGED="${STAGED:-0}"
[ "${1:-}" = "--staged" ] && STAGED=1
# Print the knobs that decide the verdict: a job log that does not say what the
# guard was watching cannot be told apart from one that watched nothing.
echo "migration-guard: dirs=\"$MIGRATION_DIRS\" staged=$STAGED${GATE_BASE_REF:+ base=$GATE_BASE_REF}"

# Destructive patterns (POSIX-extended). Two families, both matched only in
# the FORWARD PART of a migration (see forward_part below):
#   SQL — case-insensitive: DROP <object> (table, column, schema, database,
#         index, constraint, view, type, sequence, trigger, function, procedure,
#         materialized view), TRUNCATE, DELETE FROM, and ALTER TABLE … DROP
#         <anything> (the COLUMN keyword is optional in PostgreSQL and MySQL;
#         dropping a constraint deserves the marker too).
#   ORM — case-sensitive, whole words: the table/column-dropping DSL tokens of
#         the frameworks whose dirs are scanned by default: Rails/Alembic
#         (drop_table, drop_column, remove_column(s), remove_reference,
#         remove_belongs_to, remove_timestamps, drop_join_table), Django
#         (DeleteModel, RemoveField), Laravel (Schema::drop, Schema::dropIfExists,
#         dropTimestamps, dropSoftDeletes), Knex/Sequelize/TypeORM
#         (dropTable(IfExists), dropColumn(s), removeColumn).
# Forward part: everything except the BODY of a down/downgrade definition that
# follows an up/upgrade/change one at the same indentation — the body is
# recognised by indentation (deeper lines, a lone opening brace, the closing
# `end`/`}`), so helpers and anything else after the down block ARE scanned.
# A conventional down() drops exactly what up() created, and flagging every
# reversible migration would make the marker worthless. Files without an up
# definition (plain SQL, Django, down-only files) are scanned in full. This is
# a convenience for conventional layouts, not a security boundary: deliberate
# evasion through indentation is the LLM security pass's job.
# Known limits (documented in ci/README.md): a statement split across lines,
# SQL assembled from several strings, DELETE without FROM (MSSQL), a type
# change that truncates data, RunSQL/RunPython with non-literal SQL, and DSLs
# not listed here are NOT detected — that residue is the LLM security pass's
# job, never a reason to widen this regex into a parser.
SQL_RE='(DROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|INDEX|CONSTRAINT|VIEW|TYPE|SEQUENCE|TRIGGER|FUNCTION|PROCEDURE|MATERIALIZED)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].*[[:space:]]DROP[[:space:]])'
ORM_RE='(^|[^A-Za-z0-9_])(drop_table|drop_column|remove_columns?|remove_reference|remove_belongs_to|remove_timestamps|drop_join_table|dropTable(IfExists)?|dropColumns?|removeColumn|dropTimestamps|dropSoftDeletes|DeleteModel|RemoveField|Schema::drop|Schema::dropIfExists)([^A-Za-z0-9_]|$)'
# up/upgrade/change and down/downgrade definitions (Rails incl. `def self.`,
# Alembic, Laravel, Knex/Sequelize/TypeORM incl. `exports.`, `module.exports.`,
# `export const`, bare `const`/`let`). A bare assignment (`down = 2`) does NOT
# count — only a prefixed one. A down definition counts only at the SAME
# indentation as the up definition (a `down:` key or a `down(q)` call nested
# inside up() is neither). Exported for awk via ENVIRON: `-v` would re-process
# backslash escapes.
_PFX_OPT='(public[[:space:]]+)?(async[[:space:]]+)?(def[[:space:]]+(self\.)?|function[[:space:]]+)?'
_PFX_REQ='((module\.)?exports\.|export[[:space:]]+(async[[:space:]]+)?(function[[:space:]]+|const[[:space:]]+)|const[[:space:]]+|let[[:space:]]+|var[[:space:]]+)'
export UP_RE="^[[:space:]]*(${_PFX_OPT}(up|upgrade|change)[[:space:]]*([(:{]|\$)|${_PFX_REQ}(up|upgrade|change)[[:space:]]*[=:(])"
export DOWN_RE="^[[:space:]]*(${_PFX_OPT}(down|downgrade)[[:space:]]*([(:{]|\$)|${_PFX_REQ}(down|downgrade)[[:space:]]*[=:(])"
# The marker must carry a reason: at least one letter or digit inside the
# parentheses. `approved ()` and `approved (  )` are bare markers.
APPROVAL_RE='destructive:[[:space:]]*approved[[:space:]]*\([^)]*[[:alnum:]][^)]*\)'
BARE_MARKER_RE='destructive:[[:space:]]*approved'

forward_part() {     # stdin: file content → the same lines with down-block bodies blanked; rc = awk's
  awk '
    function indent(s) { match(s, /^[[:space:]]*/); return RLENGTH }
    { lines[NR] = $0 }
    # A one-line Rails `dir.down { … }` inside `reversible` is the reverse of the
    # surrounding change: that whole line is not scanned.
    /^[[:space:]]*dir\.down[[:space:]]*\{.*\}[[:space:]]*$/ { lines[NR] = ""; next }
    !u && $0 ~ ENVIRON["UP_RE"] { u = NR; ui = indent($0); next }
    u && !skip && $0 ~ ENVIRON["DOWN_RE"] && indent($0) == ui { skip = 1; lines[NR] = ""; next }
    skip {
      # body: deeper lines, blank lines, a lone opening brace (Allman style)
      if ($0 ~ /^[[:space:]]*$/ || indent($0) > ui || $0 ~ /^[[:space:]]*[{(][[:space:]]*$/) { lines[NR] = ""; next }
      # a bare closer at the definition level ends the block and is not scanned
      if ($0 ~ /^[[:space:]]*(end|[})\]]+[;,]?)[[:space:]]*$/) { lines[NR] = ""; skip = 0; next }
      skip = 0   # any other dedented line: the block ended above — this line IS scanned
    }
    END { for (i = 1; i <= NR; i++) print lines[i] }'
}
is_destructive() {   # stdin: file content → 0 destructive · 1 clean · 2 cannot evaluate
  local content fwd
  content=$(cat)
  fwd=$(printf '%s\n' "$content" | forward_part) || return 2
  # grep without -q reads its whole input: `-q` exits on the first match and the
  # pipe writer dies of SIGPIPE (141) on a large file; a here-string would need a
  # temp file whose failure reads as "clean". Exit codes stay 0/1/2.
  if printf '%s\n' "$fwd" | grep -Ei "$SQL_RE" >/dev/null; then return 0; else [ $? -le 1 ] || return 2; fi
  if printf '%s\n' "$fwd" | grep -E  "$ORM_RE" >/dev/null; then return 0; else [ $? -le 1 ] || return 2; fi
  return 1
}

# Build a regex matching any path under a configured migrations dir.
dir_re=""
for d in $MIGRATION_DIRS; do
  d_esc=$(printf '%s' "$d" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
  dir_re="${dir_re:+$dir_re|}(^|/)${d_esc}/"
done
if [ -z "$dir_re" ]; then
  # An empty MIGRATION_DIRS is a configuration error, not "no migrations": a
  # blank CI variable would otherwise switch the whole layer off from the
  # settings UI, leaving a green job that inspected nothing.
  echo "migration-guard: MIGRATION_DIRS is empty — nothing would ever be checked. Failing closed." >&2
  exit 2
fi
# bash ERE, no external tool: a broken grep must never turn a migration into "not a migration".
is_migration() { [[ "$1" =~ $dir_re ]]; }

# Resolve the change set + how to read a file at the evaluated tip.
if [ "$STAGED" = "1" ]; then
  changes=$(git -c core.quotePath=false diff --cached --name-status --no-renames)
  read_tip() { git show ":$1"; }
else
  BASE=$(GATE_LAYER=migration-guard bash "$here/base-ref.sh") || exit $?
  changes=$(git -c core.quotePath=false diff --name-status --no-renames "${BASE}...HEAD")
  read_tip() { git show "HEAD:$1"; }
fi

fail=0
while IFS=$'\t' read -r status path _rest; do
  [ -z "${status:-}" ] && continue
  is_migration "$path" || continue
  case "$status" in
    A)  # new migration — allowed, but scan for unapproved destructive DDL
      # Fail closed on an unreadable file: an empty read would sail through the
      # destructive-DDL grep and report a pass the guard never established.
      if ! content=$(read_tip "$path"); then
        echo "migration-guard: cannot read '$path' at the evaluated tip; refusing to pass a migration it could not inspect. Failing closed." >&2
        exit 2
      fi
      # Three outcomes, and only the clean one may pass: a broken awk/grep is a
      # verdict nobody established, not a pass.
      printf '%s' "$content" | is_destructive && drc=0 || drc=$?
      if [ "$drc" -ge 2 ]; then
        echo "migration-guard: cannot evaluate '$path' (awk/grep failed); refusing to pass a migration it could not inspect. Failing closed." >&2
        exit 2
      fi
      if [ "$drc" -eq 0 ]; then
        # Three grep outcomes again: found / not found / grep broke.
        if printf '%s\n' "$content" | grep -Ei "$APPROVAL_RE" >/dev/null; then arc=0; else arc=$?; fi
        if [ "$arc" -ge 2 ]; then
          echo "migration-guard: cannot evaluate '$path' (grep failed on the marker check). Failing closed." >&2
          exit 2
        fi
        if [ "$arc" -eq 0 ]; then
          echo "warn [destructive]  $path : destructive DDL present but approved" >&2
        elif printf '%s\n' "$content" | grep -Ei "$BARE_MARKER_RE" >/dev/null; then
          echo "FAIL [destructive]  $path : marker present but carries no reason — use '-- destructive: approved (TICKET-123: data archived)'" >&2
          fail=1
        else
          echo "FAIL [destructive]  $path : destructive DDL without a '-- destructive: approved (<ticket or reason>)' marker" >&2
          fail=1
        fi
      fi
      ;;
    *)  # M / D / T / anything on an already-committed migration
      echo "FAIL [immutable]    $path : committed migration changed ($status); migrations are forward-only" >&2
      fail=1
      ;;
  esac
done <<< "$changes"

if [ "$fail" = "1" ]; then
  echo "migration-guard: FAILED" >&2
  exit 1
fi
echo "migration-guard: OK"
