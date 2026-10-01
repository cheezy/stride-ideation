#!/usr/bin/env bash
# Lint + behaviour tests for positional placeholders in command/agent/skill
# markdown (D345).
#
# Claude Code substitutes a command's positional arguments into its body
# before the model reads it: every dollar-sign-plus-digit sequence not
# followed by a word character becomes the matching argument (0-indexed),
# and is left literal only when that argument is absent. An awk field
# reference inside a command body is therefore rewritten whenever the user
# passes a second token (`--goal 2`, `--yes`), while single-argument test
# runs hide the bug. OpenCode expands the same syntax.
#
# This script:
#   1. lints commands/*.md, agents/*.md and skills/**/*.md for any
#      dollar-digit, dollar-brace-digit or indexed $ARGUMENTS form
#      (bare $ARGUMENTS is the intended, allowed placeholder);
#   2. proves the lint catches planted references;
#   3. extracts the LIVE Step 2b and Step 6 fragments from
#      commands/stridify.md, applies a simulated multi-argument substitution
#      (argv = path, --goal, 2), and checks they are unchanged and still
#      produce the same output as the previous awk implementation.
#
# Run:
#   ./lib/test-command-placeholders.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STRIDIFY="${PLUGIN_ROOT}/commands/stridify.md"

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

# Every form Claude Code expands: $N, ${N}, $ARGUMENTS[N]. Bare $ARGUMENTS
# is the documented placeholder and stays allowed.
PLACEHOLDER_RE='\$[0-9]|\$\{[0-9]|\$ARGUMENTS\['

# Prints file:line:text for every placeholder hit; empty output = clean.
scan_placeholders() {
  grep -nHE "$PLACEHOLDER_RE" "$@" 2>/dev/null || true
}

lint_targets() {
  local root="$1"
  find "$root/commands" "$root/agents" "$root/skills" -type f -name '*.md' 2>/dev/null | sort
}

# Simulated Claude Code substitution: $N (not followed by a word char) and
# $ARGUMENTS[N] become argv[N] when argv has that index, else stay literal.
simulate_substitution() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re, sys
path, argv = sys.argv[1], sys.argv[2:]
text = open(path).read()
def sub(m):
    i = int(m.group(1) or m.group(2))
    return argv[i] if i < len(argv) else m.group(0)
sys.stdout.write(re.sub(r'\$ARGUMENTS\[(\d+)\]|\$(\d+)(?!\w)', sub, text))
PY
}

# Extracts the first ```bash fenced block after the heading line matching $2.
extract_block() {
  awk -v heading="$2" '
    index($0, heading) == 1 { found = 1; next }
    found && !inblock && /^```bash/ { inblock = 1; next }
    inblock && /^```/ { exit }
    inblock { print }
  ' "$1"
}

# --- lint: the live tree is clean -------------------------------------------

LIVE_HITS="$(lint_targets "$PLUGIN_ROOT" | while IFS= read -r f; do scan_placeholders "$f"; done)"
assert_eq "lint: commands/agents/skills markdown has no positional placeholder" \
  "$LIVE_HITS" ""

assert_eq "lint: commands/stridify.md is clean" "$(scan_placeholders "$STRIDIFY")" ""
assert_eq "lint: commands/ideate.md is clean" \
  "$(scan_placeholders "${PLUGIN_ROOT}/commands/ideate.md")" ""

# --- lint: planted references are caught ------------------------------------

PLANT="$TMP/plant"
mkdir -p "$PLANT/commands"
cp "$STRIDIFY" "$PLANT/commands/stridify.md"
printf '%s\n' "SOURCE_SHA=\"\$(shasum -a 256 x | awk '{print \$1}')\"" >> "$PLANT/commands/stridify.md"
assert_eq "lint: flags a planted awk field reference in a copy of stridify.md" \
  "$(lint_targets "$PLANT" | while IFS= read -r f; do scan_placeholders "$f"; done | wc -l | tr -d ' ')" "1"

check_plant() {
  local label="$1" line="$2" expected="$3"
  printf '%s\n' "$line" > "$TMP/one.md"
  local n
  n="$(scan_placeholders "$TMP/one.md" | wc -l | tr -d ' ')"
  assert_eq "$label" "$n" "$expected"
}
check_plant "lint: flags the brace form" 'echo "${2}"' 1
check_plant "lint: flags indexed \$ARGUMENTS" 'echo "$ARGUMENTS[1]"' 1
check_plant "lint: flags a multi-digit reference" 'echo $10' 1
check_plant "lint: allows bare \$ARGUMENTS" 'The user invoked you with `$ARGUMENTS`.' 0
check_plant "lint: allows a path containing digits" 'docs/2026-05-12T103000-x.md' 0
check_plant "lint: allows a named variable" 'echo "$GOAL_ARG"' 0

# --- simulated multi-argument substitution leaves stridify.md unchanged -----

SIMULATED="$TMP/stridify-substituted.md"
simulate_substitution "$STRIDIFY" "docs/x-requirements.md" "--goal" "2" > "$SIMULATED"
if cmp -s "$STRIDIFY" "$SIMULATED"; then
  PASS=$(( PASS + 1 ))
  printf 'PASS  substitution (argv = path, --goal, 2) leaves stridify.md byte-identical\n'
else
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  substitution rewrote stridify.md:\n'
  diff "$STRIDIFY" "$SIMULATED" | sed 's/^/      /'
fi

# The substitution itself works (guards against a vacuous pass above).
printf '%s\n' "awk '{print \$1}' \$2 \$ARGUMENTS[2] \$7" > "$TMP/sim-probe.md"
assert_eq "substitution simulator rewrites positional forms as Claude Code does" \
  "$(simulate_substitution "$TMP/sim-probe.md" "p" "--goal" "2")" \
  "awk '{print --goal}' 2 2 \$7"

# --- fixture ----------------------------------------------------------------

FIXTURE="$TMP/2026-05-12T103000-seven-surfaces-requirements.md"
cat > "$FIXTURE" <<'EOF'
# Some Feature

## Problem

A description of the problem.

## Decomposition seams

1. **Kanban app** (this repo) — defines the contract.
2. **stride plugin** (this repo: `stride/`) — reference workflow.
3. **stride-copilot** (separate repo) — Copilot CLI adapter.

## Assumptions

None.
EOF

# --- Step 2b: live fragment, run after substitution -------------------------

STEP2B="$TMP/step2b.sh"
extract_block "$SIMULATED" '### Step 2b' | sed "s#<plugin-root>#${PLUGIN_ROOT}#g" > "$STEP2B"
assert_eq "Step 2b: fenced bash fragment extracted from stridify.md" \
  "$(grep -c 'sti_resolve_goal' "$STEP2B")" "1"

run_step2b() {
  REQUIREMENTS_PATH="$FIXTURE" GOAL_ARG="$1" bash -c '
    . "$0"
    printf "%s|%s|%s\n" "$GOAL_INDEX" "$GOAL_NAME" "$GOAL_SLUG"' "$STEP2B"
}

assert_eq "Step 2b: --goal 2 resolves index, name with a space, and slug" \
  "$(run_step2b 2 2>&1)" "2|stride plugin|stride-plugin"
assert_eq "Step 2b: --goal by name resolves the same tuple" \
  "$(run_step2b stride-copilot 2>&1)" "3|stride-copilot|stride-copilot"

# The previous awk implementation, kept here as the reference the cut-based
# fragment must match byte for byte.
. "${SCRIPT_DIR}/filename.sh"
RESOLVED="$(sti_resolve_goal "$FIXTURE" 2)"
for f in 1 2 3; do
  assert_eq "resolver field $f: cut matches the previous awk output" \
    "$(printf '%s\n' "$RESOLVED" | cut -f"$f")" \
    "$(printf '%s' "$RESOLVED" | awk -F'\t' -v f="$f" '{print $f}')"
done

NOMATCH_OUT="$(run_step2b no-such-goal 2>&1)"
NOMATCH_RC=$?
assert_eq "Step 2b: unmatched --goal exits 1" "$NOMATCH_RC" "1"
EXPECTED_LISTING="$(printf '%s\n' "stride-ideation: --goal value 'no-such-goal' did not match any Decomposition seam in $FIXTURE. Available seams:"
  sti_extract_seams "$FIXTURE" | awk -F'\t' '{ printf "  %d. %s (slug: %s)\n", $1, $2, $3 }')"
assert_eq "Step 2b: seam listing matches the previous awk output" \
  "$NOMATCH_OUT" "$EXPECTED_LISTING"

# --- Step 6: SOURCE_SHA, live fragment and prose fallback -------------------

SHA_LINE="$(grep -E '^SOURCE_SHA=' "$SIMULATED")"
assert_eq "Step 6: exactly one SOURCE_SHA line in stridify.md" \
  "$(printf '%s\n' "$SHA_LINE" | grep -c .)" "1"

REFERENCE_SHA="$(shasum -a 256 "$FIXTURE" | awk '{print $1}' | tr 'A-Z' 'a-z')"
assert_eq "Step 6: shasum fragment yields the document's lowercase sha256" \
  "$(REQUIREMENTS_PATH="$FIXTURE" bash -c "$SHA_LINE"'; printf "%s" "$SOURCE_SHA"')" \
  "$REFERENCE_SHA"

FALLBACK="$(grep -oE 'sha256sum "\$REQUIREMENTS_PATH" [^`]*' "$SIMULATED")"
assert_eq "Step 6: sha256sum fallback documented without awk" \
  "$(printf '%s\n' "$FALLBACK" | grep -c 'cut -d')" "1"
if command -v sha256sum >/dev/null 2>&1; then
  assert_eq "Step 6: sha256sum fallback yields the same hash" \
    "$(REQUIREMENTS_PATH="$FIXTURE" bash -c "$FALLBACK")" "$REFERENCE_SHA"
else
  printf 'SKIP  Step 6: sha256sum not installed; fallback not executed\n'
fi

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
