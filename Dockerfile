# Build stage for DPDK
FROM ubuntu:22.04 as dpdk-builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-pip \
    python3-pyelftools \
    ninja-build \
    meson \
    pkg-config \
    libnuma-dev \
    libbsd-dev \
    libpcap-dev \
    libelf-dev \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Set DPDK environment variables
ENV RTE_SDK=/root/dpdk
ENV RTE_TARGET=build
ENV CC=aarch64-linux-gnu-gcc
ENV CXX=aarch64-linux-gnu-g++
ENV AR=aarch64-linux-gnu-ar
ENV RANLIB=aarch64-linux-gnu-ranlib

# Clone and build DPDK
WORKDIR /root
RUN git clone https://github.com/DPDK/dpdk.git && \
    cd dpdk && \
    git checkout v22.11 && \
    meson setup build \
    -Dplatform=generic \
    -Dprefix=/usr \
    -Dlibdir=lib/aarch64-linux-gnu \
    --cross-file config/arm/arm64_armv8_linux_gcc && \
    ninja -C build && \
    DESTDIR=/dpdk-install ninja -C build install && \
    # Verify installation
    echo "DPDK installation directory structure:" && \
    find /dpdk-install -type f -name "*.so" -o -name "*.pc" | sort && \
    echo "Contents of /dpdk-install/usr/lib/aarch64-linux-gnu:" && \
    ls -la /dpdk-install/usr/lib/aarch64-linux-gnu/ && \
    echo "Contents of /dpdk-install/usr/lib/aarch64-linux-gnu/pkgconfig:" && \
    ls -la /dpdk-install/usr/lib/aarch64-linux-gnu/pkgconfig/

# Final stage
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    libnuma1:arm64 \
    libbsd0:arm64 \
    libpcap0.8:arm64 \
    curl \
    ca-certificates \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /usr/lib/aarch64-linux-gnu/pkgconfig

# Copy DPDK installation from builder
COPY --from=dpdk-builder /dpdk-install/usr/lib/aarch64-linux-gnu/ /usr/lib/aarch64-linux-gnu/
COPY --from=dpdk-builder /dpdk-install/usr/lib/aarch64-linux-gnu/pkgconfig/ /usr/lib/aarch64-linux-gnu/pkgconfig/

# Set up cross-compilation environment
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUNNER="qemu-aarch64 -L /usr/aarch64-linux-gnu"
ENV RUSTFLAGS="-C linker=aarch64-linux-gnu-gcc -C link-arg=-L/usr/lib/aarch64-linux-gnu"
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
ENV LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu

# Verify library installation
RUN ls -la /usr/lib/aarch64-linux-gnu/ && \
    ls -la /usr/lib/aarch64-linux-gnu/pkgconfig/

# Set up workspace
WORKDIR /app

# Copy the Rust project
COPY . .

# Install Rust and cross-compilation toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . $HOME/.cargo/env && \
    rustup target add aarch64-unknown-linux-gnu

# Build the Rust project
RUN . $HOME/.cargo/env && \
    cargo build --release --target aarch64-unknown-linux-gnu