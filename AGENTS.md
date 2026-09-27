# AGENTS.md

给任何接手本仓库的 AI / 新人的快速上手文档。读完这一份就能操作。

## 这是什么

基于上游 [rootAVD](https://gitlab.com/newbit/rootAVD)（GPLv3）的**个人备份仓库**。
两份用途：

1. **Root 工具链** —— 上游 `rootAVD.sh` 及依赖，用于给模拟器打 Magisk Root
2. **备份工具链** —— 本仓库新增的三个脚本，用于备份 / 还原 / 回收 AVD

上游作者：[newbit @ xda-developers](https://forum.xda-developers.com/m/newbit.1350876)。
**保留 GPLv3 LICENSE 与上游署名，不要删除。**

---

## 关键前提：两条独立的链

| | 还原归档 | `rootAVD.sh` |
|---|---|---|
| 前提 | 需要 13G `.tar.zst` 归档 | 只需本仓库 |
| 结果 | 带你所有 App、登录态、Magisk 模块 | 干净的 root 环境 |
| Root 来源 | 归档里已 patch 的 `ramdisk.img` | 现场 patch |
| 用途 | 恢复现场 | 换新环境 / 变砖后重做 |

**GitHub 仓库不含 AVD 数据。** 归档含应用与账号数据，不适合入库，必须自己存 NAS
（当前：`/Volumes/Configs/复制粘贴用/备份/自己项目备份/rootAVD/`）。

---

## 环境实况（2026-09 实测）

- Mac mini / **arm64** / macOS 27.0
- AVD: `Pixel_8`，Android 14 (API 34) `google_apis_playstore` `arm64-v8a`
- emulator 37.1.11.0、Magisk v26.4 (26400)、Zygisk + LSPosed
- `ANDROID_HOME=$HOME/Library/Android/sdk`
- AVD 占用 **12G**（原始 30G，已压实），本地可用 ~35Gi

---

## 常用命令

### 备份 / 还原 / 回收

```bash
./pack_avd_full.sh [目标目录]     # 默认写 NAS，约 2 分钟
./unpack_avd_full.sh <归档.tar.zst>   # 一键还原，约 4 分钟
./shrink_avd.sh                  # 回收 qcow2 膨胀，约 6 分钟
```

依赖 `zstd`（脚本会自动 `brew install`）。emulator / platform-tools / system image
均从归档内取，**无网也能还原**。

### Root 一个 AVD

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
./rootAVD.sh system-images/android-34/google_apis_playstore/arm64-v8a/ramdisk.img
```

- 第一个参数是 **ramdisk.img 路径，相对 `$ANDROID_HOME`**，不是目录
- 可叠加选项：`DEBUG` `PATCHFSTAB` `GetUSBHPmodZ` `FAKEBOOTIMG` `InstallKernelModules` 等
- `./rootAVD.sh ListAllAVDs` 打印全部命令示例
- **必须在 macOS 主机上跑**，不能进模拟器 shell（脚本靠 `getprop` 探测）
- 会创建 `ramdisk.img.backup` 等备份；`./rootAVD.sh <path> restore` 可回滚

---

## 必知的坑

1. **`lib/*/libbusybox.so` 是 root 的硬依赖。** `FindWorkingBusyBox()` 遍历
   `lib/*/*busybox*`，缺失则 `abort_script` 直接退出。上游 `.gitignore` 忽略了它们，
   导致 fresh clone 后必然无法 root —— 本仓库已修正，**不要重新加回忽略**。
2. **真机连着 adb 时，`adb shell` 会打到手机上。** 手机开 WiFi 调试后
   `adb devices` 会出现 `192.168.x.x:5555`，不带 `-s` 的命令命中真机，表现为
   「模拟器没 root」「应用数对不上」的假象。验证一律用：
   ```bash
   adb -s emulator-5554 shell 'su -c id'
   ```
3. **`rootAVD.sh` 离线时会 `mv Magisk.zip Magisk.apk`**（`rename_copy_magisk()`），
   把仓库里受版本控制的 `Magisk.zip` 弄丢。恢复：`git checkout Magisk.zip`。
4. **Android 14 没有 `fstrim`**，宿主 qcow2 文件不会自动收缩，只能靠
   `qemu-img convert` 丢弃空闲簇。
5. **`qemu-img convert -c` 几乎不省空间**（实测仅 0.44% 簇被压缩），
   收益全来自丢弃空闲簇，加 `-c` 无意义。
6. **`fastboot.forceFastBoot=yes` 是 qcow2 膨胀的根因** —— quick-boot 内部快照让
   所有写入走 COW。`shrink_avd.sh` 会自动关掉它，代价是冷启动约 20 秒。
7. **旧脚本 `pack_avd_for_nas.sh` / `unpack_avd_from_nas.sh` 已删除**，
   前者不含 `system.img`，后者缺 `mkdir -p` 且失败后仍打印「✅ 完成」。

---

## 涉及的关键路径

```
AVD 数据        ~/.android/avd/Pixel_8.avd/
AVD 配置        ~/.android/avd/Pixel_8.ini
Root 引导镜像   $ANDROID_HOME/system-images/android-34/google_apis_playstore/arm64-v8a/ramdisk.img
原始 ramdisk    同目录 ramdisk.img.backup          （rootAVD.sh restore 用）
emulator        $ANDROID_HOME/emulator/emulator
qemu-img        $ANDROID_HOME/emulator/qemu-img    （SDK 自带，不在 PATH）
ADB 授权密钥    ~/.android/adbkey, adbkey.pub
备份归档        <NAS>/Pixel_8_full_backup_<时间戳>.tar.zst   约 13G
```

---

## 验证 Root 是否真的成功

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell 'su -c id'      # 期望 uid=0(0) ... context=u:r:magisk:s0
adb -s emulator-5554 shell 'magisk -V'     # 期望 26400
adb -s emulator-5554 shell 'su -c "ls /data/adb/modules"'   # 期望含 zygisk_lsposed
```

`su -c id` 的 `context=u:r:magisk:s0` 是关键 —— 只有这条能证明 Magisk 已接管。

---

## 给 AI 的操作纪律

- **改 `rootAVD.sh` 前先备份**，它是 3000 行的上游脚本，`sed` 批量替换极易出错
- **`pack_avd_full.sh` / `unpack_avd_full.sh` 拒绝在模拟器运行时执行**，
  报「模拟器正在运行」是预期行为，先 `adb -s emulator-5554 emu kill`
- **验证还原必须开机实测**，不能只看脚本打印「✅ 完成」—— 旧的
  `unpack_avd_from_nas.sh` 就是失败却报成功的反面教材
- **删除任何 AVD 文件前先确认 NAS 归档存在且校验过**（`zstd -t` + 尺寸比对）
