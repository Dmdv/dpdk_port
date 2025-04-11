#!/bin/bash

# Clean up any existing containers
docker rm -f dpdk-builder 2>/dev/null || true

# Build the Docker image
docker build -t dpdk-cross-compile .

# Create a container and copy the built binary
docker create --name dpdk-builder dpdk-cross-compile
docker cp dpdk-builder:/app/target/x86_64-unknown-linux-gnu/release/dpdk-tutorial ./dpdk-tutorial-linux
docker rm dpdk-builder

# Verify the binary
if [ -f "./dpdk-tutorial-linux" ]; then
    echo "Build complete! The Linux binary is available as 'dpdk-tutorial-linux'"
    file ./dpdk-tutorial-linux
else
    echo "Build failed! Check the Docker logs for errors."
    exit 1
fi 