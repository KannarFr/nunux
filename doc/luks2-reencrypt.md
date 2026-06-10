# In-place LUKS2 encryption of pond's root

Plan for encrypting the existing install (written 2026-06: root is *plain*
ext4 — the crypttab/fstab snapshots in `system-config/system/` describe the
old Exherbo box, not this one). In-place `cryptsetup reencrypt` keeps the
install; the alternative — fresh encrypted install + `bin/migrate-home` —
only makes sense if switching filesystems (e.g. to btrfs) at the same time.

Target layout (verify with `lsblk -f` before touching anything):

```
nvme0n1p1  1G     vfat  ESP, mounted /boot — kernel+initramfs, stays UNencrypted
nvme0n1p2  930.5G ext4  /  — becomes LUKS2, opened as /dev/mapper/root
```

Boot chain after: GRUB (no cryptodisk — /boot is plain) → initramfs
`sd-encrypt` hook prompts for the passphrase → `/dev/mapper/root`.
Swap is zram-only, so there is no swap partition to encrypt and no
hibernation image to worry about.

## 0. Prerequisites — do not skip

- [ ] restic backup complete and verified: `bin/restic-backup check`
      and a spot-restore of a file or two (`bin/restic-backup restore latest
      --target /tmp/r --include <some-path>`). Reencrypting ~930 GB in place
      with no backup is gambling the whole disk.
- [ ] `RESTIC_PASSWORD` + S3 credentials stored OFF this machine.
- [ ] Arch ISO on a USB stick; AC power (the rewrite takes ~1–3 h).
- [ ] Pick the LUKS passphrase beforehand; store it with the restic password.

## 1. From the Arch live USB

Everything below runs against `/dev/nvme0n1p2` — re-check with `lsblk` that
this is still the root partition before each destructive step.

```sh
# fs must be clean and shrunk to make room for the LUKS2 header
e2fsck -f /dev/nvme0n1p2

# shrink by 64 MiB (header needs 32 MiB; double for margin).
# Block size is 4k, so 64 MiB = 16384 blocks:
BLOCKS=$(tune2fs -l /dev/nvme0n1p2 | awk '/^Block count:/{print $3}')
resize2fs /dev/nvme0n1p2 $((BLOCKS - 16384))

# encrypt in place (LUKS2, argon2id, aes-xts — current defaults).
# Resumable: if interrupted (power loss, ctrl-c), rerun the SAME command.
cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 64M \
  /dev/nvme0n1p2

# open, grow the fs back to fill the device
cryptsetup open /dev/nvme0n1p2 root
resize2fs /dev/mapper/root
```

## 2. Make it bootable (chroot)

```sh
mount /dev/mapper/root /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt
```

Inside the chroot:

1. `/etc/mkinitcpio.conf` — add `sd-encrypt` between `block` and
   `filesystems`:
   ```
   HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
   ```
2. `/etc/default/grub` — point the kernel at the LUKS device
   (`cryptsetup luksUUID /dev/nvme0n1p2` prints the UUID):
   ```
   GRUB_CMDLINE_LINUX="rd.luks.name=<luks-uuid>=root rd.luks.options=discard root=/dev/mapper/root"
   ```
   `discard` allows TRIM through LUKS (mild metadata leak, big SSD win —
   same tradeoff the old box made). No `/etc/crypttab` entry is needed for
   root; `rd.luks.*` on the cmdline is what sd-encrypt reads.
3. `/etc/fstab` — no change required: the ext4 fs UUID survives encryption
   and now resolves on `/dev/mapper/root`.
4. Rebuild and reinstall boot bits:
   ```sh
   mkinitcpio -P
   grub-mkconfig -o /boot/grub/grub.cfg
   ```

Then `exit`, `umount -R /mnt`, `cryptsetup close root`, reboot. First boot
prompts for the passphrase before gdm.

## 3. After the first successful boot

- [ ] Verify: `lsblk -f` shows `crypto_LUKS` on nvme0n1p2;
      `cryptsetup status root` says aes-xts-plain64.
- [ ] **LUKS header backup** — without it, a corrupted header is total loss:
      ```sh
      sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
        --header-backup-file ~/pond-luks-header.img
      ```
      Keep it in `$HOME` (restic carries it off-site) *and* somewhere
      off-machine with the passphrases. Redo after any keyslot change.
- [ ] Refresh the repo snapshots: copy the real `/etc/default/grub` and
      `/etc/mkinitcpio.conf` into `system-config/system/`, delete the stale
      Exherbo-era `crypttab`/`fstab`/`dracut.conf.d/*`, snapshot the new
      `fstab`, and update the bootstrap checklist to point here.
- [ ] Optional, later: TPM2 auto-unlock (`systemd-cryptenroll
      --tpm2-device=auto`) is only meaningful once Secure Boot is on
      (sbctl + signed UKI) — with SB disabled the PCRs it would bind to are
      unverified. Separate project.
