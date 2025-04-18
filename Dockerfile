# Build stage for DPDK
FROM ubuntu:22.04 AS dpdk-builder

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
    binutils-aarch64-linux-gnu && \
    rm -rf /var/lib/apt/lists/*

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
    git fetch --tags && \
    git checkout v22.11 && \
    git show -s --oneline && \
    rm -rf build /dpdk-install && \
    meson setup build \
    -Dplatform=generic \
    -Dprefix=/usr \
    -Dlibdir=lib/aarch64-linux-gnu \
    -Dexamples=all \
    -Denable_docs=false \
    -Dtests=false \
    -Denable_drivers=net/*,bus/* \
    -Ddefault_library=shared \
    -Denable_kmods=false \
    -Dmax_lcores=128 \
    -Dmax_numa_nodes=4 \
    -Dmax_ethports=32 \
    --cross-file config/arm/arm64_armv8_linux_gcc && \
    ninja -C build && \
    DESTDIR=/dpdk-install ninja -C build install && \
    cd /dpdk-install/usr/lib/aarch64-linux-gnu && \
    ln -sf libdpdk.so.22.11 libdpdk.so && \
    mkdir -p /usr/lib/aarch64-linux-gnu/pkgconfig && \
    # Create pkg-config file
    echo "prefix=/usr" > dpdk.pc && \
    echo "libdir=\${prefix}/lib/aarch64-linux-gnu" >> dpdk.pc && \
    echo "includedir=\${prefix}/include" >> dpdk.pc && \
    echo "" >> dpdk.pc && \
    echo "Name: dpdk" >> dpdk.pc && \
    echo "Description: DPDK" >> dpdk.pc && \
    echo "Version: 22.11" >> dpdk.pc && \
    echo "Libs: -L\${libdir} -lrte_eal -lrte_mempool -lrte_ring -lrte_mbuf -lrte_net -lrte_ethdev -lrte_pci -lrte_bus_pci -lrte_kvargs -lrte_hash -lrte_timer -lrte_cmdline" >> dpdk.pc && \
    echo "Cflags: -I\${includedir}" >> dpdk.pc

# Final stage
FROM ubuntu:22.04

RUN dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y \
        libc6-dev:arm64 \
        libnuma-dev:arm64 \
        libbsd-dev:arm64 \
        libpcap-dev:arm64 \
        curl \
        ca-certificates \
        gcc-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        pkg-config \
        qemu-user-static && \
        rm -rf /var/lib/apt/lists/*

# Copy DPDK installation
COPY --from=dpdk-builder /dpdk-install/usr/lib/aarch64-linux-gnu/ /usr/lib/aarch64-linux-gnu/
COPY --from=dpdk-builder /dpdk-install/usr/lib/aarch64-linux-gnu/pkgconfig/ /usr/lib/aarch64-linux-gnu/pkgconfig/
COPY --from=dpdk-builder /dpdk-install/usr/lib/aarch64-linux-gnu/dpdk.pc /usr/lib/aarch64-linux-gnu/pkgconfig/

# Check for the presence of librte_ethdev.so
RUN ls /usr/lib/aarch64-linux-gnu | grep librte_ethdev || echo "librte_ethdev.so not found"

RUN nm -D /usr/lib/aarch64-linux-gnu/librte_ethdev.so | grep rte_eth_rx_burst
RUN nm -D /usr/lib/aarch64-linux-gnu/librte_ethdev.so | grep rte_eth_tx_burst
RUN strings /usr/lib/aarch64-linux-gnu/librte_ethdev.so | grep DPDK

# Set up cross-compilation environment
ENV PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
ENV LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu
ENV LIBRARY_PATH=/usr/lib/aarch64-linux-gnu
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUNNER="qemu-aarch64 -L /usr/aarch64-linux-gnu"
ENV RUSTFLAGS="-C linker=aarch64-linux-gnu-gcc -C link-arg=-L/usr/lib/aarch64-linux-gnu"

WORKDIR /app

# Copy the Rust project
COPY . .

# Install Rust and cross-compilation target
RUN apt-get update && \
    apt-get install -y file && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable && \
    . $HOME/.cargo/env && \
    rustup target add aarch64-unknown-linux-gnu

# Build the project
RUN . $HOME/.cargo/env && \
    cargo build --release --target aarch64-unknown-linux-gnu && \
    # Verify the binary
    file target/aarch64-unknown-linux-gnu/release/dpdk-tutorial