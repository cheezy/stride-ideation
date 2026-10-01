#!/usr/bin/env bash
# stride-ideation intra-session draft autosave helpers.
#
# Pure functions used by /stride-ideation:ideate to persist an in-progress
# ideation draft (answered sections + round state) to a scratch file under
# .stride/, so an interruption mid-session is recoverable and a later /ideate
# run can offer to resume it:
#
#   sti_scratch_dir <dir> [<name>]      -> creates <dir> and, when absent, a
#                                          <dir>/.gitignore containing `*`, so
#                                          the scratch dir ignores itself in
#                                          any repo (never overwrites one);
#                                          in a git work tree it fails unless
#                                          <dir>/<name> would be ignored
#   sti_draft_path  <dir> <ts> <slug>   -> <dir>/<ts>-<slug>-draft.md
#   sti_draft_find  <dir> <slug>        -> path of the latest NON-EMPTY draft
#                                          for <slug> (any timestamp), or
#                                          non-zero if none
#   sti_draft_save  <path> [<content>]  -> writes <content> to <path>, or
#                                          stdin byte for byte when <content>
#                                          is omitted (creating the parent dir
#                                          via sti_scratch_dir)
#   sti_draft_load  <path>              -> emits the draft content to stdout
#   sti_draft_exists <path>             -> exit 0 if the draft exists and is
#                                          non-empty, non-zero otherwise
#   sti_draft_clear <path>              -> removes the draft (no error if gone)
#
# Filename rule: the scratch path pairs with the eventual requirements doc by
# reusing the <ts>-<slug>-<artifact> convention from sti_unique_path, with the
# artifact token `draft`. The draft lives under .stride/, which carries its own
# `.gitignore` (`*`, written by sti_scratch_dir) so half-finished, possibly
# sensitive ideation is never committed — in the user's project as well as in
# this plugin's repo, and without editing the user's root .gitignore. The
# helper never serializes any secret — it only writes the content it is
# handed. Prefer stdin (or the Write tool) for content: an argv string forces
# the caller to shell-quote arbitrary prose.
#
# Resume keys on the SLUG, not the session timestamp: a fresh /ideate run has
# a new timestamp, so sti_draft_find globs every <ts>-<slug>-draft.md under the
# scratch dir and returns the latest match (ISO timestamps sort lexically). A
# different slug never matches: everything before `-<slug>-draft.md` must be a
# bare session timestamp, so `toggle` does not pick up a `dark-mode-toggle`
# draft and `auth` does not pick up `oauth` or `user-auth`.
#
# All non-error output is written to stdout. Errors go to stderr with a
# non-zero exit code. Source this file, or call functions directly via:
#   bash -c '. lib/draft.sh; sti_draft_path .stride 2026-05-12T103000 foo'
#
# This file is SOURCED into the caller's shell, so it must not change any
# shell option (no file-scope `set -u`/`set -e`): an inherited nounset aborts
# the caller on its next optional variable. Functions default every argument
# with `${N:-}` instead.

sti_draft_path() {
  local dir="${1:-}"
  local ts="${2:-}"
  local slug="${3:-}"
  if [ -z "$dir" ] || [ -z "$ts" ] || [ -z "$slug" ]; then
    echo "sti_draft_path: usage: sti_draft_path <dir> <ts> <slug>" >&2
    return 1
  fi
  # The draft must land directly in <dir>: a '/' in the timestamp or slug
  # (e.g. a typed slug like a/../../x) would place it outside the
  # self-ignoring scratch dir.
  case "$ts$slug" in
    */*)
      echo "sti_draft_path: <ts> and <slug> must not contain '/'" >&2
      return 1
      ;;
  esac
  printf '%s' "${dir%/}/${ts}-${slug}-draft.md"
}

sti_draft_find() {
  # Find the latest NON-EMPTY scratch draft for <slug> under <dir>, regardless
  # of session timestamp. Returns its path on stdout, or non-zero (no stdout)
  # when the directory is absent or no non-empty draft matches. Empty draft
  # files are ignored so a zero-length scratch never triggers a resume offer.
  local dir="${1:-}"
  local slug="${2:-}"
  if [ -z "$dir" ] || [ -z "$slug" ]; then
    echo "sti_draft_find: usage: sti_draft_find <dir> <slug>" >&2
    return 1
  fi
  [ -d "$dir" ] || return 1
  local latest=""
  local f name ts in_tree=""
  # Inside a git work tree, only drafts git actually ignores are offered: a
  # tracked or re-included draft would let the resumed (possibly sensitive)
  # writes be committed by a later `git add -A`.
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_tree=1
  fi
  # The glob only narrows the candidates: its `*` would also absorb the
  # leading words of a longer slug (`<ts>-dark-mode` for slug `toggle`), so
  # each match is then checked exactly. With no match (and nullglob unset),
  # the loop iterates once over the literal unexpanded pattern; the
  # `[ -e "$f" ]` guard skips it.
  for f in "${dir%/}/"*"-${slug}-draft.md"; do
    [ -e "$f" ] || continue
    # A symlinked "draft" (e.g. committed by a cloned repo) could point
    # anywhere; never offer one for resume.
    [ -L "$f" ] && continue
    if [ -n "$in_tree" ] && ! git -C "$dir" check-ignore -q -- "${f##*/}" 2>/dev/null; then
      continue
    fi
    [ -s "$f" ] || continue
    # Strip the literal suffix (quoted, so the slug is never a pattern) and
    # require exactly the YYYY-MM-DDTHHMMSS session timestamp before it.
    name="${f##*/}"
    ts="${name%"-${slug}-draft.md"}"
    case "$ts" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) continue ;;
    esac
    # Bash expands globs in collation order, but compare explicitly so the
    # "latest ISO timestamp wins" contract does not depend on locale ordering.
    if [ -z "$latest" ] || [ "$f" \> "$latest" ]; then
      latest="$f"
    fi
  done
  if [ -z "$latest" ]; then
    return 1
  fi
  printf '%s' "$latest"
}

sti_scratch_dir() {
  # Create the scratch directory <dir> and make it ignore itself: when
  # <dir>/.gitignore does not exist, write one containing `*` (which also
  # ignores the .gitignore). An existing .gitignore — or a symlink at that
  # path — is never overwritten.
  #
  # Refuses (non-zero, one-line diagnostic) rather than risk exposing drafts:
  #   - a symlinked <dir>, which would put drafts outside the project;
  #   - <dir> resolving to the current directory or a repository root, where a
  #     `*` .gitignore would hide every new file — so the user's root
  #     .gitignore is never created or touched;
  #   - inside a git work tree, a <dir> whose ignore rules do NOT ignore the
  #     file about to be written (e.g. a committed .gitignore re-including
  #     drafts), checked with `git check-ignore` on <dir>/<name> — pass the
  #     real file name, since a crafted negation can spare a generic probe
  #     name. A tracked file is never reported as ignored, so it fails too.
  local dir="${1:-}"
  local name="${2:-0000-00-00T000000-probe-draft.md}"
  if [ -z "$dir" ]; then
    echo "sti_scratch_dir: usage: sti_scratch_dir <dir> [<name>]" >&2
    return 1
  fi
  case "$name" in
    */*)
      echo "sti_scratch_dir: <name> must be a bare file name: $name" >&2
      return 1
      ;;
  esac
  dir="${dir%/}"
  [ -n "$dir" ] || dir="/"
  if [ -L "$dir" ]; then
    echo "sti_scratch_dir: refusing a symlinked scratch directory: $dir" >&2
    return 1
  fi
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "sti_scratch_dir: cannot create scratch directory: $dir" >&2
    return 1
  fi
  local real top
  real="$(cd "$dir" && pwd -P)" || {
    echo "sti_scratch_dir: cannot enter scratch directory: $dir" >&2
    return 1
  }
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ "$real" = "$(pwd -P)" ] || { [ -n "$top" ] && [ "$real" = "$(cd "$top" && pwd -P)" ]; }; then
    echo "sti_scratch_dir: refusing to use $dir as a scratch directory (it is the current directory or a repository root)" >&2
    return 1
  fi
  local ignore="$dir/.gitignore"
  if [ ! -e "$ignore" ] && [ ! -L "$ignore" ]; then
    if ! printf '*\n' > "$ignore" 2>/dev/null; then
      echo "sti_scratch_dir: cannot write $ignore" >&2
      return 1
    fi
  fi
  if [ -n "$top" ] && ! git -C "$dir" check-ignore -q -- "$name" 2>/dev/null; then
    echo "sti_scratch_dir: $dir/$name would not be ignored by git (tracked, or $ignore re-includes it), so it could be committed; make $ignore ignore it (e.g. a single line '*') or remove it" >&2
    return 1
  fi
}

sti_draft_save() {
  # Persist draft content to <path>, creating the parent directory (and its
  # self-ignoring .gitignore) if needed. Content is the second argument when
  # one is given — the original form, kept for back-compat, which forces the
  # caller to shell-quote the prose — otherwise stdin, copied byte for byte
  # (no quoting, no trailing-newline loss). A terminal on stdin with no
  # second argument is a usage error rather than a hang.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (content on stdin when omitted)" >&2
    return 1
  fi
  if [ "$#" -lt 2 ] && [ -t 0 ]; then
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (content on stdin when omitted)" >&2
    return 1
  fi
  local dir
  dir="$(dirname "$path")"
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "sti_draft_save: cannot create scratch directory: $dir" >&2
    return 1
  fi
  sti_scratch_dir "$dir" "$(basename "$path")" || return 1
  if [ "$#" -ge 2 ]; then
    if ! printf '%s' "${2:-}" > "$path" 2>/dev/null; then
      echo "sti_draft_save: cannot write scratch draft: $path" >&2
      return 1
    fi
  elif ! cat > "$path" 2>/dev/null; then
    echo "sti_draft_save: cannot write scratch draft: $path" >&2
    return 1
  fi
}

sti_draft_load() {
  # Emit the draft content at <path> to stdout. Errors if the file is absent.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_load: usage: sti_draft_load <path>" >&2
    return 1
  fi
  if [ ! -f "$path" ]; then
    echo "sti_draft_load: no scratch draft at: $path" >&2
    return 1
  fi
  cat "$path"
}

sti_draft_exists() {
  # Predicate: exit 0 if <path> is an existing NON-EMPTY draft, else non-zero.
  # No stdout. A zero-length scratch is treated as "no resumable draft".
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_exists: usage: sti_draft_exists <path>" >&2
    return 1
  fi
  [ -s "$path" ]
}

sti_draft_clear() {
  # Remove the scratch draft at <path>. Idempotent: no error if already gone.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_clear: usage: sti_draft_clear <path>" >&2
    return 1
  fi
  rm -f "$path"
}
