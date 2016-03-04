# exherbo-openstack
Exherbo image generator for Openstack

## How to run it?

sudo ./create-kvm-image.sh --arch=amd64 --kernelversion=4.4.4 --stageversion=current --jobs=2

## List of packages

fakeroot build-essential devscripts qemu qemu-kvm unzip virtinst git btrfs-tools kpartx
