#/bin/bash

# http://exherbo.org/docs/install-guide.html

set -e;

cfdisk /dev/sda

# prepare disk
echo "n
p
1


w" | fdisk /dev/vda
mkfs.ext4 /dev/sda1
mkdir /mnt/exherbo && mount /dev/sda1 /mnt/exherbo && cd /mnt/exherbo;

# Download stage exherbo
curl -O http://dev.exherbo.org/stages/exherbo-amd64-current.tar.xz
curl -O http://dev.exherbo.org/stages/sha1sum
grep exherbo-amd64-current.tar.xz sha1sum | sha1sum -c

tar xJpf exherbo*xz
cat <<EOF > /mnt/exherbo/etc/fstab
# <fs>       <mountpoint>    <type>    <opts>      <dump/pass>
/dev/sda1    /               ext4      defaults    0 0
EOF
mount -o rbind /dev /mnt/exherbo/dev/
mount -o bind /sys /mnt/exherbo/sys/
mount -t proc none /mnt/exherbo/proc/

# DNS resolving
cp /etc/resolv.conf etc/resolv.conf

cd /etc/paludis && vim bashrc && vim *conf
cave sync
