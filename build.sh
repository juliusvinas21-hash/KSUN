#!/bin/bash
set -euo pipefail

# Prereqs (CI already installs system packages; keep for local runs)
sudo -H apt-get update -y || true
sudo -H apt-get install -y bc python2 ccache binutils-aarch64-linux-gnu cpio zip git wget || true

kernel_dir="${PWD}"
CCACHE=$(command -v ccache || true)
objdir="${kernel_dir}/out"
anykernel="$HOME/anykernel"
builddir="${kernel_dir}/build"
ZIMAGE="$kernel_dir/out/arch/arm64/boot/Image"
kernel_name="Rectilia-vayu-KSUNEXT"
zip_name="$kernel_name-$(date +"%d%m%Y-%H%M").zip"
TC_DIR="$HOME/tc"
# Prefer NEUTRON provided via CI env; fallback to default path
: "${CLANG_DIR:=$HOME/tc/neutron-clang}"
export CONFIG_FILE="vayu_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=clhexftw
export KBUILD_BUILD_USER=home

# Ensure clang in PATH
export PATH="$CLANG_DIR/bin:$PATH"

# If clang not present, attempt to clone lightweight neutron repo (CI should set CLANG_DIR)
if ! command -v clang >/dev/null 2>&1; then
    echo "clang not found in PATH; attempting to clone prebuilt Neutron to $TC_DIR..."
    mkdir -p "$TC_DIR"
    cd "$TC_DIR"
    # NOTE: Replace this URL with a trusted Neutron prebuilt tarball in CI for speed.
    if [ ! -d "$CLANG_DIR" ]; then
        git clone --depth=1 https://github.com/Neutron-Toolchains/neutron-clang "$CLANG_DIR" || true
    fi
    export PATH="$CLANG_DIR/bin:$PATH"
fi

# Colors
NC='\033[0m'
RED='\033[0;31m'
LGR='\033[1;32m'

START=$(date +%s)

make_defconfig() {
    echo -e "${LGR}########### Generating Defconfig ############${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j"$(nproc --all)"
}

compile() {
    cd "${kernel_dir}"
    echo -e "${LGR}######### Compiling kernel #########${NC}"
    # Use ccache clang if available
    if [ -n "$CCACHE" ]; then
      CC="ccache clang"
    else
      CC="clang"
    fi

    make -j"$(nproc --all)" \
      O="${objdir}" \
      ARCH="${ARCH}" \
      CC="${CC}" \
      CLANG_TRIPLE="aarch64-linux-gnu-" \
      CROSS_COMPILE="aarch64-linux-gnu-" \
      CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
      LLVM=1 \
      LLVM_IAS=1
}

completion() {
    # Wait until out dir exists
    cd "${objdir}"
    COMPILED_IMAGE="arch/arm64/boot/Image"
    COMPILED_DTBO="arch/arm64/boot/dtbo.img"

    if [[ -f "${COMPILED_IMAGE}" ]]; then
        git clone -q https://github.com/osm0sis/AnyKernel3 -b master "$anykernel" || git clone -q https://github.com/mengkernel/AnyKernel3 "$anykernel"
        # copy whichever image exists
        cp -f "${COMPILED_IMAGE}" "$anykernel/" || true
        if [[ -f "${COMPILED_DTBO}" ]]; then
            cp -f "${COMPILED_DTBO}" "$anykernel/" || true
        fi

        cd "$anykernel" || exit 1
        # remove old zips (safety)
        find . -name "*.zip" -type f -delete || true
        zip -r AnyKernel.zip ./*
        mv AnyKernel.zip "${zip_name}"
        mv "${zip_name}" /workspace/ || mv "${zip_name}" "${kernel_dir}/" || true
        rm -rf "$anykernel"
        END=$(date +%s)
        DIFF=$((END - START))
        echo -e "${LGR}Build finished in ${DIFF}s. Zip: ${zip_name}${NC}"
        exit 0
    else
        echo -e "${RED}Compilation failed: ${COMPILED_IMAGE} not found${NC}"
        exit 1
    fi
}

# Run
make_defconfig
compile
completion
cd "${kernel_dir}"
