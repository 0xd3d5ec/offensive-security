cat > /root/arch-install.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# ===== Edit these =====
DISK="/dev/sda"          # check with lsblk (e.g. /dev/nvme0n1, /dev/vda)
HOSTNAME="arch"
USERNAME="arch"
USER_PASS="arch"
ROOT_PASS="arch"
TIMEZONE="Asia/Qatar"
LOCALE="en_US.UTF-8"
KEYMAP="us"
UCODE=""                 # "amd-ucode" or "intel-ucode" on bare metal, empty for a VM
# ======================

[[ -d /sys/firmware/efi/efivars ]] || { echo "[!] Not booted in UEFI mode"; exit 1; }

if [[ $DISK =~ (nvme|mmcblk) ]]; then P="p"; else P=""; fi
EFI="${DISK}${P}1"
ROOT="${DISK}${P}2"

echo "[!] ALL DATA ON $DISK WILL BE ERASED."
read -rp "Type YES to continue: " confirm
[[ $confirm == "YES" ]] || { echo "Aborted."; exit 1; }

echo "[*] Configuring pacman to ignore TLS certificate errors"
if ! grep -q '^XferCommand' /etc/pacman.conf; then
  sed -i '/^\[options\]/a XferCommand = /usr/bin/curl -k -L -C - -f -o %o %u' /etc/pacman.conf
fi

timedatectl set-ntp true || true
systemctl stop reflector.service 2>/dev/null || true

echo "[*] Refreshing the live keyring"
pacman -Sy --noconfirm archlinux-keyring

echo "[*] Partitioning $DISK"
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8300 -c2:ARCH "$DISK"
partprobe "$DISK"
udevadm settle

echo "[*] Formatting"
mkfs.fat -F32 -n EFI "$EFI"
mkfs.btrfs -f -L arch "$ROOT"

echo "[*] Creating Btrfs subvolumes"
mount "$ROOT" /mnt
for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "$OPTS,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o "$OPTS,subvol=@home" "$ROOT" /mnt/home
mount -o "$OPTS,subvol=@log" "$ROOT" /mnt/var/log
mount -o "$OPTS,subvol=@pkg" "$ROOT" /mnt/var/cache/pacman/pkg
mount -o "$OPTS,subvol=@snapshots" "$ROOT" /mnt/.snapshots
mount "$EFI" /mnt/boot

echo "[*] Installing base system"
pacstrap -K -P /mnt base base-devel linux linux-firmware btrfs-progs grub efibootmgr \
  networkmanager sudo vim nano git curl man-db $UCODE
genfstab -U /mnt >> /mnt/etc/fstab

echo "[*] Configuring the system"
arch-chroot /mnt /bin/bash << CHROOT
set -e
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s.localdomain %s\n' "${HOSTNAME}" "${HOSTNAME}" > /etc/hosts
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "root:${ROOT_PASS}" | chpasswd
echo "${USERNAME}:${USER_PASS}" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
systemctl enable NetworkManager
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

umount -R /mnt
echo "[+] Done. Remove the install media and run: reboot"
SCRIPT
chmod +x /root/arch-install.sh
