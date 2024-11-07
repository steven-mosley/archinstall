#!/usr/bin/env python3

import subprocess
import sys
import os
import shutil
import time
import logging
from dialog import Dialog

# Initialize dialog
d = Dialog(dialog="dialog", autowidgetsize=True)
d.set_background_title("Arch Linux Installer")

# Configure logging
logging.basicConfig(filename="/tmp/arch_installer.log", level=logging.DEBUG,
                    format='%(asctime)s %(levelname)s:%(message)s')

def run_command(command, check=True, capture_output=False, text=True):
    """
    Runs a system command using subprocess.
    """
    logging.debug(f"Running command: {' '.join(command)}")
    try:
        result = subprocess.run(command, check=check, capture_output=capture_output, text=text)
        if capture_output:
            logging.debug(f"Command output: {result.stdout}")
            return result.stdout.strip()
        return None
    except subprocess.CalledProcessError as e:
        logging.error(f"Command failed: {' '.join(command)}")
        logging.error(f"Error output: {e.stderr}")
        if capture_output and e.stderr:
            d.msgbox(f"Error: {e.stderr}", width=60, height=15)
        else:
            d.msgbox("An error occurred while executing a command. Check /tmp/arch_installer.log for details.", width=60, height=15)
        sys.exit(1)

def ensure_root():
    """
    Ensures the script is run as root.
    """
    if os.geteuid() != 0:
        d.msgbox("Please run this script as root.", width=40, height=5)
        sys.exit(1)

def install_packages():
    """
    Installs necessary packages using pacman.
    """
    required_packages = [
        "dialog",
        "gptfdisk",
        "util-linux",
        "arch-install-scripts",
        "btrfs-progs",
        "refind",
        "zram-generator",
        "networkmanager",
        "sudo",
        "zsh",
        "python-pip",
        "python-dialog"
    ]
    for pkg in required_packages:
        logging.debug(f"Checking if package {pkg} is installed.")
        result = subprocess.run(["pacman", "-Qi", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            d.infobox(f"Installing package: {pkg}", width=40, height=5)
            run_command(["pacman", "-Sy", "--noconfirm", pkg])

def welcome_message():
    """
    Displays a welcome message.
    """
    d.msgbox("""Welcome to the Arch Linux Installer Script (v1.0.0).

This script will guide you through the installation of Arch Linux with options for a Minimal or Custom setup.

**Important:** This script will erase all data on the selected disk. Ensure you have backups of any important data before proceeding.""", width=70, height=15)

def choose_installation_type():
    """
    Allows the user to choose between Minimal and Custom installation.
    """
    code, tag = d.menu("Choose Installation Type", choices=[
        ("Minimal", "Install with default settings and essential packages."),
        ("Custom", "Customize installation with additional packages and configurations.")
    ], width=70, height=10)
    if code != d.OK:
        d.msgbox("No installation type selected. Exiting.", width=40, height=5)
        sys.exit(1)
    return tag

def get_disks():
    """
    Retrieves a list of available disks.
    """
    output = run_command(["lsblk", "-dn", "-o", "NAME,SIZE"], capture_output=True)
    disks = []
    for line in output.splitlines():
        name, size = line.split()
        if any(name.startswith(prefix) for prefix in ["sd", "hd", "vd", "nvme", "mmcblk"]):
            disk = f"/dev/{name}"
            partitions = run_command(["lsblk", "-ln", "-o", "TYPE", disk], capture_output=True)
            partition_count = partitions.count("part")
            if partition_count == 0:
                info = f"Size: {size} (No partitions)"
            else:
                info = f"Size: {size} ({partition_count} partition(s))"
            disks.append((disk, info))
    return disks

def select_disk(disks):
    """
    Prompts the user to select a disk.
    """
    if not disks:
        d.msgbox("No suitable disks found. Exiting.", width=40, height=5)
        sys.exit(1)
    code, tag = d.menu("Select Disk", choices=disks, width=70, height=20)
    if code != d.OK:
        d.msgbox("No disk selected. Exiting.", width=40, height=5)
        sys.exit(1)
    return tag

def confirm_reformat(disk):
    """
    Confirms with the user if they want to reformat the selected disk.
    """
    partitions = run_command(["lsblk", "-ln", "-o", "NAME", disk], capture_output=True)
    existing_partitions = "\n".join(run_command(["lsblk", "-ln", "-o", "PARTTYPE", disk], capture_output=True).splitlines())
    if "part" in existing_partitions:
        code = d.yesno(f"The following partitions exist on {disk}:\n\n{partitions}\n\nDo you want to continue and reformat the disk?", width=70, height=15)
    else:
        code = d.yesno(f"No existing partitions found on {disk}.\n\nDo you want to continue and format the disk?", width=70, height=10)
    if code != d.OK:
        d.msgbox("Installation canceled. Exiting.", width=40, height=5)
        sys.exit(1)

def confirm_partition_scheme(disk):
    """
    Shows the proposed partition scheme and asks for confirmation.
    """
    size = run_command(["lsblk", "-dn", "-o", "SIZE", disk], capture_output=True)
    scheme = f"""{disk} (Size: {size})

  Partition 1: EFI System Partition (300 MiB)
  Partition 2: Linux Filesystem (Remaining space)
"""
    code = d.yesno(f"The disk will be partitioned as follows:\n\n{scheme}\nAll data on the disk will be erased.\n\nDo you want to proceed?", width=70, height=15)
    if code != d.OK:
        d.msgbox("Installation canceled. Exiting.", width=40, height=5)
        sys.exit(1)

def confirm_final_decision(disk):
    """
    Asks for final confirmation to erase the disk.
    """
    code = d.yesno(f"Are you absolutely sure you want to erase all data on {disk} and proceed with the installation?", width=70, height=7)
    if code != d.OK:
        d.msgbox("Installation canceled. Exiting.", width=40, height=5)
        sys.exit(1)

def partition_disk(disk):
    """
    Partitions the disk using sgdisk.
    """
    d.infobox(f"Destroying existing partitions on {disk}...", width=40, height=5)
    run_command(["sgdisk", "--zap-all", disk])
    time.sleep(2)

    d.infobox(f"Creating new partition table on {disk}...", width=40, height=5)
    run_command(["sgdisk", "-n", "1:0:+300M", "-t", "1:ef00", disk])
    run_command(["sgdisk", "-n", "2:0:0", "-t", "2:8300", disk])
    time.sleep(2)

def get_partition_names(disk):
    """
    Determines partition names based on disk type.
    """
    basename = os.path.basename(disk)
    if basename.startswith("nvme") or basename.startswith("mmcblk"):
        esp = f"{disk}p1"
        root = f"{disk}p2"
    else:
        esp = f"{disk}1"
        root = f"{disk}2"
    return esp, root

def prompt_hostname():
    """
    Prompts the user to enter a hostname.
    """
    hostname = d.inputbox("Enter a hostname for your system:", width=50)
    if not hostname:
        d.msgbox("No hostname entered. Using default 'archlinux'.", width=50, height=5)
        hostname = "archlinux"
    return hostname

def prompt_timezone():
    """
    Prompts the user to select a timezone.
    """
    regions = run_command(["ls", "/usr/share/zoneinfo"], capture_output=True).splitlines()
    code, region = d.menu("Select Region", choices=[(r, "") for r in regions], width=60, height=20)
    if code != d.OK or not region:
        d.msgbox("No region selected. Using 'UTC' as default.", width=50, height=5)
        return "UTC"
    
    cities = run_command(["ls", f"/usr/share/zoneinfo/{region}"], capture_output=True).splitlines()
    code, city = d.menu("Select City", choices=[(c, "") for c in cities], width=60, height=20)
    if code != d.OK or not city:
        d.msgbox("No city selected. Using 'UTC' as default.", width=50, height=5)
        return "UTC"
    
    timezone = f"{region}/{city}"
    return timezone

def prompt_locale():
    """
    Prompts the user to select a locale.
    """
    locales = sorted(run_command(["awk", '/^[a-z]/ {print $1}', "/usr/share/i18n/SUPPORTED"], capture_output=True).splitlines())
    choices = [(str(i+1), loc) for i, loc in enumerate(locales)]
    code, selection = d.menu("Select Locale", choices=choices, width=60, height=20)
    if code != d.OK or not selection:
        d.msgbox("No locale selected. Using 'en_US.UTF-8' as default.", width=50, height=5)
        return "en_US.UTF-8"
    
    try:
        index = int(selection) - 1
        selected_locale = locales[index]
    except (IndexError, ValueError):
        d.msgbox("Invalid selection. Using 'en_US.UTF-8' as default.", width=50, height=5)
        selected_locale = "en_US.UTF-8"
    
    return selected_locale

def prompt_password(prompt_text):
    """
    Prompts the user to enter a password with confirmation.
    """
    while True:
        password = d.passwordbox(prompt_text, width=50)
        if not password:
            d.msgbox("Password cannot be empty. Please try again.", width=50, height=5)
            continue
        if len(password) < 6:
            d.msgbox("Password must be at least 6 characters long. Please try again.", width=60, height=5)
            continue
        confirm = d.passwordbox("Confirm the password:", width=50)
        if password != confirm:
            d.msgbox("Passwords do not match. Please try again.", width=50, height=5)
            continue
        break
    return password

def prompt_user_account():
    """
    Prompts the user to create a new user account.
    """
    code = d.yesno("Would you like to create a new user account?", width=50, height=7)
    if code == d.OK:
        create_user = True
        while True:
            username = d.inputbox("Enter the username for the new account:", width=50)
            if not username:
                d.msgbox("Username cannot be empty. Please try again.", width=50, height=5)
                continue
            break
        user_password = prompt_password(f"Enter a password for {username}:")
        code = d.yesno(f"Should the user '{username}' have sudo privileges?", width=50, height=7)
        grant_sudo = True if code == d.OK else False
    else:
        create_user = False
        username = ""
        user_password = ""
        grant_sudo = False
    return create_user, username, user_password, grant_sudo

def select_optional_features():
    """
    Allows the user to select optional features/packages.
    """
    options = [
        ("btrfs", "Install btrfs-progs"),
        ("networkmanager", "Install NetworkManager"),
        ("zram", "Enable ZRAM")
    ]
    selected = []
    code, selections = d.checklist("Select optional features:", choices=options, height=15, width=60, list_height=4)
    if code == d.OK:
        selected = selections
    return selected

def detect_microcode():
    """
    Detects CPU vendor and prompts for microcode installation.
    """
    cpu_info = run_command(["grep", "-m1", "vendor_id", "/proc/cpuinfo"], capture_output=True)
    vendor = cpu_info.split(":")[1].strip().lower()
    microcode_pkg = ""
    microcode_img = ""
    if "intel" in vendor:
        code = d.yesno("CPU detected: Intel\n\nWould you like to install intel-ucode?", width=60, height=7)
        if code == d.OK:
            microcode_pkg = "intel-ucode"
            microcode_img = "intel-ucode.img"
    elif "amd" in vendor:
        code = d.yesno("CPU detected: AMD\n\nWould you like to install amd-ucode?", width=60, height=7)
        if code == d.OK:
            microcode_pkg = "amd-ucode"
            microcode_img = "amd-ucode.img"
    else:
        d.msgbox("CPU vendor not detected. Microcode will not be installed.", width=60, height=5)
    return microcode_pkg, microcode_img

def format_partitions(esp, root_partition, use_subvolumes):
    """
    Formats the EFI and root partitions.
    """
    d.infobox("Formatting partitions...", width=40, height=5)
    run_command(["mkfs.vfat", "-F32", "-n", "EFI", esp])
    run_command(["mkfs.btrfs", "-f", "-L", "Arch", root_partition])
    
    # Mount root partition
    d.infobox("Mounting root partition...", width=40, height=5)
    run_command(["mount", root_partition, "/mnt"])
    
    if use_subvolumes:
        # Create Btrfs subvolumes
        d.infobox("Creating Btrfs subvolumes...", width=40, height=5)
        run_command(["btrfs", "subvolume", "create", "/mnt/@"])
        run_command(["btrfs", "subvolume", "create", "/mnt/@home"])
        run_command(["btrfs", "subvolume", "create", "/mnt/@pkg"])
        run_command(["btrfs", "subvolume", "create", "/mnt/@log"])
        run_command(["btrfs", "subvolume", "create", "/mnt/@snapshots"])
        
        # Unmount root partition
        run_command(["umount", "/mnt"])
        
        # Mount subvolumes with options
        mount_options = "noatime,compress=zstd,discard=async,space_cache=v2"
        d.infobox("Mounting Btrfs subvolumes...", width=40, height=5)
        run_command(["mount", "-o", f"{mount_options},subvol=@", root_partition, "/mnt"])
        os.makedirs("/mnt/efi", exist_ok=True)
        os.makedirs("/mnt/home", exist_ok=True)
        os.makedirs("/mnt/var/cache/pacman/pkg", exist_ok=True)
        os.makedirs("/mnt/var/log", exist_ok=True)
        os.makedirs("/mnt/.snapshots", exist_ok=True)
        
        run_command(["mount", "-o", f"{mount_options},subvol=@home", root_partition, "/mnt/home"])
        run_command(["mount", "-o", f"{mount_options},subvol=@pkg", root_partition, "/mnt/var/cache/pacman/pkg"])
        run_command(["mount", "-o", f"{mount_options},subvol=@log", root_partition, "/mnt/var/log"])
        run_command(["mount", "-o", f"{mount_options},subvol=@snapshots", root_partition, "/mnt/.snapshots"])
    
    # Mount EFI partition
    d.infobox("Mounting EFI partition...", width=40, height=5)
    run_command(["mount", esp, "/mnt/efi"])

def install_base_system(selected_packages):
    """
    Installs the base Arch Linux system using pacstrap.
    """
    d.infobox("Installing base system... This may take a while.", width=50, height=5)
    packages = ["base", "linux", "linux-firmware"] + selected_packages
    run_command(["pacstrap", "/mnt"] + packages)

def generate_fstab():
    """
    Generates the fstab file.
    """
    d.infobox("Generating fstab...", width=40, height=5)
    run_command(["genfstab", "-U", "/mnt"], capture_output=True, text=False)
    fstab = run_command(["genfstab", "-U", "/mnt"], capture_output=True)
    with open("/mnt/etc/fstab", "w") as f:
        f.write(fstab)

def configure_system(create_user, username, user_password, grant_sudo, hostname, timezone, locale, zram_pkg):
    """
    Configures the system by chrooting into it and performing necessary setups.
    """
    # Mount necessary filesystems
    for dir in ["dev", "proc", "sys", "run"]:
        run_command(["mount", "--rbind", f"/{dir}", f"/mnt/{dir}"])
    
    # Install dialog inside chroot for further prompts
    run_command(["arch-chroot", "/mnt", "pacman", "-Sy", "--noconfirm", "dialog"])
    
    # Prepare variables for chroot
    env = os.environ.copy()
    env["esp"] = esp
    env["root_partition"] = root_partition
    env["hostname"] = hostname
    env["timezone"] = timezone
    env["locale"] = locale
    env["zram_pkg"] = zram_pkg
    env["create_user"] = str(create_user)
    env["username"] = username
    env["user_password"] = user_password
    env["grant_sudo"] = str(grant_sudo)
    
    # Define the chroot script
    chroot_script = f"""#!/bin/bash

# Set the timezone
ln -sf "/usr/share/zoneinfo/{timezone}" /etc/localtime
hwclock --systohc

# Set the hostname
echo "{hostname}" > /etc/hostname

# Configure /etc/hosts
cat <<EOL > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   {hostname}.localdomain {hostname}
EOL

# Generate locales
echo "{locale} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG={locale}" > /etc/locale.conf

# Configure ZRAM if enabled
if [ "{zram_pkg}" != "" ]; then
    cat <<EOM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOM
fi

# Set the root password
echo "root:{root_password}" | chpasswd

# Create user account if requested
if [ "{create_user}" == "True" ]; then
    useradd -m "{username}"
    echo "{username}:{user_password}" | chpasswd
    if [ "{grant_sudo}" == "True" ]; then
        usermod -aG wheel "{username}"
        sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    fi
fi

# Install rEFInd bootloader
pacman -Sy --noconfirm refind
refind-install --no-sudo --yes --alldrivers

if [ $? -ne 0 ]; then
    echo "Failed to install rEFInd. Exiting."
    exit 1
fi

# rEFInd configuration
sed -i 's/^#enable_mouse/enable_mouse/' /efi/EFI/refind/refind.conf
sed -i 's/^#mouse_speed .*/mouse_speed 8/' /efi/EFI/refind/refind.conf
sed -i 's/^#resolution .*/resolution max/' /efi/EFI/refind/refind.conf
sed -i 's/^#extra_kernel_version_strings .*/extra_kernel_version_strings linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux/' /efi/EFI/refind/refind.conf

# Create refind_linux.conf with the specified options
partuuid=$(blkid -s PARTUUID -o value {root_partition})
initrd_line=""
if [ "{microcode_img}" != "" ]; then
    initrd_line="initrd=/boot/{microcode_img} initrd=/boot/initramfs-%v.img"
else
    initrd_line="initrd=/boot/initramfs-%v.img"
fi

cat << EOF > /boot/refind_linux.conf
"Boot with standard options"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ {initrd_line}"
"Boot using fallback initramfs"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ initrd=/boot/initramfs-%v-fallback.img"
"Boot to terminal"  "root=PARTUUID=\$partuuid rw rootflags=subvol=@ {initrd_line} systemd.unit=multi-user.target"
EOF

# Ask if the user wants to use bash or install zsh
dialog --yesno "Would you like to use Zsh as your default shell instead of Bash?" 7 50
if [ $? -eq 0 ]; then
    pacman -Sy --noconfirm zsh
    chsh -s /bin/zsh
    if [ "{create_user}" == "True" ]; then
        chsh -s /bin/zsh "{username}"
    fi
fi

"""

    # Execute the chroot script
    run_command(["arch-chroot", "/mnt", "bash", "-c", chroot_script])

def install_refind_bootloader():
    """
    Installs and configures the rEFInd bootloader.
    """
    # This is handled within the chroot_script function
    pass

def finish_installation():
    """
    Offers the user to reboot or drop to the terminal.
    """
    code = d.yesno("""Installation complete! Would you like to reboot now or drop to the terminal for additional configuration?

Select 'No' to drop to the terminal.""", width=70, height=10)
    if code == d.OK:
        run_command(["umount", "-R", "/mnt"])
        run_command(["reboot"])
    else:
        # Bind mount necessary filesystems
        for dir in ["dev", "proc", "sys", "run"]:
            run_command(["mount", "--rbind", f"/{dir}", f"/mnt/{dir}"])
        d.msgbox("Type 'exit' to leave the chroot environment and complete the installation.", width=70, height=7)
        subprocess.call(["arch-chroot", "/mnt", "/bin/bash"])
        # After exiting chroot, unmount filesystems
        for dir in ["dev", "proc", "sys", "run"]:
            run_command(["umount", "-l", f"/mnt/{dir}"])
        run_command(["umount", "-R", "/mnt"])

def main():
    """
    Main function to orchestrate the installation.
    """
    try:
        ensure_root()
        install_packages()
        welcome_message()
        install_type = choose_installation_type()
        
        # Select installation type
        if install_type == "Minimal":
            selected_packages = []
            default_subvolumes = True
        else:
            selected_features = select_optional_features()
            selected_packages = []
            if "btrfs" in selected_features:
                selected_packages.append("btrfs-progs")
            if "networkmanager" in selected_features:
                selected_packages.append("networkmanager")
            if "zram" in selected_features:
                selected_packages.append("zram-generator")
            microcode_pkg, microcode_img = detect_microcode()
            if microcode_pkg:
                selected_packages.append(microcode_pkg)
            default_subvolumes = False
        
        # Disk selection
        disks = get_disks()
        selected_disk = select_disk(disks)
        confirm_reformat(selected_disk)
        confirm_partition_scheme(selected_disk)
        confirm_final_decision(selected_disk)
        partition_disk(selected_disk)
        esp, root_partition = get_partition_names(selected_disk)
        
        # System configuration
        hostname = prompt_hostname()
        timezone = prompt_timezone()
        locale = prompt_locale()
        root_password = prompt_password("Enter a root password:")
        create_user, username, user_password, grant_sudo = prompt_user_account()
        
        # Format and mount partitions
        use_subvolumes = default_subvolumes if install_type == "Minimal" else False
        format_partitions(esp, root_partition, use_subvolumes)
        
        # Install base system
        install_base_system(selected_packages)
        
        # Generate fstab
        generate_fstab()
        
        # Configure system within chroot
        configure_system(create_user, username, user_password, grant_sudo, hostname, timezone, locale, zram_pkg if install_type == "Custom" else "")
        
        # Finish installation
        finish_installation()
    
    except Exception as e:
        logging.exception("An unexpected error occurred.")
        d.msgbox(f"An unexpected error occurred: {e}\nCheck /tmp/arch_installer.log for details.", width=60, height=10)
        sys.exit(1)

if __name__ == "__main__":
    main()
