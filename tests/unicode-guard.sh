#!/usr/bin/env bash
# tests/unicode-guard.sh — negative controls for templates/ci-gate/ci/unicode-guard.sh.
#
# Each fixture is a staged change in a throwaway repo, judged with `--staged`
# (plus a few range-mode and tool-failure controls). Expected exit:
# 0 clean · 1 forbidden code point in an added line · 2 cannot evaluate.
# Both directions matter: the invisible characters that MUST be caught, and the
# ordinary non-ASCII text (Cyrillic, emoji with ZWJ, Arabic with marks) that
# must NOT be — a guard that trips on the owner's prose gets switched off.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/templates/ci-gate/ci/unicode-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q -b main . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
pass=0; fail=0

t() {  # name path expected body   (body: printf %b format — \x escapes are raw bytes)
  local name="$1" path="$2" expect="$3" body="$4" rc out
  mkdir -p "$(dirname "$path")"; printf '%b' "$body" > "$path"; git add -A
  out=$(bash "$GUARD" --staged 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$out" >&2; fi
  git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf src
}

run_fixtures() {
# --- must be caught ---
t rlo-in-comment      src/a.js 1 '// check if admin \xe2\x80\xae { return; }\n'
t lre                 src/b.js 1 'x = "\xe2\x80\xaa";\n'
t pdf                 src/b2.js 1 'x = "\xe2\x80\xac";\n'
t lri-isolate         src/c.py 1 's = "\xe2\x81\xa6abc\xe2\x81\xa9"\n'
t fsi                 src/c2.py 1 's = "\xe2\x81\xa8"\n'
t zero-width-space    src/d.go 1 'if user\xe2\x80\x8bName == "" {\n'
t word-joiner         src/e.rb 1 'admin\xe2\x81\xa0 = true\n'
t tag-char-smuggled   src/f.md 1 'normal text\xf3\xa0\x81\x81\xf3\xa0\x81\x82 hidden\n'
t tag-cancel          src/f2.md 1 'x\xf3\xa0\x81\xbf\n'
t bom-mid-line        src/g.ts 1 'const a = 1;\xef\xbb\xbf const b = 2;\n'
t bom-start-of-line-2 src/h.ts 1 'const a = 1;\n\xef\xbb\xbfconst b = 2;\n'
t bad-on-line-200     src/k.txt 1 "$(printf 'line\\n%.0s' $(seq 199))bad \\xe2\\x80\\xae\\n"

# --- must NOT be caught ---
t bom-file-start      src/l.cs 0 '\xef\xbb\xbfusing System;\n'
t zwj-emoji           src/m.md 0 'family: \xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7\n'
t zwnj-persian        src/n.md 0 '\xd9\x85\xdb\x8c\xe2\x80\x8c\xd8\xae\xd9\x88\xd8\xa7\xd9\x87\xd9\x85\n'
t lrm-rlm             src/o.md 0 'a\xe2\x80\x8eb\xe2\x80\x8fc\n'
t soft-hyphen         src/p.md 0 'co\xc2\xadoperate\n'
t cyrillic-prose      src/q.md 0 '# Тестовый файл — проверка «кавычек» и тире\n'
t cjk                 src/r.md 0 '漢字 テスト 한국어\n'
t plain-ascii         src/s.js 0 'const x = 1;\n'
t nbsp                src/s2.md 0 'a\xc2\xa0b\n'
t no-newline-at-eof   src/s3.js 0 'const x = 1;'
}
# Fixtures that need more than one staged file or an env knob:
t2() {  # name expected setup-cmd
  local name="$1" expect="$2" setup="$3" rc out
  eval "$setup"; git add -A
  out=$(bash "$GUARD" --staged 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: rc=%s expected=%s\n%s\n' "$name" "$rc" "$expect" "$out" >&2; fi
  git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf src .gitattributes; unset UNICODE_GUARD_EXCLUDE
  git config --unset diff.external >/dev/null 2>&1 || true; git config --unset color.ui >/dev/null 2>&1 || true
  git config --unset diff.noprefix >/dev/null 2>&1 || true
}
run_fixtures_env() {
t2 second-file-dirty 1 'mkdir -p src; printf "clean\n" > src/i.txt; printf "\xe2\x80\xae" > src/j.txt'
t2 excluded-path     0 'mkdir -p src/vendor; printf "\xe2\x80\xae\n" > src/vendor/x.js; export UNICODE_GUARD_EXCLUDE="(^|/)vendor/"'
t2 exclude-does-not-leak 1 'mkdir -p src/vendor src/app; printf "\xe2\x80\xae\n" > src/vendor/x.js; printf "\xe2\x80\xae\n" > src/app/y.js; export UNICODE_GUARD_EXCLUDE="(^|/)vendor/"'
# Binary content is scanned, not skipped (skipping it would make a NUL byte an
# off switch), and the bytes AFTER a NUL count too: NULs are stripped before
# awk, because busybox awk splits a record there and the tail — exactly where
# something would be hidden — stops looking like an added line.
t2 binary-with-nul-still-scanned 1 'mkdir -p src; printf "PNG\xe2\x80\xae\x1a\0tail" > src/img.png'
t2 bytes-after-a-nul-are-scanned 1 'mkdir -p src; printf "head\0 bad \xe2\x80\xae here\n" > src/afternul.js'
t2 gitattributes-minus-diff 1 'mkdir -p src; printf "*.js -diff\n" > .gitattributes; printf "var x = \"\xe2\x80\xae\";\n" > src/evil.js'
t2 formfeed-does-not-disable 1 'mkdir -p src; printf "a\x0cb\n\xe2\x80\xae\n" > src/ff.js'
t2 inline-allow 0 'mkdir -p src; printf "rle \xe2\x80\xab fixture // unicode-guard:allow\n" > src/fixture.js'
t2 empty-exclude-excludes-nothing 1 'mkdir -p src; printf "\xe2\x80\xae\n" > src/x.js; export UNICODE_GUARD_EXCLUDE='"''"''
t2 external-diff-ignored 1 'mkdir -p src; printf "\xe2\x80\xae\n" > src/x.js; git config diff.external /bin/true'
t2 color-ui-always 1 'mkdir -p src; printf "\xe2\x80\xae\n" > src/x.js; git config color.ui always'
t2 noprefix-forced-off 1 'mkdir -p src; printf "\xe2\x80\xae\n" > src/x.js; git config diff.noprefix true'
t2 single-line-hunk-numbering 1 'mkdir -p src; printf "\xe2\x80\xae\n" > src/one.js'
t2 removed-line-with-rlo 0 'mkdir -p src; printf "bad \xe2\x80\xae\n" > src/old.js; git add -A; git -c user.name=t -c user.email=t@t commit -qm old; printf "fixed\n" > src/old.js'
t2 only-output-is-path-line 1 'mkdir -p src; printf "x\n\xe2\x80\xae\n" > src/z.js'
# An added line whose CONTENT starts with "++ " reaches the parser as "+++ …":
# read as a file header it would end the hunk and hide everything after it.
t2 content-line-looks-like-a-header 1 'mkdir -p src; printf "++ diff marker\n\xe2\x80\xae\n" > src/hdr.md'
t2 content-line-looks-like-diff-git 1 'mkdir -p src; printf "+diff --git a/x b/x\n\xe2\x80\xae\n" > src/hdr2.md'
t2 content-line-looks-like-hunk 1 'mkdir -p src; printf "+@@ -1 +1 @@\n\xe2\x80\xae\n" > src/hdr3.md'
# An exclude that matches every path is an off switch, not an exclusion
t2 exclude-matches-everything 2 'mkdir -p src; printf "clean\n" > src/ok.js; export UNICODE_GUARD_EXCLUDE=.'
t2 exclude-dot-star 2 'mkdir -p src; printf "clean\n" > src/ok.js; export UNICODE_GUARD_EXCLUDE=".*"'
}

run_fixtures
run_fixtures_env

# --- the finding names the file and the new-side line number ---
mkdir -p src; printf 'a\nb\n\xe2\x80\xae\n' > src/ln.js; git add -A
out=$(bash "$GUARD" --staged 2>/dev/null) && rc=0 || rc=$?
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^src/ln.js:3: bidi'; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL line-number: rc=%s\n%s\n' "$rc" "$out" >&2; fi
git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf src

# --- range mode: the MR's commits against a base ---
git checkout -q -b feature
mkdir -p src; printf 'bad \xe2\x80\xae\n' > src/r.js; git add -A; git -c user.name=t -c user.email=t@t commit -qm feat
out=$(GATE_BASE_REF=main bash "$GUARD" 2>&1) && rc=0 || rc=$?
[ "$rc" = 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL range-mode-dirty: rc=%s\n%s\n' "$rc" "$out" >&2; }
out=$(bash "$GUARD" 2>&1) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL range-mode-no-base: rc=%s\n%s\n' "$rc" "$out" >&2; }
out=$(GATE_BASE_REF=nope bash "$GUARD" 2>&1) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL range-mode-bad-base: rc=%s\n%s\n' "$rc" "$out" >&2; }
# a base that IS the tip empties every range: one CI variable would switch the
# layer off and still report OK
out=$(GATE_BASE_REF=HEAD bash "$GUARD" 2>&1) && rc=0 || rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'off switch'; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL base-equals-head: rc=%s\n%s\n' "$rc" "$out" >&2; fi
# the run says how much of the change it actually looked at
out=$(GATE_BASE_REF=main bash "$GUARD" 2>&1) && rc=0 || rc=$?
printf '%s' "$out" | grep -qE '[0-9]+ of [0-9]+ changed paths scanned' && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL scanned-counter missing:\n%s\n' "$out" >&2; }
out=$(UNICODE_GUARD_EXCLUDE='^src/' GATE_BASE_REF=main bash "$GUARD" 2>&1) && rc=0 || rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'every changed path was excluded'; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL all-excluded warning: rc=%s\n%s\n' "$rc" "$out" >&2; fi
git checkout -q main; git branch -q -D feature

# --- tool failures fail closed (rc 2), never pass ---
mkdir -p "$TMP/badtr"; printf '#!/bin/sh\necho "tr: simulated failure" >&2\nexit 3\n' > "$TMP/badtr/tr"; chmod +x "$TMP/badtr/tr"
mkdir -p src; printf 'clean\n' > src/t.js; git add -A
out=$(PATH="$TMP/badtr:$PATH" bash "$GUARD" --staged 2>&1) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL broken-tr: rc=%s\n%s\n' "$rc" "$out" >&2; }
git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf src

mkdir -p "$TMP/badbin"; printf '#!/bin/sh\necho "awk: simulated failure" >&2\nexit 2\n' > "$TMP/badbin/awk"; chmod +x "$TMP/badbin/awk"
mkdir -p src; printf 'clean\n' > src/w.js; git add -A
out=$(PATH="$TMP/badbin:$PATH" bash "$GUARD" --staged 2>&1) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL broken-awk: rc=%s\n%s\n' "$rc" "$out" >&2; }
mkdir -p "$TMP/badgit"; printf '#!/bin/sh\ncase "$1" in -c) echo "git: simulated failure" >&2; exit 128;; esac\nexec /usr/bin/git "$@"\n' > "$TMP/badgit/git"; chmod +x "$TMP/badgit/git"
out=$(PATH="$TMP/badgit:$PATH" bash "$GUARD" --staged 2>&1) && rc=0 || rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL broken-git: rc=%s\n%s\n' "$rc" "$out" >&2; }
git rm -rq --cached . >/dev/null 2>&1 || true; rm -rf src

# --- portability: the fixture set again under busybox awk when available ---
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$TMP/bb"; ln -sf "$(command -v busybox)" "$TMP/bb/awk"
  before=$fail
  PATH="$TMP/bb:$PATH" run_fixtures; PATH="$TMP/bb:$PATH" run_fixtures_env
  [ "$fail" = "$before" ] || echo "tests/unicode-guard: busybox awk verdicts differ from the default awk" >&2
else
  echo "tests/unicode-guard: busybox not available — portability pass skipped" >&2
fi
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$TMP/mawk"; ln -sf "$(command -v mawk)" "$TMP/mawk/awk"
  before=$fail
  PATH="$TMP/mawk:$PATH" run_fixtures; PATH="$TMP/mawk:$PATH" run_fixtures_env
  [ "$fail" = "$before" ] || echo "tests/unicode-guard: mawk verdicts differ from the default awk" >&2
fi

echo "tests/unicode-guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
