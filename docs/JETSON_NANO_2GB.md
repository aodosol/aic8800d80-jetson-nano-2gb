# Jetson Nano 2GB 安裝說明

本次依使用者提供的環境調整：`aarch64`、`4.9.337-tegra`、L4T `R32.7.6`（JetPack 4.6.6）。適用的是 AIC8800D80 USB Wi-Fi，原倉庫裝置 ID 為 `a69c:5721`、`a69c:8d80`、`a69c:8d83`；請用 `lsusb` 確認網卡型號。

目前僅完成原始碼與安裝流程調整。本次修改環境是 Windows，未在 Nano 上編譯或測試連線；不能將既有 Ubuntu 22.04 / Linux 6.8 的驗證紀錄視為 Nano 的測試結果。

## 1. 在 Nano 準備環境

將修改後的**整個資料夾**複製到 Nano，先解壓縮，再於資料夾根目錄開啟終端機。不要直接在壓縮檔管理員內執行，也不要使用原廠 `aic8800_linux_drvier/install_setup.sh`。

```bash
uname -r
head -n 1 /etc/nv_tegra_release
lsusb
sudo apt update
sudo apt install build-essential bc libssl-dev eject usbutils nvidia-l4t-kernel-headers
```

Tegra 使用 NVIDIA 的核心標頭，不是 Ubuntu generic 的 `linux-headers-$(uname -r)`。標頭必須與正在執行的核心完全相符。若安裝標頭時連帶更新 NVIDIA 核心，請重新啟動，再執行下列步驟。

## 2. 檢查並安裝

從包含 `README.md`、`scripts/`、`aic8800_linux_drvier/` 的根目錄執行：

```bash
bash scripts/install-jetson.sh --check
sudo bash scripts/install-jetson.sh
```

安裝程式會檢查 ARM64 / 4.9-tegra、核心標頭版本與 `Module.symvers`，清除舊編譯產物，以 `ARCH=arm64`、`-j1` 編譯兩個模組，並檢查其 vermagic。成功後才安裝模組、韌體、udev 規則和開機載入設定。編譯完整輸出保存在 `jetson-build.log`。

2GB 機型預設只使用一個編譯工作，以降低記憶體需求。若核心仍因記憶體不足終止 gcc，先關閉其他應用程式並檢查 `free -h`、`swapon --show` 及 `dmesg` 的 OOM 訊息。

若系統已載入舊版 AIC 模組，安裝程式會提示重新啟動，避免強制中斷現有連線。完成後重新插拔 USB 網卡。

只要編譯、暫不安裝，可執行：

```bash
bash scripts/install-jetson.sh --build-only
```

自訂核心可以明確指定已準備好的匹配標頭目錄：

```bash
sudo env KDIR=/path/to/matching/kernel/build bash scripts/install-jetson.sh
```

本流程採手動安裝；更新核心後需重新執行。若曾在 Nano 安裝這個倉庫的 DKMS 版本，請先用 `sudo dkms remove aic8800d80/1.0.0 --all` 移除該版本，以免 `updates/dkms` 下的舊模組優先於本次安裝的模組。

## 3. 驗證

```bash
modinfo -F vermagic aic_load_fw
modinfo -F vermagic aic8800_fdrv
lsmod | grep -E '^aic|^cfg80211'
lsusb
nmcli device status
nmcli device wifi list
dmesg | grep -iE 'aic|firmware|Call Trace|error'
```

兩個模組的 vermagic 應以目前的 `uname -r` 開頭。網卡通常先以 `a69c:5721` 出現，經由 eject 切換到 `a69c:8d80`，載入韌體後成為 `a69c:8d83`。需進一步確認能掃描、連線及取得 IP，才算完成實機驗證。

Linux 4.9 保留既有舊版 API 分支；目前未啟用需要額外核心回補的 WPA3 / HE 選項，請先以 WPA2 基地台驗證。

若編譯失敗，請提供 `jetson-build.log`；若載入或連線失敗，提供上述驗證輸出。編譯失敗時安裝程式會停止，不會繼續安裝。

## 本次修改

- 移除 Makefile 強制使用所有 CPU 的設定，讓 `-j1` 能真正生效。
- 讓核心版本、標頭目錄與交叉編譯器參數可由呼叫端傳入；使用 `$(MAKE)` 傳遞遞迴編譯設定。
- 使用 Make 的目前目錄作為模組位置，避免從其他目錄呼叫 `make -C` 時誤用 shell 的 `PWD`。
- 修正韌體載入器先 `memset()` 才檢查 `vmalloc()` 是否失敗的問題，避免記憶體不足時解參照空指標。
- 新增 Nano 專用檢查、單工作編譯、安裝與記錄流程。

參考：[NVIDIA L4T R32.7.6](https://developer.nvidia.com/embedded/linux-tegra-r3276)、[NVIDIA 外部核心模組編譯說明](https://docs.nvidia.com/jetson/archives/l4t-archived/l4t-3275/Tegra%20Linux%20Driver%20Package%20Development%20Guide/kernel_custom.html)。
