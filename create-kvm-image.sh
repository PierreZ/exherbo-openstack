#!/bin/bash
# Copyright (c) 2016 Pierre Zemb
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Heavily inspired from:
# http://git.exherbo.org/exherbo.git/tree/scripts/create-kvm-image

# print usage instructions
usage() {
    cat <<EOF
Usage: create-kvm-image [OPTIONS]
Options:
    -a|--arch=amd64|x86                Target architecture for image file
    -k|--kernelversion=version         Kernel version to be used in image
    -t|--stageversion=version          Date of tarball, for example 20090504 or current
    --kvmtmpdir=/path/to/image         Where to build the image file. Defaults to /var/tmp/kvm-tmp
    --kvmtmpkernel=/path/to/kernel     Where to build the kernel. Defaults to \${kvmtmpdir}/rootfs
    --kvmimgname=/path/to/image      Image filename (including path). Defaults to \${kvmtmpdir}/exherbo-\${arch}.img
    -s|--kvmimagesize=number           Size of image file in gigabytes. Defaults to 6
    -j|--jobs=number                   Number of make jobs when building the kernel. Defaults to 4

Example use:
create-kvm-image --arch=amd64 --kernelversion=2.6.29.2 --stageversion=20090504

Same but using short options:
create-kvm-image -a=amd64 -k=2.6.29.2 -t=20090504
EOF
}

# print message and exit
die() {
    echo $1
    exit 1
}

# check that all commands required are installed
checkprerequisites() {
    for prereq in "${BIN_KPARTX}" "${BIN_KVMIMG}" "${BIN_PARTED}" ; do
        [[ ! -x "${prereq}" ]] && die "${prereq} is missing. Exiting."
    done
}

# makeimagefile /path/to/file size
makeimagefile() {
    "${BIN_KVMIMG}" create -f raw "$1" $2 || die "Failed to create KVM image."
}

# makepartitiontable /path/to/imagefile
makepartitiontable() {
    "${BIN_PARTED}" "$1" mklabel msdos || die "Failed to create partition table."
}

# makepartition /path/to/imagefile parttype fstype begin end
# begin and end defaults to MB
# example: makepartition /tmp/exherbo.img primary ext2 0 512
makepartition() {
    "${BIN_PARTED}" --align cylinder "$1" mkpart $2 $3 $4 $5 || die "Failed to create partition."
}

# makefilesystem /dev/mapper/loopNn fstype
makefilesystem() {
    echo "Creating $2 filesystem on $1"
    case $2 in
        ext2)
            mkfs -t ext2 -q "$1" || die "Failed to create $2 filesystem."
            ;;
        ext3)
            mkfs -t ext3 -q "$1" || die "Failed to create $2 filesystem."
            ;;
        swap)
            mkswap "$1" 2> /dev/null || die "Failed to create $2 filesystem."
            ;;
        btrfs)
            mkfs -t btrfs "$1" || die "Failed to create $2 filesystem."
            ;;
    esac
}

# mountfilesystem /dev/mapper/loopNn /path/to/rootfs
mountfilesystem() {
    echo "Mounting filesystem $1 on $2."
    [[ ! -d "$2" ]] && mkdir -p "$2"
    mount "$1" "$2" || die "Couldn't mount filesystem $1 on $2."
}

getoptions() {
    for option in "$@"; do
        case "$option" in
            -h|--help)
                usage
                exit 1
                ;;
            --kvmtmpdir=*)
                KVMTMPDIR=${option#--kvmtmpdir=}
                ;;
            --kvmtmpkernel=*)
                KVMTMPKERNEL=${option#--kvmtmpkernel=}
                ;;
            --kvmimgname=*)
                KVMIMGNAME=${option#--kvmimgname=}
                ;;
            --kvmimagesize=*)
                KVMIMGSIZE=${option#--kvmimagesize=}G
                ;;
            -s=*)
                KVMIMGSIZE=${option#-s=}G
                ;;
            --kernelversion=*)
                KERNELVER=${option#--kernelversion=}
                ;;
            -k=*)
                KERNELVER=${option#-k=}
                ;;
            --stageversion=*)
                STAGEVER=${option#--stageversion=}
                ;;
            -t=*)
                STAGEVER=${option#-t=}
                ;;
            --arch=*)
                ARCH=${option#--arch=}
                [[ ${ARCH} != amd64 && ${ARCH} != x86 ]] && die "Wrong architecture specified"
                ;;
            -a=*)
                ARCH=${option#-a=}
                [[ ${ARCH} != amd64 && ${ARCH} != x86 ]] && die "Wrong architecture specified"
                ;;
            --jobs=*)
                JOBS=${option#--jobs=}
                ;;
            -j=*)
                JOBS=${option#-j=}
                ;;
            *)
                usage
                die "Unknown option passed, ${option}. Exiting."
                ;;
        esac
    done
}

if [[ -z "$@" ]]; then
    usage
    exit 1
fi

getoptions "$@"

# Full paths to non-basesystem binaries we depend on
BIN_KPARTX=/sbin/kpartx
BIN_KVMIMG=/usr/bin/qemu-img
BIN_PARTED=/sbin/parted

checkprerequisites

[[ -z ${KERNELVER} ]] && die "No kernel version specified."
[[ -z ${STAGEVER} ]] && die "No stage tarball version version specified."
[[ -z ${ARCH} ]] && die "No architecture specified."

# Setup a few basic variables
KVMTMPDIR="${KVMTMPDIR:-/var/tmp/kvm-tmp}"
KVMTMPKERNEL="${KVMTMPKERNEL:-${KVMTMPDIR}/kernel}"
KVMIMGNAME="${KVMIMGNAME:-${KVMTMPDIR}/exherbo-${ARCH}.img}"
KVMIMGSIZE=${KVMIMGSIZE:-6G}
KVMROOTFS="${KVMTMPDIR}"/rootfs
JOBS=${JOBS:-4}

[[ ! -d "${KVMTMPDIR}" ]] && mkdir -p "${KVMTMPDIR}"
makeimagefile "${KVMIMGNAME}" ${KVMIMGSIZE}

# Create partitions
KVMIMGSECTORS=$(($(stat --format %s "${KVMIMGNAME}") / 512))

# Setup partitions
makepartitiontable "${KVMIMGNAME}"
makepartition "${KVMIMGNAME}" primary btrfs 2 $((${KVMIMGSECTORS}-1))s

# Create a loopback for the image, set up a device mapping for each partition therein
PARTITIONS=$("${BIN_KPARTX}" -av "${KVMIMGNAME}" || die "Failed to create device mappings.")
DEVMAP_ROOT=/dev/mapper/$(echo "${PARTITIONS}" | sed "1!d" | cut -d' ' -f3)

# Make filesystems
makefilesystem "${DEVMAP_ROOT}" btrfs

# Download stage tarball + kernel sources
[[ ! -f "${KVMTMPDIR}"/exherbo-${ARCH}-${STAGEVER}.tar.xz ]] && wget --directory-prefix="${KVMTMPDIR}" http://dev.exherbo.org/stages/exherbo-${ARCH}-${STAGEVER}.tar.xz
case ${KERNELVER} in
    4.*)
        [[ ! -f "${KVMTMPDIR}"/linux-${KERNELVER}.tar.xz ]] && wget --directory-prefix="${KVMTMPDIR}" https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${KERNELVER}.tar.xz
        ;;
esac

# Mount / filesystem and populate using the stage tarball
mountfilesystem "${DEVMAP_ROOT}" "${KVMROOTFS}"
mkdir -p ${KVMROOTFS}/dev ${KVMROOTFS}/sys ${KVMROOTFS}/proc
mount -o rbind /dev ${KVMROOTFS}/dev/
mount -o bind /sys ${KVMROOTFS}/sys/
mount -t proc none ${KVMROOTFS}/proc/

# Handling tar of Kernel
xz -dc "${KVMTMPDIR}"/exherbo-${ARCH}-${STAGEVER}.tar.xz | tar xf - -C "${KVMROOTFS}"
[[ ! -d "${KVMTMPKERNEL}" ]] && mkdir -p "${KVMTMPKERNEL}"
echo "Unpacking stage tarball to / filesystem"
xz -dc "${KVMTMPDIR}"/linux-${KERNELVER}.tar.xz | tar xf - -C "${KVMTMPKERNEL}"
mv "${KVMTMPKERNEL}"/linux-${KERNELVER} ${KVMROOTFS}/usr/src/linux

echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > ${KVMROOTFS}/etc/resolv.conf

chroot "${KVMROOTFS}" /bin/bash -ex<<EOF
echo LANG="en_US.UTF-8" > /etc/env.d/99locale
localedef -i en_US -f UTF-8 en_US.UTF-8
source /etc/profile
cave sync

cd /usr/src/linux

make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- mrproper
yes "" | make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- x86_64_defconfig
yes "" | make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- kvmconfig

# Enable /proc/config.gz support
sed -i -e 's/.*CONFIG_IKCONFIG[= ].*/CONFIG_IKCONFIG=y/' .config
echo 'CONFIG_IKCONFIG_PROC=y' >> .config

# Enable btrfs support
sed -i -e 's/# CONFIG_BTRFS_FS is not set/CONFIG_BTRFS_FS=y/g' .config
echo -e "CONFIG_BTRFS_FS_POSIX_ACL=y" >> .config
echo -e "# CONFIG_BTRFS_FS_CHECK_INTEGRITY is not set" >> .config
echo -e "# CONFIG_BTRFS_FS_RUN_SANITY_TESTS is not set" >> .config
echo -e "# CONFIG_BTRFS_DEBUG is not set" >> .config
echo -e "# CONFIG_BTRFS_ASSERT is not set" >> .config

make -j${JOBS} HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu-
echo "make done"

make -j${JOBS} modules HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- || die "Building modules failed."
echo "make modules done"

make install HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- || die "Installing kernel failed."
echo "make install done"

make modules_install HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- || die "Installing modules failed."
echo "make modules_install done"
EOF

# Reset roots password
chroot "${KVMROOTFS}" /usr/bin/passwd -d root

# Create grub configuration
echo "Grub configuration..."
echo "(hd0) /dev/loop0" >> ${KVMROOTFS}/root/device.map
grub-install --no-floppy --grub-mkdevicemap=${KVMROOTFS}/root/device.map --root-directory=${KVMROOTFS} /dev/loop0 || exit 1

chroot "${KVMROOTFS}" /bin/bash -ex<<EOF
# Enable SSH
wget -O /etc/ssh/sshd_config https://raw.githubusercontent.com/PierreZ/exherbo-openstack/master/sshd_config
systemctl enable sshd.service

systemd-firstboot --locale=en_US --locale-messages=en_US --timezone=Europe/Paris --hostname=exherbo --root-password=packer --setup-machine-id
ssh-keygen -A

echo "exherbo" > /etc/hostname
echo -e "127.0.0.1    localhost exherbo \n::1          localhost exherbo" > /etc/hosts
cave resolve -x sys-boot/dracut
cave resolve -x sys-fs/btrfs-progs
dracut --verbose '' ${KERNELVER}
ls /boot
EOF
echo "End Chroot";

cat <<EOF > "${KVMROOTFS}"/etc/systemd/network/dhcp.network
[Match]
Name=e*
[Network]
DHCP=yes
[DHCPv4]
UseHostname=false
EOF

# Fstab
cat <<EOF > "${KVMROOTFS}"/etc/fstab
/dev/vda1               /                 btrfs         rw,relatime,ssd,space_cache    0 0
EOF

cat<<EOF > ${KVMROOTFS}/boot/grub/grub.cfg
set timeout=10
set default=0
menuentry "Exherbo" {
    set root=(hd0,msdos1)
    linux /boot/vmlinuz-${KERNELVER} root=/dev/vda1
    initrd /boot/initramfs-${KERNELVER}.img
}
EOF

curl https://github.com/PierreZ.keys > ${KVMROOTFS}/root/.ssh/authorized_keys

sync

# Unmount
umount -lf "${KVMROOTFS}"

# Remove device mappings and loopback device
sleep 5
"${BIN_KPARTX}" -dv "${KVMIMGNAME}" || die "Failed to remove device mappings."

# Shrink images
echo "shrinking image"
virt-sparsify --convert qcow2 $KVMIMGNAME ~/exherbo.img
echo "done"
