#!/bin/bash

# --- DO NOT USE sudo IN CI ---
# sudo -H apt-get install bc python2 ccache binutils-aarch64-linux-gnu cpio

kernel_dir="${PWD}"
CCACHE=$(command -v ccache)
objdir="${kernel_dir}/out"
anykernel=$HOME/anykernel
builddir="${kernel_dir}/build"

kernel_name="Rectilia-vayu-KSUNEXT"
zip_name="$kernel_name-$(date +"%d%m%Y-%H%M").zip"

# If using Neutron Clang via workflow, CLANG_DIR is passed externally
TC_DIR="${TC_DIR:-$HOME/tc}"
CLANG_DIR="${CLANG_DIR:-$HOME/tc/clang-r530567}"

export CONFIG_FILE="vayu_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=clhexftw
export KBUILD_BUILD_USER=home
export PATH="$CLANG_DIR/bin:$PATH"

# Colors
NC='\033[0m'
RED='\033[0;31m'
LGR='\033[1;32m'

make_defconfig() {
    START=$(date +"%s")
    echo -e "${LGR}########### Generating Defconfig ############${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j$(nproc --all)
}

compile() {
    cd "${kernel_dir}"
    echo -e "${LGR}######### Compiling kernel #########${NC}"
    make -j$(nproc --all) \
        O=out \
        ARCH=${ARCH} \
        CC="ccache clang" \
        CLANG_TRIPLE="aarch64-linux-gnu-" \
        CROSS_COMPILE="aarch64-linux-gnu-" \
        CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
        LLVM=1 \
        LLVM_IAS=1
}

completion() {
    cd "${objdir}"

    # Handle both Image.gz and Image
    if [[ -f arch/arm64/boot/Image.gz ]]; then
        COMPILED_IMAGE="arch/arm64/boot/Image.gz"
    elif [[ -f arch/arm64/boot/Image ]]; then
        COMPILED_IMAGE="arch/arm64/boot/Image"
    else
        echo -e "${RED}Kernel image not found (neither Image.gz nor Image).${NC}"
        exit 1
    fi

    # DTBO is optional
    COMPILED_DTBO=""
    if [[ -f arch/arm64/boot/dtbo.img ]]; then
        COMPILED_DTBO="arch/arm64/boot/dtbo.img"
    fi

    echo -e "${LGR}Kernel compiled successfully.${NC}"
    [ -n "$COMPILED_DTBO" ] && echo -e "${LGR}DTBO compiled successfully.${NC}"

    # Clone AnyKernel3
    git clone -q https://github.com/clhexftw/AnyKernel3 -b master "$anykernel"

    # Copy kernel image
    cp -f "${objdir}/${COMPILED_IMAGE}" "$anykernel/"

    # Copy DTBO only if it exists
    if [[ -n "$COMPILED_DTBO" ]]; then
        cp -f "${objdir}/${COMPILED_DTBO}" "$anykernel/dtbo.img"
    fi

    cd "$anykernel"
    rm -f *.zip
    zip -r AnyKernel.zip *
    mv AnyKernel.zip "${kernel_dir}/${zip_name}"
    rm -rf "$anykernel"

    END=$(date +"%s")
    DIFF=$((END - START))
    echo -e "${LGR}############################################"
    echo -e "${LGR}############# OkThisIsEpic!  ##############"
    echo -e "${LGR}############################################${NC}"
    exit 0
}

make_defconfig
compile
completion

cd "${kernel_dir}"
