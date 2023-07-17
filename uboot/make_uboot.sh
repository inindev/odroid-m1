#!/bin/sh

set -e

# script exit codes:
#   5: invalid file hash

main() {
    local utag='v2023.07.02'
    local atf_file='../rkbin/rk3568_bl31_v1.28.elf'
    local tpl_file='../rkbin/rk3568_ddr_1560MHz_v1.15.bin'

    if [ '_clean' = "_$1" ]; then
        rm -f u-boot/simple-bin.fit.*
        make -C u-boot distclean
        git -C u-boot clean -f
        git -C u-boot checkout master
        git -C u-boot branch -D "uboot_$utag" 2>/dev/null || true
        git -C u-boot pull --ff-only
        rm -f *.img *.itb
        exit 0
    fi

    check_installed 'bc' 'bison' 'flex' 'libssl-dev' 'make' 'python3-dev' 'python3-pyelftools' 'python3-setuptools' 'swig'

    if [ ! -d u-boot ]; then
        git clone https://github.com/u-boot/u-boot.git
        git -C u-boot fetch --tags
    fi

    if ! git -C u-boot branch | grep -q "uboot_$utag"; then
        git -C u-boot checkout -b "uboot_$utag" "$utag"

        for patch in patches/*.patch; do
            git -C u-boot am "../$patch"
        done
    elif [ "uboot_$utag" != "$(git -C u-boot branch --show-current)" ]; then
        git -C u-boot checkout "uboot_$utag"
    fi

    # outputs: idbloader.img, u-boot.itb
    rm -f idbloader.img u-boot.itb
    if [ '_inc' != "_$1" ]; then
        make -C u-boot distclean
        make -C u-boot odroid-m1-rk3568_defconfig
    fi
    make -C u-boot -j$(nproc) BL31=$atf_file ROCKCHIP_TPL=$tpl_file
    ln -sf u-boot/idbloader.img .
    ln -sf u-boot/u-boot.itb .

    echo "\n${cya}idbloader and u-boot binaries are now ready${rst}"
    echo "\n${cya}copy images to media:${rst}"
    echo "  ${cya}sudo dd bs=4K seek=8 if=idbloader.img of=/dev/sdX conv=notrunc${rst}"
    echo "  ${cya}sudo dd bs=4K seek=2048 if=u-boot.itb of=/dev/sdX conv=notrunc,fsync${rst}"
    echo
    echo "${blu}optionally, flash to spi (apt install mtd-utils):${rst}"
    echo
    echo "  ${blu}purge petitboot:${rst}"
    echo "    ${blu}sudo flash_erase /dev/mtd0 0 0${rst}"
    echo "    ${blu}sudo flash_erase /dev/mtd1 0 0${rst}"
    echo "    ${blu}sudo flash_erase /dev/mtd2 0 0${rst}"
    echo "    ${blu}sudo flash_erase /dev/mtd3 0 0${rst}"
    echo
    echo "  ${blu}flash u-boot to spi:${rst}"
    echo "    ${blu}sudo flashcp -v idbloader.img /dev/mtd0${rst}"
    echo "    ${blu}sudo flashcp -v u-boot.itb /dev/mtd2${rst}"
    echo
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

