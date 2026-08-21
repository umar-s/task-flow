#!/usr/bin/env bash
# tests/migration-guard.sh — negative controls for templates/ci-gate/ci/migration-guard.sh.
#
# Every fixture is a NEW migration staged in a throwaway repo, judged with
# `--staged`. Expected exit: 0 clean · 1 needs the marker · 2 cannot evaluate.
# The point is the false negatives (a drop that must be caught) AND the false
# positives (a default reversible template that must NOT need the marker):
# both directions are what a regex change silently breaks.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/templates/ci-gate/ci/migration-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
pass=0; fail=0

t() {  # name path expected body
  local name="$1" path="$2" expect="$3" body="$4" rc err
  mkdir -p "$(dirname "$path")"; printf '%b\n' "$body" > "$path"; git add -A
  err=$(bash "$GUARD" --staged 2>&1 >/dev/null) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ] && ! printf '%s' "$err" | grep -qi 'warning'; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$err" >&2
  fi
  git rm -rq --cached . >/dev/null 2>&1 || true
  rm -rf db migrations prisma
}

# --- default reversible templates: NO marker needed (drop only in down) ---
t laravel-default   migrations/2024_a.php 0 'public function up(): void\n{\n  Schema::create("t", fn($t) => $t->id());\n}\npublic function down(): void\n{\n  Schema::dropIfExists("t");\n}'
t knex-default      migrations/20240101_a.js 0 'exports.up = k => k.schema.createTable("t", t => t.increments());\nexports.down = k => k.schema.dropTable("t");'
t knex-module-exports migrations/20240101_b.js 0 'module.exports.up = k => k.schema.createTable("t", t => t.increments());\nmodule.exports.down = k => k.schema.dropTableIfExists("t");'
t knex-const-style  migrations/20240101_c.js 0 'const up = async k => { await k.schema.createTable("t", t => t.increments()); };\nconst down = async k => { await k.schema.dropTable("t"); };\nmodule.exports = { up, down };'
t sequelize-object  migrations/20240101_d.js 0 'module.exports = {\n  up: async (q) => { await q.createTable("t", {}); },\n  down: async (q) => { await q.dropTable("t"); },\n};'
t typeorm-class     migrations/1700_a.ts 0 'export class M implements MigrationInterface {\n  public async up(queryRunner: QueryRunner): Promise<void> {\n    await queryRunner.query(`CREATE TABLE "t" ("id" int)`);\n  }\n  public async down(queryRunner: QueryRunner): Promise<void> {\n    await queryRunner.query(`DROP TABLE "t"`);\n  }\n}'
t rails-up-down     db/migrate/001_a.rb 0 'def up\n  create_table :t\nend\ndef down\n  drop_table :t\nend'
t rails-self-up-down db/migrate/001_b.rb 0 'def self.up\n  create_table :t\nend\ndef self.down\n  drop_table :t\nend'
t rails-reversible  db/migrate/001_c.rb 0 'def change\n  reversible do |dir|\n    dir.up { add_column :t, :c, :string }\n    dir.down { remove_column :t, :c }\n  end\nend'
t alembic-default   migrations/versions/a1_a.py 0 'def upgrade():\n    op.create_table("t", sa.Column("id", sa.Integer))\n\ndef downgrade():\n    op.drop_table("t")'
t alembic-execute   migrations/versions/a1_b.py 0 'def upgrade():\n    op.execute("CREATE TABLE t (id int)")\n\ndef downgrade():\n    op.execute("DROP TABLE t")'

# --- drops in the forward part: marker needed ---
t laravel-drop-in-up migrations/2024_b.php 1 'public function up(): void\n{\n  Schema::dropIfExists("old");\n}\npublic function down(): void {}'
t laravel-dropTimestamps migrations/2024_c.php 1 'public function up(): void\n{\n  Schema::table("t", fn($t) => $t->dropTimestamps());\n}\npublic function down(): void {}'
t knex-dropTableIfExists migrations/20240102_a.js 1 'exports.up = k => k.schema.dropTableIfExists("legacy");\nexports.down = k => {};'
t knex-dropColumns  migrations/20240102_b.js 1 'exports.up = k => k.schema.alterTable("t", t => t.dropColumns("a", "b"));\nexports.down = k => {};'
t rails-change-drop db/migrate/002_a.rb 1 'def change\n  drop_table :legacy\nend'
t rails-remove_columns db/migrate/002_b.rb 1 'def change\n  remove_columns :users, :a, :b\nend'
t rails-remove_reference db/migrate/002_c.rb 1 'def change\n  remove_reference :posts, :author\nend'
t alembic-drop_column migrations/versions/a2_a.py 1 'def upgrade():\n    op.drop_column("t", "c")\ndef downgrade():\n    pass'
t django-DeleteModel migrations/0002_a.py 1 'operations = [migrations.DeleteModel(name="Old")]'
t django-RemoveField migrations/0002_b.py 1 'operations = [migrations.RemoveField(model_name="x", name="f")]'
t sql-drop-table    prisma/migrations/1/migration.sql 1 'DROP TABLE "t";'
t sql-alter-drop-no-column-kw migrations/0003_a.sql 1 'ALTER TABLE users DROP email;'
t sql-drop-view     migrations/0003_b.sql 1 'DROP VIEW v_users;'
t sql-goose-down    migrations/0003_c.sql 1 '-- +goose Up\nCREATE TABLE t (id int);\n-- +goose Down\nDROP TABLE t;'

# --- bypass attempts: must still be caught ---
t bypass-down-first migrations/20240103_a.js 1 'export async function down(k) { await k.schema.dropTable("t"); }\nexport async function up(k) { await k.schema.dropTable("old"); }'
t bypass-up-redefined db/migrate/003_a.rb 1 'def up\n  create_table :t\nend\ndef down\n  drop_table :t\nend\ndef up\n  drop_table :users\nend'
t bypass-alembic-redefined migrations/versions/a3_a.py 1 'def upgrade():\n    pass\ndef downgrade():\n    op.drop_table("t")\ndef upgrade():\n    op.drop_table("users")'
t bypass-bare-assignment migrations/0004_a.py 1 'up = 1\ndown = 2\noperations = [migrations.DeleteModel(name="Old")]'
t rails-down-only   db/migrate/004_a.rb 1 'def down\n  drop_table :t\nend'

# --- substrings and comments: must NOT be caught ---
t comment-removefield migrations/0005_a.sql 0 '-- supports the removefield UI\nCREATE TABLE t (id int);'
t identifier-droptable migrations/0005_b.sql 0 'CREATE TABLE droptable_audit (id int);'
t sql-dropped_at    migrations/0005_c.sql 0 'ALTER TABLE t ADD COLUMN dropped_at timestamp;'
t rails-add_column  db/migrate/005_a.rb 0 'def change\n  add_column :users, :email, :string\nend'


# --- nested `down` inside up(), one-line dir.down, and big files: the reviewer's fail-open layouts ---
t rails-reversible-then-drop db/migrate/007_a.rb 1 'def change\n  reversible do |dir|\n    dir.up { add_column :t, :c, :string }\n    dir.down { remove_column :t, :c }\n  end\n  drop_table :legacy\nend'
t rails-reversible-multiline db/migrate/007_b.rb 1 'def change\n  reversible do |dir|\n    dir.down do\n      remove_column :t, :c\n    end\n  end\nend'
t knex-nested-down-key migrations/20240104_a.js 1 'exports.up = async k => {\n  const opts = {\n    down: false,\n  };\n  await k.schema.dropTable("users");\n};\nexports.down = async () => {};'
t typeorm-down-call-in-up migrations/1700_b.ts 1 'export class M {\n  public async up(q) {\n    down(q);\n    await q.query("DROP TABLE old");\n  }\n  public async down(q) {}\n}'
t sequelize-nested-up-key migrations/20240104_b.js 0 'module.exports = {\n  up: async (q) => { await q.createTable("t", {}); },\n  down: async (q) => {\n    await q.bulkInsert("x", [{\n      up: 1,\n    }]);\n    await q.dropTable("t");\n  },\n};'
big=$(head -c 120000 /dev/zero | tr '\0' 'x' | fold -w 100)
t big-file-drop-first-line migrations/0008_a.sql 1 "DROP TABLE t;\n$big"
t big-file-drop-with-marker migrations/0008_b.sql 0 "-- destructive: approved (T-9)\nDROP TABLE t;\n$big"
t big-file-clean migrations/0008_c.sql 0 "CREATE TABLE t (id int);\n$big"


# --- helpers AFTER the down block are forward code and must be scanned ---
t rails-private-helper-after-down db/migrate/008_a.rb 1 'def up\n  cleanup\nend\ndef down\n  raise ActiveRecord::IrreversibleMigration\nend\nprivate\ndef cleanup\n  drop_table :legacy\nend'
t alembic-helper-after-downgrade migrations/versions/a4_a.py 1 'def upgrade():\n    _drop_legacy()\n\ndef downgrade():\n    pass\n\ndef _drop_legacy():\n    op.drop_table("legacy")'
t knex-hoisted-helper migrations/20240105_a.js 1 'exports.up = async k => { await dropLegacy(k); };\nexports.down = async () => {};\nasync function dropLegacy(k) { await k.schema.dropTable("legacy"); }'
t typeorm-private-helper migrations/1700_c.ts 1 'export class M {\n  public async up(q) {\n    await this.cleanup(q);\n  }\n  public async down(q) {}\n  private async cleanup(q) {\n    await q.query("DROP TABLE legacy");\n  }\n}'
t laravel-allman-helper migrations/2024_d.php 1 'public function up(): void\n{\n    $this->cleanup();\n}\npublic function down(): void\n{\n    Schema::dropIfExists("t");\n}\nprivate function cleanup(): void\n{\n    Schema::dropIfExists("legacy");\n}'
t rails-drop-in-down-clean-helper db/migrate/008_b.rb 0 'def up\n  create_table :t\nend\ndef down\n  drop_table :t\nend\nprivate\ndef helper\n  add_column :t, :c, :string\nend'
t sequelize-multiline-down migrations/20240105_b.js 0 'module.exports = {\n  up: async (q) => {\n    await q.createTable("t", {});\n  },\n  down: async (q) => {\n    await q.dropTable("t");\n  },\n};'

# --- marker ---
t marker-sql        migrations/0006_a.sql 0 '-- destructive: approved (T-1, archived)\nDROP VIEW v;'
t marker-rails      db/migrate/006_a.rb 0 '# destructive: approved (T-2)\ndef change\n  drop_table :legacy\nend'

# --- infrastructure failures fail closed (rc 2), never pass ---
mkdir -p "$TMP/badbin"; printf '#!/bin/sh\necho "awk: simulated failure" >&2\nexit 2\n' > "$TMP/badbin/awk"; chmod +x "$TMP/badbin/awk"
mkdir -p migrations; printf 'operations = [migrations.DeleteModel(name="Old")]\n' > migrations/0007_a.py; git add -A
err=$(PATH="$TMP/badbin:$PATH" bash "$GUARD" --staged 2>&1 >/dev/null) && rc=0 || rc=$?
if [ "$rc" = 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL broken-awk-fails-closed: rc=%s expected=2\n%s\n' "$rc" "$err" >&2; fi
git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf migrations


mkdir -p "$TMP/badgrep"; printf '#!/bin/sh\necho "grep: simulated failure" >&2\nexit 2\n' > "$TMP/badgrep/grep"; chmod +x "$TMP/badgrep/grep"
mkdir -p migrations; printf 'operations = [migrations.DeleteModel(name="Old")]\n' > migrations/0007_b.py; git add -A
err=$(PATH="$TMP/badgrep:$PATH" bash "$GUARD" --staged 2>&1 >/dev/null) && rc=0 || rc=$?
if [ "$rc" = 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL broken-grep-fails-closed: rc=%s expected=2\n%s\n' "$rc" "$err" >&2; fi
git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf migrations

# --- portability: the same verdicts under busybox awk/grep when available ---
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$TMP/bb"; ln -sf "$(command -v busybox)" "$TMP/bb/awk"; ln -sf "$(command -v busybox)" "$TMP/bb/grep"
  for fx in 'knex-default|0|exports.up = k => k.schema.createTable("t");\nexports.down = k => k.schema.dropTable("t");' \
            'knex-drop-in-up|1|exports.up = k => k.schema.dropTableIfExists("t");\nexports.down = k => {};' \
            'bypass-up-redefined|1|def up\n  create_table :t\nend\ndef down\n  drop_table :t\nend\ndef up\n  drop_table :users\nend'; do
    IFS='|' read -r name expect body <<< "$fx"
    mkdir -p migrations; printf '%b\n' "$body" > migrations/bb.rb; git add -A
    err=$(PATH="$TMP/bb:$PATH" bash "$GUARD" --staged 2>&1 >/dev/null) && rc=0 || rc=$?
    if [ "$rc" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL busybox/%s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$err" >&2; fi
    git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf migrations
  done
else
  echo "tests/migration-guard: busybox not available — portability subset skipped" >&2
fi

echo "tests/migration-guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
