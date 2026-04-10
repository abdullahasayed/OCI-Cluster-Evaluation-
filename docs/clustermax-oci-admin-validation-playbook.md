# ClusterMAX-Inspired OCI Admin Validation Playbook

## Purpose

This playbook adapts the ClusterMAX 2.0 report and the live `clustermax.ai` criteria/expectations pages into an admin-first validation workflow for a custom-provisioned OCI GPU cluster.

It is **not** a literal reimplementation of the full ClusterMAX rating process. ClusterMAX includes customer-experience, support, pricing, compliance, and market-availability dimensions that cannot be fully reproduced from inside an admin-owned cluster. The goal here is narrower and practical:

1. Provision a cluster the way a cloud admin would.
2. Validate that the cluster behaves like a serious AI training/inference environment.
3. Build operator proficiency with the tests, tools, and evidence collection ClusterMAX references.

## Source Basis

### Source 1: ClusterMAX 2.0 report

The report identifies 10 major evaluation categories:

1. Security
2. Lifecycle
3. Orchestration
4. Storage
5. Networking
6. Reliability
7. Monitoring
8. Pricing
9. Partnerships
10. Availability

The report also explicitly references or names the following test families and benchmarks:

- `uv`/`pip` PyTorch install timing as a proxy for WAN and small-file I/O health
- `speedtest-cli`
- Real-world file download testing from sources such as NGC or Hugging Face
- `nccl-tests`
- `rccl-tests`
- Stas Bekman's `all_reduce_benchmark.py`
- `fio`
- `dcgmi health -c`
- `dcgmi diag` and DCGM background checks
- `ib_write_bw`
- `ib_write_latency`
- `ibdiagnet`
- `gpu-burn`
- `gpu-fryer`
- `TinyMeg2`
- `TorchTitan`
- `Megatron-LM`
- Example inference and serving tests such as `LLM-D` and `SGLang OME`
- Broader benchmark families mentioned in the report's hiring section: GEMMs, `vllm`, `sglang`, `mlperf`, `STAC`, `HPL`

### Source 2: Live ClusterMAX site

The live site expands the report with more detailed expectations for:

- SLURM
- Kubernetes
- Standalone nodes
- Monitoring
- Health checks

It also adds live criteria details not spelled out as explicitly in the report, including:

- Audit log retention/export expectations
- Backup and disaster recovery expectations
- Specific CVE hardening expectations around NVIDIA tooling
- Explicit multi-tenant InfiniBand/RoCE isolation details
- Expectations for automated remediation and failure prediction

## What ClusterMAX Is Really Testing

The easiest way to think about ClusterMAX is:

- Can the cluster be provisioned and handed over cleanly?
- Is the software stack sane by default?
- Is storage usable and fast enough?
- Is the high-speed network configured correctly?
- Can the platform detect and remediate failures?
- Can the provider expose enough telemetry to debug real AI workloads?
- Can real multi-node workloads reach expected efficiency?

## Admin-Side Test Matrix

The table below separates what we can test directly from the admin side versus what must be reviewed manually.

| Area | What ClusterMAX checks | Admin-side status |
| --- | --- | --- |
| Security | Compliance, pentesting, tenant isolation, driver/toolkit CVE hygiene, container escape protections | Partially automatable |
| Lifecycle | Cluster delivery speed, onboarding, offboarding, UX, hidden costs, audit logs | Partially automatable |
| Orchestration | SLURM/Kubernetes correctness, RBAC, SSO, containers, topology, defaults | Highly testable |
| Storage | Filesystem/object storage presence, mounts, caching tiers, throughput, backups, snapshots | Highly testable |
| Networking | RDMA availability, MPI stack, NCCL config, collectives bandwidth, straggler detection | Highly testable |
| Reliability | SLAs, 24x7 support, passive checks, active checks, automated drain/repair | Partially automatable |
| Monitoring | Grafana, exporters, DCGM, logs, low-level hardware metrics, profiling access | Highly testable |
| Pricing | $/GPU-hr, contract terms, bundled charges | Manual review |
| Partnerships | NVIDIA/AMD/SchedMD certifications and partnerships | Manual review |
| Availability | GPU inventory, roadmap, public capacity, region coverage | Mostly manual, partly internal |

## OCI-Focused Assumptions

This playbook assumes:

- OCI GPU bare metal or VM nodes have already been provisioned.
- We control the cluster as admins, not as a public-cloud customer.
- The cluster exposes either:
  - a SLURM environment,
  - a Kubernetes environment,
  - or both.
- Nodes are Linux-based.
- Nodes are expected to support NCCL-based multi-node training.
- Shared storage is expected at `/home` and `/data` or equivalent.

If your OCI deployment diverges from these assumptions, adjust the test steps but keep the evidence structure.

## Recommended Validation Phases

### Phase 0: Create an Evidence Folder

Always capture evidence. ClusterMAX is as much about proving operational maturity as it is about running one benchmark.

```bash
mkdir -p artifacts
./scripts/clustermax_baseline_audit.sh artifacts/baseline
```

Expected evidence:

- OS, kernel, driver, CUDA, and fabric inventory
- SLURM and/or Kubernetes control plane state
- Storage mount layout
- NCCL and RDMA configuration snapshots
- Topology outputs

### Phase 1: Provisioning and Lifecycle Validation

This phase maps to ClusterMAX lifecycle and part of orchestration.

Questions to answer:

1. Was the head/login node provisioned automatically?
2. Were GPU worker nodes provisioned with drivers, RDMA, and core packages already usable?
3. Can users be added without ad hoc workarounds?
4. Are audit logs available for create/start/stop/delete and admin actions?
5. Is cluster expansion documented and repeatable?

Evidence to collect:

- Provisioning scripts or Terraform/OCI Resource Manager plans
- Time from request to cluster-ready
- Head node access method
- Audit log API or console screenshots
- User/group onboarding workflow

Admin-side commands:

```bash
id
hostname
whoami
sudo -l
ssh -o BatchMode=yes <other-node> hostname
```

Pass signal:

- No manual surgery is needed before users can log in and run basic commands.

Failure signal:

- SSH keys, home directories, packages, or user creation require manual repair after provisioning.

### Phase 2: Node and Driver Baseline

This phase maps to orchestration, reliability, monitoring, and security.

Run:

```bash
./scripts/clustermax_baseline_audit.sh artifacts/baseline
```

Manually confirm from the generated outputs:

- `nvidia-smi` reports all GPUs cleanly
- `nvidia-smi topo -m` reflects the expected local topology
- GPUDirect RDMA support is present via `nvidia_peermem` or equivalent
- `dcgmi health -c` returns clean output
- `/etc/nccl.conf` is either absent or sane
- Nodes see InfiniBand/RoCE devices consistently

Pay special attention to ClusterMAX's repeated failure modes:

- GPUDirect RDMA not enabled
- stale GPU Operator or container toolkit versions
- broken or over-tuned NCCL defaults
- driver/library inconsistency across nodes

### Phase 3: SLURM Validation

Use this phase if OCI is exposing SLURM.

### Minimum checks

```bash
sinfo
squeue
scontrol show config | grep -E 'HealthCheck|Prolog|Epilog'
scontrol show topo
module avail
which mpirun
which nvcc
srun -N1 --gpus-per-node=1 --pty bash -lc 'hostname && nvidia-smi -L'
```

Validate against ClusterMAX expectations:

- head node is accessible
- `sinfo`, `squeue`, `scontrol`, `salloc`, `sbatch`, `srun` work
- passwordless SSH exists between nodes
- `lmod`/`module` works
- `pyxis` and `enroot` are available if containers are part of your stack
- `topology.conf` exists and matches the intended fabric design
- prolog/epilog overhead is low enough that interactive job startup does not feel broken

### Multi-node NCCL smoke

Template file:

```bash
sbatch examples/slurm/nccl_allreduce.sbatch
```

What to look for:

- all_reduce succeeds
- no hangs
- bandwidth is in family with expected values for the hardware and fabric
- all_gather and all_to_all can be tested by swapping the binary name

### Optional SLURM stretch checks

- `srun -h | grep container`
- `enroot import docker://ubuntu`
- `dcgmi test --inject --gpuid 0 -f 202 -v 99999` in a non-production window to validate drain behavior

Do **not** inject failures on active production nodes.

### Phase 4: Kubernetes Validation

Use this phase if OCI is exposing Kubernetes.

### Minimum checks

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclass
kubectl get ds -A | grep -E 'dcgm|gpu|network|node-problem'
kubectl describe node <gpu-node-name>
```

Validate against ClusterMAX expectations:

- `kubeconfig` is easy to obtain
- RBAC exists and SSO integration is possible
- NVIDIA GPU Operator is installed and current
- Network Operator is installed if using InfiniBand or RoCE
- a default `ReadWriteMany`-capable StorageClass exists if shared storage is expected
- host-path or local NVMe caching options exist
- public IP / ingress path exists for serving workloads
- node problem detector or equivalent exists for drain/repair flows

### Suggested Kubernetes performance checks

1. Run a single-node GPU smoke pod.
2. Run storage smoke via `fio` inside a PVC-backed pod.
3. Run a multi-node NCCL job via MPI Operator, JobSet, or your internal equivalent.
4. Run a small PyTorch distributed training smoke test.
5. If inference is in scope, test a disaggregated serving stack such as `LLM-D` or an internal equivalent.

Example commands:

```bash
kubectl get crd | grep -E 'mpijob|jobset|pytorchjob'
kubectl get pods -A -o wide
kubectl top nodes
kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter --tail=100
```

### Phase 5: Storage Validation

This phase maps to the report's storage criteria and the site's expanded backup/DR expectations.

### Functional checks

Confirm:

- shared POSIX storage exists
- object storage exists or is intentionally out of scope
- `/home` and `/data` are mounted consistently
- local scratch or cache space exists, such as `/lvol`, local NVMe, or equivalent

Commands:

```bash
df -h
mount | grep -E '/home|/data|/lvol'
ls -ld /home /data /lvol
```

### FIO smoke

```bash
./scripts/clustermax_fio_smoke.sh /data
./scripts/clustermax_fio_smoke.sh /home
```

What to record:

- sequential read throughput
- sequential write throughput
- random read IOPS/latency
- random write IOPS/latency
- whether results degrade badly under concurrency

### Manual storage review

These are ClusterMAX-relevant but not fully exercised by a simple benchmark:

- snapshot support
- backup retention
- cross-region replication
- checkpoint durability guarantees
- immutability/WORM capability
- CMK/BYOK support

### Phase 6: WAN and Package-Install Smoke

This phase is inspired by the report's "simple tests generally complete in under one minute" approach.

Run:

```bash
./scripts/clustermax_wan_smoke.sh
```

What this checks:

- PyTorch install/download timing through `uv` if available
- fallback to `pip download` timing if `uv` is absent
- optional `speedtest-cli` if installed

Why it matters:

- Slow installs often reveal poor WAN connectivity, local-disk pathologies, or traffic shaping.

You should also add one or two **real-world** downloads relevant to your users:

- model weights from Hugging Face
- NGC container pulls
- object storage upload/download paths

### Phase 7: Fabric and Collective Validation

This is one of the most important ClusterMAX dimensions.

### Inventory and control-plane checks

```bash
ibstat
ibv_devinfo
rdma link show
cat /etc/nccl.conf
nvidia-smi topo -m
```

### Pairwise fabric tests

If `perftest` is installed:

```bash
# node A
ib_write_bw

# node B
ib_write_bw <node-a-ip-or-hostname>
```

Also test:

- `ib_write_latency`
- `ibdiagnet`
- `ibqueryerrors`
- `perfquery`

### NCCL tests

SLURM:

```bash
sbatch examples/slurm/nccl_allreduce.sbatch
```

Kubernetes:

- run the same `all_reduce_perf`, `all_gather_perf`, and `alltoall_perf` binaries inside an MPI Operator or equivalent multi-node job

Success criteria:

- jobs complete consistently
- no unexplained hangs
- bandwidth is directionally correct for the cluster design
- repeated runs do not show severe jitter or stragglers

### Phase 8: Monitoring Validation

This phase maps directly to the live Monitoring Expectations page.

Confirm the presence of:

- Grafana or equivalent
- cluster-level CPU, memory, disk, and network dashboards
- GPU metrics via DCGM
- pod/job level metrics for Kubernetes
- job accounting for SLURM
- low-level hardware telemetry
- dmesg or system-log export into a searchable backend

ClusterMAX-specific metrics to surface where possible:

- `DCGM_FI_PROF_SM_ACTIVE`
- `DCGM_FI_PROF_SM_OCCUPANCY`
- `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`
- `DCGM_FI_DEV_PCIE_REPLAY_COUNTER`
- ECC counters
- GPU temperature and power
- NVLink/XGMI throughput
- InfiniBand/RoCE throughput

Useful checks:

```bash
kubectl get svc -A | grep grafana
dcgmi health -c
nvidia-smi dmon -s pucvmet
```

If you support kernel-level profiling for users, verify that `ncu` is available without requiring unsafe privilege escalation.

### Phase 9: Passive Health Checks

This phase maps directly to ClusterMAX health-check expectations.

Minimum passive checks to implement:

- DCGM background health checks
- XID/SXID monitoring
- PCIe replay/error monitoring
- ECC monitoring
- GPU temperature monitoring
- InfiniBand/RoCE link flap monitoring
- stalled NCCL detection
- automatic drain/cordon behavior

Evidence to collect:

- alert rules
- dashboards
- drain/repair automation
- sample incident history

Useful commands:

```bash
dcgmi health -c
dmesg | grep -E 'Xid|SXid'
nvidia-smi --query-gpu=temperature.gpu,power.draw,ecc.errors.uncorrected.volatile.total --format=csv
```

### Phase 10: Active Health Checks

Run active checks during maintenance windows, on newly provisioned nodes, or on idle nodes.

Recommended sequence:

1. `dcgmi diag -r 1`
2. `dcgmi diag -r 2`
3. `dcgmi diag -r 3`
4. local NCCL tests
5. local or pairwise IB tests
6. `gpu-burn` or `gpu-fryer`
7. `TinyMeg2` if you have it
8. small distributed training smoke

Example:

```bash
dcgmi diag -r 3
```

Admin rule:

- never start with destructive or failure-injection testing on a brand-new production cluster
- start with inventory and read-only evidence capture
- move to active diagnostics on a maintenance partition or spare nodes

### Phase 11: Real Workload Validation

ClusterMAX repeatedly uses "can a real workload reach expected performance?" as the deciding factor after basic setup checks.

Recommended progression:

1. single-node PyTorch smoke
2. multi-node NCCL smoke
3. small `TorchTitan` distributed training job
4. optional `Megatron-LM` or internal training harness
5. optional inference smoke with your serving stack

Record:

- job completion success
- tokens/sec, samples/sec, or TFLOP/s/GPU
- MFU if you already track it
- convergence sanity
- outliers between nodes

If the cluster passes synthetic collectives but fails real training, suspect:

- scheduler placement
- filesystem stalls
- CPU pinning
- container/runtime mismatches
- bad NCCL or MPI environment overrides
- hidden node heterogeneity

### Phase 12: Manual Review Bucket

The following ClusterMAX criteria should be reviewed, but are not fully automatable from this admin test framework:

- SOC 2 / ISO 27001 / FedRAMP / HIPAA / PCI / GDPR status
- penetration testing scope and recency
- audit-log retention/export policy
- support response SLAs and actual support quality
- pricing model and egress costs
- roadmap for future GPUs
- public capacity availability
- vendor partnerships and certifications

Treat these as a separate checklist reviewed against internal documentation, contracts, and ticketing systems.

## Suggested Pass/Concern/Fail Rubric

### Pass

- cluster is usable immediately after provisioning
- shared storage and local scratch are mounted correctly
- NCCL and fabric tests are stable and directionally in spec
- monitoring and health checks exist and are actionable
- at least one real distributed workload succeeds without operator heroics

### Concern

- basic functionality works, but there are visible paper cuts
- repeated tuning is needed to get expected bandwidth
- monitoring exists but is shallow
- health checks detect issues but do not remediate them
- users need tribal knowledge to be productive

### Fail

- GPUDirect RDMA is not working
- NCCL tests hang or are dramatically below expectations
- shared storage is unreliable or missing
- nodes show frequent XID, ECC, or link-flap issues with no remediation
- monitoring is insufficient to explain failures
- provisioning leaves the cluster in a broken state

## File Map In This Repo

- Baseline audit: `scripts/clustermax_baseline_audit.sh`
- WAN/package smoke: `scripts/clustermax_wan_smoke.sh`
- Storage smoke: `scripts/clustermax_fio_smoke.sh`
- SLURM NCCL template: `examples/slurm/nccl_allreduce.sbatch`

## Practical Notes For OCI

- OCI-specific network, storage, and image choices will affect the outcome more than any single benchmark command.
- If your OCI cluster uses a private backend network and a separate public/login path, keep those paths separate in the evidence.
- If you use Kubernetes, validate the GPU Operator and Network Operator versions early. ClusterMAX repeatedly treats stale operator versions as a real platform quality issue.
- If you use SLURM, prioritize `topology.conf`, health checks, and container integration early. These are common differentiators between a cluster that is merely booted and a cluster that is actually usable.

## Final Recommendation

Run this playbook in three passes:

1. **Bring-up pass**: inventory, access, storage mounts, drivers, fabric visibility.
2. **Performance pass**: `fio`, NCCL, pairwise IB, WAN/package timing.
3. **Operational maturity pass**: monitoring, passive checks, active checks, real distributed workload.

That sequence matches the spirit of ClusterMAX better than jumping directly into a training benchmark before the cluster foundations are proven.
