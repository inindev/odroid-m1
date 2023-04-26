#!/bin/sh

set -e

# script exit codes:
#   1: missing utility
#   2: download failure
#   3: image mount failure
#   4: missing file
#   9: superuser required

main() {
    # file media is sized with the number between 'mmc_' and '.img'
    #   use 'm' for 1024^2 and 'g' for 1024^3
    local media='mmc_2g.img' # or block device '/dev/sdX'
    local deb_dist='bookworm'
    local hostname='odroidm1-arm64'
    local acct_uid='debian'
    local acct_pass='debian'
    local disable_ipv6=true
    local part_uuid='0011732f-7182-416f-8962-d8b252435c47'
    local extra_pkgs='curl, pciutils, sudo, u-boot-tools, unzip, wget, xxd, xz-utils, zip, zstd'

    is_param 'clean' $@ && rm -rf cache.* && rm mmc_2g.img* && exit 0

    if [ -f "$media" ]; then
        read -p "file $media exists, overwrite? <y/N> " yn
        if ! [ "$yn" = 'y' -o "$yn" = 'Y' -o "$yn" = 'yes' -o "$yn" = 'Yes' ]; then
            echo 'exiting...'
            exit 0
        fi
    fi

    # no compression if disabled or block media
    local compress=$(is_param 'nocomp' $@ || [ -b "$media" ] && echo false || echo true)

    if $compress && [ -f "$media.xz" ]; then
        read -p "file $media.xz exists, overwrite? <y/N> " yn
        if ! [ "$yn" = 'y' -o "$yn" = 'Y' -o "$yn" = 'yes' -o "$yn" = 'Yes' ]; then
            echo 'exiting...'
            exit 0
        fi
    fi

    check_installed 'debootstrap' 'u-boot-tools' 'wget' 'xz-utils'

    print_hdr "downloading files"
    local cache="cache.$deb_dist"
    # linux firmware
    local lfw=$(download "$cache" 'https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-20230210.tar.xz')
    local lfwsha='6e3d9e8d52cffc4ec0dbe8533a8445328e0524a20f159a5b61c2706f983ce38a'
    # device tree
    local dtb=$(download "$cache" 'https://github.com/inindev/odroid-m1/releases/download/v12.0-rc3/rk3568-odroid-m1.dtb')
#    local dtb='../dtb/rk3568-odroid-m1.dtb'

    if [ "$lfwsha" != $(sha256sum "$lfw" | cut -c1-64) ]; then
        echo "invalid hash for linux firmware: $lfw"
        exit 5
    fi

    if [ ! -f "$dtb" ]; then
        echo "device tree binary is missing: $dtb"
        exit 4
    fi

    if [ ! -b "$media" ]; then
        print_hdr "creating image file"
        make_image_file "$media"
    fi

    print_hdr "partitioning media"
    parition_media "$media" "$part_uuid"

    print_hdr "formatting media"
    format_media "$media"

    mount_media "$media"

    # do not write the cache to the image
    mkdir -p "$cache/var/cache" "$cache/var/lib/apt/lists"
    mkdir -p "$mountpt/var/cache" "$mountpt/var/lib/apt/lists"
    mount -o bind "$cache/var/cache" "$mountpt/var/cache"
    mount -o bind "$cache/var/lib/apt/lists" "$mountpt/var/lib/apt/lists"

    # install debian linux from official repo packages
    print_hdr "installing root filesystem from debian.org"
    mkdir "$mountpt/etc"
    echo 'link_in_boot = 1' > "$mountpt/etc/kernel-img.conf"
    local pkgs="linux-image-arm64, dbus, dhcpcd5, openssh-server, systemd-timesyncd"
    pkgs="$pkgs, wireless-regdb, wpasupplicant"
    pkgs="$pkgs, $extra_pkgs"
    debootstrap --arch arm64 --include "$pkgs" --exclude "isc-dhcp-client" "$deb_dist" "$mountpt" 'https://deb.debian.org/debian/'

    umount "$mountpt/var/cache"
    umount "$mountpt/var/lib/apt/lists"

    print_hdr "configuring files"
    echo "$(file_apt_sources $deb_dist)\n" > "$mountpt/etc/apt/sources.list"
    echo "$(file_locale_cfg)\n" > "$mountpt/etc/default/locale"

    # disable sshd until after keys are regenerated on first boot
    rm -f "$mountpt/etc/systemd/system/sshd.service"
    rm -f "$mountpt/etc/systemd/system/multi-user.target.wants/ssh.service"

    rm -rf "$mountpt/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service"
    echo "$(file_wpa_supplicant_conf)\n" > "$mountpt/etc/wpa_supplicant/wpa_supplicant.conf"
    cp "$mountpt/usr/share/dhcpcd/hooks/10-wpa_supplicant" "$mountpt/usr/lib/dhcpcd/dhcpcd-hooks"

    # hostname
    echo $hostname > "$mountpt/etc/hostname"
    sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\tlocalhost\n127.0.1.1\t$hostname/" "$mountpt/etc/hosts"

    # enable ll alias
    sed -i '/alias.ll=/s/^#*\s*//' "$mountpt/etc/skel/.bashrc"
    sed -i '/export.LS_OPTIONS/s/^#*\s*//' "$mountpt/root/.bashrc"
    sed -i '/eval.*dircolors/s/^#*\s*//' "$mountpt/root/.bashrc"
    sed -i '/alias.l.=/s/^#*\s*//' "$mountpt/root/.bashrc"

    # motd (off by default)
    is_param 'motd' $@ && [ -f '../etc/motd' ] && cp -f '../etc/motd' "$mountpt/etc/motd"

    # setup /boot
    echo "$(script_boot_txt $part_uuid $disable_ipv6)\n" > "$mountpt/boot/boot.txt"
    mkimage -A arm64 -O linux -T script -C none -n 'u-boot boot script' -d "$mountpt/boot/boot.txt" "$mountpt/boot/boot.scr"
    echo "$(script_mkscr_sh)\n" > "$mountpt/boot/mkscr.sh"
    chmod 754 "$mountpt/boot/mkscr.sh"
    install -m 644 "$dtb" "$mountpt/boot"
    ln -sf $(basename "$dtb") "$mountpt/boot/dtb"

    print_hdr "installing firmware"
    mkdir -p "$mountpt/lib/firmware"
    local lfwn=$(basename "$lfw")
    tar -C "$mountpt/lib/firmware" --strip-components=1 --wildcards -xavf "$lfw" "${lfwn%%.*}/rockchip" "${lfwn%%.*}/rtl_bt" "${lfwn%%.*}/rtl_nic"

    print_hdr "installing rootfs expansion script to /etc/rc.local"
    echo "$(script_rc_local)\n" > "$mountpt/etc/rc.local"
    chmod 754 "$mountpt/etc/rc.local"

    print_hdr "creating user account"
    chroot "$mountpt" /usr/sbin/useradd -m $acct_uid -s /bin/bash
    chroot "$mountpt" /bin/sh -c "/usr/bin/echo $acct_uid:$acct_pass | /usr/sbin/chpasswd -c YESCRYPT"
    chroot "$mountpt" /usr/bin/passwd -e $acct_uid
    (umask 377 && echo "$acct_uid ALL=(ALL) NOPASSWD: ALL" > "$mountpt/etc/sudoers.d/$acct_uid")

    # when compressing, reduce entropy in free space to enhance compression
    if $compress; then
        print_hdr "removing entropy before compression"
        cat /dev/zero > "$mountpt/tmp/zero.bin" 2> /dev/null || true
        sync
        rm -f "$mountpt/tmp/zero.bin"
    fi

    umount "$mountpt"
    rm -rf "$mountpt"

    if $compress; then
        print_hdr "compressing image file"
        xz -z8v "$media"
        echo "\n${cya}compressed image is now ready${rst}"
        echo "\n${cya}copy image to target media:${rst}"
        echo "  ${cya}sudo sh -c 'xzcat $media.xz > /dev/sdX && sync'${rst}"
    elif [ -b "$media" ]; then
        echo "\n${cya}media is now ready${rst}"
    else
        echo "\n${cya}image is now ready${rst}"
        echo "\n${cya}copy image to media:${rst}"
        echo "  ${cya}sudo sh -c 'cat $media > /dev/sdX && sync'${rst}"
    fi
    echo
}

make_image_file() {
    local filename="$1"
    rm -f "$filename"*
    local size="$(echo "$filename" | sed -rn 's/.*mmc_([[:digit:]]+[m|g])\.img$/\1/p')"
    local bytes="$(echo "$size" | sed -e 's/g/ << 30/' -e 's/m/ << 20/')"
    dd bs=64K count=$(($bytes >> 16)) if=/dev/zero of="$filename" status=progress
}

parition_media() {
    local media="$1"
    local part_uuid="$2"

    # partition with gpt
    cat <<-EOF | sfdisk "$media"
	label: gpt
	unit: sectors
	first-lba: 2048
	part1: start=32768, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=$part_uuid, name=rootfs
	EOF
    sync
}

format_media() {
    local media="$1"

    # create ext4 filesystem
    if [ -b "$media" ]; then
        local part1="/dev/$(lsblk -no kname "$media" | grep '.*p1$')"
        mkfs.ext4 "$part1" && sync
    else
        local lodev="$(losetup -f)"
        losetup -P "$lodev" "$media" && sync
        mkfs.ext4 "${lodev}p1" && sync
        losetup -d "$lodev" && sync
    fi
}

mount_media() {
    local media="$1"

    if [ -d "$mountpt" ]; then
        echo "cleaning up mount points..."
        mountpoint -q "$mountpt/var/cache" && umount "$mountpt/var/cache"
        mountpoint -q "$mountpt/var/lib/apt/lists" && umount "$mountpt/var/lib/apt/lists"
        mountpoint -q "$mountpt" && umount "$mountpt"
    else
        mkdir -p "$mountpt"
    fi

    if [ -b "$media" ]; then
        local part1="/dev/$(lsblk -no kname "$media" | grep '.*p1$')"
        mount -n "$part1" "$mountpt"
    elif [ -f "$media" ]; then
        mount -n -o loop,offset=16M "$media" "$mountpt"
    else
        echo "file not found: $media"
        exit 4
    fi

    if [ ! -d "$mountpt/lost+found" ]; then
        echo 'failed to mount the image file'
        exit 3
    fi

    echo "media ${cya}$media${rst} successfully mounted on ${cya}$mountpt${rst}"
}

check_mount_only() {
    local img
    local flag=false
    for item in "$@"; do
        case "$item" in
            mount) flag=true ;;
            *.img) img=$item ;;
            *.img.xz) img=$item ;;
        esac
    done
    ! $flag && return

    if [ ! -f "$img" ]; then
        if [ -z "$img" ]; then
            echo "no image file specified"
        else
            echo "file not found: ${red}$img${rst}"
        fi
        exit 3
    fi

    if [ "$img" = *.xz ]; then
        tmp=$(basename "$img" .xz)
        if [ -f "$tmp" ]; then
            echo "compressed file ${bld}$img${rst} was specified but uncompressed file ${bld}$tmp${rst} exists..."
            echo -n "mount ${bld}$tmp${rst}"
            read -p " instead? <Y/n> " yn
            if ! [ -z "$yn" -o "$yn" = 'y' -o "$yn" = 'Y' -o "$yn" = 'yes' -o "$yn" = 'Yes' ]; then
                echo 'exiting...'
                exit 0
            fi
            img=$tmp
        else
            echo -n "compressed file ${bld}$img${rst} was specified"
            read -p ', decompress to mount? <Y/n>' yn
            if ! [ -z "$yn" -o "$yn" = 'y' -o "$yn" = 'Y' -o "$yn" = 'yes' -o "$yn" = 'Yes' ]; then
                echo 'exiting...'
                exit 0
            fi
            xz -dk "$img"
            img=$(basename "$img" .xz)
        fi
    fi

    echo "mounting file ${yel}$img${rst}..."
    mount_media "$img"
    trap - EXIT INT QUIT ABRT TERM
    echo "media mounted, use ${grn}sudo umount $mountpt${rst} to unmount"

    exit 0
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

# check if utility program is installed
check_installed() {
    local todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo "   run: ${bld}${grn}apt update && apt -y install$todo${rst}\n"
        exit 1
    fi
}

file_apt_sources() {
    local deb_dist="$1"

    cat <<-EOF
	# For information about how to configure apt package sources,
	# see the sources.list(5) manual.

	deb http://deb.debian.org/debian $deb_dist main contrib non-free non-free-firmware
	#deb-src http://deb.debian.org/debian $deb_dist main contrib non-free non-free-firmware

	deb http://deb.debian.org/debian-security $deb_dist-security main contrib non-free non-free-firmware
	#deb-src http://deb.debian.org/debian-security $deb_dist-security main contrib non-free non-free-firmware

	deb http://deb.debian.org/debian $deb_dist-updates main contrib non-free non-free-firmware
	#deb-src http://deb.debian.org/debian $deb_dist-updates main contrib non-free non-free-firmware
	EOF
}

file_wpa_supplicant_conf() {
    cat <<-EOF
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1
	EOF
}

file_locale_cfg() {
    cat <<-EOF
	LANG="C.UTF-8"
	LANGUAGE=
	LC_CTYPE="C.UTF-8"
	LC_NUMERIC="C.UTF-8"
	LC_TIME="C.UTF-8"
	LC_COLLATE="C.UTF-8"
	LC_MONETARY="C.UTF-8"
	LC_MESSAGES="C.UTF-8"
	LC_PAPER="C.UTF-8"
	LC_NAME="C.UTF-8"
	LC_ADDRESS="C.UTF-8"
	LC_TELEPHONE="C.UTF-8"
	LC_MEASUREMENT="C.UTF-8"
	LC_IDENTIFICATION="C.UTF-8"
	LC_ALL=
	EOF
}

script_rc_local() {
    cat <<-EOF
	#!/bin/sh

	set -e

	this=\$(realpath \$0)
	perm=\$(stat -c %a \$this)

	if [ 774 -eq \$perm ]; then
	    # expand fs
	    resize2fs \$(findmnt / -o source -n)
	    rm "\$this"
	else
	    # regen ssh keys
	    rm -f /etc/ssh/ssh_host_*
	    dpkg-reconfigure openssh-server
            systemctl enable ssh.service

	    # expand root parition
	    rp=\$(findmnt / -o source -n)
	    rpn=\$(echo "\$rp" | grep -o '[[:digit:]]*\$')
	    rd="/dev/\$(/usr/bin/lsblk -no pkname \$rp)"
	    echo ', +' | sfdisk -f -N \$rpn \$rd

	    # setup for expand fs
	    chmod 774 "\$this"
	    reboot
	fi
	EOF
}

script_boot_txt() {
    local part_uuid=$1
    local no_ipv6="$($2 && echo ' ipv6.disable=1')"

    cat <<-EOF
	# after modifying, run ./mkscr.sh

	setenv bootargs console=ttyS2,1500000 root=PARTUUID=$part_uuid rw rootwait$no_ipv6 earlycon=uart8250,mmio32,0xfe660000

	if load \${devtype} \${devnum}:\${partition} \${kernel_addr_r} /boot/vmlinuz; then
	    if load \${devtype} \${devnum}:\${partition} \${fdt_addr_r} /boot/dtb; then
	        fdt addr \${fdt_addr_r}
	        fdt resize
	        if load \${devtype} \${devnum}:\${partition} \${ramdisk_addr_r} /boot/initrd.img; then
	            booti \${kernel_addr_r} \${ramdisk_addr_r}:\${filesize} \${fdt_addr_r};
	        else
	            booti \${kernel_addr_r} - \${fdt_addr_r};
	        fi;
	    fi;
	fi
	EOF
}

script_mkscr_sh() {
    cat <<-EOF
	#!/bin/sh

	if [ ! -x /usr/bin/mkimage ]; then
	    echo 'mkimage not found, please install uboot tools:'
	    echo '  sudo apt -y install u-boot-tools'
	    exit 1
	fi

	mkimage -A arm64 -O linux -T script -C none -n 'u-boot boot script' -d boot.txt boot.scr
	EOF
}

is_param() {
    local match
    for item in $@; do
        if [ -z $match ]; then
            match=$item
        elif [ $match = $item ]; then
            return
        fi
    done
    false
}

print_hdr() {
    local msg=$1
    echo "\n${h1}$msg...${rst}"
}

# ensure inner mount points get cleaned up
on_exit() {
    if mountpoint -q "$mountpt"; then
        print_hdr "cleaning up mount points"
        mountpoint -q "$mountpt/var/cache" && umount "$mountpt/var/cache"
        mountpoint -q "$mountpt/var/lib/apt/lists" && umount "$mountpt/var/lib/apt/lists"

        read -p "$mountpt is still mounted, unmount? <Y/n> " yn
        if [ -z "$yn" -o "$yn" = 'y' -o "$yn" = 'Y' -o "$yn" = 'yes' -o "$yn" = 'Yes' ]; then
            echo "unmounting $mountpt"
            umount "$mountpt"
            sync
            rm -rf "$mountpt"
        fi
    fi
}
mountpt='rootfs'
trap on_exit EXIT INT QUIT ABRT TERM

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="${blu}==>${rst} ${bld}"

if [ 0 -ne $(id -u) ]; then
    echo 'this script must be run as root'
    echo "   run: ${bld}${grn}sudo sh make_debian_img.sh${rst}\n"
    exit 9
fi

cd "$(dirname "$(readlink -f "$0")")"
check_mount_only $@
main $@

