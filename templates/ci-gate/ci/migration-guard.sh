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

# Destructive patterns (case-insensitive, POSIX-extended). Two families:
#   SQL  — DROP TABLE/COLUMN/..., TRUNCATE, DELETE FROM, ALTER TABLE ... DROP COLUMN
#   ORM  — the DSL tokens of the migration frameworks whose dirs are scanned by
#          default: Rails/Alembic (drop_table, remove_column), Django (DeleteModel,
#          RemoveField), Laravel (Schema::drop/dropIfExists), Knex/Sequelize/
#          TypeORM (dropTable, dropColumn, removeColumn).
# Known limits (documented in ci/README.md): a statement split across lines,
# SQL built inside a string, and DSLs not listed here are NOT detected — that
# residue is the LLM security pass's job, never a reason to widen this regex
# into a parser.
DESTRUCTIVE_RE='(DROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|INDEX|CONSTRAINT)|TRUNCATE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].*DROP[[:space:]]+COLUMN|drop_table|drop_column|remove_column|dropTable|dropColumn|removeColumn|DeleteModel|RemoveField|RemoveModel|Schema::drop(IfExists)?)'
APPROVAL_RE='destructive:[[:space:]]*approved'

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
      if printf '%s' "$content" | grep -Eiq "$DESTRUCTIVE_RE"; then
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
