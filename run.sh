#!/bin/bash

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
MENU_ID=$1

run_with_sudo(){
	if [ $EUID != 0 ]; then
		sudo "$0" "$MENU_ID"
		exit $?
	fi
}

function vmware {
    echo "Deploy on vmware virtual machine" $1
    if [[ $1 = "full" ]]
    then
        sgdisk --zap-all /dev/sda
        sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"boot" /dev/vda
        sgdisk --new=2:0:+25GiB --typecode=2:8300 --change-name=2:"root" /dev/vda
        sgdisk --largest-new=3 --typecode=3:8302 --change-name=3:"home" /dev/vda
        cryptsetup luksFormat /dev/vda3
        cryptsetup open /dev/vda3 home
    fi

    mkfs.fat -F32 /dev/vda1
    mkfs.ext4 -L "root" /dev/vda2
    mkfs.ext4 -L "home" /dev/mapper/home

    mount /dev/vda2 /mnt

    mkdir -p /mnt/boot/efi
    mount /dev/vda1 /mnt/boot/efi

    mkdir -p /mnt/home
    mount /dev/mapper/home /mnt/home
}

function setup_base {
    BOARD_NAME=$(cat /sys/class/dmi/id/product_name)
    case $BOARD_NAME in
    'VMware Virtual Platform')
        FUNC="vmware"
        ;;
    *)
        echo 'Unknown product name ('${BOARD_NAME}')'
        exit 1
        ;;
    esac

    DISTRO_NAME=$(cat /etc/os-release | grep "^ID=" | cut -d'=' -f2-)
    case $DISTRO_NAME in
    'arch')
        echo 'distro = arch'
        echo 'Server = https://mirror.yandex.ru/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
        pacman -Sy dialog --noconfirm
        ;;
    'archarm')
        echo 'distro = archarm'
        ;;
    *)
        echo 'Unknown distro name'
        exit 1
        ;;
    esac

    dialog --title 'Install' --clear --defaultno --yesno 'Recreate partition table?' 10 40
    case "$?" in
    '0')
        clear
        eval ${FUNC} 'full'
        ;;
    '1')
        clear
        eval ${FUNC} 'part'
        ;;
    '-1')
        clear
        echo 'Unknown choice'
        exit 1
        ;;
    esac

    read -n 1 -s -p "Press any key to continue"
    case $DISTRO_NAME in
    'arch')
        pacstrap /mnt base base-devel linux linux-firmware nano git ansible
        genfstab -U -p /mnt >> /mnt/etc/fstab
        arch-chroot /mnt git clone https://github.com/nikalexey/sysdeploy.git /etc/sysdeploy
        arch-chroot /mnt /etc/sysdeploy/setup.sh ansible
        ;;
    'archarm')
        pacstrap /mnt base base-devel linux linux-firmware nano git ansible
        genfstab -U -p /mnt >> /mnt/etc/fstab
        arch-chroot /mnt git clone https://github.com/nikalexey/sysdeploy.git /etc/sysdeploy
        arch-chroot /mnt /etc/sysdeploy/setup.sh ansible
        ;;
    esac

    # umount -R /mnt
}

case $MENU_ID in
  "ansible")
    cd $ROOT_DIR
    /usr/bin/ansible-playbook setup.yml --ask-become-pass --ask-vault-pass --extra-vars "variable_host=local is_chroot_param=True"
	;;
  * )
    run_with_sudo
	  setup_base
	;;
esac