# ClusterMAX-OCI Smoke Test: Summary

This summary is the first real-world stress test of the playbook described in this repo: a deliberately small, single-day run of the ClusterMAX-inspired validation flow against an actual OCI node. The goal of this project — building a concise, repeatable toolkit that lets any GPU Cloud engineer reproduce the kind of analysis SemiAnalysis brings to bear in their ClusterMAX 2.0 ratings — depends on the methodology surviving first contact with real hardware. This run was that first contact, and it confirms the approach is on the right track: the evidence-first discipline held up, the scripts behaved as written, and the gaps that remain are the gaps the playbook itself predicts on a single-VM worker. What follows is a one-page distillation of what ran, what it produced, and what is left to graduate this from a promising methodology into a defensible cluster sign-off.

---

## Run context

| Field | Value |
|---|---|
| Window | 2026-05-02 14:17 – 14:54 UTC |
| Host | `oke-cese6fqqujq-nnibjvr7vnq-slshwjl7z3a-0` (single OKE worker, KVM-virtualised) |
| GPU | 1× NVIDIA A10, 23 028 MiB, driver 570.172.08 |
| OS / kernel | Ubuntu 22.04.5 LTS, 5.15.0-1074-oracle |
| CPU / RAM | 30 vCPU Intel Xeon Platinum 8358 / 235 GiB |
| Verdict | **Promising methodology, incomplete cluster verdict** |

---

## Phase coverage

| Phase | Status | Outcome |
|---|---|---|
| 0 – Repo sanity (`make test`) | Ran | All shell assets parse; shellcheck clean. Pre-flight gate works. |
| 1 – Lifecycle | Implicit | Provisioning inherited from OKE. |
| 2 – Node + driver baseline | Ran | 25 evidence files written; `SUMMARY.txt` emitted PASS/WARN/INFO labels honestly. |
| 3 – SLURM | Skipped | OKE worker context; no control plane to reach. |
| 4 – Kubernetes | Partial | Node clearly OKE-managed (kubelet, `kube-ipvs0`); kubectl-side checks not captured. |
| 5 – Storage (FIO) | Ran | Ran against boot volume `sda1` because no `/data` was mounted. |
| 6 – WAN + package install | Ran | Egress to PyTorch index and Hugging Face validated. |
| 7 – Fabric + NCCL | Not meaningful | Single VM, no IB HCA, no peer node. |
| 8 – Nsight Compute | Ran | Confirmed non-root `ncu` reachability on the A10. |
| 9 – Passive health | Implicit | One `dcgmi health -c` snapshot in baseline; no continuous monitoring. |
| 10 – Active stress | Not run | No `dcgmi diag`, no `gpu-burn`. |
| 11 – Real workload | Not run | No TorchTitan / Megatron / inference smoke. |
| 12 – Governance | Out of scope | Belongs against contracts, not scripts. |

---

## Headline results from the smokes that ran

**Phase 2 — Baseline.** 25 self-documenting capture files. Single A10 (CC 8.6), driver 570.172.08, P0 idle at 54 °C / 81.89 W. RDMA kernel modules (`mlx5_ib`, `mlx5_core`, `nvidia_peermem`) loaded but `ibstat`/`ibv_devinfo` empty — the kernel is provisioned for a fabric this VM does not have. HPC-X 2.23 and OpenMPI 5.0.8 pre-staged via Environment Modules. DCGM reports "Healthy."

**Phase 5 — FIO storage** (against `/tmp/fio-test` on `sda1`, not real shared storage):

| Workload | Throughput | IOPS | Avg / p99 latency | Util |
|---|---|---|---|---|
| Seq write 1 MiB qd=64 | 256 MiB/s | 256 | 249 ms / 472 ms | 99.6% |
| Seq read 1 MiB qd=64 | 242 MiB/s | 242 | 264 ms / 268 ms | 99.7% |
| Rand read 4 KiB qd=64 ×4 | 103 MiB/s | 26.4 k | 9.7 ms / 82.3 ms | 99.7% |
| Rand write 4 KiB qd=64 ×4 | 98.3 MiB/s | 25.2 k | 10.2 ms / 79.2 ms | 99.7% |

Device fully saturated; sequential fat tail (p99 472 ms write) is real, but this is the OS volume, not the AI storage tier.

**Phase 6 — WAN.** `pip download torch` resolved 30 wheels (~2.6 GiB closure including the full CUDA 13 stack) in **22.82 s real** — roughly 1.0–1.2 Gbps effective egress to the PyTorch CDN, no proxy or DNS stalls in the path. Hugging Face `gpt2/config.json` returned 200 OK in 0.19 s (665 B body — proves TLS works, not much else). `uv` and `speedtest-cli` were absent and were correctly noted as skipped rather than silently failed.

**Phase 8 — Nsight Compute.** As non-root `ubuntu`, `ncu --set launchstats` attached to `vector_add` (grid 4096×1×1, block 256×1×1, Stream 7, CC 8.6), profiled one pass, disconnected cleanly. The `==WARNING== No metrics to collect found in sections` line is honest: the smoke proves the access path, not the full counter policy.

---

## What this run proves about the methodology

- **Scope honesty.** The toolkit refuses to over-claim from a single VM. WARN/PASS/INFO labels distinguish "this is broken" from "this is not applicable here."
- **Evidence first.** Every script writes to stable, stamped artifact directories that diff cleanly across runs — 25 baseline files, a fio log, a WAN bundle with a 30-wheel manifest, an Nsight session log.
- **Conservative dependency chain.** The five phases that ran are exactly the five the playbook calls safe on a VM worker, in the order it asks for.
- **Real operational guardrails.** `clustermax_ncu_smoke.sh` refuses to run as root by default; `clustermax_fio_smoke.sh` auto-selects `io_uring`/`libaio`, stamps its scratch dir, and traps EXIT to clean up; `clustermax_wan_smoke.sh` is fully env-var configurable and logs missing tools rather than failing.

---

## What this run cannot conclude (and what to do next)

The high-stakes phases — fabric, multi-node NCCL, real distributed training — are **not reachable from a single OKE VM** and remain open work. To graduate this from a methodology pilot into a defensible cluster verdict:

1. Stand up a 2-node bare-metal RDMA worker pool on the OCI cluster network; rerun baseline to diff driver/library skew across nodes.
2. Mount real shared storage (FSS or block-volume `/data`) and rerun fio with concurrency sweeps (1, 4, 16) to characterise variance.
3. Install `uv` in the golden image; add a multi-GB Hugging Face checkpoint to `REAL_WORLD_URL` so the curl timing artifacts mean something.
4. Run `sbatch examples/slurm/nccl_allreduce.sbatch` on the bare-metal pair; pairwise `ib_write_bw` / `ib_write_latency` between peers.
5. Rerun `ncu` against a non-trivial kernel with `--set full` (or a curated metric set) to validate the counter policy, not just access.
6. Schedule a maintenance window for `dcgmi diag -r 3`, then a small TorchTitan or Megatron smoke tracking MFU and per-node tokens/s.

---

*Treat this run as the methodology pilot, not the cluster verdict. Everything that needed to work on a single A10 OKE VM did. Everything that did not run was correctly out of scope for this hardware.*
