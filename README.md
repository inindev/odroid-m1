# odroid-m1
debian arm64 linux for the odroid m1

---
### debian bookworm setup

<br/>

**1. download image:**
```
wget https://github.com/inindev/odroid-m1/releases/download/v12.0-rc2/odroidm1_12.0-rc2.img.xz
```

<br/>

**2. determine the location of the target micro sd card:**

 * before plugging-in device:
```
ls -l /dev/sd*
ls: cannot access '/dev/sd*': No such file or directory
```

 * after plugging-in device:
```
ls -l /dev/sd*
brw-rw---- 1 root disk 8, 0 Jul 20 18:44 /dev/sda
```
* note: for mac, the device is ```/dev/rdiskX```

<br/>

**3. in the case above, substitute 'a' for 'X' in the command below (for /dev/sda):**
```
sudo sh -c 'xzcat odroidm1_12.0-rc2.img.xz > /dev/sdX && sync'
```

#### when the micro sd has finished imaging, eject and use it to boot the odroid m1 to finish setup

<br/>

**4. login:**
```
user: debian@192.168.1.xxx
pass: debian
```

<br/>

**5. take updates:**
```
sudo apt update
sudo apt upgrade
```

<br/>

**6. create account & login as new user:**
```
sudo adduser youruserid
echo '<youruserid> ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/<youruserid>
sudo chmod 440 /etc/sudoers.d/<youruserid>
```

<br/>

**7. lockout and/or delete debian account:**
```
sudo passwd -l debian
sudo chsh -s /usr/sbin/nologin debian
```

```
sudo deluser --remove-home debian
sudo rm /etc/sudoers.d/debian
```

<br/>

**8. change hostname (optional):**
```
sudo nano /etc/hostname
sudo nano /etc/hosts
```

<br/>


---
### building debian bookworm arm64 for the odroid m1 from scratch

<br/>

The build script builds native arm64 binaries and thus needs to be run from an arm64 device such as a raspberry pi4 running 
a 64 bit arm linux. The initial build of this project used a debian arm64 raspberry pi4, but now uses a odroid m1 running 
pure debian bookworm arm64.

<br/>

**1. clone the repo:**
```
git clone https://github.com/inindev/odroid-m1.git
cd odroid-m1
```

<br/>

**2. run the debian build script**
```
cd debian
sudo sh make_debian_img.sh
```
* note: edit the build script to change various options: ```nano make_debian_img.sh```

<br/>

**3. the output if the build completes successfully**
```
mmc_2g.img.xz
```

<br/>


---
### installing on m.2 ssd /dev/nvme0n1 media

<br/>

**1. copy the image file on to the ssd media (root user required)**
```
xzcat odroidm1_12.0-rc2.img.xz > /dev/nvme0n1
```

<br/>

**2. remove mmc media and boot from petitboot**

<br/>


---
### determining partition uuid

<br/>

**the partition uuid is required for the boot script /boot/boot.txt**
```
fdisk /dev/nvme0n1

select command i

Selected partition 1
         Device: /dev/nvme0n1p1
          Start: 32768
            End: 976773119
        Sectors: 976740352
           Size: 465.7G
           Type: Linux filesystem
      Type-UUID: 0FC63DAF-8483-4772-8E79-3D69D8477DE4
           UUID: 48432519-7258-4785-977e-3b1d26d88169
           Name: rootfs

select command q to exit

```

<br/>

**place the uuid in the /boot/boot.txt build script and regenerate**
```
setenv bootargs console=ttyS2,1500000 root=PARTUUID=48432519-7258-4785-977e-3b1d26d88169 rw rootwait...
./mkscr.sh
```

<br/>
