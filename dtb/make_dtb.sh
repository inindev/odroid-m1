#!/bin/sh

set -e

main() {
    local lv='6.2.2'
    local rkpath="linux-$lv/arch/arm64/boot/dts/rockchip"

    if [ '_clean' = "_$1" ]; then
        rm -f *.dt*
        rm -rf "linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    check_installed 'device-tree-compiler' 'gcc' 'wget' 'xz-utils'

    if [ ! -f "linux-$lv.tar.xz" ]; then
        wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$lv.tar.xz"
    fi

    if [ ! -d "linux-$lv" ]; then
        tar "xavf" "linux-$lv.tar.xz" "linux-$lv/include/dt-bindings" "$rkpath"
    fi

    if [ '_links' = "_$1" ]; then
        ln -sf "$rkpath/rk3568-odroid-m1.dts"
        ln -sf "$rkpath/rk3568.dtsi"
        ln -sf "$rkpath/rk356x.dtsi"
        echo '\nlinks created\n'
        exit 0
    fi

    # build
    gcc -I "linux-$lv/include" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o rk3568-odroid-m1-top.dts "$rkpath/rk3568-odroid-m1.dts"
    dtc -@ -I dts -O dtb -o rk3568-odroid-m1.dtb rk3568-odroid-m1-top.dts

    echo '\n${cya}build complete: rk3568-odroid-m1.dtb${rst}\n'
}

# check if utility program is installed
check_installed() {
    local todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo "   run: ${bld}${grn}sudo apt update && sudo apt -y install$todo${rst}\n"
        exit 1
    fi
}

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="${blu}==>${rst} ${bld}"

main $@

