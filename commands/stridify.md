---
description: End-to-end pipeline from a stride-ideation requirements doc to created Stride goals. Validates the seven required sections, preflights auth, dispatches the requirements-decomposer subagent, stamps source_spec + source_spec_sha256, writes and commits a timestamped sibling batch JSON, then POSTs to the Stride API and renders the created G/W identifiers.
allowed-tools: Bash(date:*), Bash(git:*), Bash(. *:*), Bash(bash:*), Bash(shasum:*), Bash(sha256sum:*), Bash(awk:*), Bash(sed:*), Bash(basename:*), Bash(dirname:*), Bash(grep:*), Bash(test:*), Bash(curl:*), Bash(python3:*), Read, Write, Glob, Grep, Agent
argument-hint: "<path-to-requirements.md>"
---

# /stride-ideation:stridify

Read a stride-ideation requirements markdown document, decompose it into a Stride batch JSON (committed to disk for audit), and POST it to the Stride API in a single invocation. The decomposition logic — natural seams, sizing, multi-goal split rule, batch JSON shape — lives in `agents/requirements-decomposer.md`. This command is the surface: it parses `$ARGUMENTS`, validates the input, preflights auth, dispatches the subagent, stamps `source_spec` + `source_spec_sha256`, writes and commits the file, then strips local-audit fields, POSTs to `/api/tasks/batch`, and renders the created G/W identifiers.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse `$ARGUMENTS`

The user invoked you with `$ARGUMENTS`. Treat the value as a single path string:

- If `$ARGUMENTS` is empty, print *"Usage: `/stride-ideation:stridify <path-to-requirements.md>`"* and exit non-zero.
- Trim the value and set `REQUIREMENTS_PATH` to the trimmed string.

### Step 2: Validate the requirements doc

Before doing any expensive work, the command must confirm the input is a real, parseable requirements doc produced by (or compatible with) `/stride-ideation:ideate`. Run these checks in order; any failure prints a one-line error and exits non-zero:

1. **File exists and is a regular file.** Use `Read` or `Bash(test -f)` to confirm. If missing, print *"stride-ideation: requirements doc not found at `<REQUIREMENTS_PATH>`"* and stop.

2. **Filename family matches.** The path SHOULD end in `-requirements.md`. If it does not, warn but proceed — the slug-extraction step below may still succeed for paths produced by older versions of the plugin, and the section-validation pass below is the authoritative check anyway.

3. **All seven hard-gated sections are present.** Use `Grep` to verify that the file contains a level-2 heading for each of: `Problem`, `Goal`, `Outcome`, `Assumptions`, `Constraints`, `Non-goals`, `Success metrics`. Order is not enforced (the doc template orders Problem before Goal, but a hand-edited doc may differ). If any heading is missing, print:

   > *"stride-ideation: requirements doc is missing required section(s): `<list>`. Either re-run `/stride-ideation:ideate --continue <path>` to fill them in, or hand-edit the doc to include the missing sections."*

   And exit non-zero. Do NOT proceed with a partial doc — the decomposer subagent's output quality depends on every section being substantive.

### Step 3: Preflight auth from `.stride_auth.md`

Read auth BEFORE the expensive subagent dispatch so a misconfigured `.stride_auth.md` fails fast without first burning a decomposer pass and writing a batch JSON that can't be shipped. Locate `.stride_auth.md` (the convention is `$CLAUDE_PROJECT_DIR/.stride_auth.md` — the same file the Stride orchestrator reads). Invoke `lib/read_auth.py` and source its output:

```bash
AUTH_FILE="${CLAUDE_PROJECT_DIR:-$PWD}/.stride_auth.md"
if [ ! -f "$AUTH_FILE" ]; then
  echo "stride-ideation: .stride_auth.md not found at $AUTH_FILE" >&2
  exit 1
fi

# read_auth.py emits two STRIDE_API_URL= / STRIDE_API_TOKEN= lines.
# Source them, then unset the helper variable so the token isn't visible
# to subsequent `set` / `env` dumps inside the same shell.
AUTH_OUT="$(python3 "<plugin-root>/lib/read_auth.py" "$AUTH_FILE")" || {
  echo "stride-ideation: failed to read auth from $AUTH_FILE" >&2
  exit 1
}
eval "$AUTH_OUT"
unset AUTH_OUT
```

**Never log the token, ever, even in error paths.** This includes:
- Do NOT echo `$STRIDE_API_TOKEN` for diagnostics.
- Do NOT include the token in any error message the user sees.
- Do NOT pass the token on the command line of a process visible to `ps` — `curl -H "Authorization: Bearer $STRIDE_API_TOKEN"` is fine because curl reads the header value and does not expose it via `/proc/<pid>/cmdline` after parse.
- Do NOT save curl output that might echo the request headers back (`curl -v` dumps headers to stderr; never use `-v` here).

If `lib/read_auth.py` exits non-zero, surface its stderr (which is engineered to never contain the token value) and stop.

`$STRIDE_API_URL` and `$STRIDE_API_TOKEN` are now in the environment for use by the POST in Step 9. The token survives until Step 9 explicitly unsets it after the curl call.

### Step 4: Inherit the session timestamp and slug

Source `lib/filename.sh` and extract the inherited values from `REQUIREMENTS_PATH`:

```bash
. <plugin-root>/lib/filename.sh

SOURCE_TS="$(basename "$REQUIREMENTS_PATH" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6})-.*$/\1/')"
SLUG="$(sti_slug_from_path "$REQUIREMENTS_PATH" requirements)"
```

`SOURCE_TS` is **inherited** from the source path so the decomposition JSON pairs cleanly with its requirements doc by filename prefix. Do NOT generate a fresh timestamp — the design spec explicitly couples the two artifacts by shared prefix.

If `sti_slug_from_path` exits non-zero (the path does not match the `YYYY-MM-DDTHHMMSS-<slug>-requirements.md` format), surface the error verbatim and stop.

### Step 5: Compute the target path (don't write yet)

Use `sti_unique_path` to compute the sibling output path:

```bash
TARGET_PATH="$(sti_unique_path "$(dirname "$REQUIREMENTS_PATH")" "$SOURCE_TS" "$SLUG" stride-batch json)"
```

`stride-batch` is the artifact name (not `requirements`), so the helper produces a sibling file like `2026-05-12T103000-add-notifications-stride-batch.json` next to the requirements doc.

If a stride-batch file with the inherited timestamp + slug already exists (rare — happens when `/stridify` is rerun on the same input), `sti_unique_path` appends `-2`, `-3`, … so the prior batch is preserved. **The HARD INVARIANT 'never overwrite an existing file' applies here too.**

Do NOT create or touch `TARGET_PATH` yet. A pre-created empty file would leave a half-baked artifact if the subagent dispatch fails or is interrupted.

### Step 6: Compute the source SHA-256 and normalize the source path

Compute the SHA-256 of the requirements doc and capture it for the orchestrator-injected fields:

```bash
SOURCE_SHA="$(shasum -a 256 "$REQUIREMENTS_PATH" | awk '{print $1}' | tr 'A-Z' 'a-z')"
```

If `shasum` is unavailable on the host (rare on macOS / Linux), fall back to `sha256sum "$REQUIREMENTS_PATH" | awk '{print $1}' | tr 'A-Z' 'a-z'`. The resulting hex string MUST be **lowercase** so the on-disk audit field is a stable, canonical value.

**Normalize `REQUIREMENTS_PATH` to a stable form** so the stamped `source_spec` value is consistent across invocations from different working directories. Two acceptable forms:

```bash
# Preferred: relative to the git repo root.
REPO_ROOT="$(git rev-parse --show-toplevel)"
SOURCE_SPEC="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$REQUIREMENTS_PATH" "$REPO_ROOT")"

# Fallback when not in a git repo: absolute path.
if [ -z "$SOURCE_SPEC" ] || [ "$SOURCE_SPEC" = ".." ] || [[ "$SOURCE_SPEC" == ../* ]]; then
  SOURCE_SPEC="$(cd "$(dirname "$REQUIREMENTS_PATH")" && pwd)/$(basename "$REQUIREMENTS_PATH")"
fi
```

Do NOT use the raw `$REQUIREMENTS_PATH` as `SOURCE_SPEC` — it depends on the user's current working directory at invocation time and would make the on-disk audit field brittle for tools that read the JSON later.

### Step 7: Dispatch the `requirements-decomposer` subagent

Read the full content of the requirements doc and dispatch the subagent via the `Agent` tool:

```
Agent(
  subagent_type: "requirements-decomposer",
  prompt: <<the requirements doc text, fenced inside a "Requirements document:" block — the only input the subagent has access to>>
)
```

The subagent receives the requirements doc as its entire input (no codebase access, no Stride API access, no clarifying-question loop). Its prompt at `agents/requirements-decomposer.md` documents the decomposition methodology, the canonical batch JSON shape, and the output contract.

Wait for the subagent's response. The contract is: **a single fenced ```json document, no prose outside.** Extract the fenced JSON block. If the response contains anything outside the fence — narrative preamble, multiple JSON blocks, a markdown summary — strip the prose and use ONLY the fenced JSON content.

### Step 8: Validate output, stamp audit fields, write, and commit

Four sub-steps that together produce the on-disk audit artifact.

**(8a) Validate the subagent output.** Write the extracted JSON to a temporary file and run the structural validator at `lib/validate_batch.py`. The validator owns the canonical implementation of every check; the command body delegates and surfaces the validator's stderr verbatim on failure:

```bash
TMP_JSON="$(mktemp -t stride_stridify_validate.XXXXXX.json)"
printf '%s' "$RAW_SUBAGENT_JSON" > "$TMP_JSON"

if ! python3 "<plugin-root>/lib/validate_batch.py" "$TMP_JSON" 2>"$TMP_JSON.err"; then
  cat "$TMP_JSON.err" >&2
  rm -f "$TMP_JSON" "$TMP_JSON.err"
  exit 1
fi
rm -f "$TMP_JSON.err"
```

The validator enforces five named checks, in order:

| Check | Failure mode | Example error message |
|---|---|---|
| (a) `parse_error` | Input is not valid JSON | `JSON parse failed at line 3 col 7 (char 24): Expecting property name enclosed in double quotes` |
| (b) `wrong_root_key` | Root has `tasks` or any key other than `goals` | `root key 'tasks' is the most common batch-API mistake — Stride's POST /api/tasks/batch requires root key 'goals'` |
| (c) `empty_goals` | `goals` missing, not an array, or empty | `root.goals is an empty array — the decomposer returned no goals` |
| (d) `goal_missing_field` | A goal lacks `title`, `type`, or `tasks`, or a task is malformed | `goals[0] is missing required field 'title'` |
| (e) `bad_dependency_index` | A task's `dependencies[]` index is out of range, negative, or a forward / self reference | `goals[0].tasks[1].dependencies references index 5 but goal only has 2 tasks (valid indices 0..1)` |

A validation failure here is a **subagent regression** — the requirements-decomposer agent's contract guarantees a valid root-key=`goals` JSON. If you see one, the agent's prompt has drifted; surface the validator message verbatim and stop. The validator does NOT check per-task Stride-API field shapes — those are the decomposer agent's responsibility, and any slip-through surfaces as a verbatim 422 in Step 9.

After the validator returns zero, also confirm that `decomposition_notes` exists at the root. It is required by the subagent contract for documenting cross-goal claim ordering. If the key is missing, set it to an empty string before the next sub-step and emit a one-line warning — but do NOT fail; some single-goal decompositions legitimately have nothing cross-goal to document.

**(8b) Stamp source_spec and source_spec_sha256.** Inject the local-audit fields at the JSON root. The output JSON MUST have these exact root keys in this exact order (so a human reading the file sees the audit metadata at the top before the goal payload):

```json
{
  "source_spec": "<SOURCE_SPEC>",
  "source_spec_sha256": "<SOURCE_SHA>",
  "decomposition_notes": "...subagent value...",
  "goals": [...subagent value...]
}
```

Use the **normalized** `SOURCE_SPEC` from Step 6 (relative to repo root, or absolute as fallback) — not the raw `$REQUIREMENTS_PATH`. The hex string MUST be **lowercase** for canonical comparison.

**Defensive overwrite.** The decomposer subagent's prompt at `agents/requirements-decomposer.md` explicitly tells the agent NOT to emit `source_spec` or `source_spec_sha256` — but if the agent emits them anyway (regression, prompt drift), this command **always overwrites** them with values computed in Step 6. Never preserve agent-supplied values for these two keys. Concretely, when serializing the merged JSON:

1. Start from the subagent's output object.
2. **Delete** any `source_spec` and `source_spec_sha256` keys the subagent included.
3. Build a new object whose iteration order is `source_spec`, `source_spec_sha256`, `decomposition_notes`, `goals`.

This is the ONLY mutation made to the subagent's output — every other field (per-goal title, tasks, pitfalls, etc.) is preserved verbatim. The three audit fields are stripped from the API payload in Step 9; they remain on disk as the audit trail that pairs this batch JSON with its source requirements doc.

**(8c) Verify path uniqueness and write the file.** Re-run `sti_unique_path` with the same arguments as Step 5 to confirm `TARGET_PATH` is still untaken. If a colliding file appeared between Step 5 and now (concurrent process, manual filesystem action), use the freshly resolved path — never overwrite an existing file.

Use the `Write` tool to write the JSON document to the resolved target path. The directory containing `REQUIREMENTS_PATH` already exists (it housed the source doc), so no `mkdir -p` is needed.

**(8d) Commit.**

```bash
git add "$TARGET_PATH"
git commit -m "stride-ideation: decomposition for $SLUG"

# Alias for the ship-side steps below — keeps the variable name consistent
# with the historical /ship command body.
BATCH_PATH="$TARGET_PATH"
```

Use `git add <path>` (not `git add -A` or `git commit -a`) to avoid sweeping unrelated working-tree changes into this commit. The source requirements doc is NOT in the commit's file list — `/stridify` reads it but never modifies it.

> **Drift check omitted.** The historical `/ship` command ran a `source_spec_sha256` drift check at this point to catch the case where the user hand-edited the requirements doc between `/decompose` and `/ship`. In the merged `/stridify` flow the batch JSON was just written by this command in the current invocation, so source drift cannot have occurred. The check is skipped.

### Step 9: Strip local-audit fields, POST, and branch on HTTP status

Three sub-steps that together send the payload to Stride.

**(9a) Strip local-audit fields.** The batch JSON on disk contains three local-audit fields (`source_spec`, `source_spec_sha256`, `decomposition_notes`) that the Stride API does not accept. Strip them via `lib/strip_audit_fields.py` before sending:

```bash
API_PAYLOAD="$(python3 "<plugin-root>/lib/strip_audit_fields.py" "$BATCH_PATH")" || {
  echo "stride-ideation: failed to prepare API payload from $BATCH_PATH" >&2
  exit 1
}
```

`$API_PAYLOAD` is the JSON to POST. The on-disk file is unchanged — stripping happens in memory only, so the local audit fields stay available for tools that read the JSON later.

**(9b) POST to the Stride batch endpoint.**

```bash
RESPONSE_FILE="$(mktemp -t stride_stridify_response.XXXXXX.json)"
CURL_ERR_FILE="$(mktemp -t stride_stridify_curl_err.XXXXXX)"
HTTP_CODE="$(
  curl -sS -X POST \
    -H "Authorization: Bearer $STRIDE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD" \
    "$STRIDE_API_URL/api/tasks/batch" \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}' \
    2>"$CURL_ERR_FILE"
)"
CURL_EXIT=$?
unset STRIDE_API_TOKEN  # paranoia: drop the token from the shell as soon as POST returns
```

The `-sS` flags silence the progress bar but keep error output; we capture that stderr to `$CURL_ERR_FILE`. `-w '%{http_code}'` writes the HTTP status code to stdout; the response body goes to `$RESPONSE_FILE` via `-o`. Never use `-v` here — verbose mode would echo the Authorization header.

If `curl` failed at the transport layer (`CURL_EXIT != 0`, or `HTTP_CODE` is empty / `"000"`), the user gets curl's **verbatim** error message — never a generic "something went wrong" wrapper. The actual cause (DNS resolution failure, connection refused, TLS handshake error, timeout, etc.) is the load-bearing diagnostic.

```bash
if [ "$CURL_EXIT" -ne 0 ] || [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
  echo "stride-ideation: HTTP request failed before the Stride API responded:" >&2
  if [ -s "$CURL_ERR_FILE" ]; then
    # curl wrote a real error — surface it verbatim. curl's messages are
    # already user-friendly ("Could not resolve host: stridelikeaboss.com",
    # "Failed to connect to ... port 443: Connection refused", etc.).
    cat "$CURL_ERR_FILE" >&2
  else
    # curl exited non-zero with no stderr — uncommon but possible. Print
    # the numeric exit code so the user has something to look up.
    echo "  curl exited with status $CURL_EXIT and no stderr output." >&2
  fi
  rm -f "$RESPONSE_FILE" "$CURL_ERR_FILE"
  exit 1
fi
rm -f "$CURL_ERR_FILE"
```

The on-disk batch JSON written in Step 8 is the recovery artifact: if the POST fails for any reason, the user has a complete, audited batch document on disk and in git. A future invocation, a hand-curl, or a follow-up tool can ship that file without re-running the decomposer.

**(9c) Branch on the HTTP status code.** **Hard rule for every non-2xx branch: print the response body verbatim.** Do NOT parse it, do NOT reformat it, do NOT summarize it. The user needs the literal bytes the Stride API returned to debug the failure. Stride's 422 responses in particular carry a `details` array naming the offending field(s); rewriting the JSON would strip that signal.

| Status code | Action |
|---|---|
| 2xx | Continue to Step 10 (render the created identifiers). |
| 4xx | One-line header naming the status code, then the full response body verbatim. Exit non-zero. The body typically looks like `{"error": "...", "details": {...}}` or `{"errors": {"field": ["message"]}}` — both shapes are printed unchanged so the user sees the field-level diagnostic Stride emitted. |
| 5xx | One-line header naming the status code, then the full response body verbatim. Exit non-zero. The user should retry manually or report — `/stridify` does NOT retry, does NOT exponential-backoff, does NOT rate-limit. |
| Other (1xx, 3xx) | One-line header naming the status code, then the full response body verbatim. Exit non-zero. These shouldn't reach this code path (curl follows redirects internally and the Stride API never returns 1xx), but if one shows up we surface it rather than swallow it. |

```bash
case "$HTTP_CODE" in
  2*)
    : # fall through to Step 10
    ;;
  4*)
    echo "stride-ideation: Stride API rejected the batch (HTTP $HTTP_CODE). Response body:" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
  5*)
    echo "stride-ideation: Stride API returned HTTP $HTTP_CODE. Response body:" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
  *)
    echo "stride-ideation: unexpected HTTP status $HTTP_CODE. Response body:" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
esac
```

**No retries.** When `/stridify` fails on a 4xx or 5xx, the user is the retry mechanism: they read the verbatim body, fix the underlying issue (regenerate the requirements doc and re-run `/stridify`, hand-edit the on-disk batch JSON and curl it manually, wait out a transient 5xx, etc.), and re-invoke. Stride does not guarantee per-task idempotency on a partially-failed batch, so an automatic retry could double-create some tasks while leaving others to fail again. Manual retry is the safer contract.

### Step 10: Render the created identifiers and print the terminal message

On 2xx the Stride API returns the goals and child tasks with their auto-generated identifiers (G-prefix for goals, W-prefix for work tasks, D-prefix for defects). Parse the response and print a readable table:

```bash
python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    data = json.load(fp)

# Response shape: {"data": {"goals": [{ "identifier": "G99", "title": "...",
#                                       "tasks": [{"identifier": "W404", "title": "..."}, ...]}, ...]}}
# OR the same shape at the root without the "data" wrapper. Be permissive.
container = data.get("data", data)
goals = container.get("goals", [])

print()
print("Created goals and tasks:")
print()
for goal in goals:
    gid = goal.get("identifier", "?")
    title = goal.get("title", "(no title)")
    print(f"  {gid:>6}  {title}")
    for task in goal.get("tasks", []) or []:
        tid = task.get("identifier", "?")
        ttitle = task.get("title", "(no title)")
        print(f"  {tid:>6}    {ttitle}")
print()
PY

rm -f "$RESPONSE_FILE"
```

The table format is two columns: identifier (right-aligned, 6 chars wide for `G123` / `W1234` etc.) followed by the title, with child tasks indented under their goal. A typical successful invocation produces output like:

```
Created goals and tasks:

    G99  stride-ideate v0.1 — /ideate command
   W404    Scaffold the stride-ideation plugin repo layout
   W405    Implement the timestamped filename generator
   W406    Write the stride-ideation SKILL.md
```

After the table, print:

> Batch shipped successfully.
> The goals are now visible in the Stride workspace's Backlog column.

Do NOT print "next step:" suggestions, do NOT propose follow-on commands. The terminal state is the shipped batch.

## What this command does NOT do

- **Validate Stride API field shapes** beyond root-key + structure — that's `lib/validate_batch.py`'s job; surface 422 errors verbatim if anything slips through.
- **Modify the source requirements doc** — read-only access. The doc is committed earlier (by `/ideate`) and is treated as the source of truth.
- **Re-run ideation** — if the doc is missing sections, the error message points the user at `/stride-ideation:ideate --continue <path>` rather than auto-invoking it.
- **Strip `decomposition_notes` from the on-disk JSON** — that field is part of the saved artifact. The strip happens in memory before the POST in Step 9; the on-disk file keeps the audit fields.
- **Retry on transient failures** — fail fast and let the user re-invoke. Idempotency on the Stride side is not guaranteed for partial batches.
- **Drift-check the requirements doc against the batch JSON** — historical `/ship` did this to catch human edits between `/decompose` and `/ship`. The merged flow writes the batch JSON in the current invocation, so source drift cannot have occurred and the check is omitted.
