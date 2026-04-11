#include <cmath>
#include <cstdio>
#include <cstdlib>

__global__ void vector_add(const float* a, const float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}

int main() {
    const int n = 1 << 20;
    const size_t bytes = static_cast<size_t>(n) * sizeof(float);

    float* h_a = static_cast<float*>(std::malloc(bytes));
    float* h_b = static_cast<float*>(std::malloc(bytes));
    float* h_c = static_cast<float*>(std::malloc(bytes));

    if (!h_a || !h_b || !h_c) {
        std::fprintf(stderr, "host allocation failed\n");
        return 1;
    }

    for (int i = 0; i < n; ++i) {
        h_a[i] = static_cast<float>(i);
        h_b[i] = static_cast<float>(2 * i);
    }

    float* d_a = nullptr;
    float* d_b = nullptr;
    float* d_c = nullptr;

    if (cudaMalloc(&d_a, bytes) != cudaSuccess ||
        cudaMalloc(&d_b, bytes) != cudaSuccess ||
        cudaMalloc(&d_c, bytes) != cudaSuccess) {
        std::fprintf(stderr, "device allocation failed\n");
        return 1;
    }

    cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice);

    const int threads = 256;
    const int blocks = (n + threads - 1) / threads;

    vector_add<<<blocks, threads>>>(d_a, d_b, d_c, n);

    if (cudaDeviceSynchronize() != cudaSuccess) {
        std::fprintf(stderr, "kernel launch failed\n");
        return 1;
    }

    cudaMemcpy(h_c, d_c, bytes, cudaMemcpyDeviceToHost);

    for (int i = 0; i < n; ++i) {
        float expected = h_a[i] + h_b[i];
        if (std::fabs(h_c[i] - expected) > 1e-5f) {
            std::fprintf(stderr, "verification failed at index %d\n", i);
            return 1;
        }
    }

    std::puts("vector_add verification passed");

    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    std::free(h_a);
    std::free(h_b);
    std::free(h_c);
    return 0;
}
