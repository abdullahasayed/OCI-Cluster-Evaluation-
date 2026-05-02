SHELL := /usr/bin/env bash

BASELINE_OUTDIR ?= artifacts/baseline
WAN_OUTDIR ?=
WORKDIR ?= /tmp/clustermax-wan
TARGET_DIR ?= /data
SIZE ?= 16G
RUNTIME ?= 60
SRC_FILE ?= examples/cuda/vector_add.cu
NCU_WORKDIR ?= /tmp/clustermax-ncu

.DEFAULT_GOAL := help

.PHONY: help test baseline wan-smoke fio-smoke ncu-smoke

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make test                                               Run local repo checks.' \
		'  make baseline BASELINE_OUTDIR=artifacts/run1            Capture baseline cluster evidence.' \
		'  make wan-smoke WORKDIR=/tmp/wan WAN_OUTDIR=artifacts/wan-run1' \
		'                                                          Run package install / WAN smoke.' \
		'  make fio-smoke TARGET_DIR=/data                         Run storage smoke on a mounted path.' \
		'  make ncu-smoke NCU_WORKDIR=/tmp/ncu                     Run the Nsight Compute smoke test.' \
		'' \
		'Notes:' \
		'  - `make test` is safe to run from a laptop or CI runner.' \
		'  - The smoke targets expect a Linux OCI cluster environment with the required tools installed.' \
		'  - Run `./scripts/<name>.sh --help` for script-specific arguments.'

test:
	./scripts/run_repo_checks.sh

baseline:
	./scripts/clustermax_baseline_audit.sh "$(BASELINE_OUTDIR)"

wan-smoke:
	OUTDIR="$(WAN_OUTDIR)" ./scripts/clustermax_wan_smoke.sh "$(WORKDIR)"

fio-smoke:
	./scripts/clustermax_fio_smoke.sh "$(TARGET_DIR)" "$(SIZE)" "$(RUNTIME)"

ncu-smoke:
	./scripts/clustermax_ncu_smoke.sh "$(SRC_FILE)" "$(NCU_WORKDIR)"
