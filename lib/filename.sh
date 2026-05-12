#!/usr/bin/env bash
# stride-ideation filename helpers.
#
# Two pure functions used by /stride-ideation:ideate and
# /stride-ideation:decompose to compute unique artifact paths:
#
#   sti_slugify "Add Notifications!"            -> "add-notifications"
#   sti_unique_path <dir> <ts> <slug> <artifact> <ext>
#       -> <dir>/<ts>-<slug>-<artifact>.<ext> if it does not exist,
#          else appends -2, -3, ... until it does not.
#
# Slug rules: lowercase, dash-separated. Any character outside [a-z0-9-]
# is REPLACED with a dash (never deleted — preserves word boundaries).
# Leading/trailing dashes are trimmed; runs of dashes are collapsed.
#
# Filename rule: the HARD INVARIANT is "never overwrite an existing file."
# When a collision occurs the helper iterates the suffix counter starting
# at 2; a single file at `<base>.<ext>` and another at `<base>-2.<ext>`
# means the next attempt yields `<base>-3.<ext>`.
#
# All output is written to stdout. Errors go to stderr with a non-zero
# exit code. Source this file, or call functions directly via:
#   bash -c '. lib/filename.sh; sti_unique_path docs/spec 2026-05-12T103000 foo requirements md'

set -u

sti_slugify() {
  local input="${1:-}"
  if [ -z "$input" ]; then
    echo "sti_slugify: empty input" >&2
    return 1
  fi
  local lowered
  lowered="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
  # Replace anything outside [a-z0-9-] with a dash, collapse runs,
  # trim leading/trailing dashes.
  local replaced
  replaced="$(printf '%s' "$lowered" | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-//; s/-$//')"
  if [ -z "$replaced" ]; then
    echo "sti_slugify: slug normalized to empty string" >&2
    return 1
  fi
  printf '%s' "$replaced"
}

sti_unique_path() {
  local dir="${1:-}"
  local ts="${2:-}"
  local slug="${3:-}"
  local artifact="${4:-}"
  local ext="${5:-}"
  if [ -z "$dir" ] || [ -z "$ts" ] || [ -z "$slug" ] || [ -z "$artifact" ] || [ -z "$ext" ]; then
    echo "sti_unique_path: usage: sti_unique_path <dir> <ts> <slug> <artifact> <ext>" >&2
    return 1
  fi
  local base="${dir%/}/${ts}-${slug}-${artifact}"
  local candidate="${base}.${ext}"
  if [ ! -e "$candidate" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  local n=2
  while [ -e "${base}-${n}.${ext}" ]; do
    n=$(( n + 1 ))
    if [ "$n" -gt 1000 ]; then
      echo "sti_unique_path: refusing to scan past -1000 collisions" >&2
      return 1
    fi
  done
  printf '%s' "${base}-${n}.${ext}"
}
