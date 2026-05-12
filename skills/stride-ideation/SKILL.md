---
name: stride-ideation
description: Use when the user has a fuzzy idea, a new feature initiative, or a pre-decomposition scoping need and wants a written requirements document — drives a round-based question loop (up to 4 batched questions per round, with a mandatory round-3 framing checkpoint), hard-gates the 7 required sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success Metrics), auto-dispatches an advisory requirements-reviewer pass, then commits a timestamped requirements doc and STOPS. The terminal state is the written document — the skill never pushes the user toward /decompose, /ship, or any other next step.
skills_version: "1.0"
---

# stride-ideation

This skill turns a vague idea into a structured requirements document through a round-based questioning loop. It is invoked by the `/stride-ideation:ideate` command. The questioning loop and reviewer logic live in `commands/ideate.md` and `agents/requirements-reviewer.md` — this skill defines the surface contract: which sections are required, when the hard gates fire, what the terminal state looks like.

## Hard gate

**The skill MUST NOT write the requirements document to disk until each of the seven required sections below has substantive content.** Placeholders, "TBD", "to be filled in", or single-line gestures are not substantive. If the user attempts to short-circuit ("just write what we have"), the skill asks one more batch of questions covering the missing sections rather than skipping the gate.

The seven required sections:

1. **Goal** — what the user is trying to accomplish
2. **Problem** — what hurts today
3. **Outcome** — what the world looks like after this ships
4. **Assumptions** — load-bearing beliefs that, if wrong, change the design
5. **Constraints** — what cannot change (time, scope, tech, people)
6. **Non-goals** — explicit out-of-scope items
7. **Success Metrics** — how the user will know it worked

Additionally:
- **The skill MUST NOT take any implementation action during the session** — no code edits, no scaffolding, no commits other than the final requirements doc commit, no invocation of decomposition or shipping commands.
- **The skill MUST NEVER overwrite an existing file.** Filename uniqueness is the responsibility of `lib/filename.sh` (`sti_unique_path`); the skill defers to that helper.

## When to invoke

- The user describes a new feature, capability, or initiative in fuzzy terms ("we should probably do X", "what if we…").
- The user explicitly asks for a requirements doc, scoping doc, or design brief.
- A piece of work is too broad to decompose into Stride tasks without first capturing the shape.
- The user is choosing between approaches and needs to articulate goals + constraints before picking one.

## When NOT to invoke

- The work is already scoped (requirements doc exists, or a Stride goal already captures the shape).
- It is a bug fix with a known repro.
- The user is mid-implementation and needs course-correction, not requirements.
- The user is doing exploratory code reading or research — that is not an ideation task.

## The questioning loop

A **round** is one batched `AskUserQuestion` invocation, containing one to four related questions. Rounds proceed until each of the seven required sections has draft content; a typical session uses three to five rounds.

| Round | Default focus |
|---|---|
| 1 | Goal, Problem, Outcome — what's being built and why |
| 2 | Assumptions, Constraints, Non-goals — boundary conditions |
| 3 | Success Metrics + framing checkpoint (see below) |
| 4+ | Gap-fill for whichever sections still lack substance |

Each batched question MUST use `preview` content when the option set benefits from visual comparison (e.g., proposed scope boundaries, alternative success-metric framings). Plain-text choices use `preview: null` or omit the field.

## Round-3 framing checkpoint

**Mandatory.** Before continuing past round 3 the skill summarizes the current draft state back to the user and asks the framing question explicitly. Example phrasing:

> "Here's what I have so far:
> — **Goal:** ship a notifications digest so users stop missing approval requests
> — **Problem:** approval requests sit in inboxes for days
> — **Outcome:** approvers see a daily summary; SLA drops from days to hours
> — **Assumptions:** users have email; SMTP relay is acceptable
> — **Constraints:** no new infra; reuse existing mailer
> — **Non-goals:** real-time push, in-app inbox
> — **Success Metrics:** approval lag p50 < 8h within two weeks
>
> **Is this still framed correctly, or do you want to reframe before we draft the document?**"

If the user reframes, restart the section that changed and re-batch the follow-on questions. Do not skip this checkpoint because the session "feels clear."

## Reviewer pass

After all seven sections have draft content, and before the document is written to disk, the skill auto-dispatches the `requirements-reviewer` subagent (see `agents/requirements-reviewer.md`). The reviewer's output is **advisory** — it surfaces gaps, unstated assumptions, internal contradictions, and ambiguous acceptance criteria.

If the reviewer reports substantive findings, the skill runs **at most one** refinement round to address them, then writes the document regardless of whether the reviewer is fully satisfied. Reviewer findings never block the write indefinitely; perfect is the enemy of shipped.

## Optional auxiliary sections

The document MAY also contain:

- **Sketch** — bullet-form solution shape, if the user produced one during ideation
- **Open Questions** — items the user explicitly deferred

These are **not** gated. Include them only if the conversation generated substantive content for them.

## Terminal state

After the file is written and committed the skill prints exactly:

> "Requirements written to `<path>`."
> "You can stop here — the doc is the deliverable."
> "Or, to break this down into Stride tasks, run `/stride-ideation:decompose <path>` next."

Then the skill **stops**. It does not auto-invoke `/decompose`, does not propose follow-on tasks, does not suggest implementation steps. The terminal state is the written document. The user decides what happens next.

This is a deliberate contrast with brainstorming skills that lock terminal state to a downstream invocation. Stride ideation treats the requirements doc as a standalone deliverable.

## What this skill does NOT cover

- **Question-generation logic** — see `commands/ideate.md` for how the ideation command resolves topic, manages `--continue`, and decides which questions to batch in each round.
- **Reviewer rubric** — see `agents/requirements-reviewer.md` for the exact rubric the reviewer applies to a draft.
- **Decomposition into Stride tasks** — see `commands/decompose.md` and `agents/requirements-decomposer.md`. The ideation skill stops at the requirements doc.
- **Shipping to Stride** — see `commands/ship.md`. Out of scope for ideation.
- **Filename generation** — see `lib/filename.sh`. The skill defers to `sti_unique_path` and never computes filenames itself.
