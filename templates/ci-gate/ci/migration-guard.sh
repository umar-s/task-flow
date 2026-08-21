#!/usr/bin/env bash
# migration-guard.sh — tool-agnostic, path-based migration policy gate.
#
# Policy:
#   1) forward-only / immutability — an already-committed migration file may not
#      be modified, deleted or renamed. Only NEW migration files are allowed.
#   2) destructive DDL in a NEW migration requires an explicit approval marker
#      ("destructive: approved" in a comment) inside the same file.
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

MIGRATION_DIRS="${MIGRATION_DIRS:-migrations db/migrate db/migration prisma/migrations}"
STAGED="${STAGED:-0}"
[ "${1:-}" = "--staged" ] && STAGED=1

# Destructive patterns (POSIX-extended). Two families:
#   SQL — case-insensitive, anywhere in the file: DROP <object> (table, column,
#         schema, database, index, constraint, view, type, sequence, trigger,
#         function, procedure, materialized view), TRUNCATE, DELETE FROM, and
#         ALTER TABLE … DROP <anything> (the COLUMN keyword is optional in
#         PostgreSQL and MySQL; dropping a constraint deserves the marker too).
#   ORM — the table/column-dropping DSL tokens of the frameworks whose dirs are
#         scanned by default: Rails/Alembic (drop_table, drop_column,
#         remove_column, remove_reference, remove_belongs_to, remove_timestamps,
#         drop_join_table), Django (DeleteModel, RemoveField), Laravel
#         (Schema::drop, Schema::dropIfExists), Knex/Sequelize/TypeORM
#         (dropTable, dropColumn, removeColumn). Matched case-sensitively, as
#         whole words, and ONLY in the forward part of the file: when an
#         up/upgrade/change definition precedes a down/downgrade definition,
#         everything from that down on is not scanned for the ORM family,
#         because a conventional down() drops exactly what up() created and
#         flagging every reversible migration would make the marker worthless.
#         Any other layout (down first, no up, no down) is scanned in full.
# Known limits (documented in ci/README.md): a statement split across lines,
# SQL assembled from several strings, DELETE without FROM (MSSQL), a type
# change that truncates data, RunSQL/RunPython with non-literal SQL, and DSLs
# not listed here are NOT detected — that residue is the LLM security pass's
# job, never a reason to widen this regex into a parser.
SQL_RE='(DROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|INDEX|CONSTRAINT|VIEW|TYPE|SEQUENCE|TRIGGER|FUNCTION|PROCEDURE|MATERIALIZED)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].*[[:space:]]DROP[[:space:]])'
ORM_RE='(^|[^A-Za-z0-9_])(drop_table|drop_column|remove_column|remove_reference|remove_belongs_to|remove_timestamps|drop_join_table|dropTable|dropColumn|removeColumn|DeleteModel|RemoveField|Schema::drop|Schema::dropIfExists)([^A-Za-z0-9_]|$)'
# Start of an up/upgrade/change and a down/downgrade definition (Rails, Alembic,
# Laravel, Knex, Sequelize, TypeORM). Exported for awk via ENVIRON — `-v` would
# re-process backslash escapes.
_DEF='^[[:space:]]*(public[[:space:]]+)?(async[[:space:]]+)?(def[[:space:]]+|function[[:space:]]+|exports\.|export[[:space:]]+(async[[:space:]]+)?(function[[:space:]]+|const[[:space:]]+))?'
export UP_RE="${_DEF}(up|upgrade|change)[[:space:]]*([(:=]|$)"
export DOWN_RE="${_DEF}(down|downgrade)[[:space:]]*([(:=]|$)"
APPROVAL_RE='destructive:[[:space:]]*approved'

forward_part() {     # stdin: file content → the part scanned for ORM tokens
  awk '
    { lines[NR] = $0 }
    !u && $0 ~ ENVIRON["UP_RE"]   { u = NR }
    !d && $0 ~ ENVIRON["DOWN_RE"] { d = NR }
    END {
      cut = (u && d && u < d) ? d : NR + 1
      for (i = 1; i < cut; i++) print lines[i]
    }'
}
is_destructive() {   # stdin: file content → rc 0 if a destructive statement is found
  local content; content=$(cat)
  if printf '%s\n' "$content" | grep -Eiq "$SQL_RE"; then return 0; fi
  printf '%s\n' "$content" | forward_part | grep -Eq "$ORM_RE"
}

# Build a regex matching any path under a configured migrations dir.
dir_re=""
for d in $MIGRATION_DIRS; do
  d_esc=$(printf '%s' "$d" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
  dir_re="${dir_re:+$dir_re|}(^|/)${d_esc}/"
done
if [ -z "$dir_re" ]; then
  echo "migration-guard: no MIGRATION_DIRS configured, skipping"
  exit 0
fi
is_migration() { printf '%s' "$1" | grep -Eq "$dir_re"; }

# Resolve the change set + how to read a file at the evaluated tip.
if [ "$STAGED" = "1" ]; then
  changes=$(git -c core.quotePath=false diff --cached --name-status --no-renames)
  read_tip() { git show ":$1"; }
else
  BASE="${GATE_BASE_REF:-}"
  if [ -z "$BASE" ]; then
    if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then
      BASE="$CI_MERGE_REQUEST_DIFF_BASE_SHA"          # GitLab MR pipeline
    elif [ -n "${GITHUB_BASE_REF:-}" ]; then
      BASE="origin/${GITHUB_BASE_REF}"                # GitHub PR
    fi
  fi
  if [ -z "$BASE" ]; then
    echo "migration-guard: cannot resolve base ref (set GATE_BASE_REF). Failing closed." >&2
    exit 2
  fi
  if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    echo "migration-guard: base '$BASE' not in clone — need full history (GIT_DEPTH=0 / fetch-depth: 0). Failing closed." >&2
    exit 2
  fi
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
      if printf '%s' "$content" | is_destructive; then
        if printf '%s' "$content" | grep -Eiq "$APPROVAL_RE"; then
          echo "warn [destructive]  $path : destructive DDL present but approved" >&2
        else
          echo "FAIL [destructive]  $path : destructive DDL without '-- destructive: approved' marker" >&2
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
