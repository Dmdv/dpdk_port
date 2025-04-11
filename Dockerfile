# Build stage for DPDK
FROM ubuntu:22.04 AS dpdk-builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-pip \
    python3-pyelftools \
    meson \
    ninja-build \
    pkg-config \
    libnuma-dev \
    libbsd-dev \
    libpcap-dev

# Clone and build DPDK
WORKDIR /root
RUN git clone https://github.com/DPDK/dpdk.git && \
    cd dpdk && \
    git checkout v22.11 && \
    meson setup build -Dplatform=generic && \
    cd build && \
    meson configure -Dprefix=/usr && \
    ninja && \
    DESTDIR=/dpdk-install ninja install && \
    ls -la /dpdk-install/usr/lib/x86_64-linux-gnu/

# Final stage
FROM ubuntu:22.04

# Set up repositories for both architectures
RUN dpkg --add-architecture amd64 && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y \
    libnuma1:amd64 \
    libbsd0:amd64 \
    libpcap0.8:amd64 \
    curl \
    gcc \
    pkg-config \
    gcc-x86-64-linux-gnu \
    binutils-x86-64-linux-gnu \
    libc6-dev-amd64-cross \
    libstdc++-12-dev-amd64-cross \
    libnuma-dev:amd64 \
    libbsd-dev:amd64 \
    libpcap-dev:amd64

# Copy DPDK installation from builder stage to both native and cross-compilation paths
COPY --from=dpdk-builder /dpdk-install/usr /usr
RUN mkdir -p /usr/x86_64-linux-gnu/lib /usr/x86_64-linux-gnu/include && \
    cp -r /usr/lib/x86_64-linux-gnu/* /usr/x86_64-linux-gnu/lib/ || true && \
    cp -r /usr/include/* /usr/x86_64-linux-gnu/include/ || true && \
    rm -f /usr/x86_64-linux-gnu/lib/libnuma.so && \
    rm -f /usr/x86_64-linux-gnu/lib/libbsd.so && \
    rm -f /usr/x86_64-linux-gnu/lib/libpcap.so && \
    ln -s /usr/lib/x86_64-linux-gnu/libnuma.so.1 /usr/x86_64-linux-gnu/lib/libnuma.so && \
    ln -s /usr/lib/x86_64-linux-gnu/libbsd.so.0 /usr/x86_64-linux-gnu/lib/libbsd.so && \
    ln -s /usr/lib/x86_64-linux-gnu/libpcap.so.0.8 /usr/x86_64-linux-gnu/lib/libpcap.so && \
    ln -s /usr/lib/x86_64-linux-gnu/libdpdk.so.23 /usr/x86_64-linux-gnu/lib/libdpdk.so

# Set up Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . $HOME/.cargo/env && \
    rustup target add x86_64-unknown-linux-gnu

# Set up the workspace
WORKDIR /app
COPY . .

# Set up cross-compilation environment
ENV CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUNNER="qemu-x86_64 -L /usr/x86_64-linux-gnu" \
    PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_ALL_STATIC=1 \
    PKG_CONFIG_PATH=/usr/x86_64-linux-gnu/lib/pkgconfig \
    RUSTFLAGS="-C linker=x86_64-linux-gnu-gcc -L native=/usr/x86_64-linux-gnu/lib"

# Build the Rust project
RUN . $HOME/.cargo/env && \
    cargo build --release --target x86_64-unknown-linux-gnu 