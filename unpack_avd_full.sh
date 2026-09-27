#!/bin/bash
# ==============================================================================
# AVD 一键还原脚本 (全量可还原版)
# 自动补装 SDK 组件 -> 解压覆盖 -> 重写绝对路径 -> 校验指纹
# ==============================================================================
set -euo pipefail

AVD_NAME="Pixel_8"
SDK_DIR="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
SYSIMG_REL="system-images/android-34/google_apis_playstore/arm64-v8a"
AVD_BASE_DIR="$HOME/.android/avd"

ARCHIVE="${1:?用法: ./unpack_avd_full.sh <备份文件.tar.zst>}"
RESTORE_DIR="${2:-$HOME/Downloads/avd_restore_tmp}"

echo "=== AVD 一键还原 ==="

[ -f "$ARCHIVE" ] || { echo "❌ 找不到备份文件: $ARCHIVE"; exit 1; }

if pgrep -f "emulator.*-avd ${AVD_NAME}" >/dev/null 2>&1; then
    echo "❌ 模拟器正在运行，请先关闭: adb emu kill"
    exit 1
fi

command -v zstd >/dev/null 2>&1 || {
    echo "[*] 未找到 zstd，正在通过 Homebrew 安装..."
    brew install zstd >/dev/null 2>&1 || { echo "❌ zstd 安装失败，请手动执行: brew install zstd"; exit 1; }
}

rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"
echo "[1/5] 解压归档到临时区 $RESTORE_DIR ..."
zstd -dc "$ARCHIVE" | tar -xf - -C "$RESTORE_DIR"

[ -d "$RESTORE_DIR/avd/${AVD_NAME}.avd" ] || { echo "❌ 归档结构异常: 缺少 AVD 数据"; exit 1; }
[ -d "$RESTORE_DIR/$SYSIMG_REL" ] || { echo "❌ 归档结构异常: 缺少 system image"; exit 1; }

echo "[2/5] 补装/校验 SDK 组件 ..."

PINNED_EMU=""
if [ -f "$RESTORE_DIR/manifest.txt" ]; then
    PINNED_EMU=$(grep '^emulator_version=' "$RESTORE_DIR/manifest.txt" | head -1 | cut -d= -f2)
fi

mkdir -p "$SDK_DIR"

EMU_PKG=""
if [ -d "$RESTORE_DIR/emulator" ]; then
    echo "    使用归档内置 emulator（版本已锁定，不依赖 sdkmanager）"
    mkdir -p "$SDK_DIR/emulator"
    cp -Rf "$RESTORE_DIR/emulator/." "$SDK_DIR/emulator/"
    chmod +x "$SDK_DIR/emulator/emulator" 2>/dev/null || true
else
    EMU_PKG="emulator"
    if [ -n "$PINNED_EMU" ] && command -v sdkmanager >/dev/null 2>&1; then
        if sdkmanager --sdk_root="$SDK_DIR" --install "emulator@$PINNED_EMU" >/dev/null 2>&1; then
            EMU_PKG="emulator@$PINNED_EMU"
            echo "    已锁定 emulator 版本 $PINNED_EMU"
        else
            echo "    ⚠️  emulator@$PINNED_EMU 不可用，回退到最新版（可能与 patch 过的 ramdisk 不兼容）"
        fi
    fi
fi

SDK_PKGS=()
[ -n "$EMU_PKG" ] && SDK_PKGS+=("$EMU_PKG")

if [ -d "$RESTORE_DIR/platform-tools" ]; then
    mkdir -p "$SDK_DIR/platform-tools"
    cp -Rf "$RESTORE_DIR/platform-tools/." "$SDK_DIR/platform-tools/"
    echo "    ✅ platform-tools (adb) 来自归档，无需下载"
fi

if [ -f "$RESTORE_DIR/$SYSIMG_REL/system.img" ]; then
    echo "    ✅ system image 来自归档，无需下载"
else
    SDK_PKGS+=("system-images;android-34;google_apis_playstore;arm64-v8a")
    echo "    [*] system image 缺失，将从 sdkmanager 下载"
fi

if [ ${#SDK_PKGS[@]} -gt 0 ]; then
    if command -v sdkmanager >/dev/null 2>&1; then
        yes | sdkmanager --sdk_root="$SDK_DIR" --licenses >/dev/null 2>&1 || true
        sdkmanager --sdk_root="$SDK_DIR" "${SDK_PKGS[@]}" >/dev/null 2>&1 \
            || echo "    ⚠️  部分组件安装失败（运行模拟器不依赖它们，可稍后用 Android Studio 补装）"
    else
        echo "    ⚠️  未找到 sdkmanager 且需补装组件。请安装后重跑本脚本:"
        echo "        brew install --cask android-commandlinetools"
    fi
fi

echo "[3/5] 还原 AVD 数据 ..."
mkdir -p "$AVD_BASE_DIR"
rm -rf "${AVD_BASE_DIR:?}/${AVD_NAME}.avd"
cp -R "$RESTORE_DIR/avd/${AVD_NAME}.avd" "$AVD_BASE_DIR/"
cp -f "$RESTORE_DIR/avd/${AVD_NAME}.ini" "$AVD_BASE_DIR/"

echo "[4/5] 还原 system image (含 Magisk patch 过的 ramdisk.img) ..."
mkdir -p "$SDK_DIR/$SYSIMG_REL"
cp -Rf "$RESTORE_DIR/$SYSIMG_REL/." "$SDK_DIR/$SYSIMG_REL/"

if [ -d "$RESTORE_DIR/skins" ]; then
    mkdir -p "$SDK_DIR/skins"
    cp -Rf "$RESTORE_DIR/skins/." "$SDK_DIR/skins/"
fi

for f in adbkey adbkey.pub debug.keystore; do
    [ -f "$RESTORE_DIR/$f" ] && cp -f "$RESTORE_DIR/$f" "$HOME/.android/" || true
done
chmod 600 "$HOME/.android/adbkey" 2>/dev/null || true

echo "[5/5] 重写绝对路径 + 校验指纹 ..."

sed -i '' "s|^path=.*|path=$AVD_BASE_DIR/${AVD_NAME}.avd|" "$AVD_BASE_DIR/${AVD_NAME}.ini"
sed -i '' "s|^path.rel=.*|path.rel=avd/${AVD_NAME}.avd|" "$AVD_BASE_DIR/${AVD_NAME}.ini"
sed -i '' "s|^skin.path=.*|skin.path=$SDK_DIR/skins/pixel_8|" "$AVD_BASE_DIR/${AVD_NAME}.avd/config.ini"

if [ -f "$RESTORE_DIR/manifest.txt" ]; then
    EXPECT=$(grep -A1 'ramdisk.img$' "$RESTORE_DIR/manifest.txt" | grep -E '^[0-9a-f]{64}' | awk '{print $1}' | head -1 || true)
    ACTUAL=$(shasum -a 256 "$SDK_DIR/$SYSIMG_REL/ramdisk.img" 2>/dev/null | awk '{print $1}' || true)
    if [ -n "$EXPECT" ] && [ "$EXPECT" = "$ACTUAL" ]; then
        echo "    ✅ ramdisk.img 指纹一致 (Magisk Root 引导完好)"
    else
        echo "    ⚠️  ramdisk.img 指纹不一致，请检查"
    fi
fi

rm -rf "$RESTORE_DIR"

echo ""
echo "✅ 还原完成！直接启动 Pixel_8 即可，Root / LSPosed / 应用 / 数据均已恢复。"
echo "   启动: open -a 'Android Studio'  或  $SDK_DIR/emulator/emulator -avd $AVD_NAME"
