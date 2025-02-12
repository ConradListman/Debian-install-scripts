#!/bin/bash

#Helper function
partToString() {
	local part="$1"

	# Get filesystem type (if any)
	local fs_type=$(lsblk -no FSTYPE "$part")
	[[ -z "$fs_type" ]] && fs_type="None" # If empty, set to "None"

	# Get partition size
	local size=$(lsblk -no SIZE "$part")

	# Get mount point or swap status
	local mountpoint=$(lsblk -no MOUNTPOINT "$part")
	if [[ -z "$mountpoint" ]]; then
		if grep -q "$part" /proc/swaps; then
			mountpoint="[SWAP]"
		else
			mountpoint="Unmounted"
		fi
	else
		mountpoint="Mounted: $mountpoint"
	fi

	# Return formatted string
	echo "$part    FS:$fs_type    Size:$size    $mountpoint"
}

# Get a list of partitions and disks (ignoring loop devices, RAM disks, and CD-ROMs)
PARTITIONS=($(lsblk -rpo NAME,TYPE | awk '$2=="part" {print $1}'))
DISKS=($(lsblk -rpo NAME,TYPE | awk '$2=="disk" {print $1}'))

# Check if there are disks
if [ ${#DISKS[@]} -eq 0 ]; then
	echo "No disks found! Exiting..."
	exit 1
fi

while true; do
	read -rp "
Would you like this script to partition the disk for you?
1. Partition entire disk
2. Partition continuous space
3. Partitioning is done already
Ctrl-C to cancel
Selection: " PARTCHOICE
	if [[ "$PARTCHOICE" == 1 || "$PARTCHOICE" == 3 || "$PARTCHOICE" == 2 ]]; then
		export PARTCHOICE
		break
	fi
	echo "Error, invalid input"
done

# Partition a whole disk
if [ "$PARTCHOICE" == 1 ]; then

	# Disk selection menu
	while true; do
		echo "Which disk to partition?"
		for i in "${!DISKS[@]}"; do
			disk="${DISKS[i]}"
			model_size="$(parted "$disk" print | head -n 1)
    Total Size:$(lsblk -ndo SIZE "$disk")"
			echo "$((i + 1)). $disk    $model_size"

			# Get partitions under this disk
			for part in "${PARTITIONS[@]}"; do
				if [[ "$part" == "$disk"* ]]; then
					echo "-- $(partToString "$part")"
				fi
			done
		done
		# take input
		read -rp "Enter the number of the disk: " DISK_INDEX
		if [[ "$DISK_INDEX" =~ ^[0-9]+$ ]] && ((DISK_INDEX >= 1 && DISK_INDEX <= ${#DISKS[@]})); then
			SELECTED_DISK="${DISKS[DISK_INDEX - 1]}"
			export SELECTED_DISK
			echo "Selected disk: $SELECTED_DISK"
			read -rp "Are you sure you want to use this disk? All data on will be erased. (yes to continue)" CONFIRM
			if [ "$CONFIRM" == "yes" ]; then
				export SELECTED_DISK
				break
			fi
		else
			echo "Invalid selection. Please enter a number between 1 and ${#DISKS[@]}."
		fi
	done

	if [ -d "/sys/firmware/efi" ]; then
		BOOT_MODE="UEFI"
	else
		BOOT_MODE="BIOS"
	fi
	echo "
This system appears to have been booted in $BOOT_MODE mode.
The proper partitioning depends on the boot method. If you don't know, use the default.
u for UEFI	b for BIOS	Leave blank for $BOOT_MODE"
	while true; do
		read -rp "Selection:" BOOT_SELECTION

		if [ -z "$BOOT_SELECTION" ]; then
			export BOOT_MODE
			break
		elif [ "$BOOT_SELECTION" == "u" ]; then
			export BOOT_MODE="UEFI"
			break
		elif [ "$BOOT_SELECTION" == "b" ]; then
			export BOOT_MODE="BIOS"
			break
		fi
		echo "Error: invalid input"
	done

	# Determine swap size based on RAM and disk size
	RAM_MB=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
	DISK_MB=$(lsblk -bno SIZE "$SELECTED_DISK" | head -n 1 | awk '{print int($1 / (1024*1024))}')
	if ((RAM_MB < 2048)); then
		SWAP_SIZE=$RAM_MB * 2
	elif ((RAM_MB < 8192)); then
		SWAP_SIZE=$RAM_MB
	else
		SWAP_SIZE=4096
	fi

	if [[ $DISK_MB < 4096 ]]; then
		echo "Error: Selected disk is too small (${DISK_MB}MB). A minimum of 4GB is required."
		exit 1
	fi

	echo $SWAP_SIZE
	echo $DISK_MB

	if [[ $(($SWAP_SIZE * 4)) -gt $DISK_MB ]]; then
		SWAP_SIZE=$(($DISK_MB / 4))
	fi

	echo "Recommended swap size: $SWAP_SIZE M"

	read -rp "enter to continue" ENTER

	# Partitioning the selected disk
	echo "Partitioning $SELECTED_DISK..."
	parted -s "$SELECTED_DISK" mklabel gpt

	# Create boot partition
	if [[ "$BOOT_MODE" == "UEFI" ]]; then
		parted -s "$SELECTED_DISK" mkpart ESP fat32 1MiB 512MiB
		parted -s "$SELECTED_DISK" set 1 esp on
	elif [[ "$BOOT_MODE" == "BIOS" ]]; then
		parted -s "$SELECTED_DISK" mkpart primary 1MiB 512MiB # BIOS boot partition (for GPT)
		parted -s "$SELECTED_DISK" set 1 bios_grub on
	fi

	# Create swap partition
	parted -s "$SELECTED_DISK" mkpart primary linux-swap 512MiB $((${SWAP_SIZE}+512))Mib

	# Create root partition (all remaining space)
	parted -s "$SELECTED_DISK" mkpart primary ext4 $((${SWAP_SIZE} + 512))Mib 100%

	echo "Partitioning complete!"

	export BOOTPART=($(lsblk -rpo NAME "$SELECTED_DISK" | sed -n '3p'))
	export SWAPPART=($(lsblk -rpo NAME "$SELECTED_DISK" | sed -n '4p'))
	export ROOTPART=($(lsblk -rpo NAME "$SELECTED_DISK" | sed -n '5p'))

# Partition a section
elif [ "$PARTCHOICE" == 2 ]; then
	echo "Not yet supported"
	exit 1
# Manual partitioning
else

	# Check if there are any partitions available
	if [ ${#PARTITIONS[@]} -eq 0 ]; then
		echo "No partitions detected! Exiting..."
		exit 1
	fi

	# Print numbered menu of partitions
	echo "Select partition to use as root directory:"
	for i in "${!PARTITIONS[@]}"; do
		echo "$((i + 1)). $(partToString "${PARTITIONS[i]}")"
	done

	# Get user selection
	while true; do
		read -rp "Enter the number of the partition: " PARTITION_INDEX
		if [[ "$PARTITION_INDEX" =~ ^[0-9]+$ ]] && ((PARTITION_INDEX >= 1 && PARTITION_INDEX <= ${#PARTITIONS[@]})); then
			ROOTPART="${PARTITIONS[PARTITION_INDEX - 1]}"
			echo "Root partition set to: $ROOTPART"
			read -rp "Are you sure you want to use this partition? All data will be erased (type yes to confirm)" CONFIRM
			if [ "$CONFIRM" == "yes" ]; then
				export ROOTPART
				break
			fi
		else
			echo "Invalid selection. Please enter a number between 1 and ${#PARTITIONS[@]}."
		fi
	done
fi

echo "$ROOTPART"

read -rp "Enter to continue" ENTER

export ROOTUUID=$(blkid $ROOTPART | awk -F '"' '{print $2}')
export SWAPUUID=$(blkid $SWAPPART | awk -F '"' '{print $2}')

mkdir /mntSq
umount $ROOTPART
mkfs.ext4 $ROOTPART
mount $ROOTPART /mntSq
debootstrap --variant=minbase bookworm /mntSq
mount --bind /proc /mntSq/proc
mount --bind /dev /mntSq/dev
mount --bind /sys /mntSq/sys
cp /root/Square.ch /mntSq/Square.ch
chmod +x /mntSq/Square.ch
chroot /mntSq /bin/bash /Square.ch

rm /mntSq/Square.ch
rm /mntSq/etc/network/interfaces
cp /etc/network/interfaces /mntSq/etc/network/interfaces
echo $ROOTUUID
echo "UUID=$ROOTUUID / ext4 defaults 0 1" > /mntSq/etc/fstab
echo "UUID=$SWAPUUID none swap sw 0 0" >> /mntSq/etc/fstab

update-grub
