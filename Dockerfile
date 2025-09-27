# kxboot-pipa Build Container
# Dockerfile for building kexec-based bootloader for Xiaomi Pad 6

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set up locale to avoid issues with character encoding
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install build dependencies
RUN apt-get update && apt-get install -y \
    # Build essentials
    autoconf \
    build-essential \
    make \
    cmake \
    pkg-config \
    # Cross-compilation toolchain for aarch64
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    # Archive and download tools
    wget \
    curl \
    tar \
    bzip2 \
    xz-utils \
    # Compression tools
    zstd \
    gzip \
    # initramfs tools
    cpio \
    # Additional build dependencies that might be needed by busybox/kexec-tools
    libssl-dev \
    zlib1g-dev \
    flex \
    bison \
    bc \
    # Git for potential source management
    git \
    # Android boot image tools
    android-tools-mkbootimg \
    # Utilities
    file \
    findutils \
    # Clean up to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$(uname -m)" = "x86_64" ]; then \
    wget https://go.dev/dl/go1.25.1.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.25.1.linux-amd64.tar.gz && \
    rm go1.25.1.linux-amd64.tar.gz; \
elif [ "$(uname -m)" = "aarch64" ]; then \
    wget https://go.dev/dl/go1.25.1.linux-arm64.tar.gz && \
    tar -C /usr/local -xzf go1.25.1.linux-arm64.tar.gz && \
    rm go1.25.1.linux-arm64.tar.gz; \
fi

ENV PATH="/usr/local/go/bin:${PATH}"

# Create a non-root user for building
RUN groupadd -g 1000 builder && \
    useradd -u 1000 -g builder -m -s /bin/bash builder

# Set up working directory
WORKDIR /workspace

# Change ownership of the workspace to the builder user
RUN chown builder:builder /workspace

# Switch to the builder user
USER builder

# Set up git configuration for the builder user (in case it's needed)
RUN git config --global user.name "Builder" && \
    git config --global user.email "builder@container.local"

# Default command
CMD ["/bin/bash"]

# Build instructions:
# docker build -t kxboot-pipa-builder .
# docker run --rm -v $(pwd):/workspace -it kxboot-pipa-builder
# 
# Inside the container:
# make all