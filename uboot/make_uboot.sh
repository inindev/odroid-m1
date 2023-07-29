#!/bin/sh

set -e

# script exit codes:
#   1: missing utility

main() {
    local utag='v2023.07.02'
    local branch='2023.07'
    local atf_file='../rkbin/rk3568_bl31_v1.28.elf'
    local tpl_file='../rkbin/rk3568_ddr_1560MHz_v1.15.bin'

    if is_param 'clean' "$@"; then
        rm -f *.img *.itb
        if [ -d u-boot ]; then
            rm -f u-boot/simple-bin.fit.*
            make -C u-boot distclean
            git -C u-boot clean -f
            git -C u-boot checkout master
            git -C u-boot branch -D "$branch" 2>/dev/null || true
            git -C u-boot pull --ff-only
        fi
        echo '\nclean complete\n'
        exit 0
    fi

    check_installed 'bc' 'bison' 'flex' 'libssl-dev' 'make' 'python3-dev' 'python3-pyelftools' 'python3-setuptools' 'swig'

    if [ ! -d u-boot ]; then
        git clone https://github.com/u-boot/u-boot.git
        git -C u-boot fetch --tags
    fi

    if ! git -C u-boot branch | grep -q "$branch"; then
        git -C u-boot checkout -b "$branch" "$utag"

        cherry_pick

        local patch
        for patch in patches/*.patch; do
            git -C u-boot am "../$patch"
        done
    elif [ "$branch" != "$(git -C u-boot branch --show-current)" ]; then
        git -C u-boot checkout "$branch"
    fi

    # outputs: idbloader.img, u-boot.itb
    rm -f idbloader.img u-boot.itb
    if ! is_param 'inc' "$@"; then
        make -C u-boot distclean
        make -C u-boot odroid-m1-rk3568_defconfig
    fi
    make -C u-boot -j$(nproc) BL31="$atf_file" ROCKCHIP_TPL="$tpl_file"
    ln -sfv u-boot/idbloader.img
    ln -sfv u-boot/u-boot.itb

    is_param 'cp' "$@" && cp_to_debian

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
    echo "    ${blu}sudo flashcp -Av idbloader.img /dev/mtd0${rst}"
    echo "    ${blu}sudo flashcp -Av u-boot.itb /dev/mtd2${rst}"
    echo
}

cherry_pick() {
    # regulator: implement basic reference counter
    # https://github.com/u-boot/u-boot/commit/4fcba5d556b4224ad65a249801e4c9594d1054e8
    git -C u-boot cherry-pick 4fcba5d556b4224ad65a249801e4c9594d1054e8

    # regulator: rename dev_pdata to plat
    # https://github.com/u-boot/u-boot/commit/29fca9f23a3b730cbf91c18617e25d9d8e3a26b7
    git -C u-boot cherry-pick 29fca9f23a3b730cbf91c18617e25d9d8e3a26b7

    # dm: core: of_access: fix return value in of_property_match_string
    # https://github.com/u-boot/u-boot/commit/15a2865515fdd77d1edbc10e275b7b5a4914aa79
    git -C u-boot cherry-pick 15a2865515fdd77d1edbc10e275b7b5a4914aa79

    # rockchip: rk3568: Add support for FriendlyARM NanoPi R5S
    # https://github.com/u-boot/u-boot/commit/0ef326b5e92ee7c0f3cd27385510eb5c211b10fb
    git -C u-boot cherry-pick 0ef326b5e92ee7c0f3cd27385510eb5c211b10fb

    # rockchip: rk3568: Add support for FriendlyARM NanoPi R5C
    # https://github.com/u-boot/u-boot/commit/6a73211d4bb12d62ce82b33cee7d75d215a3d452
    git -C u-boot cherry-pick 6a73211d4bb12d62ce82b33cee7d75d215a3d452

    # rockchip: rk3568: Fix alloc space exhausted in SPL
    # https://github.com/u-boot/u-boot/commit/52472504e9c48cc1b34e0942c0075cd111ea85f0
    git -C u-boot cherry-pick 52472504e9c48cc1b34e0942c0075cd111ea85f0

    # core: read: add dev_read_addr_size_index_ptr function
    # https://github.com/u-boot/u-boot/commit/5e030632d49367944879e17a6d73828be22edd55
    git -C u-boot cherry-pick 5e030632d49367944879e17a6d73828be22edd55

    # pci: pcie_dw_rockchip: Get config region from reg prop
    # https://github.com/u-boot/u-boot/commit/bed7b2f00b1346f712f849d53c72fa8642601115
    git -C u-boot cherry-pick bed7b2f00b1346f712f849d53c72fa8642601115

    # pci: pcie_dw_rockchip: Use regulator_set_enable_if_allowed
    # https://github.com/u-boot/u-boot/commit/8b001ee59a9d4a6246098c8bc5bb894a752e7c0b
    git -C u-boot cherry-pick 8b001ee59a9d4a6246098c8bc5bb894a752e7c0b

    # pci: pcie_dw_rockchip: Speed up link probe
    # https://github.com/u-boot/u-boot/commit/7ce186ada2ce1ece344dacc20244fb91866e435b
    git -C u-boot cherry-pick 7ce186ada2ce1ece344dacc20244fb91866e435b

    # pci: pcie_dw_rockchip: Disable unused BARs of the root complex
    # https://github.com/u-boot/u-boot/commit/bc6b94b5788677c3633e0331203578ffa706ff4b
    git -C u-boot cherry-pick bc6b94b5788677c3633e0331203578ffa706ff4b

    # regulator: fixed: Add support for gpios prop
    # https://github.com/u-boot/u-boot/commit/f7b8a84a29833b6e6ddac67920d688330b299fa8
    git -C u-boot cherry-pick f7b8a84a29833b6e6ddac67920d688330b299fa8

    # rockchip: clk: clk_rk3568: Add CLK_PCIEPHY2_REF support
    # https://github.com/u-boot/u-boot/commit/583a82d5e2702f2c8aadcd75d416d6e45dd5188a
    git -C u-boot cherry-pick 583a82d5e2702f2c8aadcd75d416d6e45dd5188a

    # rockchip: rk356x: Update PCIe config, IO and memory regions
    # https://github.com/u-boot/u-boot/commit/062b712999869bdd7d6283ab8eed50e5999ac88a
    git -C u-boot cherry-pick 062b712999869bdd7d6283ab8eed50e5999ac88a

    # ata: dwc_ahci: Fix support for other platforms
    # https://github.com/u-boot/u-boot/commit/7af6616c961d213b4bf2cc88003cbd868ea11ffa
    git -C u-boot cherry-pick 7af6616c961d213b4bf2cc88003cbd868ea11ffa

    # cmd: ini: Fix build warning
    # https://github.com/u-boot/u-boot/commit/8c1bb04b5699ce74ad727d4513e1a40a58c9c628
    git -C u-boot cherry-pick 8c1bb04b5699ce74ad727d4513e1a40a58c9c628

    # board: rockchip: Add Hardkernel ODROID-M1
    # https://github.com/u-boot/u-boot/commit/94da929b933668c4b9ece7d56a2a2bb5543198c9
    git -C u-boot cherry-pick 94da929b933668c4b9ece7d56a2a2bb5543198c9
}

cp_to_debian() {
    local deb_dist=$(cat "../debian/make_debian_img.sh" | sed -n 's/\s*local deb_dist=.\([[:alpha:]]\+\)./\1/p')
    [ -z "$deb_dist" ] && return
    local cdir="../debian/cache.$deb_dist"
    echo '\ncopying to debian cache...'
    sudo mkdir -p "$cdir"
    sudo cp -v './idbloader.img' "$cdir"
    sudo cp -v './u-boot.itb' "$cdir"
}

check_installed() {
    local item todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo "   run: ${bld}${grn}sudo apt update && sudo apt -y install$todo${rst}\n"
        exit 1
    fi
}

is_param() {
    local item match
    for item in "$@"; do
        if [ -z "$match" ]; then
            match="$item"
        elif [ "$match" = "$item" ]; then
            return 0
        fi
    done
    return 1
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

cd "$(dirname "$(realpath "$0")")"
main "$@"

