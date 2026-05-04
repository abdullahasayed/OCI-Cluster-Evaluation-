# Cluster Validation Toolkit: Who, what, where and why?  

## State of the Repo: Looking Ahead

In its current iteration, this project consists of a basic framework for benchmarking and evaluating OCI clusters in particular. Through iterative deployment of clusters varying in topolgoy and computer power the goal is to create a robust yet concise set of tools that allow for engineers to do tests in line with those done by industry analysts like SemiAnalysis.
________________________________________

## Why SemiAnalysis?

SemiAnalysis' ratings and analysis of GPU compute offerings have become industry standard. Their ClusterMax 2.0 is their latest full survey of the industry. This report continues their now signature style of combining in-depth technical analysis with state-of-the-industry knowledge that, when leveraged with their seemingly endless stream of industry contacts, creates a highly effective, granular and insightful appraisal of GPU cloud offerings today. 

The stregnth of these ratings has compelled even industry heavy hitters like Oracle to pay attention to what the folks at SemiAnalysis has to say. 

Which leads to this project. Though some of SemiAnalysis' ClusterMAX rating system relies on anecdotal information from their surveys amongst other less accessible metrics, much of what justifies their conclusions is published very plainly (https://www.clustermax.ai/). 

This, the purpose of this project is to develop a playbook that will implement many of the crucial tests relied upon by analysts like those at SemiAnalysis so that even a novice cloud engineer can quickly and effectively recieve robust feedback on the particulars of their cluster. This is not designed for granular optimization work by senior engineers, but even they will find utility in a suite of tools that quickly delivers feedback and highlights weaknesses based on metrics that are recognizable and pertinent to the whole industry. 

## Execution and Details: 

The detailed workflow lives in [docs/clustermax-oci-admin-validation-playbook.md](docs/clustermax-oci-admin-validation-playbook.md). The quick commands below are meant to make the repo easier to use from a fresh checkout.

## Repo Layout

- `docs/clustermax-oci-admin-validation-playbook.md`: the full validation playbook
- `scripts/clustermax_baseline_audit.sh`: captures a baseline evidence bundle
- `scripts/clustermax_wan_smoke.sh`: checks package install and internet egress timing
- `scripts/clustermax_fio_smoke.sh`: checks sequential and random storage behavior with `fio`
- `scripts/clustermax_ncu_smoke.sh`: validates non-root Nsight Compute access
- `scripts/run_repo_checks.sh`: lightweight repo sanity checks you can run anywhere
- `examples/slurm/nccl_allreduce.sbatch`: SLURM template for a multi-node NCCL smoke
- `examples/cuda/vector_add.cu`: minimal CUDA sample used by the Nsight smoke

## Quick Start

### 1. Verify the repo itself

Run this first from the repo root:

```bash
make test
```

What it does:

- checks that the shell scripts and the SLURM template parse cleanly with `bash -n`
- runs `shellcheck` too when it is installed

This is the safest command to run on a laptop, Mac, or CI runner because it does not require GPUs, SLURM, Kubernetes, or OCI access.

### 2. Capture a baseline on a cluster node

Run this on a Linux node in the target environment:

```bash
make baseline BASELINE_OUTDIR=artifacts/baseline
```

This writes text artifacts under `artifacts/baseline/` so you can review what the cluster actually exposed at the time of the run.

### 3. Run the smoke tests you need

WAN/package smoke:

```bash
make wan-smoke WORKDIR=/tmp/clustermax-wan WAN_OUTDIR=artifacts/wan-smoke-run1
```

Storage smoke:

```bash
make fio-smoke TARGET_DIR=/data SIZE=4G RUNTIME=30
```

Nsight Compute smoke:

```bash
make ncu-smoke NCU_WORKDIR=/tmp/clustermax-ncu
```

SLURM NCCL smoke:

```bash
sbatch examples/slurm/nccl_allreduce.sbatch
```

If your `nccl-tests` binary lives somewhere else, override it at submit time:

```bash
NCCL_TEST_BIN=/opt/nccl-tests/build/all_reduce_perf \
sbatch examples/slurm/nccl_allreduce.sbatch
```

## Which Command Should I Run?

- Use `make test` when you want to validate the repo contents themselves.
- Use `make baseline` when you want a low-risk first pass on a real cluster.
- Use `make wan-smoke`, `make fio-smoke`, or `make ncu-smoke` only when you are on the right kind of Linux node and the required tools are installed.
- Use `sbatch examples/slurm/nccl_allreduce.sbatch` only when you have a working multi-node SLURM environment.

## WAN Smoke Artifacts

The WAN/package smoke now keeps a proper evidence bundle instead of relying only on terminal output.

Typical files in `WAN_OUTDIR`:

- `SUMMARY.txt`: top-level run summary with pass/fail/skip lines
- `steps.tsv`: per-step status, exit code, duration, and log path
- `config.txt`: effective test inputs and proxy-related environment
- `tool_versions.txt`: versions for `uv`, `python3`/`pip`, `curl`, and speedtest tools when present
- `curl_headers.txt` and `curl_transfer_stats.txt`: HTTP response headers and curl timing/transfer metrics
- `pip_downloads_manifest.tsv` plus checksum/file lists: what `pip download` actually fetched
- `uv_freeze.txt`: installed package snapshot after a successful `uv` install

This makes it much easier to compare runs, debug proxy or mirror behavior, and share one directory as evidence after a failed smoke.

## Prerequisites

Minimum for repo checks:

- `bash`
- optionally `shellcheck` for stronger linting

Additional tools for cluster validation:

- `fio` for storage smoke
- `python3`, `uv`, `curl`, and optionally `speedtest-cli` for WAN/package smoke
- `nvcc` and `ncu` for the Nsight Compute smoke
- `srun` / `sbatch` plus `nccl-tests` for the SLURM NCCL smoke

## Script Help

Each runnable script exposes a help screen:

```bash
./scripts/clustermax_baseline_audit.sh --help
./scripts/clustermax_wan_smoke.sh --help
./scripts/clustermax_fio_smoke.sh --help
./scripts/clustermax_ncu_smoke.sh --help
./scripts/run_repo_checks.sh --help
```

## Notes

- `artifacts/` is ignored in git because it is generated output.
- The default `fio` settings are intentionally heavier than a tiny smoke test. For a quick confidence check, start with a smaller size such as `SIZE=4G` and a shorter runtime such as `RUNTIME=30`.
- The WAN smoke intentionally exercises real download paths. If you are validating through a proxy or a private mirror, set `TORCH_INDEX_URL`, `PIP_EXTRA_INDEX_URL`, or `REAL_WORLD_URL` before running it.
- Set `KEEP_REAL_WORLD_DOWNLOAD=0` if you want curl timing artifacts without retaining the downloaded payload itself.
