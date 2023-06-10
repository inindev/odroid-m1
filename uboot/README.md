## u-boot 2023.04 for the odroid m1

<i>Note: This script is intended to be run from a 64 bit arm device such as an odroid m1 or a raspberry pi4.</i>

<br/>

**1. build u-boot images for the odroid m1**
```
sh make_uboot.sh
```

<i>the build will produce the target files idbloader.img, and u-boot.itb</i>

<br/>

**2. copy u-boot to mmc or file image**
```
sudo dd bs=4K seek=8 if=idbloader.img of=/dev/sdX conv=notrunc
sudo dd bs=4K seek=2048 if=u-boot.itb of=/dev/sdX conv=notrunc,fsync
```
* note: to write to emmc while booted from mmc, use ```/dev/mmcblk1``` for ```/dev/sdX```

<br/>

**4. optional: clean target**
```
sh make_uboot.sh clean
```

<br/>

---
## booting from spi nor flash

**1. boot from removable mmc**

[Follow the instructions](https://github.com/inindev/odroid-m1/blob/main/README.md#debian-bookworm-setup) for creating bootable mmc media.
Insert the mmc media and the hold the spi flash bypass button while powering on the device. The [button can be seen](https://wiki.odroid.com/odroid-m1/odroid-m1) near the 8 pin flash chip at the front of the board.

Note: The mmc media has a one-time reboot during first setup as it expands to the size of the mmc media. Without a [serial terminal](https://www.amazon.com/dp/B09W2B61HW) it will be difficult to know when this reboot happens. Waiting two minutes then powering down and booting again with the spi bypass button depressed again should be sufficient to reach the second boot.

<br/>

**2. install mtd-utils**

once linux is booted from the removable mmc, install mtd-utils
```
sudo apt update
sudo apt install mtd-utils
```

<br/>

**3. erase spi flash**
```
sudo flash_erase /dev/mtd0 0 0
sudo flash_erase /dev/mtd1 0 0
sudo flash_erase /dev/mtd2 0 0
sudo flash_erase /dev/mtd3 0 0
```

<br/>

**4. write u-boot to spi flash**
```
wget https://github.com/inindev/odroid-m1/releases/download/v12-rc4/idbloader.img
wget https://github.com/inindev/odroid-m1/releases/download/v12-rc4/u-boot.itb
sudo flashcp -v idbloader.img /dev/mtd0
sudo flashcp -v u-boot.itb /dev/mtd2
```

<br/>

Once the spi flash has been written, the boot sequence should prefer removable mmc media if present, then boot m.2 nvme ssd.

