#!/bin/bash
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@" || exit 1
    else
        echo "This script must be run as root or with sudo" 1>&2
        exit 1
    fi
fi

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

if mountpoint -q /mnt; then
    echo "There is already a mount point at /mnt, please unmount it before continuing" 1>&2
    exit 1
fi

echo "Before proceeding, please create the necessary partitions:"
echo "1. EFI partition (e.g., /dev/sda1) with a vfat filesystem."
echo "2. Root partition (e.g., /dev/sda2)."
echo "System will use btrfs, so don't create a home partition."
echo "Use a partitioning tool like 'fdisk' or 'gparted' to manage disk partitions."

read -e -p "Please enter the EFI partition (e.g., /dev/sda1): " EFI_PARTITION
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

read -e -p "Please enter the root partition (e.g., /dev/sda2): " ROOT_PARTITION
PARTITION_TYPE=$(lsblk -no TYPE "$ROOT_PARTITION" 2>/dev/null | head -n 1)
if [ ! -b "$ROOT_PARTITION" ] || [ "$PARTITION_TYPE" != "part" ]; then
    echo "The given root partition is not a valid block device or not a partition" 1>&2
    exit 1
fi

echo "WARNING: The following command will erase all data on $ROOT_PARTITION"
read -e -p "Are you sure you want to proceed? (y/n): " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mkfs.btrfs -f "$ROOT_PARTITION"
else
    echo "Aborting..."
    exit 1
fi

