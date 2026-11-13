#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
abi=${1:?Kernel ABI required}
linux=$(realpath "${2:?Linux stable source directory required}")
headers=$(realpath "${3:?Matching fnOS headers required}")
output=$(realpath -m "${4:?New build directory required}")
test -s "$headers/Module.symvers"
test "$(cat "$headers/include/config/kernel.release")" = "$abi"
python3 "$here/prepare.py" "$abi" "$linux" "$output"
args=(ARCH=arm64 "CROSS_COMPILE=${CROSS_COMPILE:-}")
if [[ -n ${CC:-} ]]; then args+=("CC=$CC"); fi
for part in bridge rockchip panel; do
    make -C "$headers" M="$output/$part" "${args[@]}" CONFIG_DRM_ROCKCHIP=m -j "${JOBS:-2}" modules
done
for module in bridge/dw-mipi-dsi rockchip/rockchipdrm panel/panel-rk3399-640x480; do
    file="$output/$module.ko"
    [[ $(modinfo -F vermagic "$file") == "$abi "* ]]
    modinfo -F vermagic "$file"
    sha256sum "$file"
done
