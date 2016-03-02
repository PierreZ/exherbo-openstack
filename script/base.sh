#/bin/bash
set -e;

# if one day, I need to change kernel options, here a sed command:
#sed -ir 's/^(CONFIG_XXX=.*|# CONFIG_XXX is not set)/CONFIG_XXX=m/;
#         s/^(CONFIG_FOO=.*|# CONFIG_FOO is not set)/CONFIG_FOO=m/;
#         s/^(CONFIG_BAR=.*|# CONFIG_BAR is not set)/CONFIG_BAR=m/' .config

# http://exherbo.org/docs/install-guide.html

# exec > /tmp/exherbo 2>&1

# Stage URl
STAGE_URL="http://dev.exherbo.org/stages/exherbo-amd64-current.tar.xz"
SHA1_URL="http://dev.exherbo.org/stages/sha1sum"

#Root filesystem device
# ROOTDEV=/dev/sda
ROOTDEV=/dev/vda

ROOTDEVICE="1"

#Root filesystem device
ROOTDEVDEVICE="$ROOTDEV$ROOTDEVICE"

ETC_CONFD_HOSTNAME="exherbo"

# Create partition 
echo "o
n
p
1


w
"|fdisk /dev/sda

mkfs.ext4 $ROOTDEVDEVICE
mkdir /mnt/exherbo && mount /dev/sda1 /mnt/exherbo && cd /mnt/exherbo;

# Download stage exherbo and untar it
curl --max-time 3600  -O http://dev.exherbo.org/stages/exherbo-amd64-current.tar.xz
curl --max-time 3600  -O http://dev.exherbo.org/stages/sha1sum
grep exherbo-amd64-current.tar.xz sha1sum | sha1sum -c
tar xJpf exherbo*xz

echo "exherbo pulled";

# fstab
cat <<EOF > /mnt/exherbo/etc/fstab
# <fs>       <mountpoint>    <type>    <opts>      <dump/pass>
/dev/sda1    /               ext4      defaults    0 0
EOF

# Mount everything
mount -o rbind /dev /mnt/exherbo/dev/
mount -o bind /sys /mnt/exherbo/sys/
mount -t proc none /mnt/exherbo/proc/

# DNS resolving
cat <<EOF > /mnt/exherbo/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

echo "Start Chroot";

chroot /mnt/exherbo /bin/bash -ex<<EOF
source /etc/profile
# Paludis
kak /etc/paludis/{bashrc,{*}conf}
cave sync

# Let's compile our kernel!
mkdir -p /usr/src && cd /usr/src
git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git linux
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- x86_64_defconfig
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu-
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- modules_install
cp arch/x86/boot/bzImage /boot/kernel

# Enable SSH
systemctl enable sshd.service
sed -i -e 's/.*PermitRootLogin.*$/PermitRootLogin yes/g' /etc/ssh/sshd_config
systemd-firstboot --locale=en_US.UTF-8 --locale-messages=en_US --timezone=Etc/UTC --hostname=exherbo --root-password=packer --setup-machine-id
ssh-keygen -A
grub-install $ROOTDEV

cave resolve world -c
cave resolve sys-apps/systemd
EOF

echo "End Chroot";

# GRUB
cat<<EOF > /mnt/exherbo/boot/grub/grub.cfg
 set timeout=10
 set default=0
 menuentry "Exherbo" {
     set root=(hd0,1)
     linux /kernel root=$ROOTDEVDEVICE
 }
EOF

# Flush files, umount and reboot
sync
umount /mnt/exherbo/sys/
umount /mnt/exherbo/proc/
umount /mnt/exherbo/dev/pts
umount -l /mnt/exherbo/dev/
umount -l /mnt/exherbo/
sync
reboot
