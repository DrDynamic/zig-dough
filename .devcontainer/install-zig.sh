#!/usr/bin/env sh

set -e

MINISIGN_VERSION="$1"
MINISIGN_URL="https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz"
MINISIGN_SIGNATURE_URL="https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz.minisig"
MINISIGN_PUBKEY="RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"

ZIG_VERSION="$2"
ZLS_VERSION="$3"
ZIG_TARGET_NAME="zig-x86_64-linux-${ZIG_VERSION}"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARGET_NAME}.tar.xz"
ZIG_SIGNATURE_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARGET_NAME}.tar.xz.minisig"
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

ZLS_TARGET_NAME="zls-linux-x86_64-${ZLS_VERSION}"
ZLS_URL="https://builds.zigtools.org/${ZLS_TARGET_NAME}.tar.xz"
ZLS_SIGNATURE_URL="https://builds.zigtools.org/${ZLS_TARGET_NAME}.tar.xz.minisig"
ZLS_PUBKEY="RWR+9B91GBZ0zOjh6Lr17+zKf5BoSuFvrx2xSeDE57uIYvnKBGmMjOex"

INSTALL_DIR=$(realpath $(pwd))
BIN_DIR="${INSTALL_DIR}/bin/"

alias get_file="curl --location --remote-name --no-progress-meter --fail"

mkdir -p "./bin"

get_file "${MINISIGN_URL}"
tar -xzf "minisign-${MINISIGN_VERSION}-linux.tar.gz"
ln -s "${INSTALL_DIR}/minisign-linux/x86_64/minisign" "${BIN_DIR}/minisign"
echo "Minisign installed"

get_file "${MINISIGN_SIGNATURE_URL}"
minisign -Vm minisign-"${MINISIGN_VERSION}"-linux.tar.gz -P ${MINISIGN_PUBKEY}
rm -f "minisign-${MINISIGN_VERSION}-linux.tar.gz"
echo "Minisign verified"

echo "Download zig: ${ZIG_URL}"
get_file "${ZIG_URL}"

echo "Download Zig sig: ${ZIG_SIGNATURE_URL}"
get_file "${ZIG_SIGNATURE_URL}"
minisign -Vm ${ZIG_TARGET_NAME}.tar.xz -P ${ZIG_PUBKEY}
echo "Zig verified"

tar -xf ${ZIG_TARGET_NAME}.tar.xz
ln -s "${INSTALL_DIR}/${ZIG_TARGET_NAME}/zig" "${BIN_DIR}/zig"
rm -f "${ZIG_TARGET_NAME}.tar.xz"
echo "Zig installed"

echo "Download zls: ${ZLS_URL}"
get_file "${ZLS_URL}"

echo "Download zls sig: ${ZLS_SIGNATURE_URL}"
get_file "${ZLS_SIGNATURE_URL}"
minisign -Vm ${ZLS_TARGET_NAME}.tar.xz -P ${ZLS_PUBKEY}
echo "Zls verified"

tar -xf "${ZLS_TARGET_NAME}.tar.xz"
mv "${INSTALL_DIR}/zls" "${BIN_DIR}/zls"
rm -f "${ZLS_TARGET_NAME}.tar.xz"
echo "Zls installed"