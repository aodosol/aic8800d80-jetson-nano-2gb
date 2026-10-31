# AIC8800D80 Linux 6.8 移植记录 / Linux 6.8 Porting Report

## 中文

### 目标与环境

本次工作将 2023 年的 AIC8800D80 原厂 Linux USB Wi-Fi 驱动移植到 Ubuntu 22.04 的 `6.8.0-124-generic` 内核，并在真实硬件上完成安装和联网验证。

硬件枚举过程：

```text
a69c:5721  Aic MSC（只读存储模式）
    ↓ udev/eject
a69c:8d80  AIC Wlan（固件加载模式）
    ↓ aic_load_fw + firmware
a69c:8d83  AIC 8800D80（工作模式）
```

### 源码修改

1. `aic8800_fdrv/rwnx_rx.c`

   Linux 6.3 及之后的 `ieee80211_amsdu_to_8023s()` 增加了 `mesh_control` 参数。新版本分支传入 `0`，旧内核继续使用原调用形式。

2. `aic8800_fdrv/rwnx_main.c`

   Linux 6.7 移除了 `struct wireless_dev.mtx`。新版本改用 `wiphy_lock()` / `wiphy_unlock()` 保护信道切换状态。

3. `aic8800_fdrv/rwnx_main.c`

   Linux 6.7 将 cfg80211 的 `change_beacon` 回调参数改为 `struct cfg80211_ap_update`。新版本从 `update->beacon` 取得原驱动所需的 beacon 数据。

4. `aic8800_fdrv/rwnx_mod_params.c`

   新内核已删除 `REGULATORY_IGNORE_STALE_KICKOFF`。仅在 Linux 6.5 以前设置该标志，同时保留 `REGULATORY_WIPHY_SELF_MANAGED`。

5. `aic_load_fw/aicbluetooth.c`

   Linux 6.8 FORTIFY 检测到从 `adid_addrinf` 成员开始的 `memcpy()` 跨越多个结构体字段。修改后以结构体偏移和剩余容量为边界执行复制，并在复制前校验固件表长度，避免越界及 field-spanning 警告。

6. `aic_load_fw/aic_compat_8800d80.c`

   调用端现在检查固件 patch info 解包结果。无效长度会释放 patch table 并返回 `-EINVAL`，不会继续使用不完整数据。

### 实机验证结果

- 干净构建成功，生成 `aic_load_fw.ko` 和 `aic8800_fdrv.ko`
- 模块 `vermagic` 与 `6.8.0-124-generic` 一致
- Secure Boot 处于关闭状态，模块可直接加载
- 固件 MD5 校验和下载成功
- 最终固件版本日志：`Jan 22 2024 21:31:40 - g12ee6af`
- 成功创建无线网络接口
- 扫描到 2.4 GHz 和 5 GHz 热点
- 成功连接测试用无线网络
- DHCP 成功获取 IPv4 地址和默认网关
- 最终断电重插后未再次出现 FORTIFY、field-spanning write 或 Call Trace

原厂源码仍会产生若干 `-Wmissing-prototypes` 警告，但不会阻止模块构建或加载。

### 内核升级与 DKMS 修复

系统重启后切换到 `6.8.0-138-generic`，原先只为 `6.8.0-124-generic` 安装的模块无法被新内核找到。源码在新内核上重新编译、安装和加载后，USB 设备、无线接口及原有连接均恢复正常。

仓库随后加入 `dkms.conf` 和 `scripts/install-dkms.sh`。推荐安装流程现在通过 DKMS 注册两个模块，并通过 `/etc/modules-load.d/aic8800d80.conf` 配置开机加载，从而在后续内核升级时自动重建驱动。

从手动模块切换到 DKMS 模块的热重载测试也已通过。热重载后需要重启 `wpa_supplicant` 和 `NetworkManager`，随后保存的连接和热点扫描均恢复。

## English

### Goal and environment

This work ports the 2023 vendor AIC8800D80 Linux USB Wi-Fi driver to Ubuntu 22.04 with kernel `6.8.0-124-generic`, followed by installation and network validation on physical hardware.

Hardware enumeration sequence:

```text
a69c:5721  Aic MSC (read-only storage mode)
    ↓ udev/eject
a69c:8d80  AIC Wlan (firmware-loader mode)
    ↓ aic_load_fw + firmware
a69c:8d83  AIC 8800D80 (operational mode)
```

### Source changes

1. `aic8800_fdrv/rwnx_rx.c`

   Linux 6.3 and later add the `mesh_control` argument to `ieee80211_amsdu_to_8023s()`. The new compatibility branch passes `0`, while older kernels retain the original call.

2. `aic8800_fdrv/rwnx_main.c`

   Linux 6.7 removes `struct wireless_dev.mtx`. The new branch uses `wiphy_lock()` and `wiphy_unlock()` while updating channel-switch state.

3. `aic8800_fdrv/rwnx_main.c`

   Linux 6.7 changes the cfg80211 `change_beacon` callback argument to `struct cfg80211_ap_update`. The driver now obtains its beacon data from `update->beacon` on newer kernels.

4. `aic8800_fdrv/rwnx_mod_params.c`

   New kernels remove `REGULATORY_IGNORE_STALE_KICKOFF`. The driver sets it only before Linux 6.5 and continues to use `REGULATORY_WIPHY_SELF_MANAGED`.

5. `aic_load_fw/aicbluetooth.c`

   Linux 6.8 FORTIFY reports that a `memcpy()` starting at `adid_addrinf` spans several structure fields. The new code copies through a structure-relative offset, calculates the available capacity, and validates the firmware table length before copying. This removes the field-spanning warning and prevents an overflow.

6. `aic_load_fw/aic_compat_8800d80.c`

   The caller now checks the patch-info unpack result. Invalid data frees the patch table and returns `-EINVAL` instead of continuing with incomplete fields.

### Hardware validation

- Clean build completed and produced `aic_load_fw.ko` and `aic8800_fdrv.ko`
- Module `vermagic` matches `6.8.0-124-generic`
- Secure Boot was disabled, allowing direct module loading
- Firmware MD5 verification and download completed
- Reported firmware build: `Jan 22 2024 21:31:40 - g12ee6af`
- A wireless network interface was created successfully
- 2.4 GHz and 5 GHz access points discovered
- Successfully associated with the test Wi-Fi network
- DHCP successfully assigned an IPv4 address and default gateway
- No FORTIFY, field-spanning-write, or Call Trace warning after the final physical reconnect

The vendor source still emits several `-Wmissing-prototypes` warnings. They do not prevent module compilation or loading.

### Kernel upgrade and DKMS fix

After a reboot, the system moved to `6.8.0-138-generic`. The modules previously installed only for `6.8.0-124-generic` were unavailable to the new kernel. Rebuilding, installing, and loading the source for the new kernel restored the USB device, wireless interface, and saved connection.

The repository now includes `dkms.conf` and `scripts/install-dkms.sh`. The recommended installation registers both modules with DKMS and configures boot-time loading through `/etc/modules-load.d/aic8800d80.conf`, allowing the driver to be rebuilt automatically during future kernel upgrades.

The transition from manually installed modules to DKMS modules was also tested through a live reload. Restarting `wpa_supplicant` and `NetworkManager` after the reload restored the saved connection and access-point scanning.
