#!/bin/bash

# Build the Docker image
docker build -t dpdk-cross-compile .

# Create a container and copy the built binary
docker create --name dpdk-builder dpdk-cross-compile
docker cp dpdk-builder:/app/target/x86_64-unknown-linux-gnu/release/dpdk-tutorial ./dpdk-tutorial-linux
docker rm dpdk-builder

echo "Build complete! The Linux binary is available as 'dpdk-tutorial-linux'" 