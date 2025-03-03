# Installer Script

This script automates the installation and configuration of a Linux system with a focus on Arch Linux. It performs tasks such as partition setup, filesystem configuration, and package management to streamline the installation process.

## Prerequisites

- Ensure you have a UEFI 64-bit system.
- You must run this script as root or with `sudo`.
- Make sure the necessary partitions are created before running the script:
  1. EFI partition (e.g., `/dev/sda1`) with a vfat filesystem.
  2. Root partition (e.g., `/dev/sda2`).

## Features

- Checks for UEFI and 64-bit system compatibility.
- Modifies `mkinitcpio` configuration for systemd integration.
- Configures kernel command line for btrfs filesystem.
- Removes existing initramfs images and regenerates them.
- Adjusts user and permission settings, including enabling the `wheel` group for `sudo`.
- Optimizes `makepkg` configuration based on system memory.
- Installs `systemd-boot` bootloader.
- Allows setting of root and user passwords.

## Usage

1. Clone the repository containing this script.
2. Open a terminal and navigate to the script's directory.
3. Run the script using the command:
   ```bash
   ./installer.sh
   ```
4. Follow the on-screen prompts to enter partition details and user credentials.

## Important Notes

- This script is intended for use with Arch Linux systems.
- It assumes that the partitions are already created and available.
- The script performs actions that modify system configurations, ensure you have backups of important data before execution.

## License

This script is licensed under the GNU General Public License v3.0. Please see the LICENSE file for more details.
