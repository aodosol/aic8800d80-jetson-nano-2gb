#!/usr/bin/env bash
# Native build/install for Jetson Nano (JetPack 4.x / L4T R32 / ARM64).
set -euo pipefail

MODE="${1:---install}"
case "${MODE}" in
    --check|--build-only|--install) ;;
    *) echo "Usage: bash scripts/install-jetson.sh [--check|--build-only|--install]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DRIVER_DIR="${REPO_DIR}/aic8800_linux_drvier/drivers/aic8800"
KVER="$(uname -r)"
JOBS="${JOBS:-1}"

if [[ $(uname -m) != aarch64 || ${KVER} != 4.9.*-tegra* ]]; then
    echo "This script targets native ARM64 Jetson Linux 4.9.*-tegra; found $(uname -m) ${KVER}." >&2
    exit 1
fi
if [[ ! ${JOBS} =~ ^[1-9][0-9]*$ ]]; then
    echo "JOBS must be a positive integer (recommended: 1 on Nano 2GB)." >&2
    exit 1
fi
if [[ ${MODE} == --install && ${EUID} -ne 0 ]]; then
    echo "Install with: sudo bash scripts/install-jetson.sh" >&2
    exit 1
fi
for command in make gcc tee; do
    command -v "${command}" >/dev/null || { echo "Missing command: ${command}; install build-essential." >&2; exit 1; }
done
if [[ ${MODE} == --install ]]; then
    for command in install depmod modprobe modinfo udevadm eject; do
        command -v "${command}" >/dev/null || { echo "Missing command: ${command}" >&2; exit 1; }
    done
fi

# NVIDIA header packages may expose the tree through either of these paths.
# An explicit KDIR is supported for a matching custom/prepared kernel tree.
if [[ -z ${KDIR:-} ]]; then
    for candidate in "/lib/modules/${KVER}/build" \
        "/usr/src/linux-headers-${KVER}-ubuntu18.04_aarch64/kernel-4.9" \
        "/usr/src/linux-headers-${KVER}-ubuntu18.04_aarch64"; do
        if [[ -f ${candidate}/Makefile && -f ${candidate}/include/config/kernel.release ]]; then
            KDIR="${candidate}"
            break
        fi
    done
fi
if [[ -z ${KDIR:-} || ! -f ${KDIR}/Makefile || ! -f ${KDIR}/include/config/kernel.release ]]; then
    echo "Missing prepared NVIDIA kernel headers for ${KVER}." >&2
    echo "Install matching nvidia-l4t-kernel-headers, or set KDIR to the matching prepared kernel tree." >&2
    exit 1
fi
HEADER_RELEASE="$(cat "${KDIR}/include/config/kernel.release")"
if [[ ${HEADER_RELEASE} != "${KVER}" ]]; then
    echo "Kernel header mismatch: running ${KVER}, headers ${HEADER_RELEASE}." >&2
    exit 1
fi
if [[ ! -s ${KDIR}/Module.symvers ]]; then
    echo "Missing ${KDIR}/Module.symvers; use the headers/build tree for the running NVIDIA kernel." >&2
    exit 1
fi
echo "Kernel: ${KVER}; headers: ${KDIR}; ARCH: arm64; build jobs: ${JOBS}"
[[ ${MODE} != --check ]] || exit 0

# Keep a complete log; pipefail preserves a compiler failure through tee.
make -C "${DRIVER_DIR}" KDIR="${KDIR}" KVER="${KVER}" ARCH=arm64 clean
make -C "${DRIVER_DIR}" -j"${JOBS}" KDIR="${KDIR}" KVER="${KVER}" \
    ARCH=arm64 CROSS_COMPILE= modules 2>&1 | tee "${REPO_DIR}/jetson-build.log"
[[ ${MODE} != --build-only ]] || exit 0

# Verify both outputs before changing the installed driver or firmware.
for module in aic_load_fw aic8800_fdrv; do
    VERMAGIC="$(modinfo -F vermagic "${DRIVER_DIR}/${module}/${module}.ko")"
    if [[ ${VERMAGIC%% *} != "${KVER}" ]]; then
        echo "Unexpected vermagic for ${module}: ${VERMAGIC}" >&2
        exit 1
    fi
done
make -C "${DRIVER_DIR}" KDIR="${KDIR}" KVER="${KVER}" ARCH=arm64 install
install -d /lib/firmware/aic8800D80
install -m 0644 "${REPO_DIR}"/aic8800_linux_drvier/fw/aic8800D80/* /lib/firmware/aic8800D80/
install -m 0644 "${REPO_DIR}/aic8800_linux_drvier/tools/aic.rules" /etc/udev/rules.d/aic.rules
install -d /etc/modules-load.d
printf '%s\n' aic_load_fw aic8800_fdrv > /etc/modules-load.d/aic8800d80.conf
udevadm control --reload-rules

if [[ -d /sys/module/aic_load_fw || -d /sys/module/aic8800_fdrv ]]; then
    echo "Installation complete. Reboot to use the newly built modules, then reconnect the adapter."
else
    modprobe cfg80211
    modprobe aic_load_fw
    modprobe aic8800_fdrv
    echo "Installation complete. Reconnect the USB adapter, then run: nmcli device wifi list"
fi
echo "Manual installation: rebuild after each kernel update. Build log: ${REPO_DIR}/jetson-build.log"
