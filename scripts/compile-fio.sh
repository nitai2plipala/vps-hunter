#!/bin/bash
# compile-fio.sh - Cross-compile fio as a static binary using musl toolchain
# Called inside phusion/holy-build-box-64 container
# Required env: ARCH, CROSS, HOST, VERSION
set -euo pipefail
export MANPATH="${MANPATH:-}"   # 防止 Holy Build Box activate 脚本报 unbound variable

# ── Validate required variables ────────────────────────────────────────────────
: "${ARCH:?ARCH is required}"
: "${CROSS:?CROSS is required}"
: "${HOST:?HOST is required}"
: "${VERSION:?VERSION is required}"

echo ">>> Building fio ${VERSION} for ${ARCH} (${CROSS})"

# ── Activate Holy Build Box lib environment ────────────────────────────────────
source /hbb/activate
set -x

# ── Fix obsolete CentOS repos ──────────────────────────────────────────────────
cd /etc/yum.repos.d/
rm -f CentOS-Base.repo CentOS-SCLo-scl-rh.repo CentOS-SCLo-scl.repo \
      CentOS-fasttrack.repo CentOS-x86_64-kernel.repo 2>/dev/null || true

yum install -y yum-plugin-ovl 2>/dev/null || true   # fix docker overlay fs
yum install -y xz

# ── Download musl cross-compilation toolchain ──────────────────────────────────
cd ~
TOOLCHAIN_URL="https://musl-mirror-xdhpcgbg.edgeone.dev/${CROSS}-cross.tgz"
echo ">>> Downloading toolchain: ${TOOLCHAIN_URL}"
curl -L -4 --retry 5 --retry-delay 3 --connect-timeout 20 \
  "${TOOLCHAIN_URL}" -o "${CROSS}-cross.tgz"
tar xf "${CROSS}-cross.tgz"

CC_BIN="/root/${CROSS}-cross/bin/${CROSS}-gcc"

# ── Build libaio as a static library ──────────────────────────────────────────
LIBAIO_VERSION="0.3.113"
cd ~
echo ">>> Building libaio ${LIBAIO_VERSION}"
curl -L -4 --retry 5 --retry-delay 3 --connect-timeout 20 \
  "http://ftp.de.debian.org/debian/pool/main/liba/libaio/libaio_${LIBAIO_VERSION}.orig.tar.gz" \
  -o libaio.tar.gz
tar xf libaio.tar.gz
cd libaio-*/src
CC="${CC_BIN}" ENABLE_SHARED=0 make prefix=/hbb_exe install

# ── Switch to Holy Build Box exe environment ──────────────────────────────────
source /hbb_exe/activate

# ── Download and compile fio ──────────────────────────────────────────────────
cd ~
FIO_TAG="${VERSION}"
FIO_DIR="fio-${VERSION#fio-}"

echo ">>> Downloading fio ${FIO_TAG}"
curl -L -4 --retry 10 --retry-delay 3 --connect-timeout 300 \
  "https://github.com/axboe/fio/archive/${FIO_TAG}.tar.gz" \
  -o fio.tar.gz
tar xf fio.tar.gz
cd ${FIO_DIR}*

echo ">>> Configuring fio"
CC="${CC_BIN}" ./configure \
  --disable-native \
  --build-static \
  --host="${HOST}"

echo ">>> Compiling fio"
make -j"$(nproc)"

# ── Verify binary is fully static ─────────────────────────────────────────────
echo ">>> Verifying static linkage"
libcheck fio

# ── Copy output ───────────────────────────────────────────────────────────────
cp fio "/io/fio_${ARCH}"
echo ">>> Done: fio_${ARCH} ($(du -sh "/io/fio_${ARCH}" | cut -f1))"
