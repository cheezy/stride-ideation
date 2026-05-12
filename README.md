# stride-ideation

**Turn an idea into shipped Stride tasks via three slash commands.**

This plugin replaces `superpowers:brainstorming` for projects that use [Stride](https://www.stridelikeaboss.com). Run `/stride-ideation:ideate` to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or run `/stride-ideation:decompose` to break the requirements into a Stride batch JSON, and `/stride-ideation:ship` to POST that batch to the Stride API.

## Installation

```bash
/plugin marketplace add cheezy/stride-marketplace
/plugin install stride-ideation@stride-marketplace
```

The plugin auto-discovers the three slash commands, the ideation skill, and the supporting subagents on install. No further configuration needed.

## The three commands

```text
/stride-ideation:ideate [<topic>] [--continue <path>]
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.

/stride-ideation:decompose <path-to-requirements.md>
  Reads the requirements doc, dispatches a decomposer subagent, and writes a
  Stride batch JSON file (timestamped, paired by slug with the source doc).

/stride-ideation:ship <path-to-stride-batch.json>
  Reads the batch JSON, validates it, drift-checks against its source spec,
  and POSTs it to /api/tasks/batch on your Stride instance.
```

See the design spec in the parent repo for the full ideation protocol and
decomposer rules.

## Requirements

- A Stride workspace and `.stride_auth.md` in the project where you run `/ship`
- Claude Code (the slash commands and subagent dispatch use Claude Code primitives)

## Migrating from `superpowers:brainstorming`

If your project already uses Stride, `stride-ideation` supersedes `superpowers:brainstorming` for new ideation sessions. The two skills overlap in intent (turn a fuzzy idea into a written artifact) but diverge in important ways:

| Concern | `superpowers:brainstorming` | `stride-ideation` |
|---|---|---|
| Terminal state | Funnels into the `writing-plans` skill | Stops at the committed requirements doc |
| Question style | One question at a time | Batched (up to 4 per round, `preview` for visual options) |
| Hard gates | Loose — any approved design proceeds | Seven required sections, each must have substantive content |
| Output | A design conversation | A single timestamped `*-requirements.md` |
| Decomposition | Manual follow-up | Optional second command (`/stride-ideation:decompose`) |
| Shipping | None | Optional third command (`/stride-ideation:ship`) |

**Which one should I use?**

- **Use `stride-ideation`** when the project uses Stride and you may want to ship the requirements as kanban tasks. The three-command pipeline (ideate → decompose → ship) is the headline value.
- **Use `superpowers:brainstorming`** when the project does NOT use Stride, or when you want an open-ended design conversation that funnels into the `writing-plans` flow. The two skills are intentionally allowed to coexist; we are not deprecating `brainstorming` for projects where it's the right fit.

**I have an in-flight `superpowers:brainstorming` spec — should I redo it with `stride-ideation`?**

No. Brainstorming output is already a useful artifact. Pick it up where you left off using whichever skill matches your project:

- If the brainstorm produced a written design doc that names a Problem, Goal, Constraints, and Non-goals: run `/stride-ideation:ideate --continue <path>` to refine it under the seven-section format without re-eliciting from scratch. The source document is read-only and never modified.
- If the brainstorm output is mostly conversation history and you need a structured doc: run `/stride-ideation:ideate <topic>` fresh, but paste the relevant brainstorm snippets when the round-1 questions ask for context. Treat the brainstorm as background reading, not the deliverable.
- If the brainstorm output is already what you want and you just need to break it down: skip `/ideate` entirely and run `/stride-ideation:decompose <path>` against the existing doc — the decomposer's only hard requirement is that the seven gated sections are present and substantive.

The `fixtures/` directory in this repo contains three example requirements docs showing what `/ideate` output looks like at three different scopes (small feature, multi-goal initiative, fast-and-loose exploration) — useful as a calibration reference if you're not sure what "substantive" content looks like for your case.

## Smoke test

The end-to-end plugin pipeline (validate → drift check → auth → strip audit fields → POST → render created identifiers) is covered by `lib/run_smoke_test.sh`. By default it runs in **dry mode**: each helper is invoked with a fixture input, the response-rendering code is exercised against a canned 2xx body, and no network call is made. Safe to run in CI.

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

`lib/run_smoke_test.sh --live` covers the `/decompose` + `/ship` half of the pipeline. The `/ideate` half requires an interactive Claude Code session because the ideation skill runs a real Q&A loop. The manual procedure:

1. In a Claude Code session in this repo, run `/stride-ideation:ideate <topic>` and answer the round-based questions through to the `requirements-reviewer` advisory pass. Confirm the resulting `*-requirements.md` is committed.
2. Run `/stride-ideation:decompose <path-to-requirements.md>`. Confirm the resulting `*-stride-batch.json` is committed and that the summary table looks right.
3. Run `/stride-ideation:ship <path-to-stride-batch.json>` (or invoke `lib/run_smoke_test.sh --live <path>`). Confirm the created G/W identifiers appear in the Stride workspace's Backlog column with the expected titles.

The unit-test suites (`lib/test-*.sh`) cover every helper in isolation. The smoke test confirms the helpers compose correctly. The interactive end-to-end is the human-driven check that the slash commands themselves behave correctly when driven by a real user — a thing the test harness fundamentally cannot stand in for.

## License

MIT — see [LICENSE](LICENSE).
