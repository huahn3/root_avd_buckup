# AVD 全量备份 / 还原 / 回收 使用指南

在 Root、安装 Magisk 模块或配置 LSPosed 时，模拟器经常因模块冲突而变砖、无限重启（Bootloop）或系统损坏。
本目录提供三个脚本，把 AVD 连同 **Magisk Root 引导** 打成单文件归档，支持一键还原与磁盘回收。

---

## 脚本一览

| 脚本 | 作用 | 耗时（11G userdata） |
|---|---|---|
| `pack_avd_full.sh` | 全量打包 → 单个 `.tar.zst` | 约 2 分钟 |
| `unpack_avd_full.sh` | 从归档一键还原（含 SDK 自动补装） | 约 4 分钟 |
| `shrink_avd.sh` | 回收 qcow2 膨胀，不动任何数据 | 约 6 分钟 |

依赖：`zstd`（脚本会自动 `brew install`）。`sdkmanager` 可选，归档已自带
emulator / platform-tools / system image，**无网也能还原**。

---

## 全新机器从零恢复（重要）

**GitHub 仓库只放脚本和 Root 工具链，不放 AVD 数据。**
13G 的 `.tar.zst` 归档体积过大且含你的应用与账号数据，必须自己存 NAS。

完整流程：

```bash
# 1. 克隆仓库
git clone https://github.com/huahn3/root_avd_buckup.git
cd root_avd_buckup

# 2. 从 NAS 取回归档（唯一需要你自己保管的东西）
cp /Volumes/Configs/.../Pixel_8_full_backup_<时间戳>.tar.zst .

# 3. 一键还原
./unpack_avd_full.sh ./Pixel_8_full_backup_<时间戳>.tar.zst

# 4. 启动
~/Library/Android/sdk/emulator/emulator -avd Pixel_8
```

还原后 AVD **已带 Root**，不需要再跑 `rootAVD.sh`。

### 若想 Root 一个全新的 AVD

```bash
./rootAVD.sh
```

⚠️ `lib/*/libbusybox.so` 是 **root 的硬依赖**，必须随仓库分发。
`rootAVD.sh` 的 `FindWorkingBusyBox()` 直接遍历 `lib/*/*busybox*`，
目录缺失会打印 "Can not find any working Busybox Version" 并 `abort_script` 退出。
上游仓库用 `.gitignore` 忽略了它们，导致 **fresh clone 后必然无法 root** —— 本仓库已修正。

### 两条路径的区别

| | 还原归档 | `rootAVD.sh` |
|---|---|---|
| 前提 | 需要 13G 归档 | 只需仓库 |
| 结果 | 带你所有 App、登录态、模块 | 干净的 root 环境 |
| Root 来源 | 归档里的 patched ramdisk | 现场 patch |
| 适用 | 恢复现场 | 换新环境 / 变砖后重做 |

---

## 备份包含什么

| 内容 | 路径 | 作用 |
|---|---|---|
| AVD 用户数据 | `~/.android/avd/Pixel_8.avd/` | 全部 App、沙盒数据、登录状态 |
| Magisk 模块 / LSPosed | 同上（`/data/adb`） | Root 框架与 Xposed 模块 |
| AVD 配置 | `~/.android/avd/Pixel_8.ini`、`config.ini` | 设备参数、绝对路径 |
| **Root 引导镜像** | `…/arm64-v8a/ramdisk.img` | **Magisk patch 过的，最关键** |
| 原始 ramdisk 备份 | `…/arm64-v8a/ramdisk.img.backup` | rootAVD 项目回滚用 |
| system image | `…/arm64-v8a/`（`system.img` 等） | 完整 Android 14 Google Play 镜像 |
| 设备皮肤 | `~/Library/Android/sdk/skins/` | Pixel 8 外观 |
| **emulator 本体** | `~/Library/Android/sdk/emulator/` | **锁定版本，不依赖 sdkmanager** |
| adb 密钥 | `~/.android/adbkey`、`debug.keystore` | 免重新授权、debug 签名一致 |

> 为什么要打包 emulator 本体：Google 仓库**只提供最新版** emulator，旧版本（如 `emulator@36.5.11`）已下架。
> 若还原时装到不兼容的新版 emulator，patch 过的 ramdisk 可能不生效，你会得到一个**没有 Root 的环境**且毫无提示。
> 打包本体可彻底规避此风险。

---

## 1. 打包

```bash
./pack_avd_full.sh [目标目录]
```

默认写入 `/Volumes/Configs/复制粘贴用/备份/自己项目备份/rootAVD`。
产出的 `Pixel_8_full_backup_<时间戳>.tar.zst` 约 **13G**（原始 16.7G）。
脚本会先做 `zstd -t` 完整性校验再复制，且**拒绝在模拟器运行时打包**。

## 2. 还原（变砖 / 换机 / 重装后）

```bash
./unpack_avd_full.sh "/Volumes/Configs/复制粘贴用/备份/自己项目备份/rootAVD/Pixel_8_full_backup_20260927_230917.tar.zst"
```

自动完成 5 步：

1. 解压归档到临时区并校验结构
2. 补装 SDK 组件（emulator 优先用归档内置版本）
3. 覆盖还原 AVD 数据与配置
4. 覆盖还原 system image（含 Magisk patch 过的 `ramdisk.img`）
5. **重写绝对路径**（`Pixel_8.ini` 的 `path=`、`config.ini` 的 `skin.path=`）并比对 ramdisk 指纹

启动：

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_8
# 或 open -a "Android Studio"
```

## 3. 回收磁盘

模拟器用久了 `userdata-qemu.img.qcow2` 会不断膨胀（宿主占用可超过 20G 虚拟大小），
在模拟器里删应用**不会**让宿主文件变小。定期跑：

```bash
./shrink_avd.sh
```

原理：删 quick-boot 缓存 → 合并 qcow2 内部快照 → `qemu-img convert` 丢弃空闲簇。
脚本会自动关闭 fast-boot（`fastboot.forceFastBoot=no`）以防再次膨胀，代价是冷启动约 20 秒。
压实后原文件保留为 `.bak`，确认能启动后再手动删除。

---

## 已知的坑（都已在脚本里处理）

1. **Android 14 没有 `fstrim`** —— 宿主文件不会自动收缩，只能靠 `qemu-img convert` 压实。
2. **`qemu-img convert -c` 几乎不省空间** —— 实测仅 0.44% 簇被压缩，收益全部来自丢弃空闲簇，加 `-c` 无意义。
3. **quick-boot 缓存很占地方** —— `snapshots/default_boot/ram.bin` 单独就 5.2G。
4. **内部快照导致 COW 膨胀** —— `fastboot.forceFastBoot=yes` 时每次写入都写进快照，镜像只增不减。
5. **`config.ini` 写死绝对路径** —— 换用户名或换机直接失效，还原时必须重写。
6. **旧脚本 `pack_avd_for_nas.sh` 不含 `system.img`**，`unpack_avd_from_nas.sh` 缺 `mkdir -p` 且会静默失败后仍打印"✅ 完成"。**已废弃，请勿使用。**
7. **`lib/*/libbusybox.so` 被上游 `.gitignore` 忽略** —— 这是 root 功能的硬依赖，fresh clone 后 `rootAVD.sh` 必然 abort。本仓库已纳入版本控制。
8. **`rootAVD.sh` 跑完会 `mv Magisk.zip Magisk.apk`**（`rename_copy_magisk()`，`MAGISKVERCHOOSEN` 为假时走 rename 分支），导致 `Magisk.zip` 从工作区消失、仓库变脏、二次运行失败。恢复方法：`git checkout Magisk.zip`。
9. **GitHub 仓库不含 AVD 数据** —— 13G 归档含应用与账号数据，不适合入库，必须自己存 NAS。仓库只保证「Root 工具链 + 备份/还原/回收脚本」。
10. **真机同时连着 adb 时，`adb shell` 会打到手机上** —— 若手机开了 WiFi 调试并连着（`adb devices` 出现 `192.168.x.x:5555`），不带 `-s` 的命令会命中真机而非模拟器，表现为「模拟器没有 root」「应用数量对不上」等假象。验证时务必：
    ```bash
    adb -s emulator-5554 shell 'su -c id'
    ```

---

## 备份关联路径速查

```
归档文件    ./Pixel_8_full_backup_<时间戳>.tar.zst
AVD 数据    ~/.android/avd/Pixel_8.avd/
AVD 配置    ~/.android/avd/Pixel_8.ini
Root 引导   ~/Library/Android/sdk/system-images/android-34/google_apis_playstore/arm64-v8a/ramdisk.img
emulator    ~/Library/Android/sdk/emulator/emulator
```
