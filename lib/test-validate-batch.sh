#!/usr/bin/env bash
# Unit tests for lib/validate_batch.py.
#
# Each test feeds a fixture JSON document to the validator and asserts the
# expected outcome (zero exit + no output for valid docs; non-zero exit with
# a matching error substring for invalid docs).
#
# Run:
#   ./lib/test-validate-batch.sh
#
# Exits 0 on success, non-zero on failure. Prints one-line per-test status.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="${SCRIPT_DIR}/validate_batch.py"

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

assert_ok() {
  # Validator must exit 0 with no stderr output.
  local label="$1"
  local fixture="$2"
  local stderr
  if stderr="$(python3 "$VALIDATOR" "$fixture" 2>&1 >/dev/null)"; then
    if [ -z "$stderr" ]; then
      PASS=$(( PASS + 1 ))
      printf 'PASS  %s\n' "$label"
    else
      FAIL=$(( FAIL + 1 ))
      printf 'FAIL  %s\n      unexpected stderr: %s\n' "$label" "$stderr"
    fi
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      exit code != 0; stderr: %s\n' "$label" "$stderr"
  fi
}

assert_fails_with() {
  # Validator must exit non-zero AND stderr must contain the substring.
  local label="$1"
  local fixture="$2"
  local needle="$3"
  local stderr
  if stderr="$(python3 "$VALIDATOR" "$fixture" 2>&1 >/dev/null)"; then
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected exit != 0 but got 0\n' "$label"
    return
  fi
  if printf '%s' "$stderr" | grep -Fq "$needle"; then
    PASS=$(( PASS + 1 ))
    printf 'PASS  %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected substring: %s\n      actual stderr:      %s\n' \
      "$label" "$needle" "$stderr"
  fi
}

assert_warns_with() {
  # Validator must exit 0 with empty stderr AND stdout must contain the
  # substring (the advisory scored-field warning path).
  local label="$1"
  local fixture="$2"
  local needle="$3"
  local stdout
  if ! stdout="$(python3 "$VALIDATOR" "$fixture" 2>"$TMP/warn-stderr.txt")"; then
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected exit 0 but got non-zero; stderr: %s\n' \
      "$label" "$(cat "$TMP/warn-stderr.txt")"
    return
  fi
  if [ -s "$TMP/warn-stderr.txt" ]; then
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      unexpected stderr: %s\n' \
      "$label" "$(cat "$TMP/warn-stderr.txt")"
    return
  fi
  if printf '%s' "$stdout" | grep -Fq "$needle"; then
    PASS=$(( PASS + 1 ))
    printf 'PASS  %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected stdout substring: %s\n      actual stdout: %s\n' \
      "$label" "$needle" "$stdout"
  fi
}

assert_ok_silent() {
  # Validator must exit 0 with NO output at all — no warnings, no errors.
  local label="$1"
  local fixture="$2"
  local combined
  if combined="$(python3 "$VALIDATOR" "$fixture" 2>&1)"; then
    if [ -z "$combined" ]; then
      PASS=$(( PASS + 1 ))
      printf 'PASS  %s\n' "$label"
    else
      FAIL=$(( FAIL + 1 ))
      printf 'FAIL  %s\n      expected silence but got: %s\n' "$label" "$combined"
    fi
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      exit code != 0; output: %s\n' "$label" "$combined"
  fi
}

# --- (a) parse_error -------------------------------------------------------

cat > "$TMP/parse_error.json" <<'EOF'
{ this is not json
EOF
assert_fails_with "(a) parse error — invalid JSON exits with parse failure" \
  "$TMP/parse_error.json" \
  "JSON parse failed"

# --- (b) wrong_root_key ----------------------------------------------------

cat > "$TMP/wrong_root_tasks.json" <<'EOF'
{"tasks": [{"title": "x"}]}
EOF
assert_fails_with "(b) wrong root key 'tasks' — dedicated error message" \
  "$TMP/wrong_root_tasks.json" \
  "root key 'tasks' is the most common batch-API mistake"

cat > "$TMP/wrong_root_batch.json" <<'EOF'
{"batch": []}
EOF
assert_fails_with "(b) wrong root key 'batch' — named in error" \
  "$TMP/wrong_root_batch.json" \
  "missing the required 'goals' array"

# --- (c) empty_goals -------------------------------------------------------

cat > "$TMP/empty_goals.json" <<'EOF'
{"goals": []}
EOF
assert_fails_with "(c) empty goals array exits with under-specification hint" \
  "$TMP/empty_goals.json" \
  "empty array"

cat > "$TMP/goals_not_array.json" <<'EOF'
{"goals": {"title": "oops"}}
EOF
assert_fails_with "(c) goals as object — must be an array" \
  "$TMP/goals_not_array.json" \
  "must be an array"

# --- (d) goal_missing_field ------------------------------------------------

cat > "$TMP/missing_title.json" <<'EOF'
{"goals": [{"type": "goal", "tasks": []}]}
EOF
assert_fails_with "(d) goal missing title — names the field" \
  "$TMP/missing_title.json" \
  "goals[0] is missing required field 'title'"

cat > "$TMP/missing_tasks.json" <<'EOF'
{"goals": [{"title": "T", "type": "goal"}]}
EOF
assert_fails_with "(d) goal missing tasks — names the field" \
  "$TMP/missing_tasks.json" \
  "goals[0] is missing required field 'tasks'"

cat > "$TMP/empty_tasks.json" <<'EOF'
{"goals": [{"title": "T", "type": "goal", "tasks": []}]}
EOF
assert_fails_with "(d) goal with empty tasks array fails" \
  "$TMP/empty_tasks.json" \
  "goals[0].tasks is empty"

# --- (e) bad_dependency_index ---------------------------------------------

cat > "$TMP/dep_out_of_range.json" <<'EOF'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": []},
        {"title": "Second", "type": "work", "dependencies": [5]}
      ]
    }
  ]
}
EOF
assert_fails_with "(e) dependency index out of range — names the failing path" \
  "$TMP/dep_out_of_range.json" \
  "goals[0].tasks[1].dependencies references index 5 but goal only has 2 tasks"

cat > "$TMP/dep_forward_ref.json" <<'EOF'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [1]},
        {"title": "Second", "type": "work", "dependencies": []}
      ]
    }
  ]
}
EOF
assert_fails_with "(e) forward-reference dependency fails" \
  "$TMP/dep_forward_ref.json" \
  "must point to an earlier sibling"

cat > "$TMP/dep_self_ref.json" <<'EOF'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [0]}
      ]
    }
  ]
}
EOF
assert_fails_with "(e) self-reference dependency fails" \
  "$TMP/dep_self_ref.json" \
  "must point to an earlier sibling"

cat > "$TMP/dep_negative.json" <<'EOF'
{
  "goals": [
    {
      "title": "Test goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [-1]}
      ]
    }
  ]
}
EOF
assert_fails_with "(e) negative dependency index fails" \
  "$TMP/dep_negative.json" \
  "is negative"

# --- happy paths -----------------------------------------------------------

cat > "$TMP/valid_minimal.json" <<'EOF'
{
  "decomposition_notes": "Single goal; no cross-goal deps.",
  "goals": [
    {
      "title": "Minimal goal",
      "type": "goal",
      "tasks": [
        {"title": "First task", "type": "work", "dependencies": []}
      ]
    }
  ]
}
EOF
assert_ok "valid minimal document with one goal and one task" \
  "$TMP/valid_minimal.json"

cat > "$TMP/valid_chained_deps.json" <<'EOF'
{
  "goals": [
    {
      "title": "Chained deps",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": []},
        {"title": "Second", "type": "work", "dependencies": [0]},
        {"title": "Third", "type": "work", "dependencies": [0, 1]}
      ]
    }
  ]
}
EOF
assert_ok "valid document with chained sibling dependencies" \
  "$TMP/valid_chained_deps.json"

cat > "$TMP/valid_string_dep.json" <<'EOF'
{
  "goals": [
    {
      "title": "String identifier dep",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": ["W47"]}
      ]
    }
  ]
}
EOF
assert_ok "valid: string identifier dependencies are not bounds-checked" \
  "$TMP/valid_string_dep.json"

# --- (f) length_limit -------------------------------------------------------
#
# The server binds title (goal and task) and each security_considerations
# element to varchar(255), which limits by Unicode CODE POINT — not bytes,
# not graphemes. Python's len() matches. Length-sensitive fixtures are
# generated with json.dumps to avoid heredoc newline contamination.

python3 - "$TMP" <<'PYEOF'
import json, sys
tmp = sys.argv[1]

def write(name, doc):
    with open(f"{tmp}/{name}", "w", encoding="utf-8") as fp:
        json.dump(doc, fp)

full_fields = {
    "acceptance_criteria": "It works",
    "testing_strategy": {"unit_tests": ["one"]},
    "security_considerations": ["None — test fixture"],
    "pitfalls": ["none"],
    "patterns_to_follow": "existing",
}

def task(title="Task", **overrides):
    t = {"title": title, "type": "work", "dependencies": [], **full_fields}
    t.update(overrides)
    return t

def batch(goal_title="Goal", tasks=None, **goal_overrides):
    g = {"title": goal_title, "type": "goal", "tasks": tasks or [task()]}
    g.update(goal_overrides)
    return {"goals": [g]}

write("len_task_title_256.json", batch(tasks=[task(title="x" * 256)]))
write("len_task_title_255.json", batch(tasks=[task(title="x" * 255)]))
write("len_goal_title_256.json", batch(goal_title="g" * 256))
write("len_sec_elem_271.json", batch(tasks=[task(
    security_considerations=["fine", "y" * 271])]))
write("len_goal_sec_elem_260.json", batch(
    security_considerations=["z" * 260]))
# Multibyte: 255 CJK chars is 765 UTF-8 bytes but exactly 255 code points —
# it must PASS, proving the check counts code points, not bytes.
write("len_cjk_255.json", batch(tasks=[task(title="中" * 255)]))
write("len_cjk_256.json", batch(tasks=[task(title="中" * 256)]))
PYEOF

assert_fails_with "(f) 256-char task title fails with its path and length" \
  "$TMP/len_task_title_256.json" \
  "goals[0].tasks[0].title is 256 characters"

assert_ok "(f) boundary: exactly 255 characters passes" \
  "$TMP/len_task_title_255.json"

assert_fails_with "(f) 256-char goal title fails with its path" \
  "$TMP/len_goal_title_256.json" \
  "goals[0].title is 256 characters"

assert_fails_with "(f) oversized security_considerations element names its element path" \
  "$TMP/len_sec_elem_271.json" \
  "goals[0].tasks[0].security_considerations[1] is 271 characters"

assert_fails_with "(f) goal-level security_considerations element is also checked" \
  "$TMP/len_goal_sec_elem_260.json" \
  "goals[0].security_considerations[0] is 260 characters"

assert_ok "(f) multibyte: 255 CJK code points (765 UTF-8 bytes) passes — code points, not bytes" \
  "$TMP/len_cjk_255.json"

assert_fails_with "(f) multibyte: 256 CJK code points fails as 256 characters" \
  "$TMP/len_cjk_256.json" \
  "is 256 characters"

# --- advisory scored-field completeness -------------------------------------
#
# Missing OR empty scored fields warn on stdout and never change the exit
# code. Both the missing-key and empty-array shapes are pinned.

cat > "$TMP/warn_missing_key.json" <<'EOF'
{
  "goals": [
    {
      "title": "Warn goal",
      "type": "goal",
      "tasks": [
        {
          "title": "Task without security_considerations",
          "type": "work",
          "dependencies": [],
          "acceptance_criteria": "It works",
          "testing_strategy": {"unit_tests": ["one"]},
          "pitfalls": ["none"],
          "patterns_to_follow": "existing"
        }
      ]
    }
  ]
}
EOF
assert_warns_with "advisory: missing scored-field KEY warns but validation passes" \
  "$TMP/warn_missing_key.json" \
  "goals[0].tasks[0].security_considerations is empty or missing"

cat > "$TMP/warn_empty_array.json" <<'EOF'
{
  "goals": [
    {
      "title": "Warn goal",
      "type": "goal",
      "tasks": [
        {
          "title": "Task with empty pitfalls array",
          "type": "work",
          "dependencies": [],
          "acceptance_criteria": "It works",
          "testing_strategy": {"unit_tests": ["one"]},
          "security_considerations": ["None — test fixture"],
          "pitfalls": [],
          "patterns_to_follow": "existing"
        }
      ]
    }
  ]
}
EOF
assert_warns_with "advisory: EMPTY-ARRAY scored field warns the same as a missing key" \
  "$TMP/warn_empty_array.json" \
  "goals[0].tasks[0].pitfalls is empty or missing"

cat > "$TMP/warn_whitespace_string.json" <<'EOF'
{
  "goals": [
    {
      "title": "Warn goal",
      "type": "goal",
      "tasks": [
        {
          "title": "Task with whitespace-only patterns",
          "type": "work",
          "dependencies": [],
          "acceptance_criteria": "It works",
          "testing_strategy": {"unit_tests": ["one"]},
          "security_considerations": ["None — test fixture"],
          "pitfalls": ["none"],
          "patterns_to_follow": "   "
        }
      ]
    }
  ]
}
EOF
assert_warns_with "advisory: whitespace-only string scored field warns" \
  "$TMP/warn_whitespace_string.json" \
  "goals[0].tasks[0].patterns_to_follow is empty or missing"

cat > "$TMP/all_fields_silent.json" <<'EOF'
{
  "goals": [
    {
      "title": "Fully populated goal",
      "type": "goal",
      "tasks": [
        {
          "title": "Fully populated task",
          "type": "work",
          "dependencies": [],
          "acceptance_criteria": "It works",
          "testing_strategy": {"unit_tests": ["one"]},
          "security_considerations": ["None — test fixture"],
          "pitfalls": ["none"],
          "patterns_to_follow": "existing"
        }
      ]
    }
  ]
}
EOF
assert_ok_silent "advisory: all five scored fields populated — validator is completely silent" \
  "$TMP/all_fields_silent.json"

# Ordering pin: a fatal check must exit BEFORE any advisory warning prints.
cat > "$TMP/fatal_beats_warning.json" <<'EOF'
{
  "goals": [
    {
      "title": "Ordering goal",
      "type": "goal",
      "tasks": [
        {"title": "First", "type": "work", "dependencies": [0]}
      ]
    }
  ]
}
EOF
ORDERING_STDOUT="$(python3 "$VALIDATOR" "$TMP/fatal_beats_warning.json" 2>/dev/null)"
ORDERING_EXIT=$?
if [ "$ORDERING_EXIT" -ne 0 ] && [ -z "$ORDERING_STDOUT" ]; then
  PASS=$(( PASS + 1 ))
  printf 'PASS  advisory: warnings never precede a fatal failure (stdout empty on fatal exit)\n'
else
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  advisory: warnings never precede a fatal failure\n      exit: %s stdout: %s\n' \
    "$ORDERING_EXIT" "$ORDERING_STDOUT"
fi

# Real repo fixtures: all three must pass with zero warnings (W1462 gave every
# task the five scored fields, and no title/security element approaches 255).
for repo_fixture in "$SCRIPT_DIR"/../fixtures/*-stride-batch.json; do
  assert_ok_silent "repo fixture passes silently: $(basename "$repo_fixture")" \
    "$repo_fixture"
done

# --- summary --------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
