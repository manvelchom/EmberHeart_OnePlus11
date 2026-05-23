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
[span_3](start_span)[span_4](start_span)MANIFEST="OOS16"                  # Կամ HTTPS լինկ դեպի XML մանիֆեստ[span_3](end_span)[span_4](end_span)
[span_5](start_span)[span_6](start_span)KSUN_BRANCH_OR_HASH="dev"         # KernelSU Next ճյուղը[span_5](end_span)[span_6](end_span)
[span_7](start_span)SUSFS_COMMIT_HASH_OR_BRANCH="dev" # SUSFS ճյուղը[span_7](end_span)
[span_8](start_span)[span_9](start_span)OPTIMIZE_LEVEL="O2"               # O2 կամ O3[span_8](end_span)[span_9](end_span)
[span_10](start_span)KERNEL_UNAME="EmberHeart"         # Կեռնելի անվանումը[span_10](end_span)
[span_11](start_span)BACKPORTS_RELEASE="backports-6.19" # Backports տարբերակը[span_11](end_span)

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
  [span_12](start_span)libxml2-utils rsync unzip dwarves file python3 ccache zstd[span_12](end_span)

# Repo գործիքի տեղադրում, եթե չկա
REPO="/usr/local/bin/repo"
if [ ! -x "$REPO" ]; then
  sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO"
  sudo chmod +x "$REPO"
[span_13](start_span)fi[span_13](end_span)

# Git Օպտիմիզացիա
git config --global feature.manyFiles true
git config --global core.fsmonitor true
[span_14](start_span)git config --global pack.sparse true[span_14](end_span)

# ==============================================================================
# 2. Աղբյուրների Ներբեռնում (Repo Sync)
# ==============================================================================
echo "🔄 Ներբեռնվում են կեռնելի աղբյուրները (Repo Sync)..."
[span_15](start_span)export MANIFEST="MANIFEST_$MANIFEST"[span_15](end_span)
mkdir -p "$CONFIG"
cd "$CONFIG"

if [[ "$MANIFEST" == https://* ]]; then
  mkdir -p .repo/manifests
  [span_16](start_span)curl --fail --show-error --location --proto '=https' "$MANIFEST" -o .repo/manifests/temp_manifest.xml[span_16](end_span)
  [span_17](start_span)"$REPO" init -u https://github.com/docdry0001/kernel_manifest.git -b oneplus/sm84750 -m temp_manifest.xml --repo-rev=v2.16 --depth=1 --no-clone-bundle --no-tags[span_17](end_span)
else
  [span_18](start_span)[span_19](start_span)"$REPO" init -u https://github.com/docdry0001/kernel_manifest.git -b "$BRANCH" -m "${MANIFEST#MANIFEST_}.xml" --repo-rev=v2.16 --depth=1 --no-clone-bundle --no-tags[span_18](end_span)[span_19](end_span)
fi

success=false
for i in 1 2 3; do
  if "$REPO" sync -c --no-clone-bundle --no-tags --optimized-fetch -j"$(nproc --all)" --fail-fast; then
    success=true
    break
  fi
  echo "⚠️ Repo sync-ը ձախողվեց, կրկին փորձ $i 30 վայրկյանից..."
  sleep 30
[span_20](start_span)done[span_20](end_span)
$success || { echo "❌ Repo sync-ը վերջնականապես ձախողվեց"; exit 1; [span_21](start_span)}

# ==============================================================================
# 3. Տեղեկատվության Ստացում և Պատչեր (Patching & Versioning)
# ==============================================================================
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform/common"

# Կեռնելի տարբերակի որոշում
VERSION=$(grep '^VERSION *=' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL *=' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL *=' Makefile | awk '{print $3}')
FULL_VERSION="$VERSION.$PATCHLEVEL.$SUBLEVEL"
ANDROID_VER="14" # Կարող ես փոխել ըստ քո ճյուղի (OOS14/OOS15/OOS16)[span_21](end_span)

export ANDROID_VER
export KERNEL_VER="$VERSION.$PATCHLEVEL"
[span_22](start_span)export KERNEL_FULL_VER="$ANDROID_VER-$FULL_VERSION"[span_22](end_span)

#  [span_23](start_span)Build Identity[span_23](end_span)
export KBUILD_BUILD_USER="EmberHeart"
[span_24](start_span)export KBUILD_BUILD_HOST="OnePlus"[span_24](end_span)

# [span_25](start_span)ABI Protected Exports մաքրում[span_25](end_span)
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
[span_26](start_span)rm -f common/android/abi_gki_protected_exports_* || true[span_26](end_span)
[span_27](start_span)rm -f msm-kernel/android/abi_gki_protected_exports_* || true[span_27](end_span)

# [span_28](start_span)Օժանդակ ռեպոների կլոնավորում[span_28](end_span)
cd "$GITHUB_WORKSPACE"
rm -rf AnyKernel3 kernel_patches my_patches susfs4ksu
[span_29](start_span)git clone --depth=1 https://github.com/TheWildJames/AnyKernel3.git -b "gki-2.0"[span_29](end_span)
[span_30](start_span)git clone --depth=1 https://github.com/TheWildJames/kernel_patches.git[span_30](end_span)
[span_31](start_span)git clone --depth=1 https://github.com/nullptr-t-oss/kernel_patches.git my_patches[span_31](end_span)
[span_32](start_span)git clone https://gitlab.com/simonpunk/susfs4ksu.git[span_32](end_span)

# [span_33](start_span)SUSFS ստուգում[span_33](end_span)
cd susfs4ksu
[span_34](start_span)[span_35](start_span)git checkout "$SUSFS_COMMIT_HASH_OR_BRANCH" || git checkout "gki-$ANDROID_VER-$VERSION.$PATCHLEVEL"[span_34](end_span)[span_35](end_span)

# [span_36](start_span)KernelSU Next Ավելացում[span_36](end_span)
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
if [ "$KSUN_BRANCH_OR_HASH" = "" ]; then
  [span_37](start_span)curl --fail --location --proto '=https' -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -[span_37](end_span)
else
  [span_38](start_span)curl --fail --location --proto '=https' -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -s "$KSUN_BRANCH_OR_HASH"[span_38](end_span)
fi
[span_39](start_span)git submodule update --init --recursive[span_39](end_span)

# [span_40](start_span)KSU Տարբերակի հաշվարկ[span_40](end_span)
cd KernelSU-Next/kernel
COMMITS_COUNT=$(git rev-list --count HEAD)
[span_41](start_span)BASE_VERSION=$([ $COMMITS_COUNT -lt 2684 ] && echo 10200 || echo 30000)[span_41](end_span)
[span_42](start_span)export KSUVER=$(expr $COMMITS_COUNT "+" $BASE_VERSION)[span_42](end_span)
[span_43](start_span)sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSUVER}/" Makefile[span_43](end_span)
[span_44](start_span)NEED_HOOKS=$([ "$KSUVER" -lt 12884 ] && echo "true" || echo "false")[span_44](end_span)

# [span_45](start_span)Կիրառել KSUN Hooks, եթե անհրաժեշտ է[span_45](end_span)
if [ "$NEED_HOOKS" = "true" ]; then
  cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform/common"
  [span_46](start_span)patch -p1 < ../../../kernel_patches/next/scope_min_manual_hooks_v1.4.patch[span_46](end_span)
fi

# [span_47](start_span)Baseband-guard (BBG)[span_47](end_span)
cd "$GITHUB_WORKSPACE/$CONFIG/kernel_platform"
[span_48](start_span)wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash -s fix_blkdev_rename || true[span_48](end_span)
cd common
[span_49](start_span)./scripts/config --file arch/arm64/configs/gki_defconfig --enable CONFIG_BBG[span_49](end_span)
[span_50](start_span)sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig[span_50](end_span)

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
  -[span_51](start_span)-enable CONFIG_TMPFS_XATTR --enable CONFIG_TMPFS_POSIX_ACL[span_51](end_span)

# [span_52](start_span)OnePlus BBR[span_52](end_span)
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_TCP_CONG_ADVANCED --enable CONFIG_TCP_CONG_BBR \
  -[span_53](start_span)-enable CONFIG_NET_SCH_FQ --enable CONFIG_NET_SCH_FQ_CODEL[span_53](end_span)

# [span_54](start_span)SoC Պատչեր (Kalama)[span_54](end_span)
if [ "$SOC" = "kalama" ]; then
  echo "🩹 Կիրառվում են Kalama SoC-ի հատուկ պատչերը..."
  for patch_file in ../../../my_patches/kernel_patches/op11/common/*.patch; do
    [ -f "$patch_file" ] && patch -p1 < "$patch_file" || true
  [span_55](start_span)done[span_55](end_span)
  
  # [span_56](start_span)Wild patches[span_56](end_span)
  [span_57](start_span)patch -p1 --forward < "../../../kernel_patches/common/mem_opt_prefetch.patch" || true[span_57](end_span)
  [span_58](start_span)patch -p1 --forward < "../../../kernel_patches/common/minimise_wakeup_time.patch" || true[span_58](end_span)
  [span_59](start_span)patch -p1 --forward < "../../../kernel_patches/common/int_sqrt.patch" || true[span_59](end_span)
  [span_60](start_span)patch -p1 --forward < "../../../kernel_patches/common/force_tcp_nodelay.patch" || true[span_60](end_span)
  [span_61](start_span)patch -p1 -F3 --forward < "../../../kernel_patches/common/disable_cache_hot_buddy.patch" || true[span_61](end_span)
fi

# ==============================================================================
# 5. Kali NetHunter Ինլայն Դրայվերներ (Wi-Fi Injection & USB Serial)
# ==============================================================================
echo "📡 Ավելացվում են NetHunter-ի դրայվերները և ցանցային ստեկը..."
RT2X00_TMP="$GITHUB_WORKSPACE/rt2x00-import"
rm -rf "$RT2X00_TMP"
[span_62](start_span)git clone --depth=1 https://github.com/torvalds/linux.git "$RT2X00_TMP"[span_62](end_span)

mkdir -p drivers/net/wireless/ralink
rm -rf drivers/net/wireless/ralink/rt2x00
[span_63](start_span)cp -a "$RT2X00_TMP/drivers/net/wireless/ralink/rt2x00" drivers/net/wireless/ralink/[span_63](end_span)

[span_64](start_span)grep -q 'rt2x00/Kconfig' drivers/net/wireless/ralink/Kconfig || printf '\nsource "drivers/net/wireless/ralink/rt2x00/Kconfig"\n' >> drivers/net/wireless/ralink/Kconfig[span_64](end_span)
[span_65](start_span)grep -q 'obj-\$(CONFIG_RT2X00)' drivers/net/wireless/ralink/Makefile || printf '\nobj-$(CONFIG_RT2X00) += rt2x00/\n' >> drivers/net/wireless/ralink/Makefile[span_65](end_span)

# [span_66](start_span)[span_67](start_span)Նեթհանթեր Kconfig-ների միացում (USB Wi-Fi, Bluetooth, TTL, IPSET)[span_66](end_span)[span_67](end_span)
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_BT_HCIBTUSB --enable CONFIG_USB_AIRSPY --enable CONFIG_USB_HACKRF \
  --enable CONFIG_CAN --enable CONFIG_USB_SERIAL --enable CONFIG_USB_SERIAL_CH341 \
  --enable CONFIG_USB_SERIAL_FTDI_SIO --enable CONFIG_USB_SERIAL_PL2303 \
  --enable CONFIG_WLAN_VENDOR_RALINK --enable CONFIG_RT2X00 --enable CONFIG_RT2800USB \
  --enable CONFIG_MT7601U --enable CONFIG_MT76_USB --enable CONFIG_MT7921U \
  -[span_68](start_span)[span_69](start_span)[span_70](start_span)-enable CONFIG_IP_NF_TARGET_TTL --enable CONFIG_IP_SET[span_68](end_span)[span_69](end_span)[span_70](end_span)

# [span_71](start_span)Բիլդի օպտիմիզացիա (LTO Clang)[span_71](end_span)
./scripts/config --file arch/arm64/configs/gki_defconfig \
  --enable CONFIG_LTO_CLANG_THIN --enable CONFIG_LTO_CLANG \
  -[span_72](start_span)-set-val CONFIG_FRAME_WARN 0[span_72](end_span)

if [ "$OPTIMIZE_LEVEL" = "O3" ]; then
  [span_73](start_span)./scripts/config --file arch/arm64/configs/gki_defconfig --disable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3[span_73](end_span)
else
  [span_74](start_span)[span_75](start_span)./scripts/config --file arch/arm64/configs/gki_defconfig --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE --disable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3[span_74](end_span)[span_75](end_span)
fi

# [span_76](start_span)Branding[span_76](end_span)
[span_77](start_span)CUSTOM_LOCALVERSION="-${ANDROID_VER}-${KERNEL_UNAME}"[span_77](end_span)

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
  [span_78](start_span)fi[span_78](end_span)
done

if [ -z "$CLANG_BIN" ] && command -v clang >/dev/null 2>&1; then
  [span_79](start_span)CLANG_BIN="$(dirname "$(command -v clang)")"[span_79](end_span)
fi

if [ -z "$CLANG_BIN" ]; then
  echo "❌ Ոչ մի Clang տուլչեյն չգտնվեց։ Խնդրում ենք տեղադրել AOSP Clang-ը։"
  [span_80](start_span)exit 1[span_80](end_span)
fi

[span_81](start_span)export PATH="$CLANG_BIN:/usr/lib/ccache:$PATH"[span_81](end_span)

MAKE_FLAGS=(
  LLVM=1 LLVM_IAS=1 ARCH=arm64 SUBARCH=arm64
  CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LD=ld.lld HOSTLD=ld.lld 
  AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump
  DEPMOD=depmod DTC=dtc STRIP=llvm-strip HOSTCC=clang HOSTCXX=clang++ CC=clang
[span_82](start_span))

echo "🛠️ Սկսվում է կեռնելի հավաքումը..."
cd "$KP/common"
mkdir -p out
make "${MAKE_FLAGS[@]}" O=out gki_defconfig[span_82](end_span)

[span_83](start_span)./scripts/config --file "out/.config" --set-str LOCALVERSION "${CUSTOM_LOCALVERSION}" --disable LOCALVERSION_AUTO[span_83](end_span)
[span_84](start_span)sed -i 's/scm_version="$(scm_version --short)"/scm_version=""/' scripts/setlocalversion[span_84](end_span)

[span_85](start_span)KCFLAGS="-Wno-error -pipe -fno-stack-protector -${OPTIMIZE_LEVEL}"[span_85](end_span)
[span_86](start_span)KCPPFLAGS="-DCONFIG_OPTIMIZE_INLINING"[span_86](end_span)

[span_87](start_span)make "${MAKE_FLAGS[@]}" O=out olddefconfig[span_87](end_span)
[span_88](start_span)make -j$(nproc --all) "${MAKE_FLAGS[@]}" KCFLAGS="$KCFLAGS" KCPPFLAGS="$KCPPFLAGS" O=out Image modules[span_88](end_span)
[span_89](start_span)make -j$(nproc --all) "${MAKE_FLAGS[@]}" O=out INSTALL_MOD_PATH="$KP/common/out" modules_install[span_89](end_span)

IMG="out/arch/arm64/boot/Image"
[ -f "$IMG" ] || { echo "❌ Kernel Image-ը չգտնվեց"; exit 1; [span_90](start_span)}
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
mv "$BACKPORTS_RELEASE" backports-stable[span_90](end_span)
cd backports-stable

# Պատչել CFI մակրոները
[span_91](start_span)sed -i 's/__CFI_ADDRESSABLE(init_module, __initdata)/__CFI_ADDRESSABLE(init_module)/g' backport-include/linux/module.h[span_91](end_span)
[span_92](start_span)sed -i 's/__CFI_ADDRESSABLE(cleanup_module, __exitdata)/__CFI_ADDRESSABLE(cleanup_module)/g' backport-include/linux/module.h[span_92](end_span)

[span_93](start_span)make "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" allnoconfig[span_93](end_span)

printf '%s\n' \
  'CPTCFG_CFG80211=m' 'CPTCFG_MAC80211=m' 'CPTCFG_WLAN_VENDOR_MEDIATEK=y' \
  'CPTCFG_MT76_CORE=m' 'CPTCFG_MT76_USB=m' 'CPTCFG_MT76_CONNAC_LIB=m' \
  'CPTCFG_MT792x_USB=m' 'CPTCFG_MT792x_LIB=m' 'CPTCFG_MT7921_COMMON=m' \
  [span_94](start_span)'CPTCFG_MT7921U=m' >> .config[span_94](end_span)

[span_95](start_span)make "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" olddefconfig </dev/null || true[span_95](end_span)
[span_96](start_span)make -j"$(nproc --all)" "${MAKE_FLAGS[@]}" KLIB="$KERNEL_BUILD" KLIB_BUILD="$KERNEL_BUILD" V=1 >> "$GITHUB_WORKSPACE/backports-build.log" 2>&1 || true[span_96](end_span)

# ==============================================================================
# 8. Արխիվացում (AnyKernel3 Flashable ZIP)
# ==============================================================================
echo "📦 Ստեղծվում է AnyKernel3 ֆլեշացվող արխիվը..."
[span_97](start_span)cp "$KP/common/$IMG" "$GITHUB_WORKSPACE/AnyKernel3/Image"[span_97](end_span)
cd "$GITHUB_WORKSPACE/AnyKernel3"

[span_98](start_span)sed -i '7 c\kernel.string=EmberHeart Kernel by nullptr-t-oss' anykernel.sh[span_98](end_span)
[span_99](start_span)ZIP_NAME="AnyKernel3_${MODEL}_${KERNEL_FULL_VER}_Next_${KSUVER}.zip"[span_99](end_span)

[span_100](start_span)zip -r "$ARTIFACTS_DIR/$ZIP_NAME" ./* >/dev/null[span_100](end_span)

echo "=============================================================================="
echo "🎉 ԿՈՄՊԻԼՅԱՑԻԱՆ ԱՎԱՐՏՎԵՑ ՀԱՋՈՂՈՒԹՅԱՄԲ։"
echo "📂 Flashable ZIP-ը պատրաստ է՝ $ARTIFACTS_DIR/$ZIP_NAME"
echo "=============================================================================="
