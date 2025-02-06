#!/bin/bash

#Helper function
partToString() {
    local part="$1"

    # Get filesystem type (if any)
    local fs_type=$(lsblk -no FSTYPE "$part")
    [[ -z "$fs_type" ]] && fs_type="None"  # If empty, set to "None"

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
    if [ "$PARTCHOICE" == 1 || true || "$PARTCHOICE" == 2 ]; then
        export PARTCHOICE
        break
    fi
    echo "Error, invalid input"
done

# Check if there are any partitions available
if [ ${#PARTITIONS[@]} -eq 0 ]; then
    echo "No partitions detected! Exiting..."
    exit 1
fi

# Print numbered menu of partitions
echo "Select partition to use as root directory:"
for i in "${!PARTITIONS[@]}"; do
    echo "$((i+1)). $(partToString "${PARTITIONS[i]}")"
done

# Get user selection
while true; do
    read -rp "Enter the number of the partition: " PARTITION_INDEX
    if [[ "$PARTITION_INDEX" =~ ^[0-9]+$ ]] && (( PARTITION_INDEX >= 1 && PARTITION_INDEX <= ${#PARTITIONS[@]} )); then
        ROOTPART="${PARTITIONS[PARTITION_INDEX-1]}"
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

echo "$ROOTPART"

read -rp "Enter to continue" ENTER



export ROOTUUID=$(blkid $ROOTPART | awk -F '"' '{print $2}')

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

update-grub
