#!/usr/bin/env bash
# Template: ClusterMAX-style NCCL all-reduce smoke for a SLURM cluster

#SBATCH -J nccl-allreduce
#SBATCH -N 4
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-node=8
#SBATCH --cpus-per-task=16
#SBATCH -t 00:20:00

set -euo pipefail

# Adjust these to match your environment.
NCCL_TEST_BIN="${NCCL_TEST_BIN:-/opt/nccl-tests/build/all_reduce_perf}"
MPI_TYPE="${MPI_TYPE:-pmix}"

export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
export NCCL_IB_QPS_PER_CONNECTION="${NCCL_IB_QPS_PER_CONNECTION:-2}"
export NCCL_NVLS_ENABLE="${NCCL_NVLS_ENABLE:-1}"
export NCCL_BUFFSIZE="${NCCL_BUFFSIZE:-8388608}"

if command -v module >/dev/null 2>&1; then
    module load cuda || true
fi

echo "Running NCCL all-reduce smoke"
echo "Binary: ${NCCL_TEST_BIN}"
echo "Host list: ${SLURM_NODELIST}"
echo

srun --mpi="${MPI_TYPE}" \
    --exclusive \
    "${NCCL_TEST_BIN}" \
    -b 1M \
    -e 16G \
    -f 2 \
    -g 1

echo
echo "To test other collectives, swap the binary to:"
echo "  all_gather_perf"
echo "  alltoall_perf"
