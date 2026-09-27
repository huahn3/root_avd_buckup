#!/bin/bash
# ==============================================================================
# AVD 磁盘回收脚本
# 原理: 删除 quick-boot 缓存 + 合并 qcow2 内部快照 + convert 丢弃空闲簇
#       (Android 14 无 fstrim, 宿主文件不会自动缩小, 只能靠 convert 压实)
# ==============================================================================
set -euo pipefail

AVD_NAME="${1:-Pixel_8}"
QEMU_IMG="$HOME/Library/Android/sdk/emulator/qemu-img"
AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
WORK_IMG="${TMPDIR:-/tmp}/shrink_${AVD_NAME}.qcow2"

echo "=== AVD 磁盘回收: $AVD_NAME ==="

[ -x "$QEMU_IMG" ] || { echo "❌ 找不到 qemu-img: $QEMU_IMG"; exit 1; }
[ -d "$AVD_DIR" ] || { echo "❌ 找不到 AVD: $AVD_DIR"; exit 1; }

if pgrep -f "emulator.*-avd ${AVD_NAME}" >/dev/null 2>&1; then
    echo "❌ 模拟器正在运行，请先关闭: adb emu kill"
    exit 1
fi

BEFORE=$(du -sh "$AVD_DIR" | awk '{print $1}')
BEFORE_IMG=$($QEMU_IMG info "$AVD_DIR/userdata-qemu.img.qcow2" 2>/dev/null | awk '/disk size/{print $3}')
echo "压缩前: AVD $BEFORE  userdata $BEFORE_IMG"

echo "[1/3] 删除 quick-boot 缓存 ..."
rm -rf "${AVD_DIR:?}/snapshots"
sed -i '' 's/^fastboot.forceFastBoot=yes/fastboot.forceFastBoot=no/' "$AVD_DIR/config.ini" 2>/dev/null || true
sed -i '' 's/^fastboot.forceColdBoot=no/fastboot.forceColdBoot=yes/' "$AVD_DIR/config.ini" 2>/dev/null || true

echo "[2/3] 合并 qcow2 内部快照 (若有) ..."
$QEMU_IMG snapshot -d default_boot "$AVD_DIR/userdata-qemu.img.qcow2" 2>/dev/null \
    && echo "    已合并 default_boot" \
    || echo "    无内部快照，跳过"

echo "[3/3] convert 压实 (耗时取决于数据量, 11G 约 6 分钟) ..."
rm -f "$WORK_IMG"
$QEMU_IMG convert -O qcow2 "$AVD_DIR/userdata-qemu.img.qcow2" "$WORK_IMG"

$QEMU_IMG check "$WORK_IMG" >/dev/null 2>&1 || { echo "❌ 压实结果校验失败，放弃替换"; rm -f "$WORK_IMG"; exit 1; }

OLD_IMG="${AVD_DIR}/userdata-qemu.img.qcow2.bak"
mv "$AVD_DIR/userdata-qemu.img.qcow2" "$OLD_IMG"
mv "$WORK_IMG" "$AVD_DIR/userdata-qemu.img.qcow2"

NEW_IMG=$($QEMU_IMG info "$AVD_DIR/userdata-qemu.img.qcow2" | awk '/disk size/{print $3}')
echo "    压实后 userdata $NEW_IMG (已校验无错, 原文件保留为 .bak)"

AFTER=$(du -sh "$AVD_DIR" | awk '{print $1}')
echo ""
echo "✅ 回收完成: AVD $BEFORE -> $AFTER"
echo "   确认模拟器可正常启动后, 删除回滚副本: rm -f $OLD_IMG"
echo "   启动: ~/Library/Android/sdk/emulator/emulator -avd $AVD_NAME"
