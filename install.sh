#!/usr/bin/env bash
#
# Install skills from this repo into the CLI homes:
#   - Claude Code:    ~/.claude/skills/<name>  (native skill; CLI and Desktop share it)
#   - Codex + Gemini: ~/.agents/skills/<name>  (cross-agent path, read natively by
#                     current Codex and Gemini CLI; same SKILL.md format)
#   - Codex (legacy): ~/.codex/skills/<name>   (older Codex versions)
#   - Gemini (legacy): managed block in ~/.gemini/GEMINI.md, for versions without
#                     native skill support
#
# Also mirrors each skill to ~/skills/<name> as a CLI-agnostic path.
#
# Besides the skills in this repo, external skill repos listed in
# external-skills.txt are cloned into .external/ (gitignored) and linked the
# same way. Local skills win on name collisions.
#
# Idempotent: re-runs sync added/removed skills without breaking unrelated links.
# Tests: tests/install_test.sh (sandboxed, never touches the real $HOME).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKILLS_DIR="$HOME/skills"
CLAUDE_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.agents/skills"
CODEX_DIR="$HOME/.codex/skills"
GEMINI_FILE="$HOME/.gemini/GEMINI.md"
EXTERNAL_MANIFEST="$REPO_DIR/external-skills.txt"
EXTERNAL_DIR="$REPO_DIR/.external"

BEGIN_MARK="<!-- managed-skills:begin -->"
END_MARK="<!-- managed-skills:end -->"

failures=0

mkdir -p "$SKILLS_DIR" "$CLAUDE_DIR" "$AGENTS_DIR" "$CODEX_DIR" "$(dirname "$GEMINI_FILE")"

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
    echo "  replacing symlink (was -> $current): $dst"
    if ! rm "$dst"; then
      echo "  FAILED (cannot remove old symlink): $dst" >&2
      return 1
    fi
  elif [ -e "$dst" ]; then
    echo "  SKIP (not a symlink, leaving alone): $dst" >&2
    return 1
  fi
  if ! ln -s "$src" "$dst"; then
    echo "  FAILED (cannot create symlink): $dst" >&2
    return 1
  fi
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
    for s in ${skills[@]+"${skills[@]}"}; do
      [ "$s" = "$base" ] && { known=1; break; }
    done
    if [ "$known" -eq 0 ]; then
      if ! rm "$entry"; then
        echo "  FAILED (cannot remove stale): $entry" >&2
        failures=$((failures + 1))
        continue
      fi
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
        # YAML block scalars (>, >-, |, ...) span multiple lines; unsupported
        # here, so return empty and let the caller fall back
        if (line ~ /^(>|\|)[+-]?$/) line = ""
        print line
        exit
      }
    }
  ' "$file"
}

# --- discover local skills ---------------------------------------------------

skills=()
skill_srcs=()
for dir in "$REPO_DIR"/*/; do
  [ -f "${dir}SKILL.md" ] || continue
  skills+=("$(basename "$dir")")
  skill_srcs+=("${dir%/}")
done

if [ "${#skills[@]}" -eq 0 ]; then
  # Keep going: stale links and the GEMINI.md block still need syncing.
  echo "No local skills found in $REPO_DIR (expected <name>/SKILL.md)."
else
  echo "Found ${#skills[@]} local skill(s): ${skills[*]}"
fi

# --- external skill sources --------------------------------------------------
# external-skills.txt format, one source per line (full-line # comments only):
#   <alias> <git-url> [subdir] [top-level-dirs...]
# Skills are discovered as <subdir>/<name>/SKILL.md and
# <subdir>/<category>/<name>/SKILL.md; when top-level dirs are listed, only
# those categories are installed. Pass "." as the subdir placeholder when the
# skills live at the repo root but you still want the category filter.
# Collisions: local skills win, then earlier manifest lines; skipped names
# are warned about. Every run refreshes the checkout to the upstream tip.

if [ -f "$EXTERNAL_MANIFEST" ]; then
  mkdir -p "$EXTERNAL_DIR"
  while IFS= read -r ext_line || [ -n "$ext_line" ]; do
    # strip CR so CRLF manifests don't leak \r into the last field
    ext_line="${ext_line%$'\r'}"
    ext_alias='' ext_url='' ext_subdir='' ext_includes=''
    IFS=' 	' read -r ext_alias ext_url ext_subdir ext_includes <<EOF_LINE || true
$ext_line
EOF_LINE
    case "$ext_alias" in ''|'#'*) continue ;; esac
    if [ -z "$ext_url" ]; then
      echo "WARN: skipping malformed line in external-skills.txt: $ext_alias" >&2
      continue
    fi
    case "$ext_alias" in
      .|..|*[!A-Za-z0-9._-]*)
        echo "WARN: skipping source with unsafe alias: $ext_alias" >&2
        continue
        ;;
    esac
    case "$ext_subdir" in
      /*|..|../*|*/..|*/../*)
        echo "WARN: skipping source with unsafe subdir: $ext_alias $ext_subdir" >&2
        continue
        ;;
    esac

    echo
    echo "[external: $ext_alias]"
    checkout="$EXTERNAL_DIR/$ext_alias"
    # </dev/null keeps git off our stdin (the manifest) and off the tty;
    # GIT_TERMINAL_PROMPT=0 fails fast instead of prompting for credentials
    if [ -d "$checkout/.git" ]; then
      current_url="$(git -C "$checkout" config remote.origin.url 2>/dev/null || true)"
      if [ "$current_url" != "$ext_url" ]; then
        echo "  url changed, rebuilding: $checkout"
        rm -rf "$checkout"
      # fetch the remote default branch and hard-reset to it: survives
      # upstream force-pushes and branch renames, where a ff-only pull
      # would wedge the checkout forever; offline keeps the old content
      elif GIT_TERMINAL_PROMPT=0 git -C "$checkout" fetch --depth 1 --quiet origin HEAD </dev/null 2>/dev/null \
        && git -C "$checkout" reset --hard --quiet FETCH_HEAD </dev/null 2>/dev/null; then
        echo "  updated: $checkout"
      else
        echo "  WARN (cannot update, using existing checkout): $checkout" >&2
      fi
    elif [ -e "$checkout" ]; then
      echo "  removing broken checkout (no .git): $checkout"
      rm -rf "$checkout"
    fi
    if [ ! -e "$checkout" ]; then
      if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$ext_url" "$checkout" </dev/null; then
        echo "  FAILED (cannot clone): $ext_url" >&2
        failures=$((failures + 1))
        continue
      fi
      echo "  cloned:  $checkout"
    fi

    src_root="$checkout"
    if [ -n "$ext_subdir" ] && [ "$ext_subdir" != "." ]; then
      src_root="$checkout/$ext_subdir"
    fi
    if [ ! -d "$src_root" ]; then
      echo "  FAILED (no such subdir in checkout): ${ext_subdir:-.}" >&2
      failures=$((failures + 1))
      continue
    fi

    added=0
    skipped=0
    for skill_md in "$src_root"/*/SKILL.md "$src_root"/*/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      sdir="$(dirname "$skill_md")"
      sname="$(basename "$sdir")"
      rel="${sdir#"$src_root"/}"
      top="${rel%%/*}"
      if [ -n "$ext_includes" ]; then
        # literal membership test; a for-loop over $ext_includes would let
        # the shell glob-expand entries against the caller's cwd
        inc_norm=" ${ext_includes//	/ } "
        case "$inc_norm" in
          *" $top "*) ;;
          *) continue ;;
        esac
      fi
      taken=0
      for existing in ${skills[@]+"${skills[@]}"}; do
        [ "$existing" = "$sname" ] && { taken=1; break; }
      done
      if [ "$taken" -eq 1 ]; then
        echo "  SKIP (name already taken): $ext_alias/$rel" >&2
        skipped=$((skipped + 1))
        continue
      fi
      skills+=("$sname")
      skill_srcs+=("$sdir")
      added=$((added + 1))
    done
    echo "  found $added skill(s), skipped $skipped"
  done < "$EXTERNAL_MANIFEST"
fi
echo

# --- link into each target -------------------------------------------------

for i in ${skills[@]+"${!skills[@]}"}; do
  name="${skills[$i]}"
  src="${skill_srcs[$i]}"
  echo "[$name]"
  link "$src" "$SKILLS_DIR/$name" || failures=$((failures + 1))
  link "$src" "$CLAUDE_DIR/$name" || failures=$((failures + 1))
  link "$src" "$AGENTS_DIR/$name" || failures=$((failures + 1))
  link "$src" "$CODEX_DIR/$name"  || failures=$((failures + 1))
done

echo
echo "Cleaning stale links..."
cleanup_stale "$SKILLS_DIR"
cleanup_stale "$CLAUDE_DIR"
cleanup_stale "$AGENTS_DIR"
cleanup_stale "$CODEX_DIR"

# --- build & write Gemini block -------------------------------------------

tmp="$(mktemp)"
block_file="$(mktemp)"
trap 'rm -f "$tmp" "$block_file"' EXIT

# Render $SKILLS_DIR with a ~ prefix when it lives under $HOME.
skills_display="$SKILLS_DIR"
case "$SKILLS_DIR" in
  "$HOME"/*) skills_display="~${SKILLS_DIR#"$HOME"}" ;;
esac

{
  for i in ${skills[@]+"${!skills[@]}"}; do
    name="${skills[$i]}"
    desc="$(frontmatter_field description "${skill_srcs[$i]}/SKILL.md" || true)"
    [ -n "$desc" ] || desc="(no description)"
    echo "## $name"
    echo "$desc"
    echo
    echo "触发时读取 \`$skills_display/$name/SKILL.md\` 并严格按其清单与输出格式执行。"
    echo
  done
} > "$block_file"

# The markers must each appear exactly once, on their own line, begin before
# end. Anything else means the block was damaged by hand: refuse to touch the
# file rather than risk eating user content around it.
begin_count=0
end_count=0
loose_count=0
if [ -f "$GEMINI_FILE" ]; then
  begin_count="$(grep -cxF "$BEGIN_MARK" "$GEMINI_FILE" || true)"
  end_count="$(grep -cxF "$END_MARK" "$GEMINI_FILE" || true)"
  loose_count="$(grep -cE '^[[:space:]]*<!-- managed-skills:(begin|end) -->[[:space:]]*$' "$GEMINI_FILE" || true)"
  # grep prints a count only when it could read the file; an unreadable file
  # leaves the variable empty, which must not slip past the guards below
  for c in "$begin_count" "$end_count" "$loose_count"; do
    case "$c" in
      ''|*[!0-9]*)
        echo "ERROR: cannot read $GEMINI_FILE. File left untouched." >&2
        exit 1
        ;;
    esac
  done
fi

if [ "$loose_count" -gt "$((begin_count + end_count))" ]; then
  echo "ERROR: $GEMINI_FILE has managed-block marker lines carrying extra whitespace or CRLF line endings." >&2
  echo "Clean up the marker lines, then re-run. File left untouched." >&2
  exit 1
fi

if [ "$begin_count" -gt 1 ] || [ "$end_count" -gt 1 ]; then
  echo "ERROR: $GEMINI_FILE has duplicated managed-block markers (begin x$begin_count, end x$end_count)." >&2
  echo "Remove the extra markers, then re-run. File left untouched." >&2
  exit 1
fi

if [ "$begin_count" -ne "$end_count" ]; then
  echo "ERROR: $GEMINI_FILE has an incomplete managed block (begin x$begin_count, end x$end_count)." >&2
  echo "Both markers must be present, each alone on its own line:" >&2
  echo "  $BEGIN_MARK" >&2
  echo "  $END_MARK" >&2
  echo "File left untouched." >&2
  exit 1
fi

if [ "$begin_count" -eq 1 ]; then
  begin_line="$(grep -nxF "$BEGIN_MARK" "$GEMINI_FILE" | head -1 | cut -d: -f1)"
  end_line="$(grep -nxF "$END_MARK" "$GEMINI_FILE" | head -1 | cut -d: -f1)"
  if [ "$begin_line" -gt "$end_line" ]; then
    echo "ERROR: $GEMINI_FILE has its managed-block markers in the wrong order (end at line $end_line, begin at line $begin_line)." >&2
    echo "Fix the marker order, then re-run. File left untouched." >&2
    exit 1
  fi
  # Replace content between markers. Pass block as the first file so awk can
  # buffer it (BSD awk's -v can't hold multi-line strings). Match it by name,
  # not FNR==NR — an empty block file has zero lines and would make FNR==NR
  # swallow the second file too. The END guard is a belt-and-braces check:
  # if the block never closed, fail without writing.
  if ! awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    FILENAME == ARGV[1] { block = block $0 "\n"; next }
    $0 == b   { print; printf "%s", block; skipping = 1; next }
    $0 == e   { print; skipping = 0; next }
    !skipping { print }
    END { if (skipping) exit 1 }
  ' "$block_file" "$GEMINI_FILE" > "$tmp"; then
    echo "ERROR: failed to rebuild the managed block in $GEMINI_FILE. File left untouched." >&2
    exit 1
  fi
  # Write through rather than mv: keeps $GEMINI_FILE working when it is a
  # symlink (e.g. into a dotfiles repo) and preserves its permissions.
  if ! cat "$tmp" > "$GEMINI_FILE"; then
    echo "ERROR: cannot write $GEMINI_FILE (read-only or broken symlink). File left untouched." >&2
    exit 1
  fi
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
  if ! cat "$tmp" > "$GEMINI_FILE"; then
    echo "ERROR: cannot write $GEMINI_FILE (read-only or broken symlink). File left untouched." >&2
    exit 1
  fi
  echo
  echo "Initialized managed block in $GEMINI_FILE"
fi

if [ "$failures" -gt 0 ]; then
  echo "Done, but $failures link(s) failed or were skipped; see messages above." >&2
  exit 1
fi
echo "Done."
