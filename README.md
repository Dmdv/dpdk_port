# High-Performance Packet Forwarder using DPDK and Rust

This project demonstrates how to build a high-performance packet forwarder using DPDK (Data Plane Development Kit) and Rust. It's designed to showcase the power of DPDK for network packet processing.

## 🚀 Features

- Ultra-fast packet forwarding between network interfaces
- Zero-copy packet processing
- Burst-oriented packet handling for maximum performance
- Real-time statistics monitoring
- Cross-platform compilation support via Docker

## 📋 Prerequisites

### For Development (Mac OS)

- Docker Desktop
- Git
- Rust toolchain (optional, for local development)

### For Running (Linux)

- DPDK 22.11.1 or later
- Linux kernel with DPDK support
- Root privileges (for DPDK access)

## 🛠️ Building the Project

### Using Docker (Recommended for Mac OS)

```bash
# Clone the repository
git clone https://github.com/Dmdv/dpdk.git
cd dpdk

# Build the Linux binary
./build.sh
```

The build script will:

1. Create a Docker container with all necessary dependencies
2. Cross-compile the application for Linux x86_64
3. Extract the built binary (`dpdk-tutorial-linux`)

## 🏃 Running the Application

On your Linux system with DPDK installed:

```bash
# Make the binary executable
chmod +x dpdk-tutorial-linux

# Run the packet forwarder
sudo ./dpdk-tutorial-linux -p1 0 -p2 1
```

Where:

- `-p1`: First DPDK port number
- `-p2`: Second DPDK port number

## 📊 Performance Considerations

This implementation achieves high performance through:

- Zero-copy packet processing
- Burst-oriented operations (32 packets per burst)
- Efficient memory management with DPDK memory pools
- Direct hardware access via DPDK

## 🔧 Technical Details

### Memory Management

- Uses DPDK memory pools for efficient packet buffer allocation
- Pre-allocated buffers to avoid runtime allocation overhead

### Packet Processing

- Implements bidirectional packet forwarding
- Uses burst operations for better cache utilization
- Processes up to 32 packets per burst

### Statistics

- Real-time packet counters
- Statistics displayed every second
- Tracks both received and transmitted packets

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.
