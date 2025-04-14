#!/bin/bash

set -e  # Exit on error

# Configuration
TARGETS=("x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu")
BINARY_NAME="dpdk-tutorial"
DOCKER_IMAGE="dpdk-cross-compile"

# Clean up any existing containers
echo "Cleaning up existing containers..."
docker rm -f dpdk-builder 2>/dev/null || true

# Build the Docker image
echo "Building Docker image..."
docker build -t $DOCKER_IMAGE .

# Build for each target
for TARGET in "${TARGETS[@]}"; do
    echo "Building for target: $TARGET"
    
    # Create a container
    docker create --name dpdk-builder $DOCKER_IMAGE
    
    # Build inside container
    docker start dpdk-builder
    docker exec dpdk-builder cargo build --release --target $TARGET
    
    # Copy the binary
    OUTPUT_NAME="${BINARY_NAME}-${TARGET}"
    docker cp "dpdk-builder:/app/target/${TARGET}/release/${BINARY_NAME}" "./${OUTPUT_NAME}"
    
    # Clean up
    docker rm -f dpdk-builder
    
    # Verify the binary
    if [ -f "./${OUTPUT_NAME}" ]; then
        echo "Build complete for ${TARGET}! Binary is available as '${OUTPUT_NAME}'"
        file "./${OUTPUT_NAME}"
    else
        echo "Build failed for ${TARGET}! Check the Docker logs for errors."
        exit 1
    fi
done

echo "All builds completed successfully!" 