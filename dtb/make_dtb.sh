#!/bin/sh

set -e

# script exit codes:
#   1: missing utility
#   5: invalid file hash

main() {
    local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.2.9.tar.xz'
    local lxsha='903449c164c03f0e742aacc920e18563585e07a28c6cb79e0fd6c36695fd43f5'

    local lf=$(basename $linux)
    local lv=$(echo $lf | sed -nE 's/linux-(.*)\.tar\..z/\1/p')

    if [ '_clean' = "_$1" ]; then
        rm -f *.dt*
        rm -rf "linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    check_installed 'device-tree-compiler' 'gcc' 'wget' 'xz-utils'

    [ -f $lf ] || wget $linux

    if [ $lxsha != $(sha256sum $lf | cut -c1-64) ]; then
        echo "invalid hash for linux source file: $lf"
        exit 5
    fi

    local rkpath=linux-$lv/arch/arm64/boot/dts/rockchip
    if [ ! -d "linux-$lv" ]; then
        tar xavf $lf linux-$lv/include/dt-bindings linux-$lv/include/uapi $rkpath
    fi

    if [ '_links' = "_$1" ]; then
        ln -sfv $rkpath/rk3568-pinctrl.dtsi
        ln -sfv $rkpath/rk356x.dtsi
        ln -sfv $rkpath/rk3568.dtsi
        ln -sfv $rkpath/rk3568-odroid-m1.dts
        echo '\nlinks created\n'
        exit 0
    fi

    # build
    local dt=rk3568-odroid-m1
    gcc -I linux-$lv/include -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o ${dt}-top.dts $rkpath/${dt}.dts
    dtc -@ -I dts -O dtb -o ${dt}.dtb ${dt}-top.dts
    echo "\n${cya}device tree ready: ${dt}.dtb${rst}\n"
}

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

