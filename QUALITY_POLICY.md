# Antiphoria Quality Policy

This repository defines reusable, repo-agnostic GitHub Actions quality gates for `antiphoria`.
The policy is intentionally modular so each repository can explicitly opt into only the gates it wants.

## Architecture

The shared orchestrator is:

- [.github/workflows/quality-gate.yml](.github/workflows/quality-gate.yml)

Atomic reusable workers:

- [.github/workflows/qg-trivy.yml](.github/workflows/qg-trivy.yml)
- [.github/workflows/qg-python-ruff.yml](.github/workflows/qg-python-ruff.yml)
- [.github/workflows/qg-python-test.yml](.github/workflows/qg-python-test.yml)
- [.github/workflows/qg-node-quality.yml](.github/workflows/qg-node-quality.yml)
- [.github/workflows/qg-gitleaks.yml](.github/workflows/qg-gitleaks.yml)
- [.github/workflows/qg-ci-handoff.yml](.github/workflows/qg-ci-handoff.yml)

Externally callable security signal workflow:

- [.github/workflows/scorecard.yml](.github/workflows/scorecard.yml)

## Monolith vs Badge Workflows

Use two complementary patterns in member repos:

### Monolith (branch protection + handoff)

Stack-specific templates in [workflow-templates](workflow-templates):

- [org-quality-python.yml](workflow-templates/org-quality-python.yml)
- [org-quality-node.yml](workflow-templates/org-quality-node.yml)
- [org-quality-security.yml](workflow-templates/org-quality-security.yml)

A legacy combined template remains available:

- [org-quality.yml](workflow-templates/org-quality.yml)

These call the full `quality-gate.yml` orchestrator. Enable `run-ci-handoff: true` here only.
In branch protection/rulesets, require the aggregate check: `quality-gate / quality-gate`.

### Badge sidecars (README cosmetics)

Badge templates call atomic workers directly (no orchestrator overhead):

- [org-badge-ruff.yml](workflow-templates/org-badge-ruff.yml) → `CI Lint`
- [org-badge-test.yml](workflow-templates/org-badge-test.yml) → `CI Tests`
- [org-badge-trivy.yml](workflow-templates/org-badge-trivy.yml) → `CI Trivy`
- [org-badge-gitleaks.yml](workflow-templates/org-badge-gitleaks.yml) → `Gitleaks`
- [org-badge-scorecard.yml](workflow-templates/org-badge-scorecard.yml) → OpenSSF Scorecard

Scorecard also has a legacy alias: [org-quality-scorecard.yml](workflow-templates/org-quality-scorecard.yml).

Badge workflows are cosmetic sidecars. They do not replace the monolithic required check.

### README badge markdown

Replace `REPO` with the repository name (e.g. `antiphoria-slop-provenance`):

```markdown
[![CI Lint](https://github.com/antiphoria/REPO/actions/workflows/ci-lint.yml/badge.svg)](https://github.com/antiphoria/REPO/actions/workflows/ci-lint.yml)
[![CI Tests](https://github.com/antiphoria/REPO/actions/workflows/ci-tests.yml/badge.svg)](https://github.com/antiphoria/REPO/actions/workflows/ci-tests.yml)
[![CI Trivy](https://github.com/antiphoria/REPO/actions/workflows/ci-trivy.yml/badge.svg)](https://github.com/antiphoria/REPO/actions/workflows/ci-trivy.yml)
[![Gitleaks](https://github.com/antiphoria/REPO/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/antiphoria/REPO/actions/workflows/gitleaks.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/antiphoria/REPO/badge)](https://securityscorecards.dev/viewer/?uri=github.com/antiphoria/REPO)
```

Member repos must keep one workflow file per badge under `.github/workflows/` (GitHub URL constraint).
Copy from org badge templates; filenames should match the badge URLs above.

## Gate Toggle Contract

All gate toggles are explicit boolean inputs on the orchestrator:

- `run-trivy`
- `run-python-ruff`
- `run-python-test`
- `run-node-quality`
- `run-ci-handoff`

### Default-Off Rule (Required)

Any newly added scanner/linter must follow this contract:

```yaml
inputs:
  run-new-linter:
    type: boolean
    default: false
```

This prevents accidental org-wide rollout of new tools.

## Blocking vs Advisory

All orchestrator jobs are blocking when enabled (aggregated by final `quality-gate`):

- `detect`
- `trivy` (when enabled)
- `python-ruff` (when enabled and Python detected)
- `python-test` (when enabled and Python detected)
- `node-quality` (when enabled and Node detected)

Python SAST is covered by Ruff `S` rules (flake8-bandit) in `qg-python-ruff`, not a separate gate.

## Repo-Agnostic Guardrails

- No repository-specific system build logic in shared workflows.
- No shared `liboqs` build/install in org baseline.
- No Trivy SARIF/code-scanning upload path in org baseline.
- Python gates run only when Python files are detected.
- Node gates run only when `package.json` is detected.

## Supply-Chain Hardening

Pinned versions live in:

- [ci/requirements-ruff.txt](ci/requirements-ruff.txt) (hashed)
- [ci/requirements-tools.txt](ci/requirements-tools.txt)

Current hardening:

- GitHub Actions are pinned by immutable commit SHA in workflows.
- Trivy binary is downloaded directly and verified against a pinned SHA-256 hash.
  No third-party GitHub Action is used for the scan invocation.
- Ruff installs from a pinned and hashed requirement file.
- Gitleaks uses a pinned `gitleaks-action` commit SHA.

## Structured JSON Artifact Contract

Each gate writes dedicated JSON for machine triage:

- Trivy: `trivy-results.json` + `trivy-summary.json`
- Ruff: `ruff-results.json` + `ruff-summary.json`
- Python tests: `python-test-results.json`
- Node: `node-quality-results.json`

Artifacts are uploaded separately per gate:

- `qg-trivy-<run_id>`
- `qg-python-ruff-<run_id>`
- `qg-python-test-<run_id>`
- `qg-node-quality-<run_id>`
- `qg-ci-handoff-<run_id>`

The handoff bundle includes:

- `CURSOR_CI_REPORT.md`
- `ci-handoff-manifest.json`
- copied per-gate JSON files when available

## Required Status Check

In branch protection/rulesets, require the check named:

- `quality-gate / quality-gate`

This is the final aggregate gate job from the monolithic caller.

## Pilot and Rollout

1. Add badge workflows from `org-badge-*.yml` templates.
2. Add monolithic `org-quality-python.yml` (or stack-specific equivalent) for branch protection.
3. Validate badge URLs and handoff artifact on the monolith run.
4. Roll out badge templates org-wide.
5. Keep `org-quality.yml` only for legacy compatibility.
