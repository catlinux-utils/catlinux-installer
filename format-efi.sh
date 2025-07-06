#!/bin/bash
set -e
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@" || exit 1
    else
        echo "This script must be run as root or with sudo" 1>&2
        >&2
        exit 1
    fi
fi

# Check if EFI partition is provided as argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <EFI partition device path (e.g. /dev/sda1)>"
    exit 1
fi

EFI_PARTITION=$1

# Check if partition exists
if [ ! -b "$EFI_PARTITION" ]; then
    echo "Error: $EFI_PARTITION is not a valid block device"
    exit 1
fi

# Format the EFI partition with FAT32
echo "Formatting $EFI_PARTITION as FAT32 (EFI System Partition)..."
mkfs.fat -F32 "$EFI_PARTITION"

# Set the partition type to EFI System Partition
if command -v parted >/dev/null 2>&1; then
    DISK=$(echo "$EFI_PARTITION" | sed 's/[0-9]*$//')
    PART_NUM=$(echo "$EFI_PARTITION" | grep -o '[0-9]*$')
    parted "$DISK" set "$PART_NUM" esp on
fi

echo "EFI partition formatted successfully"
