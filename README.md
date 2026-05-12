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

## License

MIT — see [LICENSE](LICENSE).
