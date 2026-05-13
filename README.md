# stride-ideation

**Turn an idea into shipped Stride tasks via two slash commands.**

This plugin provides brainstorming and ideation for projects that use [Stride](https://www.stridelikeaboss.com). Run `/stride-ideation:ideate` to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or run `/stride-ideation:stridify` to decompose the requirements into a Stride batch JSON, commit it for audit, and POST it to the Stride API in a single invocation.

## Installation

```bash
/plugin marketplace add cheezy/stride-marketplace
/plugin install stride-ideation@stride-marketplace
```

The plugin auto-discovers the two slash commands, the ideation skill, and the supporting subagents on install. No further configuration needed.

## The two commands

```text
/stride-ideation:ideate [<topic>] [--continue <path>] [--profile <name>]
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.

/stride-ideation:stridify <path-to-requirements.md>
  End-to-end pipeline: validates the requirements doc, preflights auth,
  dispatches the decomposer subagent, stamps audit metadata, writes and
  commits a sibling Stride batch JSON, then POSTs it to /api/tasks/batch
  on your Stride instance and renders the created G/W identifiers.
```

See the design spec in the parent repo for the full ideation protocol and
decomposer rules.

## Profiles

`/stride-ideation:ideate` accepts a `--profile <name>` flag that selects which forcing questions run inside the rounds and which optional sections the document may include. The seven hard-gated section names and the mandatory round-3 framing and round-4 premortem are identical across all profiles — only the augmentations change.

| Profile | When to pick it | What it adds |
|---|---|---|
| `lean` (default) | Engineering-only audience; small topic; you want the shortest path to a committed doc | Nothing — byte-for-byte equivalent to v0.3.0 behavior |
| `product` | Product/design in the audience; framing benefits from a persona-bound scenario | Round-1 JTBD four-forces forcing question; optional **Concrete Example** section in the doc; advisory reviewer checks for JTBD framing and Concrete Example presence |
| `discovery` | Early-stage topic where the case-for-action is the riskiest part | Round-2 Why-now + Alternative-options forcing questions; advisory reviewer check for Why-now content |
| `lean-startup` | Genuinely novel feature; the team is uncertain whether the underlying user need actually exists, and the next step should be a deliberate validation experiment rather than a full build | Mandatory Round-5 MVP-design batch anchored on the `(R)`-marked Assumptions entry; optional **MVP / Validation experiment** section in the doc (riskiest assumption, experiment design, success/failure criteria, time box, pivot-or-persevere decision); advisory reviewer checks for MVP section presence and falsifiable success/failure criteria |

`--profile` is optional. When omitted, the lean profile applies and v0.3.0 invocations remain byte-identical — backward compatibility is preserved by default.

## Requirements

- A Stride workspace and `.stride_auth.md` in the project where you run `/stridify`
- Claude Code (the slash commands and subagent dispatch use Claude Code primitives)

## Migrating from `superpowers:brainstorming`

If your project already uses Stride, `stride-ideation` supersedes `superpowers:brainstorming` for new ideation sessions. The two skills overlap in intent (turn a fuzzy idea into a written artifact) but diverge in important ways:

| Concern | `superpowers:brainstorming` | `stride-ideation` |
|---|---|---|
| Terminal state | Funnels into the `writing-plans` skill | Stops at the committed requirements doc |
| Question style | One question at a time | Batched (up to 4 per round, `preview` for visual options) |
| Hard gates | Loose — any approved design proceeds | Seven required sections, each must have substantive content; Assumptions must be ranked with the riskiest marked and include premortem-derived failure modes; Success Metrics must include both leading and lagging indicators |
| Output | A design conversation | A single timestamped `*-requirements.md` |
| Decomposition + shipping | Manual follow-up | Optional second command (`/stride-ideation:stridify`) — one-shot decompose + commit + POST |

**Which one should I use?**

- **Use `stride-ideation`** when the project uses Stride and you may want to ship the requirements as kanban tasks. The two-command pipeline (ideate → stridify) is the headline value.
- **Use `superpowers:brainstorming`** when the project does NOT use Stride, or when you want an open-ended design conversation that funnels into the `writing-plans` flow. The two skills are intentionally allowed to coexist; we are not deprecating `brainstorming` for projects where it's the right fit.

**I have an in-flight `superpowers:brainstorming` spec — should I redo it with `stride-ideation`?**

No. Brainstorming output is already a useful artifact. Pick it up where you left off using whichever skill matches your project:

- If the brainstorm produced a written design doc that names a Problem, Goal, Constraints, and Non-goals: run `/stride-ideation:ideate --continue <path>` to refine it under the seven-section format without re-eliciting from scratch. The source document is read-only and never modified.
- If the brainstorm output is mostly conversation history and you need a structured doc: run `/stride-ideation:ideate <topic>` fresh, but paste the relevant brainstorm snippets when the round-1 questions ask for context. Treat the brainstorm as background reading, not the deliverable.
- If the brainstorm output is already what you want and you just need to break it down and ship it: skip `/ideate` entirely and run `/stride-ideation:stridify <path>` against the existing doc — the decomposer's only hard requirement is that the seven gated sections are present and substantive. (Heads up: `/stridify` POSTs to your Stride workspace, so use a non-prod instance if you're calibrating.)

The `fixtures/` directory in this repo contains three example requirements docs showing what `/ideate` output looks like at three different scopes (small feature, multi-goal initiative, fast-and-loose exploration) — useful as a calibration reference if you're not sure what "substantive" content looks like for your case.

## Smoke test

The end-to-end plugin pipeline (validate → preflight auth → decompose → stamp + write + commit → strip audit fields → POST → render created identifiers) is covered by `lib/run_smoke_test.sh`. By default it runs in **dry mode**: each helper is invoked with a fixture input, the response-rendering code is exercised against a canned 2xx body, and no network call is made. Safe to run in CI.

```bash
# Dry run — no network call, no real tasks created.
./lib/run_smoke_test.sh
```

Expected output: five stages, ten ✓ markers, `10 passed, 0 failed`.

To exercise the full pipeline against a real Stride instance, use `--live` with a batch JSON path:

```bash
# LIVE run — POSTs to the Stride API in $CLAUDE_PROJECT_DIR/.stride_auth.md.
# CREATES REAL TASKS in that Stride workspace. Use a dev instance.
./lib/run_smoke_test.sh --live fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json
```

Auth is read from the same `.stride_auth.md` the slash commands use. Never commit `.stride_auth.md` — it carries a bearer token. The README's *Installation* and the file's own contents both link to the canonical Stride onboarding URL (`https://www.stridelikeaboss.com/api/agent/onboarding`) for setup instructions.

### Re-running the interactive end-to-end test

`lib/run_smoke_test.sh --live` covers the `/stridify` half of the pipeline (validate batch JSON, strip audit fields, POST, render). The `/ideate` half requires an interactive Claude Code session because the ideation skill runs a real Q&A loop. The manual procedure:

1. In a Claude Code session in this repo, run `/stride-ideation:ideate <topic>` and answer the round-based questions through to the `requirements-reviewer` advisory pass. Confirm the resulting `*-requirements.md` is committed.
2. Run `/stride-ideation:stridify <path-to-requirements.md>`. Confirm the resulting `*-stride-batch.json` is committed, the goals/tasks table is rendered, and the created G/W identifiers appear in the Stride workspace's Backlog column with the expected titles.

The unit-test suites (`lib/test-*.sh`) cover every helper in isolation. The smoke test confirms the helpers compose correctly. The interactive end-to-end is the human-driven check that the slash commands themselves behave correctly when driven by a real user — a thing the test harness fundamentally cannot stand in for.

## License

MIT — see [LICENSE](LICENSE).
