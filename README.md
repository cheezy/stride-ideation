# stride-ideation

**Turn an idea into shipped Stride tasks via two slash commands.**

This plugin provides brainstorming and ideation for projects that use [Stride](https://www.stridelikeaboss.com). Run `/stride-ideation:ideate` to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or run `/stride-ideation:stridify` to decompose the requirements into a Stride batch JSON, commit it for audit, and POST it to the Stride API in a single invocation.

> **Security:** for what the plugin runs on your machine, what data leaves it,
> and how your API token is handled, see **[SECURITY.md](SECURITY.md)**.

> **External service:** only `/stride-ideation:stridify` makes a network call —
> a single `POST` of the decomposed batch JSON to your configured Stride server
> (`https://www.stridelikeaboss.com` by default), authenticated with a bearer
> token you supply. `/stride-ideation:ideate` is fully local. The plugin
> contacts no other host. See [SECURITY.md](SECURITY.md) for exactly what is sent.

## Installation

**From the community plugin directory** (once the listing is approved):

```
/plugin install stride-ideation@claude-community
```

**From the Stride marketplace** (available today):

```
/plugin marketplace add cheezy/stride-marketplace
/plugin install stride-ideation@stride-marketplace
```

The plugin auto-discovers the two slash commands, the ideation skill, and the supporting subagents on install. No further configuration needed.

## Prerequisites

- **Claude Code** — the slash commands and subagent dispatch use Claude Code primitives.
- **git** — `/ideate` and `/stridify` commit their artifacts (the requirements doc and the batch JSON) to your repository for audit.
- **For `/stridify` only:** a **Stride account and API token** from [stridelikeaboss.com](https://www.stridelikeaboss.com), and a project-local **`.stride_auth.md`** (your API URL + token — **never commit it**; it carries a bearer token). `/ideate` needs none of these.

## What's in this plugin

- **2 slash commands** — `/stride-ideation:ideate` (interactive ideation → committed requirements doc) and `/stride-ideation:stridify` (decompose → commit → POST the batch).
- **1 skill** — `stride-ideation`, the ideation protocol that drives the `/ideate` question loop and section gating.
- **2 subagents** (Claude Code) — `requirements-decomposer` (turns a requirements doc into batch JSON) and `requirements-reviewer` (advisory gap review of a draft; never edits).
- **`lib/` helper scripts** — `read_auth.py` (credential extraction), `validate_batch.py` (batch-JSON shape check), `drift_check.py` (source-spec drift), `strip_audit_fields.py` (audit-field removal before POST), `filename.sh` / `draft.sh` (slug/path + draft autosave), and `run_smoke_test.sh` (end-to-end harness). All are Markdown/Python/bash — there is no `hooks.json` and no client-side hook execution.
- **`fixtures/`** — example requirements docs and their decomposed batch JSON, used by the smoke test and as references.

All agent-facing components are Markdown instructions, not executable code; the only executable surface is the `lib/` helper scripts. See [SECURITY.md](SECURITY.md) for the full runtime model.

## The two commands

```text
/stride-ideation:ideate [<topic>] [--continue <path>] [--input <path>] [--profile <name>]
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.
  --continue refines a prior committed requirements doc; --input seeds draft
  sections from a freeform brain-dump file (read-only). When --profile is
  omitted, the session recommends one before the rounds. See "Session
  experience" below.

/stride-ideation:stridify <path-to-requirements.md> [--goal <name|index>] [--yes]
  End-to-end pipeline: validates the requirements doc, preflights auth,
  dispatches the decomposer subagent, stamps audit metadata, writes and
  commits a sibling Stride batch JSON, then — after showing you the decomposed
  goal/task tree and getting your approval — POSTs it to /api/tasks/batch on
  your Stride instance and renders the created G/W identifiers.
  --goal scopes the dispatch to one surface from the doc's
  ## Decomposition seams section (see "Resilience model" below).
  --yes / --auto-approve bypasses the approval gate for scripted callers.
```

The full ideation protocol and decomposer rules live in the plugin itself —
[`skills/stride-ideation/SKILL.md`](skills/stride-ideation/SKILL.md) and
[`agents/requirements-decomposer.md`](agents/requirements-decomposer.md).

## Profiles

`/stride-ideation:ideate` accepts a `--profile <name>` flag that selects which forcing questions run inside the rounds and which optional sections the document may include. The seven hard-gated section names and the mandatory round-3 framing and round-4 premortem are identical across all profiles — only the augmentations change.

| Profile | When to pick it | What it adds |
|---|---|---|
| `lean` (default) | Engineering-only audience; small topic; you want the shortest path to a committed doc | Nothing — byte-for-byte equivalent to v0.3.0 behavior |
| `product` | Product/design in the audience; framing benefits from a persona-bound scenario | Round-1 JTBD four-forces forcing question; optional **Concrete Example** section in the doc; advisory reviewer checks for JTBD framing and Concrete Example presence |
| `discovery` | Early-stage topic where the case-for-action is the riskiest part | Round-2 Why-now + Alternative-options forcing questions; advisory reviewer check for Why-now content |
| `lean-startup` | Genuinely novel feature; the team is uncertain whether the underlying user need actually exists, and the next step should be a deliberate validation experiment rather than a full build | Mandatory Round-5 MVP-design batch anchored on the `(R)`-marked Assumptions entry; optional **MVP / Validation experiment** section in the doc (riskiest assumption, experiment design, success/failure criteria, time box, pivot-or-persevere decision); advisory reviewer checks for MVP section presence and falsifiable success/failure criteria |

`--profile` is optional. When omitted, the lean profile applies and v0.3.0 invocations remain byte-identical — backward compatibility is preserved by default. **New in v0.8.0:** when `--profile` is omitted, `/ideate` now *recommends* a profile before the rounds begin (recommended-first, with a one-line rationale, defaulting to lean) instead of silently defaulting; passing `--profile` explicitly skips the recommendation.

## Session experience (v0.8.0+)

`/stride-ideation:ideate` is a guided, recoverable, human-in-control session. These affordances are additive — a flag-free or `--profile=lean` run still produces the same committed requirements doc.

| Feature | What it does |
|---|---|
| **Round recap** | Before every round, a display-only recap shows each of the seven gated sections as `solid` / `thin` / `empty` plus the round's target sections. Never an extra question; never changes the gate, round order, or `≤ 4`-question budget. |
| **"I'm not sure — propose candidates"** | Every gated-section and forcing question carries this first-class option. Picking it makes the skill propose 2–4 concrete, topic-tailored candidates with one-line rationales; you pick, edit, or ask for more. A proposed candidate never satisfies the gate until you confirm it. |
| **Profile recommendation** | When `--profile` is omitted, a single recommendation question runs before the rounds (recommended-first, lean default). Explicit `--profile` skips it. |
| **`--input <file>` brain-dump seed** | Reads a freeform notes file **read-only** and pre-populates draft sections wherever the notes map to a gated section, then focuses the rounds on the gaps. Distinct from `--continue` (a committed requirements doc) and composable with it. The input file is never modified, moved, or committed. |
| **Draft autosave & resume** | The in-progress draft is autosaved after every round to a **gitignored** scratch file under `.stride/`, so an interruption is recoverable. On start, an unfinished draft for the same slug is detected and you're offered resume-or-fresh; the scratch file is deleted after a successful commit. Never holds the Stride API token. |
| **Reviewer decision** | When the advisory `requirements-reviewer` reports findings, they're surfaced as a multi-select decision (severity-tagged, one line each) with an explicit **"Address none — write as-is"** choice. You choose what feeds the single refinement round. At most one refinement round; the reviewer never blocks the write. |

## Preview-and-approval gate on `/stridify` (v0.8.0+)

Before POSTing the generated batch to your Stride instance, `/stride-ideation:stridify` now renders the decomposed goal/task tree — each goal title, its task count, its task titles, and the cross-goal claim order from `decomposition_notes` — and requires your explicit approval. The batch JSON is written and committed to disk *before* the gate, so on decline the command stops cleanly (exit 0) with the audited artifact intact and no POST attempted. Pass `--yes` / `--auto-approve` (explicit only, never inferred) to bypass the gate and preserve the historical fire-and-forget behavior byte-for-byte for scripted callers. The preview reads only the on-disk JSON and never prints the API token.

## Resilience model (v0.7.0+)

`/stride-ideation:stridify` is designed to survive a transient Anthropic API capacity spike without losing the assembled prompt or producing partial Stride state. The model has four layers, in execution order:

| Layer | Trigger | What happens |
|---|---|---|
| **Preflight advisory** | Doc enumerates more than 3 surfaces under `## Decomposition seams` AND `--goal` is unset | One-line stderr suggestion to use `--goal`. Never blocks — purely informational. |
| **Per-goal partitioning** | User invokes with `--goal <name|index>` | Decomposer prompt is scoped to one surface from the doc's `## Decomposition seams` section. Per-goal batches sit side-by-side (`<source-slug>-<goal-slug>-stride-batch.json`); reruns get `-2`/`-3` suffixes. |
| **Subagent dispatch retry** | `Agent` call fails with HTTP 529 Overloaded, transient network error (DNS / connection refused / timeout / TLS handshake), or an `overloaded` classification string | Up to **3 attempts** with **~30s / ~90s** backoff (total budget ~2 min). Terminal classifications (bad subagent name, contract violation, hard 4xx) fail fast on attempt 1. |
| **Retry-exhaustion fallback** | 3 consecutive transient failures | Writes a sibling `<source-stem>-decomposer-prompt.md` containing the assembled prompt + verbatim last error + recovery README (paste prompt into a fresh Claude session → save JSON response as target → run `lib/validate_batch.py` → manual POST). **Stride API POST is NOT attempted.** |

**The Stride API POST itself is not retried** — Step 9 fails fast on 4xx/5xx and surfaces the response body verbatim. Per-task idempotency on a partial batch is not guaranteed, so automatic retry could double-create some tasks while leaving others to fail again; the user reads the verbatim body and re-invokes.

`--goal <value>` accepts both `--goal value` and `--goal=value` forms, and `<value>` can be either a 1-based integer index into the seams list OR a slug-matching string (case-insensitive, hyphen-tolerant). When the seams section is absent and `--goal` is set, `/stridify` errors loudly with a verbatim "no Decomposition seams section in <path>" message rather than silently falling back to all-goals mode. The seams section itself remains freeform — the ideation skill does NOT gate it.

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

## Security

For a reviewer-facing description of what the plugin runs on your machine, the
single `/stridify` network egress, how the bearer token is handled, what is
written to disk, and what the plugin does **not** do, see
**[SECURITY.md](SECURITY.md)**. A credential-hygiene sweep of this repository is
recorded in [SUBMISSION-AUDIT.md](SUBMISSION-AUDIT.md).

**Never commit `.stride_auth.md`** — it carries your Stride bearer token. Keep it
in your project's `.gitignore`.

## License

MIT — see [LICENSE](LICENSE).
