## XPS partitions

* 1,efi
* 2,swap
* 3,root
* 4,home

## open crypt partitions

`sudo cryptsetup luksOpen /dev/nvme0n1p3 cryptroot`

## mount partitions

`mkdir -p /mnt/boot/efi && mount -t vfat /dev/nvme0n1p1 /mnt/boot/efi`

## get kernel version from an image

`file vmlinuz-linux`

## before kernel install

```bash
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs udev /dev
mkinitcpio -p linux
```

## kernel-install

`kernel-install add|remove KERNEL-VERSION KERNEL-IMAGE`

then update disk target in new loader conf.