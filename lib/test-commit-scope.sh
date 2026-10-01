#!/usr/bin/env bash
# Tests that the commit fragments in /stride-ideation:ideate (Step 9) and
# /stride-ideation:stridify (Step 8d) commit ONLY the artifact they wrote.
#
# A plain `git add <path>; git commit -m ...` commits everything already
# staged, so a user's unrelated staged work would ride along in a
# "stride-ideation:" commit. The fragments pass the artifact as a pathspec
# after `--`; these tests run the real fragments, extracted from the command
# files, in scratch repos that have other files staged beforehand.
#
# Run:
#   ./lib/test-commit-scope.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

pass() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  %s\n' "$1"
  if [ "${2:-}" != "" ]; then
    printf '      %s\n' "$2"
  fi
}
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# extract <command.md> <heading-prefix> <n> <out> — the n-th ```bash block
# under the "### <heading-prefix>" step, with the plugin-root token
# substituted the way Claude Code substitutes it when it loads the command.
extract() {
  python3 - "$1" "$2" "$3" "$4" "$PLUGIN_ROOT" <<'PY'
import re, sys
src, prefix, n, out, root = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
text = open(src).read().replace("${" + "CLAUDE_PLUGIN_ROOT" + "}", root)
lines, heading, seen, i = text.split("\n"), "", 0, 0
while i < len(lines):
    if lines[i].startswith("### "):
        heading = lines[i][4:]
    if re.match(r"^```bash\s*$", lines[i]) and heading.startswith(prefix + ":"):
        body, i = [], i + 1
        while not re.match(r"^```\s*$", lines[i]):
            body.append(lines[i])
            i += 1
        seen += 1
        if seen == n:
            open(out, "w").write("\n".join(body) + "\n")
            sys.exit(0)
    i += 1
sys.exit("block not found")
PY
}

IDEATE_COMMIT="$TMP/ideate-step9.sh"
STRIDIFY_COMMIT="$TMP/stridify-step8d.sh"
extract "${PLUGIN_ROOT}/commands/ideate.md" "Step 9" 1 "$IDEATE_COMMIT"
extract "${PLUGIN_ROOT}/commands/stridify.md" "Step 8" 3 "$STRIDIFY_COMMIT"

for f in "$IDEATE_COMMIT" "$STRIDIFY_COMMIT"; do
  name="$(basename "$f" .sh)"
  if grep -qE 'git --literal-pathspecs commit -m "[^"]*" -- "\$TARGET_PATH"' "$f" \
     && ! grep -E 'git( --literal-pathspecs)? commit' "$f" | grep -qvE -- '-- "\$TARGET_PATH"'; then
    pass "$name: every commit passes the artifact path after -- as a literal pathspec"
  else
    fail "$name: a commit runs without the literal -- pathspec"
  fi
  if grep -qE 'git --literal-pathspecs add -- "\$TARGET_PATH"' "$f"; then
    pass "$name: git add ends option parsing and matches the path literally"
  else
    fail "$name: git add is not 'git --literal-pathspecs add -- \"\$TARGET_PATH\"'"
  fi
  if grep -qE 'git (add -A|commit -a|add \.)' "$f"; then
    fail "$name: uses git add -A / commit -a"
  else
    pass "$name: never uses git add -A or git commit -a"
  fi
done

# new_repo <dir> [unborn] — scratch repo with a file staged before the
# "session" (in the artifact's own directory) and another staged elsewhere.
new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  if [ "${2:-}" != "unborn" ]; then
    printf 'base\n' > "$1/README"
    git -C "$1" add README
    git -C "$1" commit -q -m init
  fi
  mkdir -p "$1/docs/ideation"
  printf 'unrelated staged work\n' > "$1/docs/ideation/user-notes.md"
  printf 'secret-ish wip\n' > "$1/wip.txt"
  git -C "$1" add docs/ideation/user-notes.md wip.txt
}

# assert_scoped <label> <repo> <artifact> <subject>
assert_scoped() {
  local label="$1" repo="$2" artifact="$3" subject="$4"
  eq "$label: the artifact is the only path in the new commit" \
    "$(git -C "$repo" show --name-only --format= HEAD)" "$artifact"
  eq "$label: pre-staged files are still staged and uncommitted" \
    "$(git -C "$repo" diff --cached --name-only | sort | tr '\n' ' ')" "docs/ideation/user-notes.md wip.txt "
  eq "$label: the commit subject is unchanged" "$(git -C "$repo" log -1 --format=%s)" "$subject"
}

# run_fragment <repo> <fragment> NAME VALUE ... — run in a fresh bash with
# the carried-forward values prepended as single-quoted literals.
run_fragment() {
  local repo="$1" frag="$2" script="$TMP/run.sh"
  shift 2
  : > "$script"
  while [ "$#" -gt 1 ]; do
    printf "%s='%s'\n" "$1" "$2" >> "$script"
    shift 2
  done
  cat "$frag" >> "$script"
  ( cd "$repo" && bash "$script" > "$TMP/out" 2> "$TMP/err" )
  RC=$?
}

# --- ideate Step 9 -------------------------------------------------------------------

R="$TMP/ideate repo"
new_repo "$R"
DOC="docs/ideation/2026-06-01T090000-topic-requirements.md"
printf '# doc\n' > "$R/$DOC"
mkdir -p "$R/.stride"; printf 'draft' > "$R/.stride/2026-06-01T090000-topic-draft.md"
run_fragment "$R" "$IDEATE_COMMIT" TARGET_PATH "$DOC" CONTINUE_PATH '' SLUG topic DRAFT_PATH .stride/2026-06-01T090000-topic-draft.md
eq "ideate Step 9: exits 0" "$RC" "0"
assert_scoped "ideate Step 9" "$R" "$DOC" "stride-ideation: requirements for topic"
if [ ! -e "$R/.stride/2026-06-01T090000-topic-draft.md" ]; then pass "ideate Step 9: clears the draft after the commit"; else fail "ideate Step 9: draft not cleared"; fi

R="$TMP/ideate continue"
new_repo "$R"
DOC2="docs/ideation/2026-06-02T090000-topic-requirements.md"
printf '# refined\n' > "$R/$DOC2"
run_fragment "$R" "$IDEATE_COMMIT" TARGET_PATH "$DOC2" CONTINUE_PATH docs/ideation/old-requirements.md SLUG topic DRAFT_PATH .stride/none-draft.md
eq "ideate Step 9 --continue: exits 0" "$RC" "0"
assert_scoped "ideate Step 9 --continue" "$R" "$DOC2" "stride-ideation: refine requirements for topic"

R="$TMP/ideate unborn"
new_repo "$R" unborn
printf '# doc\n' > "$R/$DOC"
run_fragment "$R" "$IDEATE_COMMIT" TARGET_PATH "$DOC" CONTINUE_PATH '' SLUG topic DRAFT_PATH .stride/none-draft.md
eq "ideate Step 9 in a repo with no commits: exits 0" "$RC" "0"
assert_scoped "ideate Step 9 in a repo with no commits" "$R" "$DOC" "stride-ideation: requirements for topic"

# A failed git add (the doc was never written, so its path matches nothing)
# must stop before the draft is cleared.
R="$TMP/ideate failing add"
new_repo "$R"
printf 'draft' > "$R/keep-draft.md"
run_fragment "$R" "$IDEATE_COMMIT" TARGET_PATH docs/ideation/missing-requirements.md CONTINUE_PATH '' SLUG topic DRAFT_PATH keep-draft.md
if [ "$RC" -ne 0 ] && [ -e "$R/keep-draft.md" ]; then
  pass "ideate Step 9: a failed git add exits non-zero and keeps the draft"
else
  fail "ideate Step 9: failed git add did not stop" "rc=$RC"
fi

# A failed git commit (a pre-commit hook rejects it after the add succeeded)
# must also stop before the draft is cleared.
R="$TMP/ideate failing commit"
new_repo "$R"
printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
printf '# doc\n' > "$R/$DOC"
printf 'draft' > "$R/keep-draft.md"
run_fragment "$R" "$IDEATE_COMMIT" TARGET_PATH "$DOC" CONTINUE_PATH '' SLUG topic DRAFT_PATH keep-draft.md
if [ "$RC" -ne 0 ] && [ -e "$R/keep-draft.md" ]; then
  pass "ideate Step 9: a rejected git commit exits non-zero and keeps the draft"
else
  fail "ideate Step 9: rejected commit did not stop" "rc=$RC"
fi

# --- stridify Step 8d ----------------------------------------------------------------

R="$TMP/stridify repo"
new_repo "$R"
BATCH="docs/ideation/2026-06-01T090000-topic-stride-batch.json"
printf '{"goals": []}\n' > "$R/$BATCH"
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$BATCH" SLUG topic GOAL_SLUG ''
eq "stridify Step 8d: exits 0" "$RC" "0"
assert_scoped "stridify Step 8d" "$R" "$BATCH" "stride-ideation: decomposition for topic"

R="$TMP/stridify goal"
new_repo "$R"
printf '{"goals": []}\n' > "$R/$BATCH"
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$BATCH" SLUG topic GOAL_SLUG kanban-app
eq "stridify Step 8d --goal: exits 0" "$RC" "0"
assert_scoped "stridify Step 8d --goal" "$R" "$BATCH" "stride-ideation: decomposition for topic goal kanban-app"

R="$TMP/stridify unborn"
new_repo "$R" unborn
printf '{"goals": []}\n' > "$R/$BATCH"
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$BATCH" SLUG topic GOAL_SLUG ''
eq "stridify Step 8d in a repo with no commits: exits 0" "$RC" "0"
assert_scoped "stridify Step 8d in a repo with no commits" "$R" "$BATCH" "stride-ideation: decomposition for topic"

# A failed audit commit does not stop /stridify: Step 5 supports running
# outside a git repo, and the batch still ships from the file on disk.
R="$TMP/stridify rejected"
new_repo "$R"
printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
printf '{"goals": []}\n' > "$R/$BATCH"
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$BATCH" SLUG topic GOAL_SLUG ''
eq "stridify Step 8d: a rejected commit still carries BATCH_PATH forward" \
  "$(sed -n 's/^carry: BATCH_PATH=//p' "$TMP/out")" "$BATCH"

# --- paths git would otherwise read as globs or pathspec magic -----------------------

# A glob in the slug: a staged sibling that the glob would match stays out.
R="$TMP/stridify glob"
new_repo "$R"
GLOB_BATCH="docs/ideation/2026-06-01T090000-*-stride-batch.json"
printf '{"goals": []}\n' > "$R/$GLOB_BATCH"
printf '{"sibling": true}\n' > "$R/docs/ideation/2026-06-01T090000-other-stride-batch.json"
git -C "$R" add docs/ideation/2026-06-01T090000-other-stride-batch.json
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$GLOB_BATCH" SLUG '*' GOAL_SLUG ''
eq "glob in the path: only the literal file is committed" \
  "$(git -C "$R" show --name-only --format= HEAD)" "$GLOB_BATCH"
eq "glob in the path: the matching sibling stays staged" \
  "$(git -C "$R" diff --cached --name-only | sort | tr '\n' ' ')" \
  "docs/ideation/2026-06-01T090000-other-stride-batch.json docs/ideation/user-notes.md wip.txt "

# ":!" magic in the directory: read literally, not as "everything but this".
R="$TMP/stridify magic"
new_repo "$R"
printf 'unstaged edit\n' >> "$R/README"
mkdir -p "$R/:!evil"
MAGIC_BATCH=":!evil/2026-06-01T090000-topic-stride-batch.json"
printf '{"goals": []}\n' > "$R/$MAGIC_BATCH"
run_fragment "$R" "$STRIDIFY_COMMIT" TARGET_PATH "$MAGIC_BATCH" SLUG topic GOAL_SLUG ''
eq "':!' in the path: only the literal file is committed" \
  "$(git -C "$R" show --name-only --format= HEAD)" "$MAGIC_BATCH"
eq "':!' in the path: pre-staged files stay staged" \
  "$(git -C "$R" diff --cached --name-only | sort | tr '\n' ' ')" "docs/ideation/user-notes.md wip.txt "
eq "':!' in the path: an unstaged edit stays out of the commit" \
  "$(git -C "$R" diff --name-only)" "README"

# --- negative control: the old form really did sweep ---------------------------------

R="$TMP/old form"
new_repo "$R"
printf '{"goals": []}\n' > "$R/$BATCH"
( cd "$R" && git add "$BATCH" && git commit -q -m "stride-ideation: decomposition for topic" )
if git -C "$R" show --name-only --format= HEAD | grep -q 'wip.txt'; then
  pass "control: a commit without the pathspec sweeps pre-staged files (the defect)"
else
  fail "control: the old form did not sweep — this test would not catch a regression"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
