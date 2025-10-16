#!/bin/bash
set -e

echo "==> Preparing environment..."

# Ensure dependencies are available locally (GitHub runner already installs most)
sudo apt-get update -y
sudo apt-get install -y bc ccache binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi cpio zip unzip git

kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
anykernel="$HOME/anykernel"
ZIMAGE="$objdir/arch/arm64/boot/Image"
kernel_name="Rectilia-vayu-KSUNEXT"
zip_name="$kernel_name-$(date +"%d%m%Y-%H%M").zip"

# Prefer workflow-provided toolchain path
TC_DIR=${TC_DIR:-$HOME/toolchains}
CLANG_DIR=${CLANG_DIR:-$TC_DIR/clang}
export CONFIG_FILE="vayu_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST="clhexftw"
export KBUILD_BUILD_USER="home"
export PATH="$CLANG_DIR/bin:$PATH"

echo "==> Toolchain path: $CLANG_DIR"
clang --version || echo "⚠️ clang not found in path!"

# Colors
NC='\033[0m'
RED='\033[0;31m'
LGR='\033[1;32m'

make_defconfig() {
    echo -e "${LGR}########### Generating Defconfig ############${NC}"
    make O="$objdir" ARCH="$ARCH" "$CONFIG_FILE" -j"$(nproc --all)"
}

compile_kernel() {
    echo -e "${LGR}######### Compiling kernel #########${NC}"
    make -j"$(nproc --all)" \
        O=out \
        ARCH=$ARCH \
        CC="ccache clang" \
        CLANG_TRIPLE="aarch64-linux-gnu-" \
        CROSS_COMPILE="aarch64-linux-gnu-" \
        CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
        LLVM=1 LLVM_IAS=1
}

package_kernel() {
    cd "$objdir"
    local image="arch/arm64/boot/Image"
    local dtbo="arch/arm64/boot/dtbo.img"

    if [[ -f "$image" && -f "$dtbo" ]]; then
        echo "==> Building AnyKernel3 zip..."
        git clone -q https://github.com/clhexftw/AnyKernel3 -b master "$anykernel"
        mv -f "$image" "$dtbo" "$anykernel/"

        cd "$anykernel"
        zip -r "$zip_name" * >/dev/null
        mv "$zip_name" "$kernel_dir/$zip_name"

        echo -e "${LGR}Build completed successfully: $zip_name${NC}"
    else
        echo -e "${RED}Build failed: Missing Image or DTBO!${NC}"
        exit 1
    fi
}

make_defconfig
compile_kernel
package_kernel
