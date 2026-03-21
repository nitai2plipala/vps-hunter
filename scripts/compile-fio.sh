#!/bin/sh
# compile-fio.sh - Cross-compile fio as a static binary
# Docker image: alpine:latest
# Required env: ARCH, CROSS, HOST, VERSION
set -eu

# ── Validate required variables ────────────────────────────────────────────────
: "${ARCH:?ARCH is required}"
: "${CROSS:?CROSS is required}"
: "${HOST:?HOST is required}"
: "${VERSION:?VERSION is required}"

echo ">>> Building fio ${VERSION} for ${ARCH} (${CROSS})"

# ── Install build dependencies ─────────────────────────────────────────────────
apk add --no-cache \
    bash curl make tar xz \
    gcc musl-dev linux-headers \
    patch libaio-dev

# ── Download musl cross-compilation toolchain ──────────────────────────────────
# Alpine x64 本身是 musl，x64 架构直接用系统 gcc 即可，其他架构需要交叉工具链
if [ "${ARCH}" = "x64" ]; then
    CC_BIN="gcc"
    echo ">>> Using native Alpine gcc for x64"
else
    cd /tmp
    echo ">>> Downloading musl cross toolchain for ${CROSS}"
    curl -L --retry 5 --retry-delay 5 \
         --connect-timeout 30 --max-time 300 \
         "https://musl-mirror-o45mvnohof.edgeone.dev/${CROSS}-cross.tgz" \
         -o "${CROSS}-cross.tgz" || {
        echo ">>> musl.cc failed, trying github mirror..."
        curl -L --retry 5 --retry-delay 5 \
             --connect-timeout 30 --max-time 300 \
             "https://github.com/richfelker/musl-cross-make/releases/download/v0.9.9/${CROSS}-cross.tgz" \
             -o "${CROSS}-cross.tgz"
    }
    tar xf "${CROSS}-cross.tgz"
    CC_BIN="/tmp/${CROSS}-cross/bin/${CROSS}-gcc"
    echo ">>> Toolchain ready: ${CC_BIN}"
fi

# ── Build libaio as static library ────────────────────────────────────────────
LIBAIO_VERSION="0.3.113"
cd /tmp
echo ">>> Building libaio ${LIBAIO_VERSION}"
curl -L --retry 5 --retry-delay 3 \
     --connect-timeout 30 --max-time 60 \
     "http://ftp.de.debian.org/debian/pool/main/liba/libaio/libaio_${LIBAIO_VERSION}.orig.tar.gz" \
     -o libaio.tar.gz
tar xf libaio.tar.gz
cd libaio-*/src
CC="${CC_BIN}" ENABLE_SHARED=0 make
CC="${CC_BIN}" ENABLE_SHARED=0 make install prefix=/usr/local
echo ">>> libaio installed"

# ── Download and compile fio ───────────────────────────────────────────────────
cd /tmp
echo ">>> Downloading fio ${VERSION}"
curl -L --retry 5 --retry-delay 3 \
     --connect-timeout 30 --max-time 120 \
     "https://github.com/axboe/fio/archive/${VERSION}.tar.gz" \
     -o fio.tar.gz
tar xf fio.tar.gz
# GitHub 解压目录名为 fio-<tag去掉fio-前缀>，例如 tag=fio-3.41 → 目录=fio-3.41
FIO_DIR=$(tar tf fio.tar.gz 2>/dev/null | head -1 | cut -d/ -f1)
echo ">>> Entering directory: ${FIO_DIR}"
cd "${FIO_DIR}"

echo ">>> Configuring fio"
CC="${CC_BIN}" \
LDFLAGS="-static" \
./configure \
    --disable-native \
    --build-static \
    --disable-libzbc

echo ">>> Compiling fio ($(nproc) cores)"
CC="${CC_BIN}" \
LDFLAGS="-static" \
make -j"$(nproc)"

# ── Verify static linkage ──────────────────────────────────────────────────────
echo ">>> Verifying binary"
file fio
file fio | grep -q "statically linked" || {
    echo "ERROR: binary is not statically linked"
    exit 1
}

# ── Copy output ────────────────────────────────────────────────────────────────
cp fio "/io/fio_${ARCH}"
echo ">>> Done: fio_${ARCH} ($(du -sh "/io/fio_${ARCH}" | cut -f1))"
