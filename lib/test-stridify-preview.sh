#!/usr/bin/env bash
# Tests for the /stride-ideation:stridify Step 8.5 preview-and-approval gate
# and the Step 1 --yes / --auto-approve bypass documented in
# commands/stridify.md (W1140). The AskUserQuestion tool is only available
# inside a live Claude Code session, so this test embeds a reference shell
# implementation of the documented flag parse + preview render + gate and
# exercises it against a fixture batch JSON. The human approve/decline answer
# is injected as a parameter (standing in for the AskUserQuestion result).
#
# The reference implementations below MUST stay consistent with Step 1 and
# Step 8.5 in stridify.md. If you edit one, edit both — this test exists to
# prevent the doc and the on-the-wire behavior from drifting apart.
#
# Run:
#   ./lib/test-stridify-preview.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

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

# --- reference --yes / --auto-approve parser -------------------------------
#
# Mirrors stridify.md Step 1. --yes and --auto-approve are bare boolean
# tokens (no value form). Prints two lines: line 1 = AUTO_APPROVE (0|1),
# line 2 = the trimmed remaining arguments.

parse_yes_flag() {
  local args="$1"
  local yes=0
  local out=""
  # word-split the argument string into tokens (shellcheck SC2206 expected)
  # shellcheck disable=SC2206
  local toks=( $args )
  local t
  for t in "${toks[@]}"; do
    case "$t" in
      --yes|--auto-approve) yes=1 ;;
      *) out="${out:+$out }$t" ;;
    esac
  done
  printf '%s\n%s\n' "$yes" "$out"
}

# --- reference preview render ----------------------------------------------
#
# Mirrors stridify.md Step 8.5a. Reads ONLY the on-disk batch JSON (no auth
# material) and prints the goal/task tree + cross-goal claim order.

render_preview() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    data = json.load(fp)

goals = data.get("goals", [])
notes = data.get("decomposition_notes", "")

print()
print("Goals and tasks to be created:")
print()
for goal in goals:
    title = goal.get("title", "(no title)")
    tasks = goal.get("tasks", []) or []
    n = len(tasks)
    print(f"  Goal: {title}  ({n} task{'s' if n != 1 else ''})")
    for task in tasks:
        print(f"    - {task.get('title', '(no title)')}")
print()
if notes:
    print("Cross-goal claim order:")
    print(f"  {notes}")
    print()
PY
}

# --- POST stub + sentinel: confirm whether POST is reached ------------------
#
# The real Step 9 POST is never called in this test. post_stub stands in for
# "control reached the POST"; it writes a sentinel file the assertions check.

post_stub() { echo "POST_ATTEMPTED" > "$TMP/post_was_attempted"; }
post_was_attempted() { [ -f "$TMP/post_was_attempted" ]; }
reset_post_sentinel() { rm -f "$TMP/post_was_attempted"; }

# --- reference preview + gate ----------------------------------------------
#
# Mirrors stridify.md Step 8.5 a/b/c. Args:
#   <batch-path> <auto-approve:0|1> <answer:approve|decline>
# Always renders the preview. On bypass (auto=1) or an explicit approve, it
# calls post_stub (proceed to Step 9). On decline it prints the clean-stop
# message and returns 10 WITHOUT touching the on-disk JSON or calling POST.

render_and_gate() {
  local batch="$1" auto="$2" answer="$3"
  render_preview "$batch"
  if [ "$auto" = "1" ]; then
    post_stub        # 8.5b bypass: straight to Step 9
    return 0
  fi
  case "$answer" in
    approve)
      post_stub      # 8.5c approval: proceed to Step 9
      return 0
      ;;
    *)
      # 8.5c decline: clean stop, no POST, JSON untouched. Real impl exit 0.
      echo "stride-ideation: declined. The batch JSON is on disk at $batch"
      echo "(committed in git) for a later manual ship. No POST was attempted."
      return 10
      ;;
  esac
}

# === fixture: a multi-goal batch JSON with cross-goal claim order ==========

BATCH="$TMP/2026-05-12T120000-fixture-stride-batch.json"
cat > "$BATCH" <<'EOF'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "decomposition_notes": "Claim Goal A (data layer) first; Goal B (UI) depends on A's API surface.",
  "goals": [
    {
      "title": "Goal A — data layer",
      "type": "goal",
      "tasks": [
        { "title": "Create the schema migration" },
        { "title": "Add the context module" }
      ]
    },
    {
      "title": "Goal B — UI layer",
      "type": "goal",
      "tasks": [
        { "title": "Wire the LiveView" }
      ]
    }
  ]
}
EOF

BATCH_SHA_BEFORE="$(shasum -a 256 "$BATCH" | awk '{print $1}')"

# === case 1: --yes / --auto-approve parse (both forms + absence) ===========

y_yes="$(parse_yes_flag "--yes /path/to/doc.md")"
y_auto="$(parse_yes_flag "--auto-approve /path/to/doc.md")"
y_none="$(parse_yes_flag "/path/to/doc.md")"

if [ "$(printf '%s' "$y_yes" | sed -n 1p)" = "1" ] \
   && [ "$(printf '%s' "$y_auto" | sed -n 1p)" = "1" ] \
   && [ "$(printf '%s' "$y_none" | sed -n 1p)" = "0" ]; then
  pass "case 1: --yes and --auto-approve set bypass=1; absence leaves bypass=0 (AC3)"
else
  fail "case 1: bypass flag parse wrong" \
    "yes=$(printf '%s' "$y_yes" | sed -n 1p) auto=$(printf '%s' "$y_auto" | sed -n 1p) none=$(printf '%s' "$y_none" | sed -n 1p)"
fi

if [ "$(printf '%s' "$y_yes" | sed -n 2p)" = "/path/to/doc.md" ] \
   && [ "$(printf '%s' "$y_none" | sed -n 2p)" = "/path/to/doc.md" ]; then
  pass "case 1: the flag token is consumed and REQUIREMENTS_PATH remainder is preserved"
else
  fail "case 1: remainder wrong after flag consumption" \
    "yes_rem=$(printf '%s' "$y_yes" | sed -n 2p) none_rem=$(printf '%s' "$y_none" | sed -n 2p)"
fi

# === case 2: bypass path reaches POST without an approval prompt (AC3) ======

reset_post_sentinel
render_and_gate "$BATCH" 1 "" >"$TMP/run_bypass.log" 2>&1
rc_bypass=$?
if [ "$rc_bypass" -eq 0 ] && post_was_attempted; then
  pass "case 2: --yes bypass proceeds to POST (sentinel set, rc 0)"
else
  fail "case 2: bypass did not reach POST" "rc=$rc_bypass"
fi
if ! grep -qiF "declined" "$TMP/run_bypass.log"; then
  pass "case 2: bypass path prints no decline / prompt text"
else
  fail "case 2: bypass path unexpectedly printed decline text"
fi

# === case 3: decline path does NOT POST and leaves JSON on disk (AC2/AC4) ===

reset_post_sentinel
render_and_gate "$BATCH" 0 decline >"$TMP/run_decline.log" 2>&1
rc_decline=$?
if [ "$rc_decline" -eq 10 ] && ! post_was_attempted; then
  pass "case 3: decline does NOT attempt the POST (no sentinel)"
else
  fail "case 3: decline attempted the POST (regression)" "rc=$rc_decline"
fi
if [ -f "$BATCH" ]; then
  pass "case 3: declined batch JSON remains on disk"
else
  fail "case 3: declined batch JSON was removed (regression)"
fi
BATCH_SHA_AFTER="$(shasum -a 256 "$BATCH" | awk '{print $1}')"
if [ "$BATCH_SHA_BEFORE" = "$BATCH_SHA_AFTER" ]; then
  pass "case 3: declined batch JSON is byte-for-byte unchanged (recovery artifact preserved)"
else
  fail "case 3: declined batch JSON was rewritten (pitfall violated)"
fi
if grep -qF "No POST was attempted" "$TMP/run_decline.log"; then
  pass "case 3: decline message states the POST was not attempted"
else
  fail "case 3: decline message missing 'No POST was attempted'"
fi

# === case 4: approve path proceeds to POST (AC2) ===========================

reset_post_sentinel
render_and_gate "$BATCH" 0 approve >"$TMP/run_approve.log" 2>&1
rc_approve=$?
if [ "$rc_approve" -eq 0 ] && post_was_attempted; then
  pass "case 4: explicit approval proceeds to POST (sentinel set, rc 0)"
else
  fail "case 4: approval did not reach POST" "rc=$rc_approve"
fi

# === case 5: render lists every goal and its task count (AC1) ==============

render_preview "$BATCH" > "$TMP/preview.txt" 2>&1
if grep -qF "Goal: Goal A — data layer  (2 tasks)" "$TMP/preview.txt" \
   && grep -qF "Goal: Goal B — UI layer  (1 task)" "$TMP/preview.txt"; then
  pass "case 5: preview lists each goal with its task count (singular/plural correct)"
else
  fail "case 5: goal/task-count render wrong" "$(cat "$TMP/preview.txt")"
fi
if grep -qF -- "- Create the schema migration" "$TMP/preview.txt" \
   && grep -qF -- "- Add the context module" "$TMP/preview.txt" \
   && grep -qF -- "- Wire the LiveView" "$TMP/preview.txt"; then
  pass "case 5: preview lists every task title"
else
  fail "case 5: task titles missing from render" "$(cat "$TMP/preview.txt")"
fi

# === case 6: render shows cross-goal claim order from decomposition_notes (AC1) ===

if grep -qF "Cross-goal claim order:" "$TMP/preview.txt" \
   && grep -qF "Claim Goal A (data layer) first" "$TMP/preview.txt"; then
  pass "case 6: preview shows cross-goal claim order from decomposition_notes"
else
  fail "case 6: cross-goal claim order missing from render" "$(cat "$TMP/preview.txt")"
fi

# === case 7: --goal scoped (single-goal) batch renders the one goal ========

SINGLE="$TMP/2026-05-12T120000-fixture-kanban-app-stride-batch.json"
cat > "$SINGLE" <<'EOF'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
  "decomposition_notes": "Single-goal shape, no cross-goal coordination.",
  "goals": [
    {
      "title": "Kanban app — review queue",
      "type": "goal",
      "tasks": [
        { "title": "Add the review column" }
      ]
    }
  ]
}
EOF
render_preview "$SINGLE" > "$TMP/preview_single.txt" 2>&1
if grep -qF "Goal: Kanban app — review queue  (1 task)" "$TMP/preview_single.txt" \
   && [ "$(grep -cF 'Goal: ' "$TMP/preview_single.txt")" = "1" ]; then
  pass "case 7: --goal scoped batch renders exactly the single scoped goal"
else
  fail "case 7: single-goal render wrong" "$(cat "$TMP/preview_single.txt")"
fi

# === case 8: pitfall — no token / auth material in any gate output =========

if grep -qE 'stride_(dev|prod)_|Bearer |Authorization:' \
     "$TMP/preview.txt" "$TMP/run_bypass.log" "$TMP/run_decline.log" "$TMP/run_approve.log"; then
  fail "case 8: gate output contains potential auth material (pitfall violated)"
else
  pass "case 8: no Bearer/token/Authorization strings in preview or gate output (pitfall avoided)"
fi

# === cases 9-14: --batch mode (W2189) ======================================
#
# Mirrors stridify.md Step 1's --batch parse and its two rejections, then runs
# the REAL Step 1b and Step 9 fragments (extracted from stridify.md with the
# plugin-root token substituted, as Claude Code does) against a PATH-stubbed
# curl, so the validate-then-ship path is the shipped one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STRIDIFY="${PLUGIN_ROOT}/commands/stridify.md"

# parse_batch_flag "<args>" — prints BATCH_ARG, GOAL_ARG and the remainder on
# three lines, or "ERROR: <message>" for the two documented rejections.
parse_batch_flag() {
  # shellcheck disable=SC2206
  local toks=( $1 ) batch="" batch_given=0 goal="" rest="" i=0
  while [ "$i" -lt "${#toks[@]}" ]; do
    case "${toks[$i]}" in
      --batch) batch_given=1
               case "${toks[$(( i + 1 ))]:-}" in --*) ;; *) i=$(( i + 1 )); batch="${toks[$i]:-}" ;; esac ;;
      --batch=*) batch_given=1; batch="${toks[$i]#--batch=}" ;;
      --goal) i=$(( i + 1 )); goal="${toks[$i]:-}" ;;
      --goal=*) goal="${toks[$i]#--goal=}" ;;
      --yes|--auto-approve) ;;
      *) rest="${rest:+$rest }${toks[$i]}" ;;
    esac
    i=$(( i + 1 ))
  done
  if [ "$batch_given" = 1 ] && [ -z "$batch" ]; then
    echo "ERROR: Usage: /stride-ideation:stridify --batch <path-to-stride-batch.json> [--yes]"
  elif [ -n "$batch" ] && [ -n "$goal" ]; then
    echo "ERROR: stride-ideation: --batch ships an existing batch as-is and cannot be combined with --goal"
  elif [ -n "$batch" ] && [ -n "$rest" ]; then
    echo "ERROR: stride-ideation: --batch takes a batch JSON, not a requirements doc"
  else
    printf '%s\n%s\n%s\n' "$batch" "$goal" "$rest"
  fi
}

if [ "$(parse_batch_flag '--batch docs/a-stride-batch.json --yes' | head -n 1)" = "docs/a-stride-batch.json" ] \
   && [ "$(parse_batch_flag '--batch=docs/x=y-stride-batch.json' | head -n 1)" = "docs/x=y-stride-batch.json" ]; then
  pass "case 9: --batch parses in both shapes (split on the first '=' only)"
else
  fail "case 9: --batch parse" "$(parse_batch_flag '--batch=docs/x=y-stride-batch.json')"
fi
if parse_batch_flag '--batch b.json --goal 2' | grep -q '^ERROR: .*cannot be combined with --goal'; then
  pass "case 10: --batch with --goal is rejected with a clear error"
else
  fail "case 10: --batch + --goal not rejected"
fi
if parse_batch_flag '--batch' | grep -q '^ERROR: Usage' && parse_batch_flag '--batch=' | grep -q '^ERROR: Usage' \
   && parse_batch_flag '--batch --yes' | grep -q '^ERROR: Usage'; then
  pass "case 10c: --batch with no value prints the usage line"
else
  fail "case 10c: bare --batch"
fi
if parse_batch_flag '--batch b.json docs/x-requirements.md' | grep -q '^ERROR: .*not a requirements doc'; then
  pass "case 10b: --batch with a requirements-doc path is rejected"
else
  fail "case 10b: --batch + doc path not rejected"
fi

# Extract the real fragments.
extract_step() {  # extract_step <heading prefix> <n> <out>
  python3 - "$STRIDIFY" "$1" "$2" "$3" "$PLUGIN_ROOT" <<'PY'
import re, sys
src, prefix, n, out, root = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
text = open(src).read().replace("${" + "CLAUDE_PLUGIN_ROOT" + "}", root)
lines, heading, seen, i = text.split("\n"), "", 0, 0
while i < len(lines):
    if lines[i].startswith("### "):
        heading = lines[i][4:]
    m = re.match(r"^(\s*)```bash\s*$", lines[i])
    if m and heading.startswith(prefix + ":"):
        ind, body, i = len(m.group(1)), [], i + 1
        while not re.match(r"^\s*```\s*$", lines[i]):
            body.append(lines[i][ind:] if lines[i][:ind].strip() == "" else lines[i])
            i += 1
        seen += 1
        if seen == n:
            open(out, "w").write("\n".join(body) + "\n")
            sys.exit(0)
    i += 1
sys.exit("block not found: " + prefix)
PY
}
extract_step "Step 1b" 1 "$TMP/step1b.sh"
extract_step "Step 9" 1 "$TMP/step9.sh"
extract_step "Step 8.5" 2 "$TMP/step85c.sh"

# Fake curl: records that it ran and answers 201 with a created batch.
mkdir -p "$TMP/bin"
cat > "$TMP/created.json" <<'EOF'
{"success": true, "total": 1, "goals": [{"goal": {"identifier": "G42", "title": "Kanban app"}, "child_tasks": [{"identifier": "W420", "title": "Add queue"}]}]}
EOF
cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
out=""
while [ "\$#" -gt 0 ]; do [ "\$1" = "-o" ] && out="\$2"; shift; done
cat > /dev/null
: > "$TMP/curl.ran"
cp "$TMP/created.json" "\$out"
printf '201'
EOF
chmod +x "$TMP/bin/curl"
printf -- '- **API URL:** `https://stride.example`\n- **API Token:** `stride_dev_PREVIEW_TEST_TOKEN`\n' > "$TMP/auth.md"

# run_frag <fragment> <batch path> — fresh bash, BATCH_PATH as a literal.
run_frag() {
  rm -f "$TMP/curl.ran"
  { printf "BATCH_PATH='%s'\n" "$2"; cat "$1"; } > "$TMP/frag.sh"
  PATH="$TMP/bin:$PATH" STRIDE_AUTH_FILE="$TMP/auth.md" bash "$TMP/frag.sh" > "$TMP/frag.out" 2> "$TMP/frag.err"
  FRC=$?
  cat "$TMP/frag.out" "$TMP/frag.err" >> "$TMP/all-batch-output.txt"
}

REAL_BATCH="${PLUGIN_ROOT}/fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json"
cp "$REAL_BATCH" "$TMP/ship-me.json"
SHA_BEFORE="$(shasum -a 256 "$TMP/ship-me.json" | cut -d' ' -f1)"
run_frag "$TMP/step1b.sh" "$TMP/ship-me.json"
if [ "$FRC" -eq 0 ] && grep -q 'creates every goal and task a second time' "$TMP/frag.err" && [ ! -e "$TMP/curl.ran" ]; then
  pass "case 11: Step 1b validates a valid batch, warns about duplicate shipping, and sends nothing"
else
  fail "case 11: Step 1b on a valid batch" "rc=$FRC err=$(cat "$TMP/frag.err")"
fi
run_frag "$TMP/step9.sh" "$TMP/ship-me.json"
if [ "$FRC" -eq 0 ] && [ -e "$TMP/curl.ran" ] && grep -q 'G42' "$TMP/frag.out" && grep -q 'W420' "$TMP/frag.out"; then
  pass "case 12: Step 9 ships the --batch file through lib/ship.sh and renders the identifiers"
else
  fail "case 12: Step 9 ship" "rc=$FRC out=$(cat "$TMP/frag.out") err=$(cat "$TMP/frag.err")"
fi
if [ "$(shasum -a 256 "$TMP/ship-me.json" | cut -d' ' -f1)" = "$SHA_BEFORE" ]; then
  pass "case 12b: the --batch file is never rewritten or re-stamped"
else
  fail "case 12b: --batch file changed"
fi

printf '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "t", "type": "goal"}]}]}\n' > "$TMP/invalid.json"
run_frag "$TMP/step1b.sh" "$TMP/invalid.json"
if [ "$FRC" -eq 1 ] && grep -q "must be 'work' or 'defect'" "$TMP/frag.err" && [ ! -e "$TMP/curl.ran" ]; then
  pass "case 13: an invalid batch fails validation before any POST"
else
  fail "case 13: invalid batch" "rc=$FRC err=$(cat "$TMP/frag.err")"
fi
run_frag "$TMP/step1b.sh" "$TMP/no-such-batch.json"
if [ "$FRC" -eq 1 ] && grep -q 'batch JSON not found' "$TMP/frag.err"; then
  pass "case 13b: a batch path that does not exist stops with a clear error"
else
  fail "case 13b: missing batch path" "rc=$FRC err=$(cat "$TMP/frag.err")"
fi

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [d.pop(k,None) for k in ("source_spec","source_spec_sha256","decomposition_notes")]; json.dump(d,open(sys.argv[2],"w"))' "$REAL_BATCH" "$TMP/unstamped.json"
run_frag "$TMP/step1b.sh" "$TMP/unstamped.json"
if [ "$FRC" -eq 0 ]; then
  pass "case 14: a batch without the local audit fields still validates"
else
  fail "case 14: unstamped batch" "$(cat "$TMP/frag.err")"
fi

run_frag "$TMP/step85c.sh" "$TMP/ship-me.json"
if [ "$FRC" -eq 0 ] && grep -qF -- "/stride-ideation:stridify --batch \"$TMP/ship-me.json\"" "$TMP/frag.err" && [ ! -e "$TMP/curl.ran" ]; then
  pass "case 14b: the decline message names the --batch command and sends nothing"
else
  fail "case 14b: decline message" "$(cat "$TMP/frag.err")"
fi
if grep -qE 'stride_dev_PREVIEW_TEST_TOKEN|Bearer ' "$TMP/all-batch-output.txt"; then
  fail "case 14c: --batch output contains auth material"
else
  pass "case 14c: no token or Bearer string in any --batch fragment's output (Step 1b, Step 9 ship, decline)"
fi

run_frag "$TMP/step1b.sh" "-x-stride-batch.json"
if [ "$FRC" -eq 1 ] && grep -q "starts with '-'" "$TMP/frag.err" && [ ! -e "$TMP/curl.ran" ]; then
  pass "case 14d: a batch path starting with '-' is refused before anything runs"
else
  fail "case 14d: dash path" "rc=$FRC err=$(cat "$TMP/frag.err")"
fi

# === summary ==============================================================

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
