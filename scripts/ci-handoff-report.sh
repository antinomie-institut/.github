#!/usr/bin/env bash
# Build CURSOR_CI_REPORT.md and a machine-readable bundle from downloaded workflow artifacts.
set -euo pipefail

INPUT_DIR="${1:-handoff-raw}"
OUT_DIR="${2:-handoff-bundle}"

mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/CURSOR_CI_REPORT.md"
MANIFEST="$OUT_DIR/ci-handoff-manifest.json"

first_match() {
  local pattern="$1"
  while IFS= read -r -d '' file; do
    echo "$file"
    return 0
  done < <(find "$INPUT_DIR" -type f -name "$pattern" -print0 2>/dev/null || true)
  return 1
}

copy_if_present() {
  local src="$1"
  local dest="$2"
  if [[ -n "$src" && -f "$src" ]]; then
    cp "$src" "$OUT_DIR/$dest"
    return 0
  fi
  return 1
}

TRIVY_RESULTS_SRC="$(first_match 'trivy-results.json' || true)"
TRIVY_SUMMARY_SRC="$(first_match 'trivy-summary.json' || true)"
RUFF_RESULTS_SRC="$(first_match 'ruff-results.json' || true)"
RUFF_SUMMARY_SRC="$(first_match 'ruff-summary.json' || true)"
PYTHON_TEST_RESULTS_SRC="$(first_match 'python-test-results.json' || true)"
NODE_QUALITY_RESULTS_SRC="$(first_match 'node-quality-results.json' || true)"
CODEAUDIT_RESULTS_SRC="$(first_match 'codeaudit-results.json' || true)"
JOB_RESULTS_SRC="$INPUT_DIR/_job_results.json"

copy_if_present "$TRIVY_RESULTS_SRC" "trivy-results.json" || true
copy_if_present "$TRIVY_SUMMARY_SRC" "trivy-summary.json" || true
copy_if_present "$RUFF_RESULTS_SRC" "ruff-results.json" || true
copy_if_present "$RUFF_SUMMARY_SRC" "ruff-summary.json" || true
copy_if_present "$PYTHON_TEST_RESULTS_SRC" "python-test-results.json" || true
copy_if_present "$NODE_QUALITY_RESULTS_SRC" "node-quality-results.json" || true
copy_if_present "$CODEAUDIT_RESULTS_SRC" "codeaudit-results.json" || true
if [[ -f "$JOB_RESULTS_SRC" ]]; then
  cp "$JOB_RESULTS_SRC" "$OUT_DIR/_job_results.json"
fi

# Copy CodeAudit HTML files if present.
while IFS= read -r -d '' f; do
  lower="$(echo "$f" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *codeaudit* ]]; then
    cp "$f" "$OUT_DIR/codeaudit-$(basename "$f")" 2>/dev/null || true
  fi
done < <(find "$INPUT_DIR" -type f -name '*.html' -print0 2>/dev/null || true)

has_file() {
  local file="$1"
  if [[ -f "$OUT_DIR/$file" ]]; then
    echo true
  else
    echo false
  fi
}

jq -n \
  --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg input_dir "$INPUT_DIR" \
  --arg output_dir "$OUT_DIR" \
  --argjson has_job_results "$(has_file "_job_results.json")" \
  --argjson has_trivy_results "$(has_file "trivy-results.json")" \
  --argjson has_trivy_summary "$(has_file "trivy-summary.json")" \
  --argjson has_ruff_results "$(has_file "ruff-results.json")" \
  --argjson has_ruff_summary "$(has_file "ruff-summary.json")" \
  --argjson has_python_test_results "$(has_file "python-test-results.json")" \
  --argjson has_node_quality_results "$(has_file "node-quality-results.json")" \
  --argjson has_codeaudit_results "$(has_file "codeaudit-results.json")" \
  '{
    generated_at: $generated_at,
    input_dir: $input_dir,
    output_dir: $output_dir,
    files: {
      job_results: $has_job_results,
      trivy_results: $has_trivy_results,
      trivy_summary: $has_trivy_summary,
      ruff_results: $has_ruff_results,
      ruff_summary: $has_ruff_summary,
      python_test_results: $has_python_test_results,
      node_quality_results: $has_node_quality_results,
      codeaudit_results: $has_codeaudit_results
    }
  }' >"$MANIFEST"

{
  echo "# CI handoff for Cursor"
  echo
  echo "- **Workflow run**: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-unknown}"
  echo "- **Repository**: \`${GITHUB_REPOSITORY:-unknown}\`"
  echo "- **SHA**: \`${GITHUB_SHA:-unknown}\`"
  echo "- **Ref**: \`${GITHUB_REF_NAME:-unknown}\`"
  echo
  echo "## Manifest"
  echo
  echo '```json'
  cat "$MANIFEST"
  echo '```'
  echo
} >"$REPORT"

if [[ -f "$OUT_DIR/_job_results.json" ]]; then
  {
    echo "## Job results"
    echo
    echo '```json'
    cat "$OUT_DIR/_job_results.json"
    echo '```'
    echo
  } >>"$REPORT"
fi

if [[ -f "$OUT_DIR/trivy-summary.json" ]]; then
  {
    echo "## Trivy"
    echo
    vuln="$(jq -r '.counts.vulnerabilities // 0' "$OUT_DIR/trivy-summary.json")"
    secret="$(jq -r '.counts.secrets // 0' "$OUT_DIR/trivy-summary.json")"
    misconf="$(jq -r '.counts.misconfigurations // 0' "$OUT_DIR/trivy-summary.json")"
    lic="$(jq -r '.counts.licenses // 0' "$OUT_DIR/trivy-summary.json")"
    echo "| Category | Count |"
    echo "|----------|-------|"
    echo "| Vulnerabilities | ${vuln} |"
    echo "| Secrets | ${secret} |"
    echo "| Misconfigurations | ${misconf} |"
    echo "| Licenses | ${lic} |"
    echo
  } >>"$REPORT"
fi

if [[ -f "$OUT_DIR/ruff-summary.json" ]]; then
  {
    echo "## Ruff"
    echo
    diagnostics="$(jq -r '.total_diagnostics // 0' "$OUT_DIR/ruff-summary.json")"
    lint_outcome="$(jq -r '.lint_outcome // "unknown"' "$OUT_DIR/ruff-summary.json")"
    format_outcome="$(jq -r '.format_outcome // "unknown"' "$OUT_DIR/ruff-summary.json")"
    echo "- Lint outcome: **${lint_outcome}**"
    echo "- Format outcome: **${format_outcome}**"
    echo "- Diagnostics: **${diagnostics}**"
    echo
  } >>"$REPORT"
fi

if [[ -f "$OUT_DIR/python-test-results.json" ]]; then
  {
    echo "## Python tests"
    echo
    result="$(jq -r '.result // "unknown"' "$OUT_DIR/python-test-results.json")"
    reason="$(jq -r '.reason // ""' "$OUT_DIR/python-test-results.json")"
    echo "- Result: **${result}**"
    if [[ -n "$reason" ]]; then
      echo "- Reason: \`${reason}\`"
    fi
    echo
  } >>"$REPORT"
fi

if [[ -f "$OUT_DIR/node-quality-results.json" ]]; then
  {
    echo "## Node quality"
    echo
    echo "- Package manager: **$(jq -r '.package_manager // "unknown"' "$OUT_DIR/node-quality-results.json")**"
    echo "- Install: **$(jq -r '.install.status // "unknown"' "$OUT_DIR/node-quality-results.json")**"
    echo "- Lint: **$(jq -r '.lint.status // "unknown"' "$OUT_DIR/node-quality-results.json")**"
    echo "- Check: **$(jq -r '.check.status // "unknown"' "$OUT_DIR/node-quality-results.json")**"
    echo "- Build: **$(jq -r '.build.status // "unknown"' "$OUT_DIR/node-quality-results.json")**"
    echo
  } >>"$REPORT"
fi

if [[ -f "$OUT_DIR/codeaudit-results.json" ]]; then
  {
    echo "## CodeAudit (advisory)"
    echo
    echo "- Install outcome: **$(jq -r '.install_outcome // "unknown"' "$OUT_DIR/codeaudit-results.json")**"
    echo "- Filescan outcome: **$(jq -r '.filescan_outcome // "unknown"' "$OUT_DIR/codeaudit-results.json")**"
    echo
  } >>"$REPORT"
fi

{
  echo "## Files in this bundle"
  echo
  (cd "$OUT_DIR" && ls -la)
  echo
  echo "---"
  echo
  echo "Attach **CURSOR_CI_REPORT.md** and JSON outputs to Cursor for LLM triage. Fix findings until **quality-gate** is green."
} >>"$REPORT"

echo "Wrote $REPORT and $MANIFEST"
