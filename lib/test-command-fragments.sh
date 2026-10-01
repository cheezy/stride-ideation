#!/usr/bin/env bash
# Tests that every ```bash fragment in commands/ideate.md and
# commands/stridify.md is self-contained: each Bash tool call is a fresh
# shell, so a fragment must source the helper it uses itself, read only the
# values it declares on its "# Carried forward:" line, and reach bundled
# scripts through the plugin-root token Claude Code substitutes when it loads
# the command.
#
# Static checks run over every fenced bash block (indented ones included).
# Dynamic checks then run the fragments in order, each in a brand-new bash
# process, with inputs supplied ONLY as single-quoted literal assignments
# built from the "carry: NAME=value" lines earlier fragments printed — the
# same contract the commands give the model. Fragments that reach the network
# (lib/ship.sh in /stridify Steps 3 and 9) are checked statically and for the
# unset-root guard only.
#
# Run:
#   ./lib/test-command-fragments.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IDEATE="${PLUGIN_ROOT}/commands/ideate.md"
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

pass() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  %s\n' "$1"
  if [ "${2:-}" != "" ]; then
    printf '      %s\n' "$2"
  fi
}

# --- static checks -------------------------------------------------------------

# One python pass over both commands; it prints PASS/FAIL lines we tally.
python3 - "$PLUGIN_ROOT" > "$TMP/static.out" <<'PY'
import os, re, sys

root = sys.argv[1]
TOKEN = "${" + "CLAUDE_PLUGIN_ROOT" + "}"
GUARD = '[ -n "' + TOKEN + '" ] || {'
PLACEHOLDER = "<" + "plugin-root" + ">"

helpers = {}
for helper in ("filename.sh", "draft.sh"):
    for line in open(os.path.join(root, "lib", helper)):
        m = re.match(r"^(sti_[a-z_]+)\(\)", line)
        if m:
            helpers[m.group(1)] = helper

EXTERNALS = ("mkdir", "mktemp", "rm", "cat", "tr", "sleep", "grep", "awk", "sed",
             "cut", "basename", "dirname", "shasum", "sha256sum", "git",
             "python3", "bash", "date", "curl")
CMD_POS = r"(?:^|[|;(!]|&&|\|\||\$\(|\bthen\b|\bif\b|\bdo\b|\belse\b)\s*"


def result(ok, label, detail=""):
    print(("PASS  " if ok else "FAIL  ") + label + ("" if ok or not detail else "\n      " + detail))


def blocks(text):
    lines = text.split("\n")
    heading, out, i = "", [], 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("### "):
            heading = line[4:].split(":")[0]
        m = re.match(r"^(\s*)```bash\s*$", line)
        if m:
            indent, body, i = len(m.group(1)), [], i + 1
            while not re.match(r"^\s*```\s*$", lines[i]):
                body.append(lines[i][indent:] if lines[i][:indent].strip() == "" else lines[i])
                i += 1
            out.append((heading, body))
        i += 1
    return out


def code_lines(body):
    # Lines that are shell, not comments and not heredoc payload.
    code, delim = [], None
    for line in body:
        if delim:
            if line.strip() == delim:
                delim = None
            continue
        m = re.search(r"<<-?'([A-Z_]+)'", line)
        if m:
            delim = m.group(1)
        if line.lstrip().startswith("#"):
            continue
        code.append(line)
    return code


for name in ("ideate.md", "stridify.md"):
    path = os.path.join(root, "commands", name)
    text = open(path).read()
    front = text.split("---")[1]
    allowed = re.search(r"^allowed-tools:(.*)$", front, re.M).group(1)

    result(PLACEHOLDER not in text, f"{name}: no {PLACEHOLDER} placeholder remains")
    result(text.count("**Every Bash tool call is a fresh shell.**") == 1,
           f"{name}: states once that every Bash call is a fresh shell")
    result("curl" not in allowed, f"{name}: allowed-tools grants no curl")
    broad = [c for c in ("rm", "cat", "mktemp") if f"Bash({c}:*)" in allowed]
    result(not broad, f"{name}: allowed-tools grants no rm, cat or mktemp", ", ".join(broad))

    stray = [ln for ln in text.split("\n") if TOKEN in ln
             and not all(seg.startswith("/lib/") or seg.startswith('" ] || {')
                         for seg in ln.split(TOKEN)[1:])]
    result(not stray, f"{name}: the plugin-root token appears only in lib paths and the guard",
           "; ".join(s.strip()[:80] for s in stray))

    # Commands the prose tells the model to run inline (`mkdir -p ...`) need
    # allowed-tools entries too. curl is excluded: it is named only as what
    # not to do, and the no-curl check above covers it. "no `cmd`" is prose
    # saying the command is NOT needed.
    inline = sorted({m.group(1) for m in re.finditer(r"(?<!no )`(" + "|".join(EXTERNALS) + r")\s[^`]*`", text)
                     if m.group(1) != "curl"})
    missing_inline = [w for w in inline if f"Bash({w}:*)" not in allowed]
    result(not missing_inline, f"{name}: allowed-tools lists every command the prose runs inline", ", ".join(missing_inline))

    for n, (heading, body) in enumerate(blocks(text), 1):
        label = f"{name} {heading} (block {n})"
        code = code_lines(body)
        joined = "\n".join(code)

        # (1) every sti_* call has its own helper sourced earlier in the block
        missing = []
        for idx, line in enumerate(code):
            for fn in re.findall(r"\b(sti_[a-z_]+)\b", line):
                want = '. "' + TOKEN + "/lib/" + helpers.get(fn, "?") + '"'
                if not any(want in prev for prev in code[:idx]):
                    missing.append(fn)
        result(not missing, f"{label}: sources the helper for every sti_* call", ", ".join(sorted(set(missing))))

        # (2) the unset-root guard precedes the first use of the token
        uses = [i for i, ln in enumerate(code) if TOKEN + "/lib/" in ln]
        if uses:
            guards = [i for i, ln in enumerate(code) if GUARD in ln]
            result(bool(guards) and guards[0] < uses[0], f"{label}: guards an unset plugin root before using it")

        # (3) every variable read is assigned here or declared as carried forward
        carried = set(re.findall(r'^: "\$\{([A-Z_][A-Z0-9_]*)\??:?\?', joined, re.M))
        decl = re.search(r"^#\s*Carried forward:(.*)$", "\n".join(body), re.M)
        declared = set(re.findall(r"\b([A-Z][A-Z0-9_]+)\b", decl.group(1))) if decl else set()
        assigned = set(re.findall(r"\b([A-Z_][A-Z0-9_]*)=", joined))
        for ln in code:
            m = re.search(r"\bread\b(.*)", ln)
            if m:
                assigned |= set(re.findall(r"\b([A-Z_][A-Z0-9_]*)\b", m.group(1).split("<<")[0]))
        reads = set(re.findall(r"\$\{?([A-Z_][A-Z0-9_]*)", joined)) - {"CLAUDE_PLUGIN_ROOT", "IFS"}
        unknown = sorted(reads - assigned - carried)
        result(not unknown, f"{label}: reads only values it assigns or declares as carried forward", ", ".join(unknown))
        undeclared = sorted(carried - declared)
        result(not undeclared, f"{label}: every guarded input is named on its Carried forward line", ", ".join(undeclared))

        # (4) every external command it runs is in allowed-tools
        used = sorted({w for w in EXTERNALS for ln in code if re.search(CMD_POS + re.escape(w) + r"\b", ln)})
        not_allowed = [w for w in used if f"Bash({w}:*)" not in allowed]
        result(not not_allowed, f"{label}: allowed-tools lists every command it runs", ", ".join(not_allowed))
PY
while IFS= read -r line; do
  case "$line" in
    "PASS  "*) PASS=$(( PASS + 1 )); printf '%s\n' "$line" ;;
    "FAIL  "*) FAIL=$(( FAIL + 1 )); printf '%s\n' "$line" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$TMP/static.out"

# --- dynamic checks: fixtures ------------------------------------------------------

# An installed-plugin copy at a path with a space, and a scratch git repo
# (also with a space) to run the fragments in.
PLUG="$TMP/plug in"
REPO="$TMP/repo dir"
mkdir -p "$PLUG" "$REPO/my docs"
cp -R "${PLUGIN_ROOT}/lib" "$PLUG/lib"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
git -C "$REPO" init -q
git -C "$REPO" commit -q --allow-empty -m init

REQ_REL="my docs/2026-05-12T103000-seven-surfaces-requirements.md"
cat > "$REPO/$REQ_REL" <<'EOF'
# Seven surfaces

## Problem
p

## Decomposition seams

1. **Kanban app** — owns the contract
2. **stride plugin** — adapter
3. **stride-copilot** — port
EOF
git -C "$REPO" add "$REQ_REL"
git -C "$REPO" commit -q -m req

# extract <command.md> <substitute-root|""> <outdir> — one file per bash
# block, named <Step_key>-<n>.sh, with the plugin-root token replaced the way
# Claude Code replaces it (or left alone when the substitute is empty).
extract() {
  mkdir -p "$3"
  python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
src, sub, out = sys.argv[1:4]
text = open(src).read()
if sub:
    text = text.replace("${" + "CLAUDE_PLUGIN_ROOT" + "}", sub)
lines, heading, counts, i = text.split("\n"), "", {}, 0
while i < len(lines):
    line = lines[i]
    if line.startswith("### "):
        heading = line[4:].split(":")[0].replace(" ", "_")
    m = re.match(r"^(\s*)```bash\s*$", line)
    if m:
        indent, body, i = len(m.group(1)), [], i + 1
        while not re.match(r"^\s*```\s*$", lines[i]):
            body.append(lines[i][indent:] if lines[i][:indent].strip() == "" else lines[i])
            i += 1
        counts[heading] = counts.get(heading, 0) + 1
        with open(os.path.join(out, f"{heading}-{counts[heading]}.sh"), "w") as fp:
            fp.write("\n".join(body) + "\n")
    i += 1
PY
}

extract "$STRIDIFY" "$PLUG" "$TMP/s"
extract "$IDEATE" "$PLUG" "$TMP/i"
extract "$STRIDIFY" "" "$TMP/s-raw"
extract "$IDEATE" "" "$TMP/i-raw"

# sq VALUE — the single-quoted literal the commands tell the model to write.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# run <block-file> [NAME VALUE]... — run one fragment in a brand-new bash in
# the scratch repo, inputs only as prepended literal assignments. Leaves
# $OUT, $ERR and $RC.
run() {
  local block="$1" script="$TMP/run.sh"
  shift
  : > "$script"
  while [ "$#" -gt 1 ]; do
    printf '%s=%s\n' "$1" "$(sq "$2")" >> "$script"
    shift 2
  done
  cat "$block" >> "$script"
  ( cd "$REPO" && env -u CLAUDE_PLUGIN_ROOT bash "$script" > "$TMP/out" 2> "$TMP/err" )
  RC=$?
  OUT="$(cat "$TMP/out")"
  ERR="$(cat "$TMP/err")"
}

carry() { printf '%s\n' "$OUT" | sed -n "s/^carry: $1=//p"; }

check() {
  local label="$1" want_rc="$2"
  if [ "$RC" -eq "$want_rc" ] && ! printf '%s' "$ERR" | grep -q 'command not found'; then
    pass "$label"
  else
    fail "$label" "rc=$RC (want $want_rc); stderr: $(printf '%s' "$ERR" | head -c 300)"
  fi
}

eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi; }

# --- dynamic: /stridify in order ---------------------------------------------------

S="$TMP/s"
run "$S/Step_2-1.sh" REQUIREMENTS_PATH "$REQ_REL" GOAL_ARG ''
check "stridify Step 2 advisory: runs in a fresh shell" 0

run "$S/Step_2b-1.sh" REQUIREMENTS_PATH "$REQ_REL" GOAL_ARG '2'
check "stridify Step 2b: resolves --goal in a fresh shell" 0
GOAL_INDEX="$(carry GOAL_INDEX)"; GOAL_SLUG="$(carry GOAL_SLUG)"
eq "stridify Step 2b: carries GOAL_INDEX and GOAL_SLUG" "$GOAL_INDEX|$GOAL_SLUG" "2|stride-plugin"

run "$S/Step_4-1.sh" REQUIREMENTS_PATH "$REQ_REL"
check "stridify Step 4: runs in a fresh shell" 0
SOURCE_TS="$(carry SOURCE_TS)"; SLUG="$(carry SLUG)"
eq "stridify Step 4: carries SOURCE_TS and SLUG" "$SOURCE_TS|$SLUG" "2026-05-12T103000|seven-surfaces"

run "$S/Step_5-1.sh" REQUIREMENTS_PATH "$REQ_REL" SOURCE_TS "$SOURCE_TS" SLUG "$SLUG" GOAL_SLUG "$GOAL_SLUG"
check "stridify Step 5: runs in a fresh shell" 0
SLUG_FOR_PATH="$(carry SLUG_FOR_PATH)"; TARGET_PATH="$(carry TARGET_PATH)"
eq "stridify Step 5: carries the per-goal target path" "$TARGET_PATH" "my docs/2026-05-12T103000-seven-surfaces-stride-plugin-stride-batch.json"

run "$S/Step_6-1.sh" REQUIREMENTS_PATH "$REQ_REL"
check "stridify Step 6 SHA: runs in a fresh shell" 0
eq "stridify Step 6 SHA: carries the lowercase SHA-256" "$(carry SOURCE_SHA)" \
  "$(shasum -a 256 "$REPO/$REQ_REL" | cut -d' ' -f1 | tr 'A-Z' 'a-z')"

run "$S/Step_6-2.sh" REQUIREMENTS_PATH "$REQ_REL"
check "stridify Step 6 source path: runs in a fresh shell" 0
eq "stridify Step 6 source path: carries the repo-relative SOURCE_SPEC" "$(carry SOURCE_SPEC)" "$REQ_REL"

run "$S/Step_7-1.sh" REQUIREMENTS_PATH "$REQ_REL" GOAL_INDEX "$GOAL_INDEX"
check "stridify Step 7e: scopes the doc in a fresh shell" 0
if printf '%s' "$OUT" | grep -q 'stride plugin' && ! printf '%s' "$OUT" | grep -q 'stride-copilot'; then
  pass "stridify Step 7e: prints the doc scoped to the chosen seam"
else
  fail "stridify Step 7e: scoped doc is wrong" "$(printf '%s' "$OUT" | tail -n 5)"
fi

run "$S/Step_7.5-1.sh" REQUIREMENTS_PATH "$REQ_REL" SOURCE_TS "$SOURCE_TS" SLUG_FOR_PATH "$SLUG_FOR_PATH"
check "stridify Step 7.5a: runs in a fresh shell" 0
eq "stridify Step 7.5a: carries the prompt path" "$(carry PROMPT_PATH)" "my docs/2026-05-12T103000-seven-surfaces-stride-plugin-decomposer-prompt.md"

# Step 8a validates the file the Write tool wrote under .stride/.
cp "${PLUGIN_ROOT}/fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json" "$TMP/good.json"
mkdir -p "$REPO/.stride"
cp "$TMP/good.json" "$REPO/.stride/stridify-subagent-output.json"
run "$S/Step_8-1.sh"
check "stridify Step 8a: validates the written JSON in a fresh shell" 0
printf '{"tasks": []}\n' > "$REPO/.stride/stridify-subagent-output.json"
run "$S/Step_8-1.sh"
check "stridify Step 8a: rejects a wrong-root batch (exit 1)" 1
if printf '%s' "$ERR" | grep -q 'wrong_root_key\|goals'; then
  pass "stridify Step 8a: the validator's message reaches stderr"
else
  fail "stridify Step 8a: validator message missing" "$ERR"
fi
# A line that would have closed the old heredoc is just bad JSON now.
printf 'STRIDE_BATCH_JSON\ntouch pwned-8a\n' > "$REPO/.stride/stridify-subagent-output.json"
run "$S/Step_8-1.sh"
check "stridify Step 8a: a crafted payload is only invalid JSON (exit 1)" 1
if [ ! -e "$REPO/pwned-8a" ]; then pass "stridify Step 8a: nothing in the payload runs"; else fail "stridify Step 8a: payload executed"; fi

run "$S/Step_8-2.sh" REQUIREMENTS_PATH "$REQ_REL" SOURCE_TS "$SOURCE_TS" SLUG_FOR_PATH "$SLUG_FOR_PATH"
check "stridify Step 8c: re-resolves the target in a fresh shell" 0
eq "stridify Step 8c: target is unchanged when untaken" "$(carry TARGET_PATH)" "$TARGET_PATH"

cp "$TMP/good.json" "$REPO/$TARGET_PATH"   # the Write tool's job
run "$S/Step_8-3.sh" TARGET_PATH "$TARGET_PATH" SLUG "$SLUG" GOAL_SLUG "$GOAL_SLUG"
check "stridify Step 8d: commits in a fresh shell" 0
BATCH_PATH="$(carry BATCH_PATH)"
eq "stridify Step 8d: carries BATCH_PATH" "$BATCH_PATH" "$TARGET_PATH"
eq "stridify Step 8d: commit names the goal" "$(git -C "$REPO" log -1 --format=%s)" "stride-ideation: decomposition for seven-surfaces goal stride-plugin"

run "$S/Step_8.5-1.sh" BATCH_PATH "$BATCH_PATH"
check "stridify Step 8.5a: renders the tree in a fresh shell" 0
run "$S/Step_8.5-2.sh" BATCH_PATH "$BATCH_PATH"
check "stridify Step 8.5c: decline exits 0" 0

# --- dynamic: /ideate in order ---------------------------------------------------

I="$TMP/i"
HOSTILE="Bob's \"idea\" \$(touch pwned) & co"
run "$I/Step_3-1.sh" CONTINUE_PATH '' TOPIC "$HOSTILE"
check "ideate Step 3: slugifies a hostile topic in a fresh shell" 0
ISLUG="$(carry SLUG)"
if [ -n "$ISLUG" ] && [ ! -e "$REPO/pwned" ]; then pass "ideate Step 3: the topic is data, nothing runs"; else fail "ideate Step 3: slug '$ISLUG' or pwned file"; fi

SESSION_TS=2026-06-01T090000
run "$I/Step_4-1.sh" SESSION_TS "$SESSION_TS" SLUG "$ISLUG"
check "ideate Step 4: computes the target in a fresh shell" 0
ITARGET="$(carry TARGET_PATH)"
eq "ideate Step 4: carries TARGET_PATH" "$ITARGET" "docs/ideation/$SESSION_TS-$ISLUG-requirements.md"

run "$I/Step_4-2.sh" CONTINUE_PATH "$ITARGET" TARGET_PATH "$ITARGET"
check "ideate Step 4 invariant: refuses to overwrite the source (exit 1)" 1
run "$I/Step_4-2.sh" CONTINUE_PATH '' TARGET_PATH "$ITARGET"
check "ideate Step 4 invariant: passes in a fresh session" 0

mkdir -p "$REPO/.stride"
printf 'old draft' > "$REPO/.stride/2026-05-01T000000-$ISLUG-draft.md"
run "$I/Step_4d-1.sh" SLUG "$ISLUG"
check "ideate Step 4d: finds a draft in a fresh shell" 0
EXISTING="$(carry EXISTING_DRAFT)"
eq "ideate Step 4d: carries the existing draft" "$EXISTING" ".stride/2026-05-01T000000-$ISLUG-draft.md"

run "$I/Step_4d-2.sh" SESSION_TS "$SESSION_TS" SLUG "$ISLUG" EXISTING_DRAFT "$EXISTING"
check "ideate Step 4d start-fresh: runs in a fresh shell" 0
DRAFT="$(carry DRAFT_PATH)"
eq "ideate Step 4d start-fresh: carries a fresh DRAFT_PATH" "$DRAFT" ".stride/$SESSION_TS-$ISLUG-draft.md"
if [ ! -e "$REPO/$EXISTING" ]; then pass "ideate Step 4d start-fresh: discards the abandoned draft"; else fail "ideate Step 4d start-fresh: abandoned draft still present"; fi

run "$I/Step_7-1.sh" SESSION_TS "$SESSION_TS" SLUG "$ISLUG"
check "ideate Step 7: re-resolves the target in a fresh shell" 0
eq "ideate Step 7: target unchanged when untaken" "$(carry TARGET_PATH)" "$ITARGET"

mkdir -p "$REPO/docs/ideation"
printf '# doc\n' > "$REPO/$ITARGET"          # the Write tool's job
printf 'draft' > "$REPO/$DRAFT"
run "$I/Step_9-1.sh" TARGET_PATH "$ITARGET" CONTINUE_PATH '' SLUG "$ISLUG" DRAFT_PATH "$DRAFT"
check "ideate Step 9: commits and clears the draft in a fresh shell" 0
if [ ! -e "$REPO/$DRAFT" ]; then pass "ideate Step 9: the autosave draft is removed"; else fail "ideate Step 9: draft still present"; fi

# --- edge cases ---------------------------------------------------------------------

run "$S/Step_4-1.sh"
check "a missing carried value stops the fragment (exit 1)" 1
if printf '%s' "$ERR" | grep -q 'REQUIREMENTS_PATH was not carried forward'; then
  pass "a missing carried value names itself"
else
  fail "a missing carried value: message" "$ERR"
fi

# Unsubstituted and with CLAUDE_PLUGIN_ROOT unset, every fragment that uses
# the plugin root must stop with the guard message before touching a path.
for f in "$TMP"/s-raw/*.sh "$TMP"/i-raw/*.sh; do
  grep -q 'CLAUDE_PLUGIN_ROOT}/lib/' "$f" || continue
  # Satisfy the carried-forward guards so the root guard is what trips.
  vars="$(sed -n 's/^: "\${\([A-Z_][A-Z0-9_]*\).*/\1/p' "$f")"
  set --
  for v in $vars; do set -- "$@" "$v" "x"; done
  run "$f" "$@"
  if [ "$RC" -eq 1 ] && printf '%s' "$ERR" | grep -q 'stride-ideation: CLAUDE_PLUGIN_ROOT is not set'; then
    pass "unset plugin root stops $(basename "$(dirname "$f")")/$(basename "$f")"
  else
    fail "unset plugin root does not stop $(basename "$(dirname "$f")")/$(basename "$f")" "rc=$RC; stderr: $(printf '%s' "$ERR" | head -c 200)"
  fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
