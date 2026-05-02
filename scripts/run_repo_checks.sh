#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: run_repo_checks.sh

Run lightweight repo checks that are safe on a laptop or CI runner.

Checks:
  - bash syntax validation for the shell scripts and SLURM template
  - shellcheck linting when shellcheck is installed
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

FILES=(
    "${ROOT_DIR}/scripts/clustermax_baseline_audit.sh"
    "${ROOT_DIR}/scripts/clustermax_fio_smoke.sh"
    "${ROOT_DIR}/scripts/clustermax_ncu_smoke.sh"
    "${ROOT_DIR}/scripts/clustermax_wan_smoke.sh"
    "${ROOT_DIR}/scripts/run_repo_checks.sh"
    "${ROOT_DIR}/examples/slurm/nccl_allreduce.sbatch"
)

echo "== bash -n =="
bash -n "${FILES[@]}"
echo "syntax check passed"

echo
echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${FILES[@]}"
    echo "shellcheck passed"
else
    echo "shellcheck not found; skipping lint"
fi

echo
echo "Repo checks passed."
