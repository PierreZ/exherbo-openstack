#/bin/bash
set -e;

# http://exherbo.org/docs/install-guide.html

# Stage URl
STAGE_URL="http://dev.exherbo.org/stages/exherbo-amd64-current.tar.xz"
SHA1_URL="http://dev.exherbo.org/stages/sha1sum"

#Root filesystem device
ROOTDEV=/dev/vda

ROOTDEVICE="1"

#Root filesystem device
ROOTDEVDEVICE="$ROOTDEV$ROOTDEVICE"

ETC_CONFD_HOSTNAME="exherbo"

# Creating disk
sed -e 's/\t\([\+0-9a-zA-Z]*\)[ \t].*/\1/' << EOF | fdisk $ROOTDEV
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
    # default - start at beginning of disk 
  w # write the partition table
  q # and we're done
EOF

mkfs.ext4 $ROOTDEVDEVICE
mkdir /mnt/exherbo && mount /dev/sda1 /mnt/exherbo && cd /mnt/exherbo;

# Download stage exherbo and untar it
curl -O http://dev.exherbo.org/stages/exherbo-amd64-current.tar.xz
curl -O http://dev.exherbo.org/stages/sha1sum
grep exherbo-amd64-current.tar.xz sha1sum | sha1sum -c
tar xJpf exherbo*xz

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

# Chroot
env -i TERM=$TERM SHELL=/bin/bash HOME=$HOME $(which chroot) /mnt/exherbo /bin/bash
source /etc/profile

# Paludis
cd /etc/paludis && vim bashrc && vim *conf
cave sync

# Let's compile our kernel!
mkdir -p /usr/src && cd /usr/src
git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git linux
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- menuconfig
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu-
make HOSTCC=x86_64-pc-linux-gnu-gcc CROSS_COMPILE=x86_64-pc-linux-gnu- modules_install
cp arch/x86/boot/bzImage /boot/kernel

# GRUB
grub-install $ROOTDEV
cat<<EOF > /boot/grub/grub.cfg
 set timeout=10
 set default=0
 menuentry "Exherbo" {
     set root=(hd0,1)
     linux /kernel root=$ROOTDEVDEVICE
 }
EOF

# TODO: config systemd
