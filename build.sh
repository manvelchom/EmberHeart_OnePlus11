#!/bin/bash
set -euo pipefail

# ==============================================================================
# 200IQ CONFIGURATION PANEL (Փոխարինում է GitHub Inputs/Env-ին)
# ==============================================================================
# Լրացրու քո սարքի տվյալները (Այս տվյալները նախկինում գալիս էին op_config_json-ից)
export MODEL="OnePlus11"          # Քո սարքի մոդելը
export SOC="kalama"               # SoC անվանումը (օրինակ՝ kalama)
export BRANCH="oneplus/sm8475"    # Մանիֆեստի ճյուղը (Branch)

# Inputs (action.yml-ի լոկալ տարբերակները)
MANIFEST="OOS16"                  # Կամ HTTPS լինկ դեպի XML մանիֆեստ
KSUN_BRANCH_OR_HASH="dev"         # KernelSU Next ճյուղը
SUSFS_COMMIT_HASH_OR_BRANCH="dev" # SUSFS ճյուղը
OPTIMIZE_LEVEL="O2"               # O2 կամ O3
KERNEL_UNAME="EmberHeart"         # Կեռնելի անվանումը
BACKPORTS_RELEASE="backports-6.19" # Backports տարբերակը

# Միջավայրի հիմնական պանակներ
export GITHUB_WORKSPACE="$(pwd)"
CONFIG="$MODEL"
ARTIFACTS_DIR="$GITHUB_WORKSPACE/$CONFIG/artifacts"
mkdir -p "$ARTIFACTS_DIR"

echo "🚀 Մեկնարկում է OnePlus EmberHeart Կեռնելի Լոկալ Կոմպիլյացիան..."

# ==============================================================================
# 1. Կախվածությունների Տեղադրում (Dependencies)
# ==============================================================================
echo "📦 Տեղադրվում են անհրաժեշտ փաթեթները..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl ca-certificates build-essential clang lld flex bison \
  libelf-dev libssl-dev libncurses-dev zlib1g-dev liblz4-tool \
  libxml2-utils rsync unzip dwarves file python3 ccache zstd

# Repo գործիքի տեղադրում, եթե չկա
REPO="/usr/local/bin/repo"
if [ ! -x "$REPO" ]; then
  sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO"
  sudo chmod +x "$REPO"
fi

# Git Օպտիմիզացիա
git config --global feature.manyFiles true
git config --global core.fsmonitor true
git config --global pack.sparse true

# ==============================================================================
# 2. Աղբյուրների Ներբեռնում (Repo Sync)
# ==============================================================================
echo "🔄 Ներբեռնվում են կեռնելի աղբյուրները (Repo Sync)..."
export MANIFEST="MANIFEST_$MANIFEST"
mkdir -p "$CONFIG"
cd "$CONFIG"

if [[ "$MANIFEST" == https://* ]]; then
  mkdir -p .repo/manifests
  curl --fail --show-error --location --proto '=https' "$MANIFEST" -o .repo/manifests/temp_manifest.xml
  "$REPO" init -u https://github.com/docdry0001/kernel_manifest.git -b oneplus/sm84750 -m temp_manifest.xml --repo-rev=v2.16 --depth=1 --no-clone-bundle --no-tags
else
  "$REPO" init -u https://github.com/docdry0001/kernel_manifest.git -b "$BRANCH" -m "${MANIFEST#MANIFEST_}.xml" --repo-rev=v2.16 --depth=1 --no-clone-bundle --no-tags
fi

success=false
for i in 1 2 3; do
  if "$REPO" sync -c --no-clone-bundle --no-tags --optimized-fetch -j"$(nproc --all)" --fail-fast; then
    success=true
    break
  fi
  echo "⚠️ Repo sync-ը ձախողվեց, կրկին փորձ $i 30 վայրկյանից..."
  sleep 30
done
$success || { echo "❌ Repo sync-ը վերջնականապես ձախողվեց"; exit 1; }

# ==============================================================================
# 3. Տեղեկատվության Ստացում և Պատչեր (Patching & Versioning)
# ==============================================================================
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform/common"

# Կեռնելի տարբերակի որոշում
VERSION=$(grep '^VERSION *=' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL *=' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL *=' Makefile | awk '{print $3}')
FULL_VERSION="$VERSION.$PATCHLEVEL.$SUBLEVEL"
ANDROID_VER="14" # Կարող ես փոխել ըստ քո ճյուղի (OOS14/OOS15/OOS16)

export ANDROID_VER
export KERNEL_VER="$VERSION.$PATCHLEVEL"
export KERNEL_FULL_VER="$ANDROID_VER-$FULL_VERSION"

# Build Identity
export KBUILD_BUILD_USER="EmberHeart"
export KBUILD_BUILD_HOST="OnePlus"

# ABI Protected Exports մաքրում
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
rm -f common/android/abi_gki_protected_exports_* || true
rm -f msm-kernel/android/abi_gki_protected_exports_* || true

# Օժանդակ ռեպոների կլոնավորում
cd "$GITHUB_WORKSPACE"
rm -rf AnyKernel3 kernel_patches my_patches susfs4ksu
git clone --depth=1 https://github.com/TheWildJames/AnyKernel3.git -b "gki-2.0"
git clone --depth=1 https://github.com/TheWildJames/kernel_patches.git
git clone --depth=1 https://github.com/nullptr-t-oss/kernel_patches.git my_patches
git clone https://gitlab.com/simonpunk/susfs4ksu.git

# SUSFS ստուգում
cd susfs4ksu
git checkout "$SUSFS_COMMIT_HASH_OR_BRANCH" || git checkout "gki-$ANDROID_VER-$VERSION.$PATCHLEVEL"

# KernelSU Next Ավելացում
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
if [ "$KSUN_BRANCH_OR_HASH" = "" ]; then
  curl --fail --location --proto '=https' -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -
else
  curl --fail --location --proto '=https' -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -s "$KSUN_BRANCH_OR_HASH"
fi
git submodule update --init --recursive

# KSU Տարբերակի հաշվարկ
cd KernelSU-Next/kernel
COMMITS_COUNT=$(git rev-list --count HEAD)
BASE_VERSION=$([ $COMMITS_COUNT -lt 2684 ] && echo 10200 || echo 30000)
export KSUVER=$(expr $COMMITS_COUNT "+" $BASE_VERSION)
sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSUVER}/" Makefile
NEED_HOOKS=$([ "$KSUVER" -lt 12884 ] && echo "true" || echo "false")

# Կիրառել KSUN Hooks, եթե անհրաժեշտ է
if [ "$NEED_HOOKS" = "true" ]; then
  cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform/common"
  patch -p1 < ../../../kernel_patches/next/scope_min_manual_hooks_v1.4.patch
fi

# Baseband-guard (BBG)
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash -s fix_blkdev_rename || true
cd common
./scripts/config --file arch/arm64/configs/gki_defconfig --enable CONFIG_BBG
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig

# ==============================================================================
# 4. Կեռնելի Կոնֆիգուրացիա (Kconfig / defconfig)
# ==============================================================================
echo "🔧 Կոնֆիգուրացվում են KernelSU, SUSFS և BBR պարամետրերը..."
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_KSU --disable CONFIG_KSU_KPROBES_HOOK --enable CONFIG_KSU_SUSFS \
  --enable CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT --enable CONFIG_KSU_SUSFS_SUS_PATH \
  --enable CONFIG_KSU_SUSFS_SUS_MOUNT --enable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
  --enable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT --enable CONFIG_KSU_SUSFS_SUS_KSTAT \
  --disable CONFIG_KSU_SUSFS_SUS_OVERLAYFS --enable CONFIG_KSU_SUSFS_TRY_UMOUNT \
  --enable CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT --enable CONFIG_KSU_SUSFS_SPOOF_UNAME \
  --enable CONFIG_KSU_SUSFS_ENABLE_LOG --enable CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  --enable CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT \
  --enable CONFIG_KSU_SUSFS_SUS_MAP --disable CONFIG_KSU_SUSFS_SUS_SU \
  --enable CONFIG_TMPFS_XATTR --enable CONFIG_TMPFS_POSIX_ACL

# OnePlus BBR
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_TCP_CONG_ADVANCED --enable CONFIG_TCP_CONG_BBR \
  --enable CONFIG_NET_SCH_FQ --enable CONFIG_NET_SCH_FQ_CODEL

# SoC Պատչեր (Kalama)
if [ "$SOC" = "kalama" ]; then
  echo "🩹 Կիրառվում են Kalama SoC-ի հատուկ պատչերը..."
  for patch_file in ../../../my_patches/kernel_patches/op11/common/*.patch; do
    [ -f "$patch_file" ] && patch -p1 < "$patch_file" || true
  done
  
  # Wild patches
  patch -p1 --forward < "../../../kernel_patches/common/mem_opt_prefetch.patch" || true
  patch -p1 --forward < "../../../kernel_patches/common/minimise_wakeup_time.patch" || true
  patch -p1 --forward < "../../../kernel_patches/common/int_sqrt.patch" || true
  patch -p1 --forward < "../../../kernel_patches/common/force_tcp_nodelay.patch" || true
  patch -p1 -F3 --forward < "../../../kernel_patches/common/disable_cache_hot_buddy.patch" || true
fi

# ==============================================================================
# 5. Kali NetHunter Ինլայն Դրայվերներ (Wi-Fi Injection & USB Serial)
# ==============================================================================
echo "📡 Ավելացվում են NetHunter-ի դրայվերները և ցանցային ստեկը..."
RT2X00_TMP="$GITHUB_WORKSPACE/rt2x00-import"
rm -rf "$RT2X00_TMP"
git clone --depth=1 https://github.com/torvalds/linux.git "$RT2X00_TMP"

mkdir -p drivers/net/wireless/ralink
rm -rf drivers/net/wireless/ralink/rt2x00
cp -a "$RT2X00_TMP/drivers/net/wireless/ralink/rt2x00" drivers/net/wireless/ralink/

grep -q 'rt2x00/Kconfig' drivers/net/wireless/ralink/Kconfig || printf '\nsource "drivers/net/wireless/ralink/rt2x00/Kconfig"\n' >> drivers/net/wireless/ralink/Kconfig
grep -q 'obj-\$(CONFIG_RT2X00)' drivers/net/wireless/ralink/Makefile || printf '\nobj-$(CONFIG_RT2X00) += rt2x00/\n' >> drivers/net/wireless/ralink/Makefile

# Նեթհանթեր Kconfig-ների միացում (USB Wi-Fi, Bluetooth, TTL, IPSET)
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_BT_HCIBTUSB --enable CONFIG_USB_AIRSPY --enable CONFIG_USB_HACKRF \
  --enable CONFIG_CAN --enable CONFIG_USB_SERIAL --enable CONFIG_USB_SERIAL_CH341 \
  --enable CONFIG_USB_SERIAL_FTDI_SIO --enable CONFIG_USB_SERIAL_PL2303 \
  --enable CONFIG_WLAN_VENDOR_RALINK --enable CONFIG_RT2X00 --enable CONFIG_RT2800USB \
  --enable CONFIG_MT7601U --enable CONFIG_MT76_USB --enable CONFIG_MT7921U \
  --enable CONFIG_IP_NF_TARGET_TTL --enable CONFIG_IP_SET

# Բիլդի օպտիմիզացիա (LTO Clang)
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_LTO_CLANG_THIN --enable CONFIG_LTO_CLANG \
  --set-val CONFIG_FRAME_WARN 0

if [ "$OPTIMIZE_LEVEL" = "O3" ]; then
  ./scripts/config --file arch/arm64/configs/gki_defconfig --disable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3
else
  ./scripts/config --file arch/arm64/configs/gki_defconfig --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE --disable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3
fi

# Branding
CUSTOM_LOCALVERSION="-${ANDROID_VER}-${KERNEL_UNAME}"

# ==============================================================================
# 6. Տուլչեյնի Որոնում և Կոմպիլյացիա (Toolchain & Compilation)
# ==============================================================================
echo "🔍 Որոնվում է Clang տուլչեյնը..."
KP="$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
CLANG_BIN=""
for base in "$KP/prebuilts" "$KP/prebuilts-master"; do
  latest=$(ls -d "$base"/clang/host/linux-x86/clang-r*/ 2>/dev/null | sort -V | tail -n1 || true)
  if [ -n "$latest" ] && [ -x "$latest/bin/clang" ]; then
    CLANG_BIN="$latest/bin"
    break
  fi
done

if [ -z "$CLANG_BIN" ] && command -v clang >/dev/null 2>&1; then
  CLANG_BIN="$(dirname "$(command -v clang)")"
fi

if [ -z "$CLANG_BIN" ]; then
  echo "❌ Ոչ մի Clang տուլչեյն չգտնվեց։ Խնդրում ենք տեղադրել AOSP Clang-ը։"
  exit 1
fi

export PATH="$CLANG_BIN:/usr/lib/ccache:$PATH"

MAKE_FLAGS=(
  LLVM=1 LLVM_IAS=1 ARCH=arm64 SUBARCH=arm64
  CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LD=ld.lld HOSTLD=ld.lld 
  AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump
  DEPMOD=depmod DTC=dtc STRIP=llvm-strip HOSTCC=clang HOSTCXX=clang++ CC=clang
)

echo "🛠️ Սկսվում է կեռնելի հավաքումը..."
cd "$KP/common"
mkdir -p out
make "${MAKE_FLAGS[@]}" O=out gki_defconfig

./scripts/config --file "out/.config" --set-str LOCALVERSION "${CUSTOM_LOCALVERSION}" --disable LOCALVERSION_AUTO
sed -i 's/scm_version="$(scm_version --short)"/scm_version=""/' scripts/setlocalversion

KCFLAGS="-Wno-error -pipe -fno-stack-protector -${OPTIMIZE_LEVEL}"
KCPPFLAGS="-DCONFIG_OPTIMIZE_INLINING"

make "${MAKE_FLAGS[@]}" O=out olddefconfig
make -j$(nproc --all) "${MAKE_FLAGS[@]}" KCFLAGS="$KCFLAGS" KCPPFLAGS="$KCPPFLAGS" O=out Image modules
make -j$(nproc --all) "${MAKE_FLAGS[@]}" O=out INSTALL_MOD_PATH="$KP/common/out" modules_install

IMG="out/arch/arm64/boot/Image"
[ -f "$IMG" ] || { echo "❌ Kernel Image-ը չգտնվեց"; exit 1; }
echo "✅ Կեռնելը հաջողությամբ կոմպիլյացվեց։"

# ==============================================================================
# 7. OpenWrt Backports v6.19-ի Հավաքում (Wi-Fi drivers)
# ==============================================================================
echo "📦 Սկսվում է OpenWrt Backports-ի հավաքումը..."
cd "$GITHUB_WORKSPACE"
URL="https://github.com/openwrt/backports/releases/download/backports-v6.19/backports-6.19.tar.zst"
KERNEL_BUILD="$KP/common/out"

wget -q -O backports.tar.zst "$URL"
tar -xf backports.tar.zst
rm -rf backports-stable
mv "$BACKPORTS_RELEASE" backports-stable
cd backports-stable

# Պատչել CFI մակրոները
sed -i 's/__CFI_ADDRESSABLE(init_module, __initdata)/__CFI_ADDRESSABLE(init_module)/g' backport-include/linux/module.h
sed -i 's/__CFI_ADDRESSABLE(cleanup_module, __exitdata)/__CFI_ADDRESSABLE(cleanup_module)/g' backport-include/linux/module.h

make "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" allnoconfig

printf '%s\n' \
  'CPTCFG_CFG80211=m' 'CPTCFG_MAC80211=m' 'CPTCFG_WLAN_VENDOR_MEDIATEK=y' \
  'CPTCFG_MT76_CORE=m' 'CPTCFG_MT76_USB=m' 'CPTCFG_MT76_CONNAC_LIB=m' \
  'CPTCFG_MT792x_USB=m' 'CPTCFG_MT792x_LIB=m' 'CPTCFG_MT7921_COMMON=m' \
  'CPTCFG_MT7921U=m' >> .config

make "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" olddefconfig </dev/null || true
make -j"$(nproc --all)" "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" V=1 >> "$GITHUB_WORKSPACE/backports-build.log" 2>&1 || true

# ==============================================================================
# 8. Արխիվացում (AnyKernel3 Flashable ZIP)
# ==============================================================================
echo "📦 Ստեղծվում է AnyKernel3 ֆլեշացվող արխիվը..."
cp "$KP/common/$IMG" "$GITHUB_WORKSPACE/AnyKernel3/Image"
cd "$GITHUB_WORKSPACE/AnyKernel3"

sed -i '7 c\kernel.string=EmberHeart Kernel by nullptr-t-oss' anykernel.sh
ZIP_NAME="AnyKernel3_${MODEL}_${KERNEL_FULL_VER}_Next_${KSUVER}.zip"

zip -r "$ARTIFACTS_DIR/$ZIP_NAME" ./* >/dev/null

echo "=============================================================================="
echo "🎉 ԿՈՄՊԻԼՅԱՑԻԱՆ ԱՎԱՐՏՎԵՑ ՀԱՋՈՂՈՒԹՅԱՄԲ։"
echo "📂 Flashable ZIP-ը պատրաստ է՝ $ARTIFACTS_DIR/$ZIP_NAME"
echo "=============================================================================="
