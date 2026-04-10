#!/usr/bin/env bash

set -euo pipefail

OUTDIR="${1:-artifacts/clustermax-baseline-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${OUTDIR}"

have() {
    command -v "$1" >/dev/null 2>&1
}

capture() {
    local name="$1"
    shift
    local args=("$@")

    {
        printf '$ %q' "${args[0]}"
        for arg in "${args[@]:1}"; do
            printf ' %q' "$arg"
        done
        printf '\n\n'
        "${args[@]}"
    } >"${OUTDIR}/${name}.txt" 2>&1 || true
}

capture_shell() {
    local name="$1"
    local cmd="$2"

    {
        printf '$ %s\n\n' "${cmd}"
        bash -lc "${cmd}"
    } >"${OUTDIR}/${name}.txt" 2>&1 || true
}

summary() {
    local label="$1"
    local cmd="$2"

    if bash -lc "${cmd}" >/dev/null 2>&1; then
        printf '[PASS] %s\n' "${label}" >>"${OUTDIR}/SUMMARY.txt"
    else
        printf '[WARN] %s\n' "${label}" >>"${OUTDIR}/SUMMARY.txt"
    fi
}

printf 'ClusterMAX baseline audit\n' >"${OUTDIR}/SUMMARY.txt"
printf 'Generated: %s\n\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"${OUTDIR}/SUMMARY.txt"

capture_shell host_overview 'hostname; whoami; id; uname -a; uptime'

if [[ -f /etc/os-release ]]; then
    capture os_release cat /etc/os-release
fi

if have lscpu; then
    capture cpu_inventory lscpu
fi

if have free; then
    capture memory_inventory free -h
fi

if have lsblk; then
    capture block_devices lsblk
fi

if have df; then
    capture df_h df -h
fi

capture_shell mount_layout 'mount | grep -E "/home|/data|/lvol" || true'

if have ip; then
    capture ip_link ip -br link
    capture ip_addr ip -br addr
fi

capture_shell rdma_modules 'lsmod | grep -E "nvidia_peermem|nv_peer_mem|mlx5|ib_" || true'

if have nvidia-smi; then
    capture gpu_list nvidia-smi -L
    capture gpu_topology nvidia-smi topo -m
    capture gpu_query nvidia-smi --query-gpu=index,name,driver_version,pstate,pci.bus_id,temperature.gpu,power.draw,memory.total --format=csv
fi

if have dcgmi; then
    capture dcgm_discovery dcgmi discovery -l
    capture dcgm_health dcgmi health -c
fi

if [[ -f /etc/nccl.conf ]]; then
    capture nccl_conf cat /etc/nccl.conf
else
    printf '/etc/nccl.conf not present\n' >"${OUTDIR}/nccl_conf.txt"
fi

capture_shell env_nccl 'env | sort | grep "^NCCL_" || true'

if have ibstat; then
    capture ibstat ibstat
fi

if have ibv_devinfo; then
    capture ibv_devinfo ibv_devinfo
fi

if have rdma; then
    capture rdma_link rdma link show
fi

if have ibdiagnet; then
    capture ibdiagnet_version ibdiagnet --version
fi

if have docker; then
    capture docker_version docker version
fi

if have enroot; then
    capture enroot_version enroot version
fi

if have sinfo; then
    capture slurm_sinfo sinfo
    capture_shell slurm_health_config 'scontrol show config | grep -E "HealthCheck|Prolog|Epilog|SlurmctldHost|Topology" || true'
    capture slurm_topology scontrol show topo
    capture slurm_partitions scontrol show partition
fi

if have srun; then
    capture_shell slurm_container_help 'srun -h | grep container || true'
fi

if have module; then
    capture_shell module_avail 'module avail'
else
    capture_shell module_avail 'type module || true'
fi

if have nvcc; then
    capture nvcc_version nvcc --version
fi

if have mpirun; then
    capture mpi_version mpirun --version
fi

if have kubectl; then
    capture k8s_nodes kubectl get nodes -o wide
    capture k8s_pods kubectl get pods -A -o wide
    capture k8s_storageclass kubectl get storageclass
    capture_shell k8s_gpu_stack 'kubectl get ds -A | grep -E "dcgm|gpu|network|node-problem" || true'
fi

summary 'NVIDIA GPUs visible via nvidia-smi' 'command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L | grep -q "GPU "'
summary 'DCGM available' 'command -v dcgmi >/dev/null 2>&1'
summary 'GPUDirect/RDMA kernel module visible' 'lsmod | grep -Eq "nvidia_peermem|nv_peer_mem"'
summary 'NCCL config file present or intentionally omitted' 'test -f /etc/nccl.conf || true'
summary 'SLURM present' 'command -v sinfo >/dev/null 2>&1'
summary 'Kubernetes present' 'command -v kubectl >/dev/null 2>&1'
summary 'Shared mount hints present' 'mount | grep -Eq "/home|/data|/lvol"'

printf '\nArtifacts written to %s\n' "${OUTDIR}" | tee -a "${OUTDIR}/SUMMARY.txt"
