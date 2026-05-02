#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: clustermax_wan_smoke.sh [WORKDIR]

Measure package install and real-world download timing from the current host.

Arguments:
  WORKDIR  Scratch directory for virtualenv and downloads.
           Default: /tmp/clustermax-wan-YYYYMMDD-HHMMSS

Environment:
  OUTDIR               Artifact directory. Default: artifacts/wan-smoke-YYYYMMDD-HHMMSS
  TORCH_SPEC           Package spec to install or download. Default: torch
  TORCH_INDEX_URL      Primary package index. Default: https://download.pytorch.org/whl/cu124
  PIP_EXTRA_INDEX_URL  Extra package index. Default: https://pypi.org/simple
  REAL_WORLD_URL       URL to fetch with curl. Default: https://huggingface.co/gpt2/resolve/main/config.json
  KEEP_REAL_WORLD_DOWNLOAD  Keep the downloaded curl artifact. Default: 1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
WORKDIR="${1:-/tmp/clustermax-wan-${STAMP}}"
OUTDIR="${OUTDIR:-artifacts/wan-smoke-${STAMP}}"
TORCH_SPEC="${TORCH_SPEC:-torch}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://pypi.org/simple}"
REAL_WORLD_URL="${REAL_WORLD_URL:-https://huggingface.co/gpt2/resolve/main/config.json}"
KEEP_REAL_WORLD_DOWNLOAD="${KEEP_REAL_WORLD_DOWNLOAD:-1}"

PIP_DOWNLOAD_DIR="${WORKDIR}/pip-downloads"
UV_VENV_DIR="${WORKDIR}/uv-venv"
REAL_WORLD_OUTPUT="${WORKDIR}/real-world-download.bin"
SUMMARY_FILE="${OUTDIR}/SUMMARY.txt"
STEPS_FILE="${OUTDIR}/steps.tsv"
FAILURES=0
LAST_STEP_RC=0

mkdir -p "${WORKDIR}" "${OUTDIR}"

have() {
    command -v "$1" >/dev/null 2>&1
}

note() {
    printf '[INFO] %s\n' "$1" | tee -a "${SUMMARY_FILE}"
}

pass() {
    printf '[PASS] %s\n' "$1" | tee -a "${SUMMARY_FILE}"
}

warn() {
    printf '[WARN] %s\n' "$1" | tee -a "${SUMMARY_FILE}"
}

skip() {
    printf '[SKIP] %s\n' "$1" | tee -a "${SUMMARY_FILE}"
}

fail() {
    printf '[FAIL] %s\n' "$1" | tee -a "${SUMMARY_FILE}"
    FAILURES=$((FAILURES + 1))
}

capture_shell() {
    local name="$1"
    local cmd="$2"

    {
        printf '$ %s\n\n' "${cmd}"
        bash -lc "${cmd}"
    } >"${OUTDIR}/${name}.txt" 2>&1 || true
}

capture_config() {
    {
        printf 'Generated: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        printf 'Working directory: %s\n' "${WORKDIR}"
        printf 'Artifact directory: %s\n' "${OUTDIR}"
        printf 'Torch spec: %s\n' "${TORCH_SPEC}"
        printf 'Torch index: %s\n' "${TORCH_INDEX_URL}"
        printf 'Extra index: %s\n' "${PIP_EXTRA_INDEX_URL}"
        printf 'Real-world URL: %s\n' "${REAL_WORLD_URL}"
        printf 'Keep curl artifact: %s\n' "${KEEP_REAL_WORLD_DOWNLOAD}"
        printf '\nRelevant proxy environment:\n'
        env | sort | grep -E '^(http_proxy|https_proxy|HTTP_PROXY|HTTPS_PROXY|no_proxy|NO_PROXY|all_proxy|ALL_PROXY)=' || true
    } >"${OUTDIR}/config.txt"
}

capture_tool_versions() {
    {
        if have uv; then
            echo '## uv'
            uv --version
            echo
        fi

        if have python3; then
            echo '## python3'
            python3 --version
            echo
            echo '## pip'
            python3 -m pip --version
            echo
        fi

        if have curl; then
            echo '## curl'
            curl --version | sed -n '1,3p'
            echo
        fi

        if have speedtest-cli; then
            echo '## speedtest-cli'
            speedtest-cli --version
            echo
        elif have speedtest; then
            echo '## speedtest'
            speedtest --version 2>&1 | sed -n '1,3p'
            echo
        fi
    } >"${OUTDIR}/tool_versions.txt" 2>&1 || true
}

run_shell_step() {
    local step_id="$1"
    local label="$2"
    local cmd="$3"
    local logfile="${OUTDIR}/${step_id}.log"
    local timing_file="${OUTDIR}/${step_id}.time"
    local start_epoch end_epoch duration rc status

    {
        printf '== %s ==\n' "${label}"
        printf 'Started: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        printf '$ %s\n\n' "${cmd}"
    } | tee "${logfile}"

    start_epoch="$(date +%s)"

    set +e
    if [[ -x /usr/bin/time ]]; then
        /usr/bin/time -p -o "${timing_file}" bash -lc "${cmd}" 2>&1 | tee -a "${logfile}"
        rc=${PIPESTATUS[0]}
    else
        bash -lc "${cmd}" 2>&1 | tee -a "${logfile}"
        rc=${PIPESTATUS[0]}
        end_epoch="$(date +%s)"
        printf 'real %s\n' "$((end_epoch - start_epoch))" >"${timing_file}"
    fi
    set -e

    end_epoch="$(date +%s)"
    duration=$((end_epoch - start_epoch))

    {
        printf '\n'
        cat "${timing_file}"
        printf 'exit_code %s\n' "${rc}"
    } | tee -a "${logfile}" >/dev/null

    if [[ "${rc}" -eq 0 ]]; then
        status="PASS"
        pass "${label}"
    else
        status="FAIL"
        fail "${label} (exit code ${rc})"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${step_id}" "${status}" "${rc}" "${duration}" "${logfile}" >>"${STEPS_FILE}"

    LAST_STEP_RC="${rc}"
    return 0
}

write_file_manifest() {
    local source_dir="$1"
    local prefix="$2"
    local files_list="${OUTDIR}/${prefix}_files.txt"
    local manifest="${OUTDIR}/${prefix}_manifest.tsv"
    local sha_file="${OUTDIR}/${prefix}_sha256.txt"

    find "${source_dir}" -maxdepth 1 -type f | sort >"${files_list}" || true
    : >"${manifest}"

    while IFS= read -r file_path; do
        [[ -n "${file_path}" ]] || continue
        printf '%s\t%s\n' "$(basename "${file_path}")" "$(wc -c <"${file_path}")" >>"${manifest}"
    done <"${files_list}"

    if [[ -s "${files_list}" ]]; then
        : >"${sha_file}"
        while IFS= read -r file_path; do
            [[ -n "${file_path}" ]] || continue
            if have sha256sum; then
                sha256sum "${file_path}" >>"${sha_file}"
            elif have shasum; then
                shasum -a 256 "${file_path}" >>"${sha_file}"
            fi
        done <"${files_list}"
    fi
}

printf 'ClusterMAX WAN/package smoke\n' >"${SUMMARY_FILE}"
printf 'Generated: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"${SUMMARY_FILE}"
printf 'Working directory: %s\n' "${WORKDIR}" >>"${SUMMARY_FILE}"
printf 'Artifact directory: %s\n\n' "${OUTDIR}" >>"${SUMMARY_FILE}"
printf 'step\tstatus\texit_code\tduration_seconds\tlog_file\n' >"${STEPS_FILE}"

capture_config
capture_tool_versions
capture_shell host_overview 'hostname; whoami; id; uname -a'
capture_shell dns_config 'if command -v resolvectl >/dev/null 2>&1; then resolvectl status; elif [[ -f /etc/resolv.conf ]]; then cat /etc/resolv.conf; fi'
capture_shell pip_config 'if command -v python3 >/dev/null 2>&1; then python3 -m pip config list -v; fi'

note "Working directory: ${WORKDIR}"
note "Artifact directory: ${OUTDIR}"
note "Configuration captured in ${OUTDIR}/config.txt"
note "Tool versions captured in ${OUTDIR}/tool_versions.txt"

echo "Working directory: ${WORKDIR}"
echo "Artifact directory: ${OUTDIR}"
echo "Torch spec       : ${TORCH_SPEC}"
echo "Torch index      : ${TORCH_INDEX_URL}"
echo "Extra index      : ${PIP_EXTRA_INDEX_URL}"
echo "Real-world URL   : ${REAL_WORLD_URL}"
echo

if have uv; then
    local_cmd=''
    rm -rf "${UV_VENV_DIR}"
    printf -v local_cmd 'uv venv %q' "${UV_VENV_DIR}"
    run_shell_step uv_venv 'uv virtualenv creation' "${local_cmd}"

    if [[ "${LAST_STEP_RC}" -eq 0 ]]; then
        printf -v local_cmd 'source %q && uv pip install %q --index-url %q --extra-index-url %q' \
            "${UV_VENV_DIR}/bin/activate" "${TORCH_SPEC}" "${TORCH_INDEX_URL}" "${PIP_EXTRA_INDEX_URL}"
        run_shell_step uv_install "uv pip install ${TORCH_SPEC}" "${local_cmd}"
    else
        skip 'Skipping uv install because venv creation failed'
    fi

    if [[ "${LAST_STEP_RC}" -eq 0 ]]; then
        printf -v local_cmd 'source %q && uv pip freeze | sort > %q' \
            "${UV_VENV_DIR}/bin/activate" "${OUTDIR}/uv_freeze.txt"
        run_shell_step uv_freeze 'uv pip freeze artifact capture' "${local_cmd}"
    else
        skip 'Skipping uv freeze artifact capture because uv install failed'
    fi
else
    skip 'uv not found; skipping uv-based install timing'
fi

if have python3; then
    local_cmd=''
    rm -rf "${PIP_DOWNLOAD_DIR}"
    mkdir -p "${PIP_DOWNLOAD_DIR}"
    printf -v local_cmd 'python3 -m pip download --dest %q --index-url %q --extra-index-url %q %q' \
        "${PIP_DOWNLOAD_DIR}" "${TORCH_INDEX_URL}" "${PIP_EXTRA_INDEX_URL}" "${TORCH_SPEC}"
    run_shell_step pip_download "pip download ${TORCH_SPEC}" "${local_cmd}"
    write_file_manifest "${PIP_DOWNLOAD_DIR}" 'pip_downloads'
else
    warn 'python3 not found; skipping pip download timing'
fi

if have curl; then
    local_cmd=''
    if [[ "${KEEP_REAL_WORLD_DOWNLOAD}" == "1" ]]; then
        printf -v local_cmd 'curl -L --fail --show-error --dump-header %q --output %q --write-out %q %q > %q' \
            "${OUTDIR}/curl_headers.txt" \
            "${REAL_WORLD_OUTPUT}" \
            $'http_code=%{http_code}\nremote_ip=%{remote_ip}\nsize_download=%{size_download}\nspeed_download=%{speed_download}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\n' \
            "${REAL_WORLD_URL}" \
            "${OUTDIR}/curl_transfer_stats.txt"
    else
        printf -v local_cmd 'curl -L --fail --show-error --dump-header %q --output /dev/null --write-out %q %q > %q' \
            "${OUTDIR}/curl_headers.txt" \
            $'http_code=%{http_code}\nremote_ip=%{remote_ip}\nsize_download=%{size_download}\nspeed_download=%{speed_download}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\n' \
            "${REAL_WORLD_URL}" \
            "${OUTDIR}/curl_transfer_stats.txt"
    fi
    run_shell_step curl_download 'curl real-world download' "${local_cmd}"
    if [[ "${KEEP_REAL_WORLD_DOWNLOAD}" == "1" && -f "${REAL_WORLD_OUTPUT}" ]]; then
        write_file_manifest "${WORKDIR}" 'workdir'
    fi
else
    warn 'curl not found; skipping real-world download timing'
fi

if have speedtest-cli; then
    run_shell_step speedtest_cli 'speedtest-cli' 'speedtest-cli'
elif have speedtest; then
    run_shell_step speedtest 'speedtest' 'speedtest'
else
    skip 'speedtest tool not found; skipping WAN throughput test'
fi

capture_shell artifacts_index "find $(printf '%q' "${OUTDIR}") -maxdepth 1 -type f | sort"
printf '\nArtifacts written to %s\n' "${OUTDIR}" | tee -a "${SUMMARY_FILE}"

if [[ "${FAILURES}" -gt 0 ]]; then
    exit 1
fi
