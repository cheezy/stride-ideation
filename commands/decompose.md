---
description: Decompose a stride-ideation requirements doc into a Stride batch JSON document. Validates the seven required sections, dispatches the requirements-decomposer subagent, validates the JSON root key, writes a timestamped sibling file, commits it, and prints a goals/tasks summary. Terminal message is neutral about whether the user proceeds to /ship.
allowed-tools: Bash(date:*), Bash(git:*), Bash(. *:*), Bash(bash:*), Bash(shasum:*), Bash(sha256sum:*), Bash(awk:*), Bash(sed:*), Bash(basename:*), Bash(dirname:*), Bash(test:*), Read, Write, Glob, Grep, Agent
argument-hint: "<path-to-requirements.md>"
---

# /stride-ideation:decompose

Read a stride-ideation requirements markdown document and produce a Stride batch JSON document at a sibling timestamped path. The decomposition logic — natural seams, sizing, multi-goal split rule, batch JSON shape — lives in `agents/requirements-decomposer.md`. This command is the surface: it parses `$ARGUMENTS`, validates the input, dispatches the subagent, post-processes the result by stamping `source_spec` + `source_spec_sha256` at the JSON root, writes the file, commits it, and prints a summary table.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse `$ARGUMENTS`

The user invoked you with `$ARGUMENTS`. Treat the value as a single path string:

- If `$ARGUMENTS` is empty, print *"Usage: `/stride-ideation:decompose <path-to-requirements.md>`"* and exit non-zero.
- Trim the value and set `REQUIREMENTS_PATH` to the trimmed string.

### Step 2: Validate the requirements doc

Before dispatching the subagent, the command must confirm the input is a real, parseable requirements doc produced by (or compatible with) `/stride-ideation:ideate`. Run these checks in order; any failure prints a one-line error and exits non-zero:

1. **File exists and is a regular file.** Use `Read` or `Bash(test -f)` to confirm. If missing, print *"stride-ideation: requirements doc not found at `<REQUIREMENTS_PATH>`"* and stop.

2. **Filename family matches.** The path SHOULD end in `-requirements.md`. If it does not, warn but proceed — the slug-extraction step below may still succeed for paths produced by older versions of the plugin, and the section-validation pass below is the authoritative check anyway.

3. **All seven hard-gated sections are present.** Use `Grep` to verify that the file contains a level-2 heading for each of: `Problem`, `Goal`, `Outcome`, `Assumptions`, `Constraints`, `Non-goals`, `Success metrics`. Order is not enforced (the doc template orders Problem before Goal, but a hand-edited doc may differ). If any heading is missing, print:

   > *"stride-ideation: requirements doc is missing required section(s): `<list>`. Either re-run `/stride-ideation:ideate --continue <path>` to fill them in, or hand-edit the doc to include the missing sections."*

   And exit non-zero. Do NOT proceed with a partial doc — the decomposer subagent's output quality depends on every section being substantive.

### Step 3: Inherit the session timestamp and slug

Source `lib/filename.sh` and extract the inherited values from `REQUIREMENTS_PATH`:

```bash
. <plugin-root>/lib/filename.sh

SOURCE_TS="$(basename "$REQUIREMENTS_PATH" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6})-.*$/\1/')"
SLUG="$(sti_slug_from_path "$REQUIREMENTS_PATH" requirements)"
```

`SOURCE_TS` is **inherited** from the source path so the decomposition JSON pairs cleanly with its requirements doc by filename prefix. Do NOT generate a fresh timestamp — the design spec explicitly couples the two artifacts by shared prefix.

If `sti_slug_from_path` exits non-zero (the path does not match the `YYYY-MM-DDTHHMMSS-<slug>-requirements.md` format), surface the error verbatim and stop.

### Step 4: Compute the target path (don't write yet)

Use `sti_unique_path` to compute the sibling output path:

```bash
TARGET_PATH="$(sti_unique_path "$(dirname "$REQUIREMENTS_PATH")" "$SOURCE_TS" "$SLUG" stride-batch json)"
```

`stride-batch` is the artifact name (not `requirements`), so the helper produces a sibling file like `2026-05-12T103000-add-notifications-stride-batch.json` next to the requirements doc.

If a stride-batch file with the inherited timestamp + slug already exists (rare — happens when `/decompose` is rerun on the same input), `sti_unique_path` appends `-2`, `-3`, … so the prior batch is preserved. **The HARD INVARIANT 'never overwrite an existing file' applies here too.**

Do NOT create or touch `TARGET_PATH` yet. A pre-created empty file would leave a half-baked artifact if the subagent dispatch fails or is interrupted.

### Step 5: Compute the source SHA-256 and normalize the source path

Compute the SHA-256 of the requirements doc and capture it for the orchestrator-injected fields:

```bash
SOURCE_SHA="$(shasum -a 256 "$REQUIREMENTS_PATH" | awk '{print $1}' | tr 'A-Z' 'a-z')"
```

If `shasum` is unavailable on the host (rare on macOS / Linux), fall back to `sha256sum "$REQUIREMENTS_PATH" | awk '{print $1}' | tr 'A-Z' 'a-z'`. The resulting hex string MUST be **lowercase** so it compares byte-for-byte with the value `/ship` will recompute in its drift check.

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

Do NOT use the raw `$REQUIREMENTS_PATH` as `SOURCE_SPEC` — it depends on the user's current working directory at invocation time and would make `/ship`'s drift check brittle across different shells.

### Step 6: Dispatch the `requirements-decomposer` subagent

Read the full content of the requirements doc and dispatch the subagent via the `Agent` tool:

```
Agent(
  subagent_type: "requirements-decomposer",
  prompt: <<the requirements doc text, fenced inside a "Requirements document:" block — the only input the subagent has access to>>
)
```

The subagent receives the requirements doc as its entire input (no codebase access, no Stride API access, no clarifying-question loop). Its prompt at `agents/requirements-decomposer.md` documents the decomposition methodology, the canonical batch JSON shape, and the output contract.

Wait for the subagent's response. The contract is: **a single fenced ```json document, no prose outside.** Extract the fenced JSON block. If the response contains anything outside the fence — narrative preamble, multiple JSON blocks, a markdown summary — strip the prose and use ONLY the fenced JSON content.

### Step 7: Validate the subagent output

Parse the extracted JSON. Any failure here prints a one-line error and exits non-zero — do NOT write a partial or malformed file:

1. **JSON parses.** If parsing fails, print *"stride-ideation: decomposer returned malformed JSON — first 500 chars: `<excerpt>`"* and stop. Save the raw response to a tmp file for debugging if convenient.

2. **Root key is `goals`.** The most common batch-API mistake is a root key of `tasks`. If the root object has `tasks` instead of `goals`, do NOT silently fix it. Print:

   > *"stride-ideation: decomposer emitted root key `tasks` — Stride's batch API requires `goals`. The agent prompt at agents/requirements-decomposer.md should have prevented this; please re-run /decompose and report the regression if it persists."*

   Exit non-zero. If the root key is anything OTHER than `goals` or `tasks` (e.g., `goal`, `batch`, `result`), print a similar error naming the offending key and stop.

3. **`goals` is a non-empty array.** A decomposer that returns `{"goals": []}` has failed its task. Print *"stride-ideation: decomposer returned an empty goals array — check the requirements doc for under-specification"* and exit non-zero.

4. **`decomposition_notes` exists at the root.** It is required by the subagent contract for documenting cross-goal claim ordering. If missing, set it to an empty string and emit a one-line warning — but do NOT fail; some single-goal decompositions legitimately have nothing cross-goal to document.

### Step 8: Stamp source_spec and source_spec_sha256

Inject the local-audit fields at the JSON root. The output JSON MUST have these exact root keys in this exact order (so a human reading the file sees the audit metadata at the top before the goal payload):

```json
{
  "source_spec": "<SOURCE_SPEC>",
  "source_spec_sha256": "<SOURCE_SHA>",
  "decomposition_notes": "...subagent value...",
  "goals": [...subagent value...]
}
```

Use the **normalized** `SOURCE_SPEC` from Step 5 (relative to repo root, or absolute as fallback) — not the raw `$REQUIREMENTS_PATH`. The hex string MUST be **lowercase** so `/ship`'s drift check compares byte-for-byte.

**Defensive overwrite.** The decomposer subagent's prompt at `agents/requirements-decomposer.md` explicitly tells the agent NOT to emit `source_spec` or `source_spec_sha256` — but if the agent emits them anyway (regression, prompt drift), the orchestrator **always overwrites** them with values computed here. Never preserve agent-supplied values for these two keys. Concretely, when serializing the merged JSON:

1. Start from the subagent's output object.
2. **Delete** any `source_spec` and `source_spec_sha256` keys the subagent included.
3. Build a new object whose iteration order is `source_spec`, `source_spec_sha256`, `decomposition_notes`, `goals`.

This is the ONLY mutation the orchestrator makes to the subagent's output — every other field (per-goal title, tasks, pitfalls, etc.) is preserved verbatim.

**Why both fields.** `/stride-ideation:ship` reads `source_spec_sha256` and recomputes it against the file at `source_spec`. If the recomputed hash differs from the stamped one, the requirements doc has drifted since `/decompose` ran and `/ship` prompts the user. Both fields are stripped by `/ship` before the API payload is sent, so they exist only on disk for local audit.

### Step 9: Verify path uniqueness and write the file

Re-run `sti_unique_path` with the same arguments as Step 4 to confirm `TARGET_PATH` is still untaken. If a colliding file appeared between Step 4 and now (concurrent process, manual filesystem action), use the freshly resolved path — never overwrite an existing file.

Use the `Write` tool to write the JSON document to the resolved target path. The directory containing `REQUIREMENTS_PATH` already exists (it housed the source doc), so no `mkdir -p` is needed.

### Step 10: Commit

```bash
git add "$TARGET_PATH"
git commit -m "stride-ideation: decomposition for $SLUG"
```

Use `git add <path>` (not `git add -A` or `git commit -a`) to avoid sweeping unrelated working-tree changes into this commit. The source requirements doc is NOT in the commit's file list — `/decompose` reads it but never modifies it.

### Step 11: Print the summary table + neutral terminal message

Render a compact table summarizing the decomposition. For each goal in `goals`, print:

```
Goal: <title>
  Complexity: <complexity>  |  Tasks: <count>  |  Priority: <priority>
```

If the goal's first task has empty `dependencies` (it is ready to claim immediately), append a third line: `  First task is ready to claim`. If the first task has dependencies — either array indices into the same goal or string identifiers — omit this readiness line entirely. The omission is the signal: a goal without a readiness line has a blocking dependency the user should resolve before claiming.

If `decomposition_notes` contains a cross-goal claim ordering hint (any mention of "claim", "first", "before", "after", or "CROSS-GOAL DEPENDENCY"), print a separate section:

```
Cross-goal claim ordering:
<the full decomposition_notes text, prefixed by two spaces>
```

Then print **exactly** these three lines, substituting the resolved target path:

> Stride batch written to `<TARGET_PATH>`.
> Review it, edit by hand if needed.
> To create the goals in Stride, run `/stride-ideation:ship <TARGET_PATH>` when ready.

Do NOT auto-invoke `/ship`. Do NOT propose follow-on tasks. Do NOT push the user toward shipping — the terminal state is the written JSON document.

## What this command does NOT do

- **POSTing to the Stride API** — that is `/stride-ideation:ship`. This command produces a file on disk only.
- **Modifying the source requirements doc** — read-only access. The doc is committed earlier (by `/ideate`) and is treated as the source of truth.
- **Re-running ideation** — if the doc is missing sections, the error message points the user at `/stride-ideation:ideate --continue <path>` rather than auto-invoking it.
- **Stripping `decomposition_notes` from the on-disk JSON** — that field is part of the saved artifact. `/ship` strips it from the API payload, not from the file.
