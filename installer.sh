#!/bin/bash

set -e

# Functions
setup_logging() {
    LOGFILE="/var/log/arch_install_$(date +%Y%m%d_%H%M%S).log"
    exec 1> >(tee "$LOGFILE") 2>&1
    echo "Starting installation at $(date)"
    trap 'cp "$LOGFILE" /mnt/var/log/' EXIT
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        if command -v sudo >/dev/null 2>&1; then
            exec sudo "$0" "$@" || exit 1
        else
            echo "This script must be run as root or with sudo" 1>&2
            exit 1
        fi
    fi
}

check_uefi() {
    if [ -d /sys/firmware/efi ]; then
        PLATFORM_SIZE=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)
        if [ "$PLATFORM_SIZE" != "64" ]; then
            echo "This script requires a 64-bit UEFI system" 1>&2
            exit 1
        fi
    else
        echo "This script requires a UEFI system" 1>&2
        exit 1
    fi
}

check_mount() {
    if mountpoint -q /mnt; then
        echo "There is already a mount point at /mnt, please unmount it before continuing" 1>&2
        exit 1
    fi
}

get_partitions() {
    echo "Please create the necessary partitions:"
    echo "1. EFI partition (e.g., /dev/sda1) with a vfat filesystem."
    echo "2. Root partition (e.g., /dev/sda2)."
    echo "System will use btrfs, so don't create a home partition."
    echo "Use a partitioning tool like 'fdisk' or 'gparted' to manage disk partitions."

    lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL

    read -e -p "Please enter the EFI partition (e.g., /dev/sda1): " EFI_PARTITION
    validate_efi_partition

    read -e -p "Please enter the root partition (e.g., /dev/sda2): " ROOT_PARTITION
    validate_root_partition
}

validate_efi_partition() {
    PARTITION_TYPE=$(lsblk -no TYPE "$EFI_PARTITION" 2>/dev/null | head -n 1)
    FS_TYPE=$(lsblk -no FSTYPE "$EFI_PARTITION" 2>/dev/null | head -n 1)
    if [ ! -b "$EFI_PARTITION" ] || [ "$PARTITION_TYPE" != "part" ]; then
        echo "The given EFI partition is not a valid block device or not a partition" 1>&2
        exit 1
    fi
    if [ "$FS_TYPE" != "vfat" ]; then
        echo "The given EFI partition is not a vfat filesystem" 1>&2
        exit 1
    fi
}

validate_root_partition() {
    PARTITION_TYPE=$(lsblk -no TYPE "$ROOT_PARTITION" 2>/dev/null | head -n 1)
    if [ ! -b "$ROOT_PARTITION" ] || [ "$PARTITION_TYPE" != "part" ]; then
        echo "The given root partition is not a valid block device or not a partition" 1>&2
        exit 1
    fi
}

format_root_partition() {
    echo "WARNING: The following command will erase all data on $ROOT_PARTITION"
    read -e -p "Are you sure you want to proceed? (y/n): " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Formatting $ROOT_PARTITION as btrfs..."
        mkfs.btrfs -L ArchRoot -f "$ROOT_PARTITION"
    else
        echo "Aborting..."
        exit 1
    fi
}

create_subvolumes() {
    echo "Creating subvolumes..."
    mount "$ROOT_PARTITION" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@home-snapshots
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@var-log
    btrfs subvolume create /mnt/@pacman-pkgs
    btrfs subvolume set-default 256 /mnt
    umount -R /mnt
}

mount_subvolumes() {
    echo "Mounting subvolumes..."
    mount_options="defaults,noatime,nodiratime,compress=zstd,space_cache=v2"
    mount -o subvol=@,$mount_options "$ROOT_PARTITION" /mnt
    mount --mkdir -o subvol=@home "$ROOT_PARTITION" /mnt/home
    mount --mkdir -o subvol=@snapshots "$ROOT_PARTITION" /mnt/.snapshots
    mount --mkdir -o subvol=@home-snapshots "$ROOT_PARTITION" /mnt/home/.snapshots
    mount --mkdir -o subvol=@var "$ROOT_PARTITION" /mnt/var
    chattr +C /mnt/var
    mount --mkdir -o subvol=@var-log "$ROOT_PARTITION" /mnt/var/log
    mount --mkdir -o subvol=@pacman-pkgs "$ROOT_PARTITION" /mnt/var/cache/pacman/pkg
}

mount_efi() {
    echo "Mounting EFI partition..."
    mount --mkdir -o defaults,fmask=0077,dmask=0077 "$EFI_PARTITION" /mnt/efi
    mkdir -p /mnt/efi/EFI/Linux
}

install_base_system() {
    echo "Installing base packages..."
    pacstrap -K /mnt base base-devel linux-zen linux-zen-headers linux-firmware amd-ucode intel-ucode sudo nano btrfs-progs networkmanager wpa_supplicant reflector git sed snapper
}

configure_system() {
    echo "Generating fstab..."
    genfstab -U /mnt >>/mnt/etc/fstab

    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
    arch-chroot /mnt hwclock --systohc
    arch-chroot /mnt sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
    arch-chroot /mnt sed -i "s/#pl_PL.UTF-8/pl_PL.UTF-8/" /etc/locale.gen
    arch-chroot /mnt locale-gen

    echo "LANG=pl_PL.UTF-8" >/mnt/etc/locale.conf
    echo "KEYMAP=pl" >/mnt/etc/vconsole.conf
}

setup_networking() {
    ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

    mkdir -p /mnt/etc/systemd/resolved.conf.d/
    sh -c "echo -e '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com' > /mnt/etc/systemd/resolved.conf.d/dns-over-tls.conf"
    sh -c "echo -e 'FallbackDNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net 8.8.8.8#dns.google 2606:4700:4700::1111#cloudflare-dns.com 2620:fe::9#dns.quad9.net 2001:4860:4860::8888#dns.google' >> /mnt/etc/systemd/resolved.conf.d/dns-over-tls.conf"
    sh -c "echo -e 'DNSOverTLS=yes' >> /mnt/etc/systemd/resolved.conf.d/dns-over-tls.conf"

    arch-chroot /mnt systemctl enable systemd-resolved.service
    arch-chroot /mnt systemctl enable NetworkManager.service
}

configure_mkinitcpio() {
    echo "Editing mkinitcpio ..."
    sed -i '/^HOOKS=/ s/ keyboard//' /mnt/etc/mkinitcpio.conf
    sed -i '/^HOOKS=/ s/ udev//' /mnt/etc/mkinitcpio.conf
    sed -i '/^HOOKS=/ s/ keymap//' /mnt/etc/mkinitcpio.conf
    sed -i '/^HOOKS=/ s/ consolefont//' /mnt/etc/mkinitcpio.conf
    sed -i '/^HOOKS=/ s/base/base systemd keyboard/' /mnt/etc/mkinitcpio.conf
    sed -i '/^HOOKS=/ s/block/sd-vconsole block/' /mnt/etc/mkinitcpio.conf

    configure_mkinitcpio_preset
    setup_kernel_cmdline

    rm /mnt/boot/initramfs-*.img 2>/dev/null
    echo "Regenerating the initramfs ..."
    arch-chroot /mnt mkinitcpio -P
}

configure_mkinitcpio_preset() {
    sed -i -E "s@^(#|)default_uki=.*@default_uki=\"/efi/EFI/Linux/ArchLinux-linux-zen.efi\"@" /mnt/etc/mkinitcpio.d/linux-zen.preset
    sed -i -E "s@^(#|)fallback_uki=.*@fallback_uki=\"/efi/EFI/Linux/ArchLinux-linux-zen-fallback.efi\"@" /mnt/etc/mkinitcpio.d/linux-zen.preset
    sed -i -E "s@^(#|)default_options=.*@default_options=\"--splash /usr/share/systemd/bootctl/splash-arch.bmp\"@" /mnt/etc/mkinitcpio.d/linux-zen.preset
    sed -i -E "s@^(#|)fallback_options=.*@fallback_options=\"-S autodetect --cmdline /etc/kernel/cmdline_fallback\"@" /mnt/etc/mkinitcpio.d/linux-zen.preset
    sed -i -E "s@^(#|)default_image=.*@#&@" /mnt/etc/mkinitcpio.d/linux-zen.preset
    sed -i -E "s@^(#|)fallback_image=.*@#&@" /mnt/etc/mkinitcpio.d/linux-zen.preset
}

setup_kernel_cmdline() {
    ROOT_UUID=$(lsblk -no UUID "$ROOT_PARTITION")
    echo "root=UUID=$ROOT_UUID rw rootfstype=btrfs rootlags=subvol=@ modprobe.blacklist=pcspkr" >/mnt/etc/kernel/cmdline
    echo "root=UUID=$ROOT_UUID rw rootfstype=btrfs rootlags=subvol=@ modprobe.blacklist=pcspkr" >/mnt/etc/kernel/cmdline_fallback
}

configure_system_settings() {
    sed -i '/^# %wheel ALL=(ALL:ALL) ALL/ s/# //' /mnt/etc/sudoers
    echo 'Defaults passwd_timeout=0' >/mnt/etc/sudoers.d/disable-timeout.conf

    sed -i "/\[multilib\]/,/Include/"'s/^#//' /mnt/etc/pacman.conf
    sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf

    configure_makepkg
}

configure_makepkg() {
    sed -i '/^OPTIONS=/s/\b lto\b/ !lto/g' /mnt/etc/makepkg.conf
    sed -i '/^OPTIONS=/s/\b debug\b/ !debug/g' /mnt/etc/makepkg.conf

    TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
    nc=$(grep -c ^processor /proc/cpuinfo)

    if [[ $TOTAL_MEM -gt 8000000 ]]; then
        sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /mnt/etc/makepkg.conf
        sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /mnt/etc/makepkg.conf
    fi
}

install_bootloader() {
    echo "Installing systemd-boot"
    bootctl --esp-path=/mnt/efi install
}

setup_users() {
    setup_root_password
    setup_user_account
}

setup_root_password() {
    echo "Enter a password for root:"
    read -s PASSWORD
    echo "Confirm password:"
    read -s CONFIRM_PASSWORD
    while [ "$PASSWORD" != "$CONFIRM_PASSWORD" ]; do
        echo "Passwords do not match. Please try again"
        echo "Enter a password for root:"
        read -s PASSWORD
        echo "Confirm password:"
        read -s CONFIRM_PASSWORD
    done
    echo "root:$PASSWORD" | arch-chroot /mnt chpasswd
}

setup_user_account() {
    echo "Enter username:"
    read USERNAME

    echo "Enter a password for $USERNAME:"
    read -s PASSWORD
    echo "Confirm password:"
    read -s CONFIRM_PASSWORD
    while [ "$PASSWORD" != "$CONFIRM_PASSWORD" ]; do
        echo "Passwords do not match. Please try again"
        echo "Enter a password for $USERNAME:"
        read -s PASSWORD
        echo "Confirm password:"
        read -s CONFIRM_PASSWORD
    done

    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | arch-chroot /mnt chpasswd
}

# Main execution
setup_logging
check_root
check_uefi
check_mount
get_partitions
format_root_partition
create_subvolumes
mount_subvolumes
mount_efi
install_base_system
configure_system
setup_networking
configure_mkinitcpio
configure_system_settings
install_bootloader
setup_users

echo "Installation completed at $(date)"
