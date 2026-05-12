---
description: Drive an interactive ideation session that turns a fuzzy idea into a committed requirements markdown document. Hard-gated by the stride-ideation skill on the seven required sections; terminal state is the written doc (does NOT auto-invoke /decompose).
allowed-tools: Bash(date:*), Bash(git:*), Bash(. *:*), Bash(bash:*), Read, Write, Glob, Grep, Skill, Agent
argument-hint: "[<topic>]"
---

# /stride-ideation:ideate

Drive an interactive ideation session that produces a committed `*-requirements.md` document under `docs/superpowers/specs/`. The protocol — round-based question batching, hard-gated sections, advisory reviewer pass — is defined in `skills/stride-ideation/SKILL.md`. This command is the surface: it parses `$ARGUMENTS`, captures the session timestamp, resolves the slug, drives the skill, and finishes by writing and committing the doc.

> **Scope of this command (v0.1):** `<topic>` argument only. The `--continue <path>` flag is implemented in a separate task and is not handled here — if the user passes it now, fall through to the topic prompt and treat the rest as the topic string.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse `$ARGUMENTS`

The user invoked you with `$ARGUMENTS`. Treat the value as a topic string:

- If `$ARGUMENTS` is non-empty, set `TOPIC` to the trimmed value.
- If `$ARGUMENTS` is empty, ask the user once via `AskUserQuestion`: *"What's the topic for this ideation session?"* (free-text input). Use the response as `TOPIC`.

Do not parse flags in this version. The future `--continue <path>` task will own that branch.

### Step 2: Capture the session timestamp

Run `date -u +%Y-%m-%dT%H%M%S` once and store the result as `SESSION_TS`. This single value MUST be used for every artifact written during this session — do not recompute it later. Capturing the timestamp at invocation time is what makes re-runs sortable and keeps the requirements doc / decomposition output paired by prefix.

### Step 3: Resolve the topic slug

Source `lib/filename.sh` (it ships with the plugin) and call `sti_slugify "$TOPIC"`:

```bash
. <plugin-root>/lib/filename.sh
SLUG="$(sti_slugify "$TOPIC")"
```

Where `<plugin-root>` is the resolved path to the installed `stride-ideation` plugin. If `sti_slugify` exits non-zero (empty slug), surface the error verbatim and stop — do NOT silently pick a fallback slug.

Confirm `SLUG` with the user once via `AskUserQuestion` before the session begins, offering the computed value as the first option and "Type a different slug" as a fallback. The slug is locked for the rest of the session.

### Step 4: Compute the target path (don't write yet)

Call `sti_unique_path docs/superpowers/specs "$SESSION_TS" "$SLUG" requirements md`:

```bash
TARGET_PATH="$(sti_unique_path docs/superpowers/specs "$SESSION_TS" "$SLUG" requirements md)"
```

`TARGET_PATH` is the path you WILL write to in Step 8. Do NOT create or touch this file yet. Pre-creating it as empty would leave a half-baked artifact on the filesystem if the user interrupts mid-session, which is the explicit failure mode the spec is guarding against.

### Step 5: Invoke the `stride-ideation` skill

Use the `Skill` tool to invoke `stride-ideation`, passing the topic and the locked slug in the args block:

```
Skill(skill: "stride-ideation", args: "topic=<TOPIC>; slug=<SLUG>; session_ts=<SESSION_TS>; target_path=<TARGET_PATH>")
```

The skill enforces:
- the hard gate against premature implementation,
- the round-based `AskUserQuestion` loop (≤ 4 questions per round),
- the mandatory round-3 framing checkpoint,
- the seven hard-gated sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success Metrics),
- the advisory `requirements-reviewer` subagent pass before the write.

When the skill returns, you will have a single string `DRAFT_DOC` containing the fully composed requirements markdown — every gated section present and substantive. If the skill returns without a draft (user aborted, hard gate not satisfied), stop here and exit cleanly — do NOT write anything to disk and do NOT commit.

### Step 6: Conform the draft to the spec template

The skill returns prose for each section but the on-disk format is fixed by the design spec's "Output: requirements markdown template". Ensure `DRAFT_DOC` looks like:

```markdown
# <Topic>

*Date: YYYY-MM-DD HH:MM*
*Session: <SESSION_TS>-<SLUG>*

## Problem
<one paragraph max>

## Goal
<outcome, not feature>

## Success metrics
- <bulleted, each measurable>

## Assumptions
- <bullets>

## Constraints
- <bullets — non-negotiable>

## Non-goals
- <bullets, each with a reason>

## Outcome
<what the world looks like after this ships>

## Sketch
<optional; 1–5 paragraphs if present>

## Open questions
<optional; bullets of deferred items>
```

The seven hard-gated sections appear above the two optional ones (`Sketch`, `Open questions`). Include the optional sections only if the conversation produced substantive content for them. If the draft is missing any gated section, treat that as a skill bug and abort — do NOT paper over it by writing an incomplete doc.

### Step 7: Verify the target path is still untaken

Re-run `sti_unique_path` with the same arguments as Step 4 and confirm the returned path equals `TARGET_PATH`. If it differs (another process wrote a colliding file during the session), use the new value — never overwrite an existing file. This is the HARD INVARIANT documented in `lib/filename.sh`.

### Step 8: Write the file

Use the `Write` tool to write `DRAFT_DOC` to the resolved target path. The directory `docs/superpowers/specs/` may not exist on a fresh repo; create it via `mkdir -p docs/superpowers/specs` before the write if Step 4's path resolution depended on it.

### Step 9: Commit

```bash
git add "$TARGET_PATH"
git commit -m "stride-ideation: requirements for $SLUG"
```

Commit message format: `stride-ideation: requirements for <slug>`. Do not include the session timestamp in the message — the filename already carries it.

If the working tree had unrelated uncommitted changes before the session, the commit MUST include only the new requirements doc. Use `git add <path>` (not `git add -A` or `git commit -a`) to avoid sweeping unrelated work into this commit.

### Step 10: Print the neutral terminal message

Print **exactly** these three lines, substituting the resolved path:

> Requirements written to `<TARGET_PATH>`.
> You can stop here — the doc is the deliverable.
> Or, to break this down into Stride tasks, run `/stride-ideation:decompose <TARGET_PATH>` next.

Do NOT add follow-up suggestions, do NOT auto-invoke `/decompose`, do NOT propose implementation steps. The terminal state is the written document.

## What this command does NOT do

- `--continue <path>` mode — a separate task implements that.
- Decomposition into Stride tasks — see `/stride-ideation:decompose`.
- Shipping to a Stride workspace — see `/stride-ideation:ship`.
- Modifying any file other than the new requirements doc — pre-existing files are untouched.
