#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "${1:?Provide the reference beta3-fix1 DEB}")
output=$(realpath -m "${2:?Provide the output DEB path}")
if [[ $# != 2 && $# != 4 ]]; then
    echo "Usage: $0 reference.deb output.deb [out-612 out-618]" >&2
    exit 2
fi
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
dpkg-deb -R "$input" "$stage"
for source in "$repo"/src/*; do
    target=$(find "$stage" -type f -name "${source##*/}" -print)
    test -f "$target"
    install -m "$(stat -c %a "$target")" "$source" "$target"
done
for abi in 6.12.41-trim 6.18.18.c1202-trim; do
    if [[ $# == 4 ]]; then
        build=$3
        [[ $abi != 6.18* ]] || build=$4
        modules="$stage/usr/lib/modules/$abi/updates/lshz-beta3"
        install -m644 "$build/bridge/dw-mipi-dsi.ko" "$build/rockchip/rockchipdrm.ko" \
            "$build/panel/panel-rk3399-640x480.ko" "$modules/"
    fi
    for module in rockchipdrm dw-mipi-dsi panel-rk3399-640x480; do
        file="$stage/usr/lib/modules/$abi/updates/lshz-beta3/$module.ko"
        [[ $(modinfo -F vermagic "$file") == "$abi "* ]]
    done
done
(
    cd "$stage"
    find . -path './DEBIAN' -prune -o -type f -print0 |
        sort -z | xargs -0 md5sum > DEBIAN/md5sums
)
dpkg-deb --root-owner-group --build "$stage" "$output"
