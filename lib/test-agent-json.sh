#!/usr/bin/env bash
# Every fenced ```json block in the agent prompts must parse as JSON (D346).
#
# The agents' output contracts are their fenced json blocks: a model copies
# the shape it is shown. The reviewer's output-format block once wrote its
# allowed values as "a" | "b" unions inside the fence, which is not JSON, and
# nothing caught it because no test parsed the agents' fences. This script:
#   1. parses every ```json fence in agents/requirements-reviewer.md and
#      agents/requirements-decomposer.md with json.loads (never eval), and
#      requires at least one fence per file so an empty match cannot pass;
#   2. proves the checker fails on a planted "a" | "b" union;
#   3. proves a markdown file with no json fence passes rather than erroring.
#
# lib/run_smoke_test.sh runs this script as one of its stages.
#
# Run:
#   ./lib/test-agent-json.sh
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
fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; }

# check_fences <file> <min-fences>
# Prints "<n> fences parsed" on success; on failure prints the first bad
# block's number and the parser error, and exits non-zero. The fence text is
# only ever handed to json.loads.
check_fences() {
  python3 - "$1" "$2" <<'PY'
import json, re, sys
path, minimum = sys.argv[1], int(sys.argv[2])
text = open(path, encoding="utf-8").read()
# Any opener a renderer treats as json: case-insensitive, trailing blanks, CRLF.
blocks = re.findall(r"^```json[ \t]*\r?\n(.*?)^```", text, re.S | re.M | re.I)
if len(blocks) < minimum:
    sys.exit(f"found {len(blocks)} json fence(s), expected at least {minimum}")
for n, block in enumerate(blocks, 1):
    try:
        json.loads(block)
    except ValueError as exc:
        sys.exit(f"block {n}: {exc}")
print(f"{len(blocks)} fences parsed")
PY
}

# --- 1. the shipped agent prompts ------------------------------------------

for agent in requirements-reviewer requirements-decomposer; do
  file="${PLUGIN_ROOT}/agents/${agent}.md"
  if out="$(check_fences "$file" 1 2>&1)"; then
    pass "agents/${agent}.md: every json fence parses (${out})"
  else
    fail "agents/${agent}.md: a json fence does not parse" "$out"
  fi
done

# --- 2. mutation: a planted union must fail --------------------------------

planted="${TMP}/planted.md"
sed 's/"verdict": "issues_found"/"verdict": "approved" | "issues_found"/' \
  "${PLUGIN_ROOT}/agents/requirements-reviewer.md" > "$planted"
if ! grep -qF '"approved" | "issues_found"' "$planted"; then
  fail "mutation: could not plant a union (the reviewer template changed shape)" ""
elif check_fences "$planted" 1 > /dev/null 2>&1; then
  fail "mutation: a planted \"a\" | \"b\" union was not caught" ""
else
  pass "mutation: a planted \"a\" | \"b\" union makes the check fail"
fi

# --- 3. a file with no json fence passes -----------------------------------

nofence="${TMP}/nofence.md"
printf '# Notes\n\nNo fenced blocks here.\n\n```bash\necho hi\n```\n' > "$nofence"
if out="$(check_fences "$nofence" 0 2>&1)"; then
  pass "no-fence file passes (${out})"
else
  fail "no-fence file should pass" "$out"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
