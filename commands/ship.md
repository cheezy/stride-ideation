---
description: POST a stride-ideation batch JSON to the Stride API. Validates the root key, reads auth from .stride_auth.md, strips local-audit fields before sending, and prints the created G/W identifiers in a readable table. Drift check against source_spec is implemented in a separate task.
allowed-tools: Bash(date:*), Bash(git:*), Bash(. *:*), Bash(bash:*), Bash(curl:*), Bash(python3:*), Bash(awk:*), Bash(sed:*), Bash(grep:*), Bash(test:*), Read, Glob, Grep
argument-hint: "<path-to-stride-batch.json>"
---

# /stride-ideation:ship

Read a Stride batch JSON document produced by `/stride-ideation:decompose` and POST it to the Stride API. This command is the surface: it validates the input, loads auth from `.stride_auth.md`, strips local-audit fields, dispatches the HTTP POST, and renders the response.

> **Scope of this command (v0.3 basic):** parse, validate, strip, POST, render. Drift checks against `source_spec_sha256` are layered on in a separate task. Error-handling polish (verbatim 4xx/5xx surfacing, retries, etc.) is also a separate task. The base behavior must be correct on its own first.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse `$ARGUMENTS`

The user invoked you with `$ARGUMENTS`. Treat the value as a single path string:

- If `$ARGUMENTS` is empty, print *"Usage: `/stride-ideation:ship <path-to-stride-batch.json>`"* and exit non-zero.
- Trim the value and set `BATCH_PATH` to the trimmed string.

### Step 2: Validate the batch JSON

Run the structural validator at `lib/validate_batch.py`. It enforces the five named checks (parse, root key, empty goals, missing fields, bad dependency index) and surfaces a precise error message on the first violation:

```bash
if ! python3 "<plugin-root>/lib/validate_batch.py" "$BATCH_PATH" 2>/tmp/ship-validate.err; then
  cat /tmp/ship-validate.err >&2
  rm -f /tmp/ship-validate.err
  exit 1
fi
rm -f /tmp/ship-validate.err
```

The **root-key check is the load-bearing one** for this command — Stride's `/api/tasks/batch` endpoint returns a 422 if the root is anything other than `goals`. The validator catches that locally so the user sees a single descriptive error instead of an HTTP 422 dump.

Do NOT proceed past Step 2 if the validator fails. The Stride API is the user's database — a malformed payload that slipped through would create no tasks but might still trigger rate-limiting or noise an audit trail.

### Step 2b: Source-spec drift check

If the batch JSON has both `source_spec` and `source_spec_sha256` at its root (the normal case — `/stride-ideation:decompose` stamps these), recompute the SHA-256 of the file at `source_spec` and compare against the stamped value. On mismatch, the requirements doc has drifted since `/decompose` ran and the batch JSON may no longer reflect the user's current intent. Prompt the user; default to abort.

```bash
python3 "<plugin-root>/lib/drift_check.py" "$BATCH_PATH" 2>/tmp/ship-drift.err
DRIFT_EXIT=$?

case "$DRIFT_EXIT" in
  0)
    # No drift, or no source_spec stamped (hand-written-JSON path).
    # Proceed silently — no prompt, no output. This is the no-noise rule
    # from the pitfall: do not require the user to type 'y' when there's
    # nothing to confirm.
    rm -f /tmp/ship-drift.err
    ;;
  1)
    # Drift detected. Surface the warning verbatim — it names the
    # source_spec, the stamped SHA, and the recomputed SHA so the
    # user knows exactly what changed.
    cat /tmp/ship-drift.err >&2
    rm -f /tmp/ship-drift.err

    # Prompt with [y/N]; default to abort.
    printf 'Continue with stale JSON, or run /decompose again? [y/N] ' >&2
    read -r REPLY < /dev/tty
    case "$REPLY" in
      y|Y|yes|YES) : ;;  # user confirmed — fall through to Step 3
      *)
        echo "stride-ideation: aborted — re-run /stride-ideation:decompose <requirements-path> to refresh the batch JSON, then retry /ship." >&2
        exit 1
        ;;
    esac
    ;;
  2)
    # Drift checker errored (source file missing, batch JSON malformed,
    # etc.). The validator in Step 2 already covered the JSON-parse
    # case, so this branch typically means the source_spec file was
    # moved or deleted since /decompose ran.
    cat /tmp/ship-drift.err >&2
    rm -f /tmp/ship-drift.err
    echo "stride-ideation: aborted — fix the underlying error and retry /ship." >&2
    exit 1
    ;;
esac
```

**Key behaviors enforced by this step:**

- **Drift detected** → user is prompted. The default answer is **no** (abort). The prompt text quotes the `[y/N]` casing convention so it is unambiguous which letter is the default.
- **No drift** → no prompt, no output. The `/ship` invocation feels exactly the same as in v0.3-without-drift-checks — the no-noise rule from the pitfall.
- **No `source_spec` stamped** (hand-written JSON, the rare power-user case) → no prompt. Drift detection does not apply when there is no baseline.
- **Source file disappeared** → abort with the underlying error message. Never silently skip the check — that would hide regressions.

### Step 3: Read auth from `.stride_auth.md`

Locate `.stride_auth.md` (the convention is `$CLAUDE_PROJECT_DIR/.stride_auth.md` — the same file the Stride orchestrator reads). Invoke `lib/read_auth.py` and source its output:

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

### Step 4: Strip local-audit fields from the payload

The batch JSON on disk contains three local-audit fields (`source_spec`, `source_spec_sha256`, `decomposition_notes`) that the Stride API does not accept. Strip them via `lib/strip_audit_fields.py` before sending:

```bash
API_PAYLOAD="$(python3 "<plugin-root>/lib/strip_audit_fields.py" "$BATCH_PATH")" || {
  echo "stride-ideation: failed to prepare API payload from $BATCH_PATH" >&2
  exit 1
}
```

`$API_PAYLOAD` is the JSON to POST. The on-disk file is unchanged — stripping happens in memory only, so the local audit fields stay available for future `/ship` invocations (e.g., drift re-checks).

### Step 5: POST to the Stride batch endpoint

```bash
RESPONSE_FILE="$(mktemp -t stride_ship_response.XXXXXX.json)"
HTTP_CODE="$(
  curl -sS -X POST \
    -H "Authorization: Bearer $STRIDE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD" \
    "$STRIDE_API_URL/api/tasks/batch" \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}'
)"
unset STRIDE_API_TOKEN  # paranoia: drop the token from the shell as soon as POST returns
```

The `-sS` flags silence progress bars but keep error output. `-w '%{http_code}'` writes the HTTP status code to stdout; the response body goes to `$RESPONSE_FILE` via `-o`. Never use `-v` here — verbose mode would echo the Authorization header.

If `curl` itself fails (exit non-zero), surface a generic transport error without the token:

```bash
if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
  echo "stride-ideation: HTTP transport failed (network error, DNS, TLS handshake, ...)." >&2
  rm -f "$RESPONSE_FILE"
  exit 1
fi
```

### Step 6: Branch on the HTTP status code

| Status code | Action |
|---|---|
| 2xx | Continue to Step 7 (render the created identifiers). |
| 4xx | Surface the response body verbatim (it contains Stride's error reason) and exit non-zero. The body is JSON like `{"error": "..."}` or `{"errors": {...}}` depending on the case. Print the full response. |
| 5xx | Print a generic *"stride-ideation: Stride API returned 5xx — see response body below"* line followed by the response body. Exit non-zero. The user should retry or report. |

Concretely:

```bash
case "$HTTP_CODE" in
  2*)
    : # fall through to Step 7
    ;;
  4*)
    echo "stride-ideation: Stride API rejected the batch (HTTP $HTTP_CODE):" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
  5*)
    echo "stride-ideation: Stride API returned $HTTP_CODE — see response body below" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
  *)
    echo "stride-ideation: unexpected HTTP status $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    rm -f "$RESPONSE_FILE"
    exit 1
    ;;
esac
```

### Step 7: Render the created identifiers

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

### Step 8: Print the neutral terminal message

After the table, print:

> Batch shipped successfully.
> The goals are now visible in the Stride workspace's Backlog column.

Do NOT print "next step:" suggestions, do NOT propose follow-on commands. The terminal state is the shipped batch.

## What this command does NOT do

- **Validate Stride API field shapes** beyond root-key + structure — that's `lib/validate_batch.py`'s job; surface 422 errors verbatim if anything slips through.
- **Modify the source batch JSON or its companion requirements doc** — both are read-only.
- **Retry on transient failures** — fail fast and let the user re-invoke. Idempotency on the Stride side is not guaranteed for partial batches.
