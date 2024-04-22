#!/bin/bash

sudo apt update && sudo apt install -y qemu-user-static binfmt-support debootstrap

# Create Debian Minimal root filesystem
mkdir -p debianMinimalRootFS
sudo debootstrap --arch=arm64 --foreign buster debianMinimalRootFS
sudo cp /usr/bin/qemu-aarch64-static debianMinimalRootFS/usr/bin/
sudo cp /etc/resolv.conf debianMinimalRootFS/etc/

sudo chroot ./debianMinimalRootFS
/debootstrap/debootstrap --second-stage

cat <<EOT > /etc/apt/sources.list
deb http://deb.debian.org/debian buster main contrib non-free
deb-src http://deb.debian.org/debian buster main contrib non-free
deb http://security.debian.org/ buster/updates main contrib non-free
deb-src http://security.debian.org/ buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-updates main contrib non-free
deb-src http://deb.debian.org/debian buster-updates main contrib non-free
EOT
cat /etc/apt/sources.list
apt update
apt install locales dialog -y
dpkg-reconfigure locales

    # Select en_US.UTF-8 UTF-8 only, click ok on the dialog box.
    # On next dialog box, again select en_US.UTF-8, click ok.

apt install vim openssh-server ntpdate sudo ifupdown net-tools udev iputils-ping wget dosfstools unzip binutils libatomic1 -y
passwd
useradd -m skywalker
passwd skywalker
usermod --shell /bin/bash skywalker
cat >> /etc/network/interfaces <<EOT
auto enp0s1
iface enp0s1 inet dhcp
EOT
echo "alias ping='ping -4'" >> ~/.bashrc
echo "alias ping='ping -4'" >> /home/skywalker/.bashrc
echo "proc  /proc  proc   defaults      0  0" | tee -a /etc/fstab
echo "PARTUUID=1234abcd-01   /    ext4   defaults,noatime 0 1" | tee -a /etc/fstab
echo "PARTUUID=1234abcd-02  /boot vfat   defaults         0 2" | tee -a /etc/fstab
echo "PARTUUID=1234abcd-03  /data ext4   defaults         0 0" | tee -a /etc/fstab
chown root:root /usr/bin/sudo
chmod 4755 /usr/bin/sudo
adduser skywalker sudo
echo "deathstar" > etc/hostname
echo "127.0.1.1 deathstar" >> /etc/hosts
sudo rm ./debianMinimalRootFS/usr/bin/qemu-aarch64-static
cd ./debianMinimalRootFS
sudo tar cvf debianMinimalRootFS.tar *
ls -ltha

dd if=/dev/zero of=debianMinimalRootFS.img bs=1M count=16384

# Set up loop device with partitions
LOOP_DEVICE=$(sudo losetup -fP --show debianMinimalRootFS.img)
echo "Loop device created at ${LOOP_DEVICE}"
echo -e "o\nn\np\n1\n\n+8G\nn\np\n2\n\n+512M\nn\np\n3\n\n\nt\n2\nb\nw" | sudo fdisk ${LOOP_DEVICE}

# Re-read the partition table
sudo partprobe ${LOOP_DEVICE}
ls ${LOOP_DEVICE}*

# Format the partitions (assuming three partitions)
sudo mkfs.ext4 ${LOOP_DEVICE}p1 # ROOTFS Partition
sudo mkfs.vfat ${LOOP_DEVICE}p2 # BOOT Partition
sudo mkfs.ext4 ${LOOP_DEVICE}p3 # DATA Partition

# Create mount directories
mkdir -p mnt_rootfs mnt_boot mnt_data

# Mount the partitions
sudo mount ${LOOP_DEVICE}p1 mnt_rootfs
sudo mount ${LOOP_DEVICE}p2 mnt_boot
sudo mount ${LOOP_DEVICE}p3 mnt_data

sudo tar --same-owner --same-permissions -xvf ./debianMinimalRootFS/debianMinimalRootFS.tar -C ./mnt_rootfs/
ls -ltha ./mnt_rootfs/

MOUNT_POINT="./mnt_rootfs"

ROOT_UUID=$(blkid -o value -s UUID ${LOOP_DEVICE}p1)
BOOT_UUID=$(blkid -o value -s UUID ${LOOP_DEVICE}p2)
DATA_UUID=$(blkid -o value -s UUID ${LOOP_DEVICE}p3)

sudo cp "${MOUNT_POINT}/etc/fstab" "${MOUNT_POINT}/etc/fstab.bak"

sudo sed -i "s/PARTUUID=1234abcd-01/UUID=${ROOT_UUID}/g" "${MOUNT_POINT}/etc/fstab"
sudo sed -i "s/PARTUUID=1234abcd-02/UUID=${BOOT_UUID}/g" "${MOUNT_POINT}/etc/fstab"
sudo sed -i "s/PARTUUID=1234abcd-03/UUID=${DATA_UUID}/g" "${MOUNT_POINT}/etc/fstab"

# Display the updated fstab
sudo cat "${MOUNT_POINT}/etc/fstab"

# Unmount partitions
sudo umount mnt_rootfs mnt_boot mnt_data
rmdir mnt_rootfs mnt_boot mnt_data

# Detach the loop device
sudo losetup -d ${LOOP_DEVICE}

LOOP_DEVICE=$(sudo losetup -fP --show debianMinimalRootFS.img)
sudo mkdir /mnt/debianroot
sudo mount ${LOOP_DEVICE}p1 /mnt/debianroot  # Replace p1 with the appropriate partition number if different
sudo mount ${LOOP_DEVICE}p2 /mnt/debianroot/boot
sudo mount ${LOOP_DEVICE}p3 /mnt/debianroot/data
# Bind necessary directories to use them within the chroot environment
sudo mount --bind /dev /mnt/debianroot/dev
sudo mount --bind /proc /mnt/debianroot/proc
sudo mount --bind /sys /mnt/debianroot/sys

# If your root filesystem expects /dev/pts and /run, bind these as well
sudo mount --bind /dev/pts /mnt/debianroot/dev/pts
sudo mount --bind /run /mnt/debianroot/run

# Now chroot into the mounted root filesystem
sudo chroot /mnt/debianroot /bin/bash
sudo mkdir /data
sudo chmod -R 777 /data
mount -a
apt update
apt install systemd-sysv -y

# Compile the Kernel

sudo apt update
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    libncurses-dev bison flex libssl-dev libelf-dev bc qemu-user-static -y
sudo mkdir -p /opt/kernels/6.6.6
sudo chown -R $USER:$USER /opt
cd /opt/kernels/6.6.6
wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.6.6.tar.gz
tar xzf linux-6.6.6.tar.gz
cd linux-6.6.6
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
make defconfig
make menuconfig
# android options
# compile the kernel and the modules
make -j $(nproc) Image modules

# skywalker@xwing-7760:/opt/kernels/6.6.6/linux-6.6.6$ make kernelrelease
# 6.6.6-labarge-android-vm-20apr24
# skywalker@xwing-7760:/opt/kernels/6.6.6/linux-6.6.6$ 

KERNEL_RELEASE=$(make kernelrelease)
sudo make INSTALL_MOD_PATH=/mnt/debianroot modules_install
sudo cp -v arch/arm64/boot/Image /mnt/debianroot/boot/vmlinuz-${KERNEL_RELEASE}
sudo cp -v System.map /mnt/debianroot/boot/System.map-${KERNEL_RELEASE}
sudo cp -v .config /mnt/debianroot/boot/config-${KERNEL_RELEASE}

# In CHROOT
sudo apt-get -y install grub2-common efivar grub-efi-arm64 -y
boot_partition=$(mount | grep ' /boot' | awk '{print $1}')
mkdir -p /boot/efi
grub-install --boot-directory=/boot --efi-directory=/boot/efi "${boot_partition}"
sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
echo 'GRUB_DISABLE_OS_PROBER=true' | sudo tee -a /etc/default/grub
sudo apt-get install initramfs-tools -y
sudo update-initramfs -c -k 6.6.6-labarge-android-vm-20apr24
sudo update-grub

exit

# from linux-6.6.6 directory
# Then unmount all the bound directories and the root filesystem
sudo umount /mnt/debianroot/dev/pts
sudo umount /mnt/debianroot/run
sudo umount /mnt/debianroot/dev
sudo umount /mnt/debianroot/proc
sudo umount /mnt/debianroot/sys

# Finally, unmount the root filesystem and detach the loop device
sudo umount /mnt/debianroot/boot
sudo umount /mnt/debianroot/data
sudo umount /mnt/debianroot
sudo losetup -d $LOOP_DEVICE

mkdir /opt/android_vm
sudo cp -v arch/arm64/boot/Image /opt/android_vm/
sudo cp /mnt/debianroot/boot/initrd.img-6.6.6-labarge-android-vm-20apr24 /opt/android_vm/

# Install Qemu for Amr64 Emulation
sudo apt update
sudo apt install qemu-system-arm -y

# Boot QEMU without a kernel specified
sudo qemu-system-aarch64 \
    -m 8096 \
    -cpu cortex-a72 \
    -machine virt \
    -smp cores=8 \
    -net user,hostfwd=tcp::2222-:22 \
    -net nic \
    -drive file=debianMinimalRootFS.img,format=raw,id=hd0,if=none \
    -device virtio-blk-device,drive=hd0 \
    -kernel /opt/android_vm/Image \
    -initrd /opt/android_vm/initrd.img-6.6.6-labarge-android-vm-20apr24 \
    -append "console=ttyAMA0 root=/dev/vda1 init=/lib/systemd/systemd" \
    -nographic
