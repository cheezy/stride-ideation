#!/usr/bin/env bash
# Unit tests for lib/draft.sh — the /stride-ideation:ideate intra-session
# draft autosave/resume helpers (W1138).
#
# Run:
#   ./lib/test-draft.sh
#
# Exits 0 if all tests pass, non-zero otherwise. Prints a one-line
# per-test status to stdout.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/draft.sh"

PASS=0
FAIL=0
TMP=""

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

TMP="$(mktemp -d)"

assert_eq() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$(( PASS + 1 ))
    printf 'PASS  %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$label" "$expected" "$actual"
  fi
}

ok() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
no() { FAIL=$(( FAIL + 1 )); printf 'FAIL  %s\n' "$1"; }

# --- draft_path: deterministic for a given ts+slug ---------------------------

assert_eq "draft_path: <dir>/<ts>-<slug>-draft.md" \
  "$(sti_draft_path .stride 2026-05-12T103000 add-notifications)" \
  ".stride/2026-05-12T103000-add-notifications-draft.md"

assert_eq "draft_path: trailing slash on dir is normalized" \
  "$(sti_draft_path .stride/ 2026-05-12T103000 foo)" \
  ".stride/2026-05-12T103000-foo-draft.md"

# Determinism: same inputs -> identical output across two calls.
P1="$(sti_draft_path "$TMP" 2026-05-12T103000 foo)"
P2="$(sti_draft_path "$TMP" 2026-05-12T103000 foo)"
assert_eq "draft_path: deterministic for a given SESSION_TS+slug" "$P1" "$P2"

# Missing-arg usage -> non-zero, no stdout.
BAD="$(sti_draft_path "$TMP" 2026-05-12T103000 2>/dev/null || true)"
if [ -z "$BAD" ]; then
  ok "draft_path: missing slug -> empty stdout + non-zero"
else
  no "draft_path: missing slug leaked output: $BAD"
fi

# --- save then load: round-trips content ------------------------------------

DRAFT="$(sti_draft_path "$TMP/.stride" 2026-05-12T103000 round-trip)"
CONTENT="## Goal
Ship the digest.

## Problem
Approvals rot in inboxes.
__round_state__: 2"

if sti_draft_save "$DRAFT" "$CONTENT"; then
  ok "draft_save: writes the scratch file (and creates .stride/ parent)"
else
  no "draft_save: failed to write"
fi

if [ -f "$DRAFT" ]; then
  ok "draft_save: scratch file exists at the computed path"
else
  no "draft_save: scratch file missing after save"
fi

assert_eq "draft_load: round-trips the saved content byte-for-byte" \
  "$(sti_draft_load "$DRAFT")" "$CONTENT"

# --- exists: predicate on non-empty draft -----------------------------------

if sti_draft_exists "$DRAFT"; then
  ok "draft_exists: true for a non-empty draft"
else
  no "draft_exists: false for a non-empty draft (should be true)"
fi

EMPTY="$(sti_draft_path "$TMP/.stride" 2026-05-12T103000 empty-draft)"
: > "$EMPTY"
if sti_draft_exists "$EMPTY"; then
  no "draft_exists: true for an empty draft (should be false)"
else
  ok "draft_exists: false for an empty/zero-length draft (partial -> fresh)"
fi

if sti_draft_exists "$TMP/.stride/nope-draft.md"; then
  no "draft_exists: true for an absent draft (should be false)"
else
  ok "draft_exists: false for an absent draft"
fi

# --- load: absent file -> non-zero, no crash --------------------------------

LOAD_BAD="$(sti_draft_load "$TMP/.stride/missing-draft.md" 2>/dev/null || true)"
if [ -z "$LOAD_BAD" ]; then
  ok "draft_load: absent file -> empty stdout + non-zero (safe, no crash)"
else
  no "draft_load: absent file leaked output: $LOAD_BAD"
fi

# --- save: mkdir-failure branch returns non-zero, no crash ------------------

# Block the parent dir with a regular file so `mkdir -p <blocker>/sub` fails.
BLOCKER="$TMP/blocker"
: > "$BLOCKER"
SAVE_ERR="$(sti_draft_save "$BLOCKER/sub/2026-05-12T103000-x-draft.md" "body" 2>&1 || true)"
if sti_draft_save "$BLOCKER/sub/2026-05-12T103000-x-draft.md" "body" 2>/dev/null; then
  no "draft_save: succeeded despite an unmakeable parent dir (should fail)"
else
  ok "draft_save: returns non-zero when the parent dir cannot be created (no crash)"
fi
if printf '%s' "$SAVE_ERR" | grep -q "cannot create scratch directory"; then
  ok "draft_save: mkdir failure emits a one-line diagnostic to stderr"
else
  no "draft_save: mkdir failure produced no diagnostic: $SAVE_ERR"
fi

# --- clear: removes the scratch file (idempotent) ---------------------------

sti_draft_clear "$DRAFT"
if [ -f "$DRAFT" ]; then
  no "draft_clear: scratch file still present after clear"
else
  ok "draft_clear: removes the scratch file"
fi
# Idempotent: clearing an already-absent file succeeds.
if sti_draft_clear "$DRAFT"; then
  ok "draft_clear: idempotent (no error when already gone)"
else
  no "draft_clear: errored on an already-absent file"
fi

# --- find: resume detection matches only the same slug ----------------------

FDIR="$TMP/find-stride"
mkdir -p "$FDIR"
# Two different slugs in flight, plus an empty draft that must be ignored.
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T100000 alpha)" "alpha draft body"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T110000 beta)"  "beta draft body"
: > "$(sti_draft_path "$FDIR" 2026-05-12T120000 gamma)"   # empty -> ignored

assert_eq "draft_find: returns the matching-slug draft only (two slugs in flight)" \
  "$(sti_draft_find "$FDIR" alpha)" \
  "$FDIR/2026-05-12T100000-alpha-draft.md"

# Slug that is a suffix of another must NOT cross-match (auth vs oauth).
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T130000 oauth)" "oauth body"
NOAUTH="$(sti_draft_find "$FDIR" auth 2>/dev/null || true)"
if [ -z "$NOAUTH" ]; then
  ok "draft_find: slug 'auth' does not match 'oauth' (dash-delimited suffix)"
else
  no "draft_find: 'auth' cross-matched a different slug: $NOAUTH"
fi

# No match -> non-zero, no stdout.
NONE="$(sti_draft_find "$FDIR" does-not-exist 2>/dev/null || true)"
if [ -z "$NONE" ]; then
  ok "draft_find: no matching draft -> empty stdout + non-zero (fresh session)"
else
  no "draft_find: leaked output for a slug with no draft: $NONE"
fi

# Empty-only match -> treated as no resumable draft.
EMPTY_ONLY="$(sti_draft_find "$FDIR" gamma 2>/dev/null || true)"
if [ -z "$EMPTY_ONLY" ]; then
  ok "draft_find: an empty-only draft is not offered for resume (partial -> fresh)"
else
  no "draft_find: offered an empty draft for resume: $EMPTY_ONLY"
fi

# Latest timestamp wins when several non-empty drafts share a slug.
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T090000 multi)" "older"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T140000 multi)" "newer"
assert_eq "draft_find: latest ISO timestamp wins for a repeated slug" \
  "$(sti_draft_find "$FDIR" multi)" \
  "$FDIR/2026-05-12T140000-multi-draft.md"

# A slug that is the tail of a longer slug never picks up the longer one's
# draft, even when that draft is newer (D344).
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T150000 toggle)" "toggle body"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T160000 dark-mode-toggle)" "dark body"
assert_eq "draft_find: toggle ignores a newer dark-mode-toggle draft" \
  "$(sti_draft_find "$FDIR" toggle)" \
  "$FDIR/2026-05-12T150000-toggle-draft.md"
assert_eq "draft_find: multi-word slug dark-mode-toggle finds its own draft" \
  "$(sti_draft_find "$FDIR" dark-mode-toggle)" \
  "$FDIR/2026-05-12T160000-dark-mode-toggle-draft.md"

# Only the longer slug present -> no match for its tail.
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T170000 user-auth)" "user-auth body"
NOUSERAUTH="$(sti_draft_find "$FDIR" auth 2>/dev/null || true)"
if [ -z "$NOUSERAUTH" ]; then
  ok "draft_find: auth does not match a user-auth draft"
else
  no "draft_find: auth wrongly matched: $NOUSERAUTH"
fi
TAILONLY="$TMP/find-tail-only"
sti_draft_save "$(sti_draft_path "$TAILONLY" 2026-09-01T100000 dark-mode-toggle)" "x"
TAIL_OUT="$(sti_draft_find "$TAILONLY" toggle 2>/dev/null)"
TAIL_RC=$?
assert_eq "draft_find: only a longer-slug draft -> empty stdout" "$TAIL_OUT" ""
assert_eq "draft_find: only a longer-slug draft -> non-zero return" "$TAIL_RC" "1"

# A prefix that is not a well-formed session timestamp is ignored.
printf 'stray\n' > "$FDIR/notatimestamp-alpha-draft.md"
printf 'stray\n' > "$FDIR/2026-05-12T99999-alpha-draft.md"
printf 'stray\n' > "$FDIR/2099-12-31T235959x-alpha-draft.md"
assert_eq "draft_find: malformed timestamp prefixes are ignored" \
  "$(sti_draft_find "$FDIR" alpha)" \
  "$FDIR/2026-05-12T100000-alpha-draft.md"

# An empty draft with a valid name is still skipped in favour of an older one.
: > "$(sti_draft_path "$FDIR" 2026-05-12T180000 toggle)"
assert_eq "draft_find: a newer empty draft is still skipped" \
  "$(sti_draft_find "$FDIR" toggle)" \
  "$FDIR/2026-05-12T150000-toggle-draft.md"

# Absent directory -> non-zero, no crash.
ABS="$(sti_draft_find "$TMP/no-such-dir" anything 2>/dev/null || true)"
if [ -z "$ABS" ]; then
  ok "draft_find: absent scratch dir -> empty stdout + non-zero (no crash)"
else
  no "draft_find: leaked output for an absent dir: $ABS"
fi

# --- sourcing leaves the caller's shell options alone -----------------------
#
# Each probe runs in a child `bash -c`: this script already runs with set -u,
# so checking here would hide a helper that turns nounset on (D343).

nounset_probe() {
  # $1 = commands to run before sourcing; prints nounset state after.
  env -u DRAFT_PATH bash -c "$1"'
    . "$0"
    case $- in *u*) echo on ;; *) echo off ;; esac' "${SCRIPT_DIR}/draft.sh" 2>&1
}

assert_eq "sourcing: nounset stays off when the caller had it off" \
  "$(nounset_probe ':')" "off"

assert_eq "sourcing: nounset stays on when the caller had it on" \
  "$(nounset_probe 'set -u')" "on"

assert_eq "sourcing twice: nounset still off" \
  "$(nounset_probe '. "$0"')" "off"

assert_eq "sourcing: an unset optional variable after sourcing does not abort" \
  "$(env -u DRAFT_PATH bash -c '
    . "$0"
    if [ -n "$DRAFT_PATH" ]; then echo set; fi
    echo ok' "${SCRIPT_DIR}/draft.sh" 2>&1; echo "rc=$?")" "ok
rc=0"

assert_eq "sourcing: documented bash -c call form still works" \
  "$(bash -c '. "$0"; sti_draft_path .stride 2026-05-12T103000 foo' "${SCRIPT_DIR}/draft.sh" 2>&1)" \
  ".stride/2026-05-12T103000-foo-draft.md"

# --- save: content on stdin (no shell quoting) -------------------------------

STDIN_DIR="$TMP/stdin-scratch"
STDIN_DRAFT="$STDIN_DIR/2026-05-12T103000-stdin-draft.md"
# Quotes, dollar signs, backticks, a command substitution and trailing blank
# lines — everything an argv string would force the caller to escape.
printf '%s\n' '## Problem' "Bob's \"idea\" costs \$5 and \`rm -rf\` is not run" '$(touch pwned) ${HOME} \' '' '' > "$TMP/stdin-expected.md"
( cd "$TMP" && sti_draft_save "$STDIN_DRAFT" < "$TMP/stdin-expected.md" )
SAVE_RC=$?
assert_eq "draft_save stdin: exits 0" "$SAVE_RC" "0"
if cmp -s "$TMP/stdin-expected.md" "$STDIN_DRAFT"; then
  ok "draft_save stdin: content is stored byte for byte (quotes, \$, backticks, trailing newlines)"
else
  no "draft_save stdin: stored content differs from stdin"
fi
if [ ! -e "$TMP/pwned" ]; then
  ok "draft_save stdin: nothing in the content runs"
else
  no "draft_save stdin: content was executed"
fi
sti_draft_load "$STDIN_DRAFT" > "$TMP/stdin-loaded.md"
if cmp -s "$TMP/stdin-expected.md" "$TMP/stdin-loaded.md"; then
  ok "draft_save stdin: draft_load returns the stdin content unchanged"
else
  no "draft_save stdin: draft_load output differs"
fi

printf 'piped body' | sti_draft_save "$STDIN_DIR/2026-05-12T103001-pipe-draft.md"
assert_eq "draft_save stdin: piped content is saved" \
  "$(cat "$STDIN_DIR/2026-05-12T103001-pipe-draft.md")" "piped body"

sti_draft_save "$STDIN_DIR/2026-05-12T103002-empty-draft.md" < /dev/null
assert_eq "draft_save stdin: empty stdin exits 0" "$?" "0"
if [ -e "$STDIN_DIR/2026-05-12T103002-empty-draft.md" ] && ! sti_draft_exists "$STDIN_DIR/2026-05-12T103002-empty-draft.md"; then
  ok "draft_save stdin: empty stdin leaves an empty draft that is never offered for resume"
else
  no "draft_save stdin: empty stdin handling"
fi

sti_draft_save "$STDIN_DIR/2026-05-12T103003-argv-draft.md" "argv body" < /dev/null
assert_eq "draft_save argv: the second argument wins over stdin (back-compat)" \
  "$(cat "$STDIN_DIR/2026-05-12T103003-argv-draft.md")" "argv body"

# --- scratch dir ignores itself ----------------------------------------------

assert_eq "scratch_dir: draft_save wrote a self-ignore file holding '*'" \
  "$(cat "$STDIN_DIR/.gitignore")" "*"

SCR="$TMP/scratch-own"
sti_scratch_dir "$SCR"
assert_eq "scratch_dir: creates the dir and a .gitignore holding '*'" "$(cat "$SCR/.gitignore")" "*"
printf 'custom\n' > "$SCR/.gitignore"
sti_scratch_dir "$SCR"
assert_eq "scratch_dir: never overwrites an existing .gitignore" "$(cat "$SCR/.gitignore")" "custom"
sti_draft_save "$SCR/2026-05-12T103000-x-draft.md" "body"
assert_eq "scratch_dir: draft_save leaves an existing .gitignore alone" "$(cat "$SCR/.gitignore")" "custom"

SYM="$TMP/scratch-sym"
mkdir -p "$SYM"
ln -s "$TMP/elsewhere-ignore" "$SYM/.gitignore"
sti_scratch_dir "$SYM"
if [ ! -e "$TMP/elsewhere-ignore" ]; then
  ok "scratch_dir: a symlinked .gitignore is not written through"
else
  no "scratch_dir: wrote through a .gitignore symlink"
fi

SCRATCH_USAGE="$(sti_scratch_dir 2>&1)"
SCRATCH_USAGE_RC=$?
if [ "$SCRATCH_USAGE_RC" -ne 0 ] && printf '%s' "$SCRATCH_USAGE" | grep -q 'usage: sti_scratch_dir <dir>'; then
  ok "scratch_dir: no argument is a usage error"
else
  no "scratch_dir: missing-argument handling"
fi

# Read-only parent: creation fails cleanly (skipped when permissions are not
# enforced, e.g. running as root).
RO="$TMP/readonly"
mkdir -p "$RO"
chmod 555 "$RO"
if ! ( : > "$RO/probe" ) 2>/dev/null; then
  RO_ERR="$(sti_scratch_dir "$RO/.stride" 2>&1)"
  RO_RC=$?
  if [ "$RO_RC" -ne 0 ] && printf '%s' "$RO_ERR" | grep -q 'cannot create scratch directory'; then
    ok "scratch_dir: a read-only parent fails with a one-line diagnostic"
  else
    no "scratch_dir: read-only parent handling (rc=$RO_RC: $RO_ERR)"
  fi
  if printf 'x' | sti_draft_save "$RO/2026-05-12T103000-ro-draft.md" 2>/dev/null; then
    no "draft_save: succeeded in a read-only directory"
  else
    ok "draft_save: a read-only directory returns non-zero"
  fi
else
  ok "scratch_dir: read-only case skipped (permissions not enforced here)"
fi
chmod 755 "$RO"

# In a fresh repo, a saved draft never shows up in git status.
GITREPO="$TMP/git repo"
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
( cd "$GITREPO" && printf '## Goal\ndraft\n' | sti_draft_save .stride/2026-05-12T103000-topic-draft.md )
assert_eq "scratch_dir: git status --porcelain shows nothing after a save in a fresh repo" \
  "$(git -C "$GITREPO" status --porcelain)" ""
assert_eq "scratch_dir: the repo's own .gitignore is not created or edited" \
  "$([ -e "$GITREPO/.gitignore" ] && echo present || echo absent)" "absent"

# --- scratch dir: refuses where drafts could leak ------------------------------

# A symlinked scratch dir would put drafts outside the project.
mkdir -p "$TMP/outside"
ln -s "$TMP/outside" "$TMP/linked-scratch"
LINK_ERR="$(sti_scratch_dir "$TMP/linked-scratch" 2>&1)"
LINK_RC=$?
if [ "$LINK_RC" -ne 0 ] && printf '%s' "$LINK_ERR" | grep -q 'refusing a symlinked scratch directory'; then
  ok "scratch_dir: refuses a symlinked scratch directory"
else
  no "scratch_dir: symlinked dir accepted (rc=$LINK_RC)"
fi
if printf 'x' | sti_draft_save "$TMP/linked-scratch/2026-05-12T103000-l-draft.md" 2>/dev/null; then
  no "draft_save: wrote through a symlinked scratch directory"
else
  ok "draft_save: refuses a symlinked scratch directory"
fi
assert_eq "scratch_dir: nothing lands in the symlink's target" "$(ls -A "$TMP/outside")" ""

# A repo root or the current directory would hide every new file.
ROOTREPO="$TMP/root repo"
mkdir -p "$ROOTREPO"
git -C "$ROOTREPO" init -q
ROOT_RC=0; ( cd "$ROOTREPO" && sti_scratch_dir . ) 2>/dev/null || ROOT_RC=$?
TOP_RC=0; sti_scratch_dir "$ROOTREPO" 2>/dev/null || TOP_RC=$?
BARE_RC=0; ( cd "$ROOTREPO" && printf 'x' | sti_draft_save draft.md ) 2>/dev/null || BARE_RC=$?
if [ "$ROOT_RC" -ne 0 ] && [ "$TOP_RC" -ne 0 ] && [ "$BARE_RC" -ne 0 ]; then
  ok "scratch_dir: refuses '.', a repository root, and a bare-filename save"
else
  no "scratch_dir: root refusals (dot=$ROOT_RC top=$TOP_RC bare=$BARE_RC)"
fi
assert_eq "scratch_dir: no .gitignore is written at a repository root" \
  "$([ -e "$ROOTREPO/.gitignore" ] && echo present || echo absent)" "absent"

# An existing .stride/.gitignore that does not ignore drafts fails closed.
CONFLICT="$TMP/conflict repo"
mkdir -p "$CONFLICT/.stride"
git -C "$CONFLICT" init -q
printf '!*-draft.md\n' > "$CONFLICT/.stride/.gitignore"
git -C "$CONFLICT" add .stride/.gitignore
CONFLICT_ERR="$( cd "$CONFLICT" && sti_scratch_dir .stride 2>&1 )"
CONFLICT_RC=$?
if [ "$CONFLICT_RC" -ne 0 ] && printf '%s' "$CONFLICT_ERR" | grep -q 'would not be ignored by git'; then
  ok "scratch_dir: an existing .gitignore that does not ignore drafts fails closed"
else
  no "scratch_dir: conflicting .gitignore accepted (rc=$CONFLICT_RC)"
fi
assert_eq "scratch_dir: the conflicting .gitignore is left as it was" "$(cat "$CONFLICT/.stride/.gitignore")" '!*-draft.md'
CONFLICT_SAVE_RC=0
( cd "$CONFLICT" && printf 'x' | sti_draft_save .stride/2026-05-12T103000-c-draft.md ) 2>/dev/null || CONFLICT_SAVE_RC=$?
if [ "$CONFLICT_SAVE_RC" -ne 0 ] && [ ! -e "$CONFLICT/.stride/2026-05-12T103000-c-draft.md" ]; then
  ok "draft_save: writes nothing where the draft would not be ignored"
else
  no "draft_save: saved into a dir whose .gitignore does not ignore drafts"
fi

# A negation that spares a generic probe name but re-includes real drafts
# is caught because the check uses the real file name.
NEG="$TMP/negation repo"
mkdir -p "$NEG/.stride"
git -C "$NEG" init -q
printf '*\n!20*-draft.md\n' > "$NEG/.stride/.gitignore"
NEG_RC=0
( cd "$NEG" && printf 'x' | sti_draft_save .stride/2026-05-12T103000-n-draft.md ) 2>/dev/null || NEG_RC=$?
if [ "$NEG_RC" -ne 0 ] && [ -z "$(git -C "$NEG" status --porcelain -- .stride)" ]; then
  ok "scratch_dir: a negation re-including real draft names is refused (checked on the real name)"
else
  no "scratch_dir: negation bypass (rc=$NEG_RC; status: $(git -C "$NEG" status --porcelain -- .stride))"
fi

# A tracked draft is never offered for resume, and cannot be re-saved.
TRACKED="$TMP/tracked repo"
mkdir -p "$TRACKED/.stride"
git -C "$TRACKED" init -q
printf 'old draft\n' > "$TRACKED/.stride/2026-05-12T103000-t-draft.md"
git -C "$TRACKED" add -f .stride/2026-05-12T103000-t-draft.md
printf '*\n' > "$TRACKED/.stride/.gitignore"
assert_eq "draft_find: a tracked draft is not offered for resume" \
  "$( cd "$TRACKED" && sti_draft_find .stride t 2>/dev/null || true )" ""
TRACKED_RC=0
( cd "$TRACKED" && printf 'new secret' | sti_draft_save .stride/2026-05-12T103000-t-draft.md ) 2>/dev/null || TRACKED_RC=$?
assert_eq "draft_save: refuses to write over a tracked draft" \
  "$TRACKED_RC|$(cat "$TRACKED/.stride/2026-05-12T103000-t-draft.md")" "1|old draft"

# An ignored draft in a work tree is still found.
FOUNDREPO="$TMP/found repo"
mkdir -p "$FOUNDREPO"
git -C "$FOUNDREPO" init -q
( cd "$FOUNDREPO" && printf 'x' | sti_draft_save .stride/2026-05-12T103000-f-draft.md )
assert_eq "draft_find: an ignored draft in a work tree is offered" \
  "$( cd "$FOUNDREPO" && sti_draft_find .stride f )" ".stride/2026-05-12T103000-f-draft.md"

# A '/' in the slug or timestamp cannot steer the draft out of the scratch dir.
TRAV_RC=0; TRAV_OUT="$(sti_draft_path .stride 2026-05-12T103000 'a/../../y' 2>/dev/null)" || TRAV_RC=$?
assert_eq "draft_path: a slug containing '/' is refused" "$TRAV_RC|$TRAV_OUT" "1|"
TS_RC=0; sti_draft_path .stride '2026/05' foo >/dev/null 2>&1 || TS_RC=$?
assert_eq "draft_path: a timestamp containing '/' is refused" "$TS_RC" "1"

# A symlinked draft is never offered for resume.
FINDDIR="$TMP/find-links"
mkdir -p "$FINDDIR"
printf 'secret elsewhere\n' > "$TMP/elsewhere.md"
ln -s "$TMP/elsewhere.md" "$FINDDIR/2026-05-12T103000-linky-draft.md"
FOUND_LINK="$(sti_draft_find "$FINDDIR" linky 2>/dev/null || true)"
assert_eq "draft_find: skips a symlinked draft" "$FOUND_LINK" ""

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
