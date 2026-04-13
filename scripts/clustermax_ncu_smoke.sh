#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_FILE="${1:-${ROOT_DIR}/examples/cuda/vector_add.cu}"
WORKDIR="${2:-/tmp/clustermax-ncu-$(date +%Y%m%d-%H%M%S)}"
BIN_FILE="${WORKDIR}/vector_add"

if ! command -v nvcc >/dev/null 2>&1; then
    echo "nvcc is required but was not found in PATH" >&2
    exit 1
fi

if ! command -v ncu >/dev/null 2>&1; then
    echo "ncu is required but was not found in PATH" >&2
    exit 1
fi

if [[ "${ALLOW_ROOT:-0}" != "1" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "run this as a normal user; using root defeats the purpose of the non-sudo Nsight validation" >&2
    exit 1
fi

if [[ ! -f "${SRC_FILE}" ]]; then
    echo "CUDA source file not found: ${SRC_FILE}" >&2
    exit 1
fi

mkdir -p "${WORKDIR}"

echo "Source   : ${SRC_FILE}"
echo "Workdir  : ${WORKDIR}"
echo "Binary   : ${BIN_FILE}"
echo

echo "== Build sample =="
nvcc -O3 -o "${BIN_FILE}" "${SRC_FILE}"
echo

echo "== Run sample without profiler =="
"${BIN_FILE}"
echo

echo "== Run sample under Nsight Compute =="
ncu --set launchstats --target-processes all "${BIN_FILE}"
echo

echo "Nsight Compute smoke passed for current user."
