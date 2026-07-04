#!/usr/bin/env bash
#
# Sandboxed tests for install.sh. Every case runs against a throwaway copy of
# the repo with HOME pointing into a temp dir — the real $HOME is never touched.
#
# Usage: tests/install_test.sh

set -u

TEST_ROOT="$(mktemp -d)"
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null; rm -rf "$TEST_ROOT"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SRC="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0

check() { # check <desc> <command...>  — command's exit code decides pass/fail
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "  FAIL: $desc"
  fi
}

# new_env <case-name> — fresh repo copy + empty fake home; sets $H, $R, $CASE_DIR
new_env() {
  CASE_DIR="$TEST_ROOT/$1"
  H="$CASE_DIR/home"
  R="$CASE_DIR/repo"
  mkdir -p "$H"
  cp -R "$REPO_SRC" "$R"
  rm -rf "$R/.git"
}

# run_install — runs install.sh with the fake home; captures out/err/rc
run_install() {
  HOME="$H" /bin/bash "$R/install.sh" > "$CASE_DIR/out" 2> "$CASE_DIR/err"
  echo "$?" > "$CASE_DIR/rc"
}

rc_is() { [ "$(cat "$CASE_DIR/rc")" = "$1" ]; }
out_has() { grep -qF "$1" "$CASE_DIR/out"; }
gemini_has() { grep -qF "$1" "$H/.gemini/GEMINI.md"; }
gemini_unchanged() { cmp -s "$H/.gemini/GEMINI.md" "$CASE_DIR/gemini.orig"; }
snapshot_gemini() { cp "$H/.gemini/GEMINI.md" "$CASE_DIR/gemini.orig"; }
links_to_repo() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

BEGIN_MARK="<!-- managed-skills:begin -->"
END_MARK="<!-- managed-skills:end -->"

# --- normal path -----------------------------------------------------------

echo "[fresh install]"
new_env fresh
run_install
check "exits 0" rc_is 0
for d in skills .claude/skills .agents/skills .codex/skills; do
  check "code-review linked in ~/$d" links_to_repo "$H/$d/code-review" "$R/code-review"
done
check "GEMINI.md has begin marker" gemini_has "$BEGIN_MARK"
check "GEMINI.md has end marker" gemini_has "$END_MARK"
check "GEMINI.md lists code-review" gemini_has "## code-review"
check "GEMINI.md points at ~/skills path" gemini_has "~/skills/code-review/SKILL.md"

echo "[idempotent re-run]"
new_env rerun
run_install
snapshot_gemini
run_install
check "second run exits 0" rc_is 0
check "GEMINI.md byte-identical after re-run" gemini_unchanged
check "reports ok, not linked" out_has "  ok:      $H/skills/code-review"

# --- link() boundaries -----------------------------------------------------

echo "[existing non-symlink is preserved]"
new_env nonsymlink
mkdir -p "$H/.claude/skills/code-review"
echo keep > "$H/.claude/skills/code-review/marker"
run_install
check "exits non-zero (skip counted)" test "$(cat "$CASE_DIR/rc")" != "0"
check "real dir left alone" test -f "$H/.claude/skills/code-review/marker"
check "SKIP message printed" grep -qF "SKIP (not a symlink" "$CASE_DIR/err"

echo "[foreign symlink is replaced with a warning]"
new_env foreign
mkdir -p "$H/.claude/skills" "$CASE_DIR/other-repo/code-review"
ln -s "$CASE_DIR/other-repo/code-review" "$H/.claude/skills/code-review"
run_install
check "exits 0" rc_is 0
check "now points into this repo" links_to_repo "$H/.claude/skills/code-review" "$R/code-review"
check "warning shows old target" out_has "replacing symlink (was -> $CASE_DIR/other-repo/code-review)"
check "old target dir untouched" test -d "$CASE_DIR/other-repo/code-review"

echo "[link failure -> non-zero exit, no fake success]"
new_env perms
mkdir -p "$H/.codex/skills"
chmod 555 "$H/.codex/skills"
run_install
chmod 755 "$H/.codex/skills"
check "exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "FAILED message printed" grep -qF "FAILED (cannot create symlink)" "$CASE_DIR/err"
check "no fake linked: message for codex dir" bash -c "! grep -qF '  linked:  $H/.codex/skills/' '$CASE_DIR/out'"

# --- frontmatter parsing ---------------------------------------------------

echo "[missing description falls back]"
new_env nodesc
mkdir -p "$R/tmpskill"
printf -- '---\nname: tmpskill\n---\n\n# T\n' > "$R/tmpskill/SKILL.md"
run_install
check "falls back to (no description)" gemini_has "(no description)"

echo "[block-scalar description falls back instead of leaking '>-']"
new_env blockscalar
mkdir -p "$R/tmpskill"
printf -- '---\nname: tmpskill\ndescription: >-\n  folded text here\n---\n\n# T\n' > "$R/tmpskill/SKILL.md"
run_install
check "no literal >- in GEMINI.md" bash -c "! grep -qxF -- '>-' '$H/.gemini/GEMINI.md'"
check "falls back to (no description)" gemini_has "(no description)"

echo "[quoted description is unquoted]"
new_env quoted
mkdir -p "$R/tmpskill"
printf -- '---\nname: tmpskill\ndescription: "Quoted text"\n---\n\n# T\n' > "$R/tmpskill/SKILL.md"
run_install
check "quotes stripped" bash -c "grep -qxF 'Quoted text' '$H/.gemini/GEMINI.md'"

# --- stale cleanup ---------------------------------------------------------

echo "[removed skill is cleaned up, unrelated links survive]"
new_env stale
mkdir -p "$H/.claude/skills" "$CASE_DIR/elsewhere"
ln -s "$CASE_DIR/elsewhere" "$H/.claude/skills/unrelated"
run_install
rm -rf "$R/code-review"
run_install
check "exits 0" rc_is 0
check "stale link removed" test ! -e "$H/.claude/skills/code-review"
check "unrelated link survives" test -L "$H/.claude/skills/unrelated"
check "GEMINI.md entry removed" bash -c "! grep -qF '## code-review' '$H/.gemini/GEMINI.md'"

echo "[zero skills still cleans up and empties the block]"
new_env zeroskills
run_install
for d in "$R"/*/; do
  [ -f "${d}SKILL.md" ] && rm -rf "$d"
done
run_install
check "exits 0" rc_is 0
check "all repo links removed" bash -c "! ls '$H/.claude/skills/' | grep -q ."
check "block emptied of entries" bash -c "! grep -qF '## ' '$H/.gemini/GEMINI.md'"
check "markers still present" gemini_has "$BEGIN_MARK"

# --- GEMINI.md managed block -----------------------------------------------

echo "[user content around the block is preserved]"
new_env usercontent
mkdir -p "$H/.gemini"
printf 'user header\n' > "$H/.gemini/GEMINI.md"
run_install
printf 'user footer\n' >> "$H/.gemini/GEMINI.md"
run_install
check "exits 0" rc_is 0
check "header preserved" gemini_has "user header"
check "footer preserved" gemini_has "user footer"
check "block updated in place" gemini_has "## code-review"

damaged_case() { # damaged_case <name> <gemini-content>
  new_env "$1"
  mkdir -p "$H/.gemini"
  printf '%s\n' "$2" > "$H/.gemini/GEMINI.md"
  snapshot_gemini
  run_install
  check "$1: exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
  check "$1: file left untouched" gemini_unchanged
  check "$1: error mentions file untouched" grep -qF "File left untouched" "$CASE_DIR/err"
}

echo "[damaged marker states refuse to touch the file]"
damaged_case begin-only "$(printf 'head\n%s\nuser tail' "$BEGIN_MARK")"
damaged_case end-only "$(printf 'head\n%s\nuser tail' "$END_MARK")"
damaged_case end-before-begin "$(printf 'head\n%s\nmiddle\n%s\nuser tail' "$END_MARK" "$BEGIN_MARK")"
damaged_case duplicate-begin "$(printf 'head\n%s\nold\n%s\n%s\nuser tail' "$BEGIN_MARK" "$END_MARK" "$BEGIN_MARK")"
damaged_case trailing-space-end "$(printf 'head\n%s\nold\n%s \nuser tail' "$BEGIN_MARK" "$END_MARK")"

echo "[symmetric whitespace/CRLF-damaged markers are detected]"
new_env wsmark
mkdir -p "$H/.gemini"
printf 'head\n%s \nold\n%s \ntail\n' "$BEGIN_MARK" "$END_MARK" > "$H/.gemini/GEMINI.md"
snapshot_gemini
run_install
check "trailing-space both: exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "trailing-space both: file untouched" gemini_unchanged
check "trailing-space both: error mentions whitespace" grep -qF "extra whitespace or CRLF" "$CASE_DIR/err"

new_env crlfmark
mkdir -p "$H/.gemini"
printf 'head\r\n%s\r\nold\r\n%s\r\ntail\r\n' "$BEGIN_MARK" "$END_MARK" > "$H/.gemini/GEMINI.md"
snapshot_gemini
run_install
check "CRLF both: exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "CRLF both: file untouched" gemini_unchanged

echo "[unreadable GEMINI.md fails with a clear error]"
new_env noread
run_install
snapshot_gemini
chmod 000 "$H/.gemini/GEMINI.md"
run_install
chmod 644 "$H/.gemini/GEMINI.md"
check "exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "clear cannot-read error" grep -qF "ERROR: cannot read" "$CASE_DIR/err"
check "file untouched" gemini_unchanged

echo "[read-only GEMINI.md fails with a clear error]"
new_env rogemini
run_install
snapshot_gemini
chmod 444 "$H/.gemini/GEMINI.md"
run_install
chmod 644 "$H/.gemini/GEMINI.md"
check "exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "clear cannot-write error" grep -qF "ERROR: cannot write" "$CASE_DIR/err"
check "file untouched" gemini_unchanged

echo "[stale removal failure doesn't abort the rest]"
new_env staleperm
run_install
rm -rf "$R/code-review"
chmod 555 "$H/skills"
run_install
chmod 755 "$H/skills"
check "exits non-zero" test "$(cat "$CASE_DIR/rc")" != "0"
check "FAILED stale message" grep -qF "FAILED (cannot remove stale)" "$CASE_DIR/err"
check "later dirs still cleaned" test ! -e "$H/.claude/skills/code-review"
check "GEMINI.md still synced" bash -c "! grep -qF '## code-review' '$H/.gemini/GEMINI.md'"

echo "[unreadable SKILL.md falls back to no description]"
new_env noskillread
mkdir -p "$R/tmpskill"
printf -- '---\nname: tmpskill\ndescription: secret\n---\n' > "$R/tmpskill/SKILL.md"
chmod 000 "$R/tmpskill/SKILL.md"
run_install
chmod 644 "$R/tmpskill/SKILL.md"
check "exits 0" rc_is 0
check "falls back to (no description)" gemini_has "(no description)"

echo "[markers as substrings are not markers]"
new_env substring
mkdir -p "$H/.gemini"
printf 'note: %s is a marker and %s too\n' "$BEGIN_MARK" "$END_MARK" > "$H/.gemini/GEMINI.md"
run_install
check "exits 0" rc_is 0
check "substring line preserved" gemini_has "note: $BEGIN_MARK is a marker"
check "a real block was appended" bash -c "grep -qxF '$BEGIN_MARK' '$H/.gemini/GEMINI.md'"

echo "[symlinked GEMINI.md stays a symlink]"
new_env gsymlink
mkdir -p "$H/.gemini" "$CASE_DIR/dotfiles"
printf 'dotfiles managed\n' > "$CASE_DIR/dotfiles/GEMINI.md"
ln -s "$CASE_DIR/dotfiles/GEMINI.md" "$H/.gemini/GEMINI.md"
run_install
check "exits 0" rc_is 0
check "still a symlink" test -L "$H/.gemini/GEMINI.md"
check "dotfiles target got the block" grep -qxF "$BEGIN_MARK" "$CASE_DIR/dotfiles/GEMINI.md"
check "dotfiles content preserved" grep -qF "dotfiles managed" "$CASE_DIR/dotfiles/GEMINI.md"

# --- summary ---------------------------------------------------------------

echo
echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
