# AIC8800D80 Linux USB Wi-Fi Driver

[中文](#中文说明) | [English](#english)

**Jetson Nano 2GB（JetPack 4.x / ARM64 / Linux 4.9-tegra）：請先閱讀 [Nano 安裝說明](docs/JETSON_NANO_2GB.md)，使用 `sudo bash scripts/install-jetson.sh`。此平台尚待實機編譯與連線驗證。**

**Jetson Nano 2GB:** see the [Nano installation guide](docs/JETSON_NANO_2GB.md). The native installer targets JetPack 4.x / ARM64 / Linux 4.9-tegra; hardware validation is pending.

This repository contains the AIC8800D80 USB Wi-Fi driver, firmware, Linux 6.8 compatibility fixes, and DKMS support. It was built and tested on Ubuntu 22.04 with kernels `6.8.0-124-generic` and `6.8.0-138-generic`, using USB device `a69c:8d80` / `a69c:8d83`.

本仓库包含 AIC8800D80 USB Wi-Fi 驱动、固件、Linux 6.8 兼容补丁及 DKMS 支持。已在 Ubuntu 22.04、内核 `6.8.0-124-generic` 和 `6.8.0-138-generic`、USB 设备 `a69c:8d80` / `a69c:8d83` 上完成编译及实机验证。

## 中文说明

### 已验证功能

- 固件从 `a69c:8d80` 启动态下载，并重新枚举为 `a69c:8d83`
- 2.4 GHz 和 5 GHz Wi-Fi 扫描
- WPA/WPA2 关联
- DHCP 获取 IPv4 地址
- NetworkManager 管理
- 模块卸载、重新加载和 USB 重新插入

### 支持环境

当前版本已验证：

- Ubuntu 22.04
- Linux `6.8.0-124-generic`、`6.8.0-138-generic`
- x86_64
- AIC8800D80 USB Wi-Fi，VID:PID 为 `a69c:5721`、`a69c:8d80` 或 `a69c:8d83`

代码保留了旧内核兼容分支，但其他发行版及内核版本尚未逐一验证。

### 1. 安装编译依赖

```bash
sudo apt update
sudo apt install build-essential linux-headers-$(uname -r) dkms eject
```

确认当前内核的构建目录存在：

```bash
test -e /lib/modules/$(uname -r)/build && echo "kernel headers ready"
```

### 2. 推荐：使用 DKMS 安装

在仓库根目录执行：

```bash
chmod +x scripts/install-dkms.sh
sudo ./scripts/install-dkms.sh
```

此脚本会安装固件和 udev 规则、注册并构建两个 DKMS 模块，并配置开机自动加载。以后安装新内核时，DKMS 会为新内核自动重建驱动；新内核对应的头文件必须已经安装。

安装完成后可直接跳到“验证”章节。以下第 3 至 5 节保留为手动安装方法。

### 3. 手动安装：固件和 udev 规则

在仓库根目录执行：

```bash
sudo install -d /lib/firmware/aic8800D80
sudo install -m 0644 aic8800_linux_drvier/fw/aic8800D80/* /lib/firmware/aic8800D80/
sudo install -m 0644 aic8800_linux_drvier/tools/aic.rules /etc/udev/rules.d/aic.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

udev 规则会弹出网卡自带的只读存储设备，使硬件从 `a69c:5721` 切换到 Wi-Fi 启动态。

### 4. 手动安装：编译驱动

```bash
cd aic8800_linux_drvier/drivers/aic8800
make clean
make
```

成功后会生成：

```text
aic_load_fw/aic_load_fw.ko
aic8800_fdrv/aic8800_fdrv.ko
```

编译时可能看到 `no previous prototype` 警告。这些是原厂源码已有的非致命警告；最终构建应以退出状态 0 结束。

### 5. 手动安装：安装并加载模块

仍在 `aic8800_linux_drvier/drivers/aic8800` 目录中执行：

```bash
sudo make install
sudo modprobe cfg80211
sudo modprobe aic_load_fw
sudo modprobe aic8800_fdrv
```

如果旧模块已经加载，先替换内存中的版本：

```bash
sudo modprobe -r aic8800_fdrv aic_load_fw
sudo modprobe aic_load_fw
sudo modprobe aic8800_fdrv
```

然后拔出并重新插入网卡。等待数秒，让设备依次完成存储模式弹出、固件下载和 Wi-Fi 接口创建。

### 6. 验证

```bash
lsmod | grep -E '^aic|^cfg80211'
nmcli device status
nmcli device wifi list
journalctl -k -b | grep -i aic
```

成功时应能看到：

- `aic_load_fw` 和 `aic8800_fdrv` 已加载
- 类似 `wlx40a5ef5f040a` 的 Wi-Fi 接口
- `nmcli device wifi list` 能列出附近热点
- 内核日志包含 `fw download complete` 和 `New interface create wlan0`

### 7. 卸载

```bash
sudo modprobe -r aic8800_fdrv aic_load_fw
sudo dkms remove aic8800d80/1.0.0 --all
sudo rm -f /etc/modules-load.d/aic8800d80.conf
cd aic8800_linux_drvier/drivers/aic8800
sudo make uninstall
sudo rm -rf /lib/firmware/aic8800D80
sudo rm -f /etc/udev/rules.d/aic.rules
sudo udevadm control --reload-rules
```

### 内核升级说明

推荐使用上述 DKMS 安装方式。升级内核时，只要对应的内核头文件已经安装，DKMS 就会自动重建并安装驱动。手动安装方式仍需在每次内核升级后重新编译和安装。

### 故障排查

- 看不到 USB 设备：执行 `lsusb`，并重新插入网卡。
- 设备停在 `a69c:5721`：确认 `eject` 已安装、udev 规则存在，然后重新插入网卡。
- 设备停在 `a69c:8d80`：确认 `aic_load_fw` 已加载，且固件位于 `/lib/firmware/aic8800D80/`。
- 有接口但扫描为空：重启无线管理服务：

  ```bash
  sudo systemctl restart wpa_supplicant.service NetworkManager.service
  ```

- 模块格式错误：确认驱动是针对当前 `uname -r` 编译的，并检查 `modinfo` 中的 `vermagic`。

详细的 Linux 6.8 修改记录见 [docs/PORTING_REPORT.md](docs/PORTING_REPORT.md)。

## English

### Verified functionality

- Firmware download from boot-stage device `a69c:8d80`, followed by re-enumeration as `a69c:8d83`
- 2.4 GHz and 5 GHz Wi-Fi scanning
- WPA/WPA2 association
- IPv4 configuration through DHCP
- NetworkManager integration
- Module reload and physical USB reconnect

### Supported environment

The current version was tested with:

- Ubuntu 22.04
- Linux `6.8.0-124-generic` and `6.8.0-138-generic`
- x86_64
- AIC8800D80 USB Wi-Fi with VID:PID `a69c:5721`, `a69c:8d80`, or `a69c:8d83`

Compatibility branches for older kernels remain in the source, but other distributions and kernel versions have not been tested individually.

### 1. Install build dependencies

```bash
sudo apt update
sudo apt install build-essential linux-headers-$(uname -r) dkms eject
```

Check that the kernel build directory exists:

```bash
test -e /lib/modules/$(uname -r)/build && echo "kernel headers ready"
```

### 2. Recommended: install with DKMS

Run from the repository root:

```bash
chmod +x scripts/install-dkms.sh
sudo ./scripts/install-dkms.sh
```

The script installs firmware and the udev rule, registers and builds both DKMS modules, and configures them to load at boot. DKMS then rebuilds the driver when a new kernel is installed, provided that the matching kernel headers are installed.

After the script finishes, continue at the verification section. Sections 3 through 5 below describe the manual alternative.

### 3. Manual installation: firmware and udev rule

Run these commands from the repository root:

```bash
sudo install -d /lib/firmware/aic8800D80
sudo install -m 0644 aic8800_linux_drvier/fw/aic8800D80/* /lib/firmware/aic8800D80/
sudo install -m 0644 aic8800_linux_drvier/tools/aic.rules /etc/udev/rules.d/aic.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

The udev rule ejects the adapter's read-only storage device so it can switch from `a69c:5721` to Wi-Fi boot mode.

### 4. Manual installation: build the driver

```bash
cd aic8800_linux_drvier/drivers/aic8800
make clean
make
```

A successful build creates:

```text
aic_load_fw/aic_load_fw.ko
aic8800_fdrv/aic8800_fdrv.ko
```

The vendor source emits several non-fatal `no previous prototype` warnings. The build itself should finish with exit status 0.

### 5. Manual installation: install and load the modules

From `aic8800_linux_drvier/drivers/aic8800`, run:

```bash
sudo make install
sudo modprobe cfg80211
sudo modprobe aic_load_fw
sudo modprobe aic8800_fdrv
```

If an older build is already loaded, replace it with the installed modules:

```bash
sudo modprobe -r aic8800_fdrv aic_load_fw
sudo modprobe aic_load_fw
sudo modprobe aic8800_fdrv
```

Physically reconnect the adapter. Allow a few seconds for storage-mode ejection, firmware download, and Wi-Fi interface creation.

### 6. Verify the installation

```bash
lsmod | grep -E '^aic|^cfg80211'
nmcli device status
nmcli device wifi list
journalctl -k -b | grep -i aic
```

A working installation shows:

- Loaded `aic_load_fw` and `aic8800_fdrv` modules
- A Wi-Fi interface similar to `wlx40a5ef5f040a`
- Nearby access points in `nmcli device wifi list`
- `fw download complete` and `New interface create wlan0` in the kernel log

### 7. Uninstall

```bash
sudo modprobe -r aic8800_fdrv aic_load_fw
sudo dkms remove aic8800d80/1.0.0 --all
sudo rm -f /etc/modules-load.d/aic8800d80.conf
cd aic8800_linux_drvier/drivers/aic8800
sudo make uninstall
sudo rm -rf /lib/firmware/aic8800D80
sudo rm -f /etc/udev/rules.d/aic.rules
sudo udevadm control --reload-rules
```

### Kernel upgrades

The recommended DKMS installation automatically rebuilds and installs the driver after a kernel upgrade, provided that matching kernel headers are installed. A manual installation must still be rebuilt and reinstalled after every kernel upgrade.

### Troubleshooting

- USB device is absent: run `lsusb` and physically reconnect the adapter.
- Device remains at `a69c:5721`: verify that `eject` is installed and the udev rule exists, then reconnect the adapter.
- Device remains at `a69c:8d80`: verify that `aic_load_fw` is loaded and that firmware files exist under `/lib/firmware/aic8800D80/`.
- Interface exists but scans return no results: restart the wireless management services:

  ```bash
  sudo systemctl restart wpa_supplicant.service NetworkManager.service
  ```

- Invalid module format: make sure the module was built for the current `uname -r` and inspect its `vermagic` with `modinfo`.

See [docs/PORTING_REPORT.md](docs/PORTING_REPORT.md) for the Linux 6.8 porting and validation record.
