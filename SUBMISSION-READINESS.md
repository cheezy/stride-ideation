# Community Directory Submission — Readiness Checklist

Go/no-go package for submitting the **stride-ideation** plugin to the Anthropic
community plugin directory. Produced by task **W1287**, the final task of the
submission-readiness goal. **This package stops at ready-to-submit — it does NOT
submit the form.**

- **Date:** 2026-06-22
- **Plugin:** `stride-ideation` v0.8.0
- **Public repo:** <https://github.com/cheezy/stride-ideation>
- **Marketplace (today's install path):** `cheezy/stride-marketplace`

## Prior-task status

| Task | Produced | State |
|------|----------|-------|
| **W1282** | `SUBMISSION-AUDIT.md` — baseline validation + triaged findings | ✅ Done |
| **W1283** | `plugin.json` completed (author.url, concise catalog-blurb description) | ✅ Done |
| **W1284** | Credential-hygiene sweep — **all clear**, appended to the audit | ✅ Done |
| **W1285** | `SECURITY.md` — reviewer-facing runtime model (single POST egress, no hooks.json); file-backed | ✅ Done |
| **W1286** | `README.md` made self-contained (both install paths, prerequisites, component inventory, external-service note, security link) | ✅ Done |
| **W1287** | This readiness checklist | ✅ (this doc) |

## Hard validation gate (fresh run)

```
$ claude plugin validate --strict stride-ideation/
Validating plugin manifest: .../stride-ideation/.claude-plugin/plugin.json
✔ Validation passed        (exit 0)
```

Validator: Claude Code 2.1.186. The marketplace manifest
(`stride-marketplace/.claude-plugin/marketplace.json`) also passes `--strict`
(recorded in `SUBMISSION-AUDIT.md`).

## Submission package contents

- **Security doc:** [`SECURITY.md`](SECURITY.md) — trust boundary, the single `/stridify` `POST /api/tasks/batch` egress, token handling, disk writes, and the explicit no-`hooks.json` / no-client-side-hook-execution model.
- **Listing storefront:** [`README.md`](README.md) — self-contained: both install paths, prerequisites, component inventory, external-service disclosure, security link.
- **Audit trail:** [`SUBMISSION-AUDIT.md`](SUBMISSION-AUDIT.md) — validator results + credential-hygiene all-clear.
- **Manifest:** [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) — `name: stride-ideation`, `version: 0.8.0`, MIT, author + url, homepage/repository → public repo.

## Where to submit (this author)

The account on file (`cheezy@letstango.ca`) is an **individual author**, so the
Console submission path applies (not the claude.ai Teams/Enterprise admin
directory path).

| Author type | Submission entry point |
|-------------|------------------------|
| **Individual author (this case)** | Console plugin submission — `platform.claude.com/plugins/submit` |
| Teams / Enterprise | claude.ai admin directory — `claude.ai/admin-settings/directory/submissions/plugins/new` |

> ⚠️ **Verify before submitting.** These URLs come from prior product research
> and were **not** re-confirmed against a live page at package time. Open the
> Console and confirm the current submission entry point before relying on the
> exact path. (Pitfall: don't record a submission URL as confirmed without
> verifying it is current.)

## Open follow-ups before clicking submit

1. **🔴 BLOCKER — push the plugin repo and update the marketplace pin.** The 5
   deliverable commits (`d4e14be`, `7924aa8`, `3ad5ad6`, `80d3c70`, `f0306cc`)
   plus this readiness doc are committed **locally only** (5 commits ahead of
   `origin/main` at package time). The directory pulls from the **public** repo,
   so these must be pushed to `github.com/cheezy/stride-ideation` **and** the
   `cheezy/stride-marketplace` pin for `stride-ideation` must be updated **before**
   the listing will reflect this work. *Not yet pushed — awaiting your go-ahead.*
2. **🟡 Non-blocking — trim the marketplace blurb.** The `plugins[].description`
   for `stride-ideation` in the separate `cheezy/stride-marketplace` repo is an
   oversized changelog-style paragraph (~5,510 chars — audit finding #3). It
   lives outside this plugin repo (out of this goal's scope) but reads poorly as
   a catalog blurb — worth trimming in the marketplace repo before the listing
   goes live.

## Credential rotation

**Not required.** The W1284 credential-hygiene sweep found no tracked secrets, no
hardcoded credentials/token literals (fixtures included), and no real token
literal in git history (only synthetic test placeholders in the lib test
scripts). No rotation blocks this submission.

## Go / No-Go

**Validation, manifest, security doc, README, and credential hygiene are all
GREEN.** The only hard blocker is operational, not content: **the plugin repo
must be pushed public and the marketplace pin updated** (item 1). Once pushed,
the package is ready to submit.

**This goal ends here. The submission form is intentionally NOT submitted** —
that is the user's call.
