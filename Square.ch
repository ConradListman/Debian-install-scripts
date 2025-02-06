#!/bin/bash

# Prompt user for hostname
while true; do
    read -rp "Enter the new hostname for the system (Default \"Square0\"): " NEWHOST

    # Validate input: must be non-empty and contain only valid hostname characters
    if [ -z "$NEWHOST" ]; then
        export NEWHOST="Square0"
        break
    elif [[ "$NEWHOST" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,29}$ ]]; then
        export NEWHOST
        break
    else
        echo "Invalid hostname. Please use only letters, numbers, and hyphens."
    fi
done

echo "Hostname set to: $NEWHOST"

read -rp "Enter to continue" ENTER

# Decide on username
while true; do
    read -rp "Enter the username for the system's user (Default \"user\"): " NEWUSER

    # If empty, set to default
    if [ -z "$NEWUSER" ]; then
        export NEWUSER="user"
        break
    # Validate: must start with a lowercase letter, only contain valid characters, and be 1-32 chars long
    elif [[ "$NEWUSER" =~ ^[a-z][a-z0-9_-]{0,29}$ ]]; then
        export NEWUSER
        break
    else
        echo "Invalid username. Usernames must start with a lowercase letter and contain only lowercase letters, numbers, hyphens (-), and underscores (_), and be 1-32 characters long."
    fi
done


echo "username set to: $NEWUSER"

read -rp "Enter to continue" ENTER
adduser $NEWUSER
echo "make root password"
passwd
#nano sources.list
apt update
apt install linux-image-amd64 systemd nano grub2 net-tools ifupdown
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
ln -sf /lib/systemd/systemd /sbin/init
echo $NEWHOST > /etc/hostname
echo "Hostname set to: $NEWHOST"

#grub-install
#update-grub
exit
