FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Proxy for amd64 packages only (primary: aptcacheserver:8000, fallback: localhost:8080)
RUN (bash -c 'echo > /dev/tcp/aptcacheserver/8000' 2>/dev/null \
     && echo 'Acquire::http::Proxy "http://aptcacheserver:8000";' \
     || echo 'Acquire::http::Proxy "http://localhost:8080";') \
     > /etc/apt/apt.conf.d/01proxy

RUN dpkg --add-architecture arm64

# Add ports.ubuntu.com for arm64 packages (bypasses proxy)
RUN echo '\
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse\n\
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse\n\
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse\
' >> /etc/apt/sources.list && \
    sed -i 's/^deb http/deb [arch=amd64] http/g' /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    make \
    bc \
    flex \
    bison \
    libssl-dev \
    libssl-dev:arm64 \
    libelf-dev \
    libelf-dev:arm64 \
    libdw-dev \
    debhelper \
    dpkg-dev \
    fakeroot \
    cpio \
    rsync \
    kmod \
    lsb-release \
    python3 \
    mmdebstrap \
    qemu-user-static \
    binfmt-support \
    genext2fs \
    e2fsprogs \
    debian-archive-keyring \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /sdk
