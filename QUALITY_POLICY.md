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
- [.github/workflows/qg-python-codeaudit.yml](.github/workflows/qg-python-codeaudit.yml)
- [.github/workflows/qg-node-quality.yml](.github/workflows/qg-node-quality.yml)
- [.github/workflows/qg-ci-handoff.yml](.github/workflows/qg-ci-handoff.yml)

## Caller Templates

Use stack-specific templates in [workflow-templates](workflow-templates):

- [org-quality-python.yml](workflow-templates/org-quality-python.yml)
- [org-quality-node.yml](workflow-templates/org-quality-node.yml)
- [org-quality-security.yml](workflow-templates/org-quality-security.yml)

A legacy combined template remains available:

- [org-quality.yml](workflow-templates/org-quality.yml)

## Gate Toggle Contract

All gate toggles are explicit boolean inputs on the orchestrator:

- `run-trivy`
- `run-python-ruff`
- `run-python-test`
- `run-python-codeaudit`
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

Blocking jobs (aggregated by final `quality-gate`):

- `detect`
- `trivy` (when enabled)
- `python-ruff` (when enabled and Python detected)
- `python-test` (when enabled and Python detected)
- `node-quality` (when enabled and Node detected)

Advisory job:

- `python-codeaudit` (when enabled and Python detected)

`python-codeaudit` always emits structured JSON artifacts, but it does not block `quality-gate`.

## Repo-Agnostic Guardrails

- No repository-specific system build logic in shared workflows.
- No shared `liboqs` build/install in org baseline.
- No Trivy SARIF/code-scanning upload path in org baseline.
- Python gates run only when Python files are detected.
- Node gates run only when `package.json` is detected.

## Supply-Chain Hardening

Pinned versions live in:

- [ci/requirements-ruff.txt](ci/requirements-ruff.txt) (hashed)
- [ci/requirements-codeaudit.txt](ci/requirements-codeaudit.txt) (pinned)
- [ci/requirements-tools.txt](ci/requirements-tools.txt)

Current hardening:

- GitHub Actions are pinned by immutable commit SHA in workflows.
- Trivy action is pinned, and scanner version is explicit (`trivy-version` input).
- Ruff installs from a pinned and hashed requirement file.
- CodeAudit is pinned; the workflow verifies the top-level wheel SHA before install.

## Structured JSON Artifact Contract

Each gate writes dedicated JSON for machine triage:

- Trivy: `trivy-results.json` + `trivy-summary.json`
- Ruff: `ruff-results.json` + `ruff-summary.json`
- Python tests: `python-test-results.json`
- Node: `node-quality-results.json`
- CodeAudit: `codeaudit-results.json`

Artifacts are uploaded separately per gate:

- `qg-trivy-<run_id>`
- `qg-python-ruff-<run_id>`
- `qg-python-test-<run_id>`
- `qg-node-quality-<run_id>`
- `qg-python-codeaudit-<run_id>`
- `qg-ci-handoff-<run_id>`

The handoff bundle includes:

- `CURSOR_CI_REPORT.md`
- `ci-handoff-manifest.json`
- copied per-gate JSON files when available

## Required Status Check

In branch protection/rulesets, require the check named:

- `quality-gate`

This is the final aggregate gate job.

## Pilot and Rollout

1. Pilot in one representative Python repo using `org-quality-python.yml`.
2. Pilot in one representative Node repo using `org-quality-node.yml`.
3. Validate artifact separation and JSON outputs in both pilots.
4. Roll out stack-specific templates org-wide.
5. Keep `org-quality.yml` only for legacy compatibility.
