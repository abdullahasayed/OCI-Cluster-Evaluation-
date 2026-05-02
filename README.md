# OCI Cluster Validation Toolkit

This repo packages a practical, admin-first validation flow for an OCI GPU cluster inspired by ClusterMAX-style checks. It is mainly a docs-and-scripts repo: the "tests" here are operational smoke tests and evidence-capture scripts, not application unit tests.

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
make baseline OUTDIR=artifacts/baseline
```

This writes text artifacts under `artifacts/baseline/` so you can review what the cluster actually exposed at the time of the run.

### 3. Run the smoke tests you need

WAN/package smoke:

```bash
make wan-smoke WORKDIR=/tmp/clustermax-wan
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
