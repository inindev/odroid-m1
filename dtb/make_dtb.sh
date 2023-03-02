#!/bin/sh

set -e

# prerequisites: build-essential device-tree-compiler
# kernel.org linux version

main() {
    local lv='6.2.1'

    if [ '_clean' = "_$1" ]; then
        rm -f *.dt?
        rm -rf "linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    if [ ! -f "linux-$lv.tar.xz" ]; then
        wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$lv.tar.xz"
    fi

    local lrcp="linux-$lv/arch/arm64/boot/dts/rockchip"
    if [ ! -d "linux-$lv" ]; then
        tar "xavf" "linux-$lv.tar.xz" "linux-$lv/include/dt-bindings" "$lrcp"
    fi

    if [ '_links' = "_$1" ]; then
        ln -sf "$lrcp/rk3568-odroid-m1.dts"
        echo '\nlink created\n'
        exit 0
    fi

    # build
    gcc -I "linux-$lv/include" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o rk3568-odroid-m1-top.dts "$lrcp/rk3568-odroid-m1.dts"
    dtc -@ -I dts -O dtb -o rk3568-odroid-m1.dtb rk3568-odroid-m1-top.dts

    echo '\nbuild complete: rk3568-odroid-m1.dtb\n'
}

main "$1"

