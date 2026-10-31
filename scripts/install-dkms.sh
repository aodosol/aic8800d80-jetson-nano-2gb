#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="aic8800d80"
PACKAGE_VERSION="1.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DRIVER_DIR="${REPO_DIR}/aic8800_linux_drvier/drivers/aic8800"
SOURCE_DIR="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this script as root: sudo ./scripts/install-dkms.sh" >&2
    exit 1
fi

for command in dkms make install depmod modprobe; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "Missing required command: ${command}" >&2
        exit 1
    fi
done

if [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
    echo "Missing kernel headers for $(uname -r)" >&2
    exit 1
fi

install -d /lib/firmware/aic8800D80
install -m 0644 "${REPO_DIR}"/aic8800_linux_drvier/fw/aic8800D80/* /lib/firmware/aic8800D80/
install -m 0644 "${REPO_DIR}/aic8800_linux_drvier/tools/aic.rules" /etc/udev/rules.d/aic.rules

if dkms status -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" | grep -q .; then
    dkms remove -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" --all
fi

rm -rf "${SOURCE_DIR}"
install -d "${SOURCE_DIR}"
cp -a "${DRIVER_DIR}/." "${SOURCE_DIR}/"

dkms add -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}"
dkms build -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" -k "$(uname -r)"
dkms install -m "${PACKAGE_NAME}" -v "${PACKAGE_VERSION}" -k "$(uname -r)" --force

printf '%s\n' aic_load_fw aic8800_fdrv > /etc/modules-load.d/aic8800d80.conf
depmod -a
udevadm control --reload-rules
udevadm trigger
modprobe aic_load_fw
modprobe aic8800_fdrv

echo "AIC8800D80 DKMS installation completed for $(uname -r)."
