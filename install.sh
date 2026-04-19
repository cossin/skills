#!/usr/bin/env bash
#
# Install skills from this repo into the three CLI homes:
#   - Claude Code: ~/.claude/skills/<name>  (native skill)
#   - Codex:       ~/.codex/skills/<name>   (native skill, same SKILL.md format)
#   - Gemini:      referenced from ~/.gemini/GEMINI.md (no native skill system)
#
# Also mirrors each skill to ~/skills/<name> as a CLI-agnostic path.
# Idempotent: re-runs sync added/removed skills without breaking unrelated links.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKILLS_DIR="$HOME/skills"
CLAUDE_DIR="$HOME/.claude/skills"
CODEX_DIR="$HOME/.codex/skills"
GEMINI_FILE="$HOME/.gemini/GEMINI.md"

BEGIN_MARK="<!-- managed-skills:begin -->"
END_MARK="<!-- managed-skills:end -->"

mkdir -p "$SKILLS_DIR" "$CLAUDE_DIR" "$CODEX_DIR" "$(dirname "$GEMINI_FILE")"

# --- helpers ---------------------------------------------------------------

link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    local current
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      echo "  ok:      $dst"
      return 0
    fi
    rm "$dst"
  elif [ -e "$dst" ]; then
    echo "  SKIP (not a symlink, leaving alone): $dst" >&2
    return 1
  fi
  ln -s "$src" "$dst"
  echo "  linked:  $dst"
}

# Remove stale symlinks in $1 that point into this repo but whose target
# is no longer in the current skill list ($skills).
cleanup_stale() {
  local target_dir="$1"
  [ -d "$target_dir" ] || return 0
  local entry base resolved known
  for entry in "$target_dir"/*; do
    [ -L "$entry" ] || continue
    resolved="$(readlink "$entry")"
    case "$resolved" in
      "$REPO_DIR"/*) ;;
      *) continue ;;
    esac
    base="$(basename "$entry")"
    known=0
    for s in "${skills[@]}"; do
      [ "$s" = "$base" ] && { known=1; break; }
    done
    if [ "$known" -eq 0 ]; then
      rm "$entry"
      echo "  removed stale: $entry"
    fi
  done
}

# Extract a top-level frontmatter field value from a SKILL.md.
frontmatter_field() {
  local field="$1" file="$2"
  awk -v key="$field:" '
    BEGIN { fm = 0 }
    /^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
    fm == 1 {
      # match "key:" at start of line
      if (index($0, key) == 1) {
        line = substr($0, length(key) + 1)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        # strip surrounding quotes
        if (line ~ /^".*"$/) line = substr(line, 2, length(line) - 2)
        print line
        exit
      }
    }
  ' "$file"
}

# --- discover skills -------------------------------------------------------

skills=()
for dir in "$REPO_DIR"/*/; do
  [ -f "${dir}SKILL.md" ] || continue
  skills+=("$(basename "$dir")")
done

if [ "${#skills[@]}" -eq 0 ]; then
  echo "No skills found in $REPO_DIR (expected <name>/SKILL.md)"
  exit 0
fi

echo "Found ${#skills[@]} skill(s): ${skills[*]}"
echo

# --- link into each target -------------------------------------------------

for name in "${skills[@]}"; do
  src="$REPO_DIR/$name"
  echo "[$name]"
  link "$src" "$SKILLS_DIR/$name" || true
  link "$src" "$CLAUDE_DIR/$name" || true
  link "$src" "$CODEX_DIR/$name"  || true
done

echo
echo "Cleaning stale links..."
cleanup_stale "$SKILLS_DIR"
cleanup_stale "$CLAUDE_DIR"
cleanup_stale "$CODEX_DIR"

# --- build & write Gemini block -------------------------------------------

tmp="$(mktemp)"
block_file="$(mktemp)"
trap 'rm -f "$tmp" "$block_file"' EXIT

{
  for name in "${skills[@]}"; do
    desc="$(frontmatter_field description "$REPO_DIR/$name/SKILL.md")"
    [ -n "$desc" ] || desc="(no description)"
    echo "## $name"
    echo "$desc"
    echo
    echo "触发时读取 \`~/skills/$name/SKILL.md\` 并严格按其清单与输出格式执行。"
    echo
  done
} > "$block_file"

if [ -f "$GEMINI_FILE" ] && grep -qF "$BEGIN_MARK" "$GEMINI_FILE"; then
  # Replace content between markers. Pass block as the first file so awk can
  # buffer it (BSD awk's -v can't hold multi-line strings).
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    FNR == NR { block = block $0 "\n"; next }
    $0 == b   { print; printf "%s", block; skipping = 1; next }
    $0 == e   { print; skipping = 0; next }
    !skipping { print }
  ' "$block_file" "$GEMINI_FILE" > "$tmp"
  mv "$tmp" "$GEMINI_FILE"
  echo
  echo "Updated managed block in $GEMINI_FILE"
else
  {
    if [ -f "$GEMINI_FILE" ] && [ -s "$GEMINI_FILE" ]; then
      cat "$GEMINI_FILE"
      echo
    fi
    echo "$BEGIN_MARK"
    cat "$block_file"
    echo "$END_MARK"
  } > "$tmp"
  mv "$tmp" "$GEMINI_FILE"
  echo
  echo "Initialized managed block in $GEMINI_FILE"
fi

echo "Done."
