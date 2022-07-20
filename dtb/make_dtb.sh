#!/bin/sh

set -e

# prerequisites: build-essential device-tree-compiler
# kernel.org linux version

main() {
    local lv='5.19-rc7'

    if [ 'clean' = "$1" ]; then
        rm -f rk356?*
        rm -rf "linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    local cache="cache.$lv"
    local ltar=$(download "$cache" "https://git.kernel.org/torvalds/t/linux-$lv.tar.gz")
    local odroidm1=$(download "$cache/patches" 'https://raw.githubusercontent.com/tobetter/linux/odroid-5.19.y/arch/arm64/boot/dts/rockchip/rk3568-odroid-m1.dts')
    local rk3568=$(download "$cache/patches" 'https://raw.githubusercontent.com/tobetter/linux/odroid-5.19.y/arch/arm64/boot/dts/rockchip/rk3568.dtsi')
    local rk356x=$(download "$cache/patches" 'https://raw.githubusercontent.com/tobetter/linux/odroid-5.19.y/arch/arm64/boot/dts/rockchip/rk356x.dtsi')

    if [ ! -d "linux-$lv" ]; then
        local ext=$(printf '%s' "$ltar" | awk -F . '{if (NF>1) {print $NF}}')
        local cf=''
        case "$ext" in
            'xz')  cf='J' ;;
            'gz')  cf='z' ;;
            'tar') cf=''  ;;
            *) echo 'error' && exit 1 ;;
        esac
        tar "${cf}xvf" "$ltar" "linux-$lv/include/dt-bindings" "linux-$lv/include/uapi" "linux-$lv/arch/arm64/boot/dts/rockchip"
    fi

    # patches from hardkernel https://github.com/tobetter/linux/tree/odroid-5.19.y
    local lrcp="linux-$lv/arch/arm64/boot/dts/rockchip"
    if [ ! -f "$lrcp/rk3568-odroid-m1.dts" ]; then
        cp "$odroidm1" "$lrcp"
        cp "$rk3568" "$lrcp"
        cp "$rk356x" "$lrcp"
    fi

    if [ 'links' = "$1" ]; then
        ln -sf "$lrcp/rk3568-odroid-m1.dts"
        ln -sf "$lrcp/rk3568.dtsi"
        ln -sf "$lrcp/rk356x.dtsi"
        echo '\nlinks created\n'
        exit 0
    fi

    # see: https://patchwork.kernel.org/project/linux-arm-kernel/patch/20220329094446.415219-2-tobetter@gmail.com
    #if [ ! -f "$lrcp/rk3568-odroid-m1.dts" ]; then
    #    patch -p1 -d "linux-$lv" < patches/0001-arm64-dts-rockchip-add-hardkernel-odroid-m1-board.patch
    #fi

    # build
    gcc -I "linux-$lv/include" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o rk3568-odroid-m1-top.dts "$lrcp/rk3568-odroid-m1.dts"
    dtc -O dtb -o rk3568-odroid-m1.dtb rk3568-odroid-m1-top.dts

    echo '\nbuild complete: rk3568-odroid-m1.dtb\n'
}

# download / return file from cache
download() {
    local cache="$1"
    local url="$2"

    [ -d "$cache" ] || mkdir -p "$cache"

    local filename=$(basename "$url")
    local filepath="$cache/$filename"
    [ -f "$filepath" ] || wget "$url" -P "$cache"
    [ -f "$filepath" ] || exit 2

    echo "$filepath"
}

main "$1"

