#!/bin/bash
# ==============================================================================
# AVD 完整备份脚本 (全量可还原版)
# 备份 AVD 数据 + Magisk Root 引导 + system image + skin + adb 密钥 + SDK 组件清单
# ==============================================================================
set -euo pipefail

AVD_NAME="Pixel_8"
SDK_DIR="$HOME/Library/Android/sdk"
AVD_BASE_DIR="$HOME/.android/avd"
SYSIMG_REL="system-images/android-34/google_apis_playstore/arm64-v8a"

DEST_DIR="${1:-/Volumes/Configs/复制粘贴用/备份/自己项目备份/rootAVD}"
STAGE_DIR="${TMPDIR:-/tmp}/avd_backup_stage"
ARCHIVE_NAME="Pixel_8_full_backup_$(date +%Y%m%d_%H%M%S).tar.zst"

echo "=== AVD 完整备份 ==="

if pgrep -f "emulator.*-avd ${AVD_NAME}" >/dev/null 2>&1; then
    echo "❌ 模拟器正在运行，请先关闭: adb emu kill"
    exit 1
fi

for p in "$AVD_BASE_DIR/${AVD_NAME}.avd" "$AVD_BASE_DIR/${AVD_NAME}.ini" "$SDK_DIR/$SYSIMG_REL"; do
    [ -e "$p" ] || { echo "❌ 缺少: $p"; exit 1; }
done

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

MANIFEST="$STAGE_DIR/manifest.txt"
{
    echo "backup_time=$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "host=$(scutil --get ComputerName 2>/dev/null || hostname)"
    echo "avd_name=$AVD_NAME"
    echo "emulator_version=$("$SDK_DIR/emulator/emulator" -version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    echo "avd_ini=$AVD_BASE_DIR/${AVD_NAME}.ini"
    echo "avd_dir=$AVD_BASE_DIR/${AVD_NAME}.avd"
    echo "system_image_dir=$SDK_DIR/$SYSIMG_REL"
    echo "sdk_packages=emulator|platform-tools|platforms;android-34|build-tools;34.0.0|system-images;android-34;google_apis_playstore;arm64-v8a"
    echo "--- ramdisk 指纹 (Magisk Root 引导) ---"
    shasum -a 256 "$SDK_DIR/$SYSIMG_REL/ramdisk.img" 2>/dev/null || true
    shasum -a 256 "$SDK_DIR/$SYSIMG_REL/ramdisk.img.backup" 2>/dev/null || true
    echo "--- userdata 指纹 (应用/数据/Magisk模块/LSPosed) ---"
    shasum -a 256 "$AVD_BASE_DIR/${AVD_NAME}.avd/userdata-qemu.img.qcow2" 2>/dev/null || true
} > "$MANIFEST"

echo "[*] 生成清单完成"

echo "[*] 打包中 (userdata 11G + system.img 3.1G, 请耐心等待)..."
tar -cf - \
    --exclude '.DS_Store' \
    --exclude 'tmpAdbCmds' \
    -C "$HOME/.android" "avd/${AVD_NAME}.avd" "avd/${AVD_NAME}.ini" \
    -C "$HOME/.android" "adbkey" "adbkey.pub" "debug.keystore" \
    -C "$SDK_DIR" "$SYSIMG_REL" "skins" "emulator" "platform-tools" \
    -C "$STAGE_DIR" "manifest.txt" \
  | zstd -T0 -6 -o "$STAGE_DIR/$ARCHIVE_NAME"

echo "[*] 校验归档完整性..."
zstd -t "$STAGE_DIR/$ARCHIVE_NAME" >/dev/null 2>&1 || { echo "❌ 归档损坏"; exit 1; }

SIZE=$(du -h "$STAGE_DIR/$ARCHIVE_NAME" | awk '{print $1}')
echo "    归档: $ARCHIVE_NAME  ($SIZE)"

echo "[*] 复制到目标目录 $DEST_DIR ..."
mkdir -p "$DEST_DIR"
cp "$STAGE_DIR/$ARCHIVE_NAME" "$DEST_DIR/"

RSIZE=$(du -h "$DEST_DIR/$ARCHIVE_NAME" | awk '{print $1}')
echo "✅ 备份完成: $DEST_DIR/$ARCHIVE_NAME  ($RSIZE)"
