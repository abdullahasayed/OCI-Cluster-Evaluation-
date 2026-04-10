#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${1:-/data}"
SIZE="${2:-16G}"
RUNTIME="${3:-60}"

if ! command -v fio >/dev/null 2>&1; then
    echo "fio is required but was not found in PATH" >&2
    exit 1
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "target directory does not exist: ${TARGET_DIR}" >&2
    exit 1
fi

ENGINE="libaio"
if fio --enghelp 2>/dev/null | grep -q '^io_uring$'; then
    ENGINE="io_uring"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
TEST_DIR="${TARGET_DIR}/.clustermax-fio-${STAMP}"
TEST_FILE="${TEST_DIR}/fio-test.bin"

mkdir -p "${TEST_DIR}"

cleanup() {
    rm -f "${TEST_FILE}" 2>/dev/null || true
    rmdir "${TEST_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

echo "Target dir : ${TARGET_DIR}"
echo "Size       : ${SIZE}"
echo "Runtime(s) : ${RUNTIME}"
echo "ioengine   : ${ENGINE}"
echo

fio --name=seqwrite \
    --filename="${TEST_FILE}" \
    --rw=write \
    --bs=1M \
    --numjobs=1 \
    --iodepth=64 \
    --ioengine="${ENGINE}" \
    --direct=1 \
    --size="${SIZE}" \
    --runtime="${RUNTIME}" \
    --time_based=1 \
    --group_reporting

echo

fio --name=seqread \
    --filename="${TEST_FILE}" \
    --rw=read \
    --bs=1M \
    --numjobs=1 \
    --iodepth=64 \
    --ioengine="${ENGINE}" \
    --direct=1 \
    --size="${SIZE}" \
    --runtime="${RUNTIME}" \
    --time_based=1 \
    --group_reporting

echo

fio --name=randread \
    --filename="${TEST_FILE}" \
    --rw=randread \
    --bs=4k \
    --numjobs=4 \
    --iodepth=64 \
    --ioengine="${ENGINE}" \
    --direct=1 \
    --size="${SIZE}" \
    --runtime="${RUNTIME}" \
    --time_based=1 \
    --group_reporting

echo

fio --name=randwrite \
    --filename="${TEST_FILE}" \
    --rw=randwrite \
    --bs=4k \
    --numjobs=4 \
    --iodepth=64 \
    --ioengine="${ENGINE}" \
    --direct=1 \
    --size="${SIZE}" \
    --runtime="${RUNTIME}" \
    --time_based=1 \
    --group_reporting
