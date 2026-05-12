---
description: Drive an interactive ideation session that turns a fuzzy idea into a committed requirements markdown document. Supports --continue <path> to refine a prior requirements doc. Hard-gated by the stride-ideation skill on the seven required sections; terminal state is the written doc (does NOT auto-invoke /decompose).
allowed-tools: Bash(date:*), Bash(git:*), Bash(. *:*), Bash(bash:*), Read, Write, Glob, Grep, Skill, Agent
argument-hint: "[<topic>] [--continue <path>]"
---

# /stride-ideation:ideate

Drive an interactive ideation session that produces a committed `*-requirements.md` document under `docs/superpowers/specs/`. The protocol — round-based question batching, hard-gated sections, advisory reviewer pass — is defined in `skills/stride-ideation/SKILL.md`. This command is the surface: it parses `$ARGUMENTS`, captures the session timestamp, resolves the slug, drives the skill, and finishes by writing and committing the doc.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse `$ARGUMENTS`

The user invoked you with `$ARGUMENTS`. Walk the tokens in any order:

- If `--continue` appears, set `CONTINUE_PATH` to the value of the **next** token and remove both tokens. The remaining tokens (if any) are ignored — in `--continue` mode the topic is inherited from the source file and not re-prompted.
- If `--continue` is absent, treat the trimmed remainder as `TOPIC`. If the remainder is empty, ask the user once via `AskUserQuestion`: *"What's the topic for this ideation session?"* (free-text input).

Validate `CONTINUE_PATH` immediately:

- If `CONTINUE_PATH` is set but the file does not exist (or is not a regular file), print a one-line error naming the path and exit non-zero. Do NOT fall back to a fresh session — the user explicitly asked for `--continue`.
- If `CONTINUE_PATH` does not end in `-requirements.md` (the artifact family this command refines), warn but proceed; the slug extraction may still work for paths produced by older versions of the plugin.

### Step 2: Capture the session timestamp

Run `date -u +%Y-%m-%dT%H%M%S` once and store the result as `SESSION_TS`. This single value MUST be used for every artifact written during this session — do not recompute it later. Capturing the timestamp at invocation time is what makes re-runs sortable and keeps the requirements doc / decomposition output paired by prefix.

**Even in `--continue` mode, always generate a fresh `SESSION_TS`.** Do not reuse the timestamp embedded in `CONTINUE_PATH` — that timestamp belongs to the source document, and reusing it would defeat the "never overwrite an existing file" invariant. The refined doc is a sibling, not a replacement.

### Step 3: Resolve the topic slug

Source `lib/filename.sh` (it ships with the plugin) and resolve the slug depending on mode:

```bash
. <plugin-root>/lib/filename.sh

if [ -n "$CONTINUE_PATH" ]; then
  # --continue mode: inherit slug from source path; never re-prompt.
  SLUG="$(sti_slug_from_path "$CONTINUE_PATH" requirements)"
else
  # Fresh session: slugify the user-supplied topic.
  SLUG="$(sti_slugify "$TOPIC")"
fi
```

Where `<plugin-root>` is the resolved path to the installed `stride-ideation` plugin. If either helper exits non-zero, surface the error verbatim and stop — do NOT silently pick a fallback slug.

**Confirm `SLUG` with the user only in fresh-session mode.** In `--continue` mode the slug is inherited and locked — re-prompting would violate the "no re-prompt" acceptance criterion and risk accidentally diverging the artifact family. In fresh-session mode, ask the user via `AskUserQuestion` offering the computed value as the first option and "Type a different slug" as a fallback. Either way, the slug is locked for the rest of the session.

### Step 4: Compute the target path (don't write yet)

Call `sti_unique_path docs/superpowers/specs "$SESSION_TS" "$SLUG" requirements md`:

```bash
TARGET_PATH="$(sti_unique_path docs/superpowers/specs "$SESSION_TS" "$SLUG" requirements md)"
```

`TARGET_PATH` is the path you WILL write to in Step 8. Do NOT create or touch this file yet. Pre-creating it as empty would leave a half-baked artifact on the filesystem if the user interrupts mid-session, which is the explicit failure mode the spec is guarding against.

**HARD INVARIANT — `--continue` mode:** `TARGET_PATH` MUST NOT equal `CONTINUE_PATH`. `sti_unique_path` builds the new path from a fresh `SESSION_TS`, so the two paths only collide if the user manually crafted a colliding name on disk in the same second — which the collision discriminator handles. Verify the invariant before continuing:

```bash
if [ -n "$CONTINUE_PATH" ] && [ "$TARGET_PATH" = "$CONTINUE_PATH" ]; then
  echo "stride-ideation: refusing to overwrite source document at $CONTINUE_PATH" >&2
  exit 1
fi
```

### Step 4b: Read the prior document (only in `--continue` mode)

If `CONTINUE_PATH` is set, **read-only** load its content via the `Read` tool:

```
PRIOR_DOC="$(Read $CONTINUE_PATH)"
```

The skill will receive this content as starting context for the session. The source file is **never** edited, written, moved, or `git add`-ed during this command — read access only. If you find yourself reaching for `Write` or `Edit` on `CONTINUE_PATH`, stop: that is the failure mode the pitfall forbids.

In fresh-session mode, leave `PRIOR_DOC` empty.

### Step 5: Invoke the `stride-ideation` skill

Use the `Skill` tool to invoke `stride-ideation`, passing the topic, locked slug, session timestamp, target path, and the prior document (if any):

```
Skill(skill: "stride-ideation",
      args: "topic=<TOPIC>; slug=<SLUG>; session_ts=<SESSION_TS>; target_path=<TARGET_PATH>; prior_doc=<PRIOR_DOC>")
```

When `PRIOR_DOC` is non-empty, the skill starts the session with that content already loaded as context — refining and sharpening rather than re-eliciting every section from scratch. The Q&A loop, the round-3 checkpoint, the hard gates, and the advisory reviewer pass all still run; `--continue` does not lower the bar, only the starting cost.

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
if [ -n "$CONTINUE_PATH" ]; then
  git commit -m "stride-ideation: refine requirements for $SLUG"
else
  git commit -m "stride-ideation: requirements for $SLUG"
fi
```

Commit message format: `stride-ideation: requirements for <slug>` (fresh) or `stride-ideation: refine requirements for <slug>` (continue). Do not include the session timestamp in the message — the filename already carries it.

If the working tree had unrelated uncommitted changes before the session, the commit MUST include only the new requirements doc. Use `git add <path>` (not `git add -A` or `git commit -a`) to avoid sweeping unrelated work into this commit. In `--continue` mode the source document MUST NOT appear in the commit's file list (it was not modified, so `git status` will already show it clean — but verify nothing accidental crept in).

### Step 10: Print the neutral terminal message

Print **exactly** these three lines, substituting the resolved path:

> Requirements written to `<TARGET_PATH>`.
> You can stop here — the doc is the deliverable.
> Or, to break this down into Stride tasks, run `/stride-ideation:decompose <TARGET_PATH>` next.

Do NOT add follow-up suggestions, do NOT auto-invoke `/decompose`, do NOT propose implementation steps. The terminal state is the written document.

## What this command does NOT do

- Decomposition into Stride tasks — see `/stride-ideation:decompose`.
- Shipping to a Stride workspace — see `/stride-ideation:ship`.
- Modifying any file other than the new requirements doc — pre-existing files (including a `--continue` source document) are read-only.
