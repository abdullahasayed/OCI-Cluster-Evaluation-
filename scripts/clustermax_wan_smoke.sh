#!/usr/bin/env bash

set -euo pipefail

WORKDIR="${1:-/tmp/clustermax-wan-$(date +%Y%m%d-%H%M%S)}"
TORCH_SPEC="${TORCH_SPEC:-torch}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://pypi.org/simple}"
REAL_WORLD_URL="${REAL_WORLD_URL:-https://huggingface.co/gpt2/resolve/main/config.json}"

mkdir -p "${WORKDIR}"

timer() {
    local label="$1"
    shift

    echo "== ${label} =="
    if command -v /usr/bin/time >/dev/null 2>&1; then
        /usr/bin/time -p "$@"
    else
        time "$@"
    fi
    echo
}

echo "Working directory: ${WORKDIR}"
echo "Torch spec       : ${TORCH_SPEC}"
echo "Torch index      : ${TORCH_INDEX_URL}"
echo "Extra index      : ${PIP_EXTRA_INDEX_URL}"
echo "Real-world URL   : ${REAL_WORLD_URL}"
echo

if command -v uv >/dev/null 2>&1; then
    rm -rf "${WORKDIR}/uv-venv"
    timer "uv PyTorch install" \
        uv venv "${WORKDIR}/uv-venv"
    # shellcheck disable=SC1091
    source "${WORKDIR}/uv-venv/bin/activate"
    timer "uv pip install ${TORCH_SPEC}" \
        uv pip install "${TORCH_SPEC}" --index-url "${TORCH_INDEX_URL}" --extra-index-url "${PIP_EXTRA_INDEX_URL}"
    deactivate
else
    echo "uv not found; skipping uv timing"
    echo
fi

if command -v python3 >/dev/null 2>&1; then
    rm -rf "${WORKDIR}/pip-downloads"
    mkdir -p "${WORKDIR}/pip-downloads"
    timer "pip download ${TORCH_SPEC}" \
        python3 -m pip download --dest "${WORKDIR}/pip-downloads" --index-url "${TORCH_INDEX_URL}" --extra-index-url "${PIP_EXTRA_INDEX_URL}" "${TORCH_SPEC}"
else
    echo "python3 not found; skipping pip timing"
    echo
fi

if command -v curl >/dev/null 2>&1; then
    timer "curl real-world download" \
        curl -L --fail --output /dev/null "${REAL_WORLD_URL}"
fi

if command -v speedtest-cli >/dev/null 2>&1; then
    timer "speedtest-cli" speedtest-cli
elif command -v speedtest >/dev/null 2>&1; then
    timer "speedtest" speedtest
else
    echo "speedtest tool not found; skipping WAN throughput test"
    echo
fi
