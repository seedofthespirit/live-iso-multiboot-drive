#!/bin/bash
# -*- coding: utf-8; indent-tabs-mode: nil; -*-

# Function:
# The script creates partitions on the given USB drive so that it can boot multiple
# bootable ISO-9660 images on the UEFI firmware system as well as the legacy BIOS firmware system.
# It installs the grub bootloader on the generated partitions of the USB drive,
# and installs grub.cfg that is capable of detecting suitable live Linux ISO-9660 image files
# so that the user can select the one to boot.
# So grub will present menu items in two steps:
#   one to select the loopback.cfg compatible ISO-9660 image file,
#   second to select the boot option provided by the ISO-9660 live system.
#
# Features:
# a. The resulting USB drive can boot any ISO-9660 image that is stored in the Boot-ISO
#    partition. You can choose which ISO-9660 image to boot in the beginning, so the booting
#    comes in two steps: one to choose the ISO-9660 image, second to choose the boot option
#    provided by the ISO-9660 live system.
# b. The number of ISO-9660 images you can store on the drive is limited by the size of
#    the ISO-9660 images and the size of the Boot-ISO partition which is determined
#    through the script dialog.
# c. The USB drive can boot both on a UEFI firmware machine and on a legacy BIOS machine.
#    (We recommend you don't enable legacy BIOS boot support on the UEFI machine.
#    It might not work.)
# d. Linux only. Windows ISO-9660 images are not supported.
#
# Assumptions:
# 1. The grub.cfg that is used by this script assumes the live Linux ISO-9660 image has either
#    /boot/grub/loopback.cfg or /boot/loopback.cfg within its ISO-9660 filesystem and the
#    loopback.cfg is capable of booting the Linux kernel within the ISO-9660 filesystem.
# 2. The user account is able to run the sudo command.
#    Sudo is used to run the following commands only:
#      /sbin/fdisk
#      /sbin/parted
#      /sbin/mkfs.vfat
#      /sbin/mkfs.ext2
#      /bin/mount
#      /bin/umount
#      /usr/sbin/grub-install
#      /bin/mkdir
#      /bin/cp
#
# What it does in sequence:
# 1. Identify the USB device to program on.
# 2. Erase the whole drive and create a new GPT partition table.
# 3. Create a very small partition for grub boot loader to use for legacy BIOS booting.
#    This partition will not be formatted.
# 4. Create the EFI system partition which is also used for grub to boot the system.
#    This partition will be formatted as a fat32 filesystem.
# 5. Create a partition where live Linux hybrid-boot ISO-9660 images are stored.
#    This partition will be formatted as an ext2 filesystem.
#    A dialog will ask for the size for this partition.
#    Also the ISO directory ${ISO_9660_DIRECTORY} is created in this filesystem.
# 6. Install grub EFI x64 to the boot partition (which coincides with the EFI system partition).
# 7. Install grub i386-pc to the MBR and the boot partition.
# 8. Install grub.cfg
#
# Partition   | Name      | filesystem | flags
# ------------+-----------+------------+------------
# Partition 1 | bios-grub | None       | bios_grub
# Partition 2 | ISO-BOOT  | fat32      | esp,boot
# Partition 3 | Boot-ISO  | ext2       |
#
# Note:
# * The script will present a warning when it is going to overwrite the USB drive.
# * You can stop and exit the script whenever you don't want to make a crusial decision such as overwriting the USB device.
# * If you have made a mistake you can always run the script again as long as you select the correct USB drive.
# * Once the script is done you can add more partitions on the drive for your own purpose other than booting the live system.
# * The reason we use ext2 for the Boot-ISO partition is to minimize write operations on the flash memory.
# * Always back up the USB drive content if you store your important data. Flash drives are getting cheaper.
#   I believe flash memory is not too reliable especially in the long term. Bitrot happens.
#

# The global constants used in the script
PARTITION_1_MIB=1             # 1 MiB for the bios_grub partition
PARTITION_2_MIB=100           # 100 MiB is more than adequate for the EFI partition and for the boot partition.
PARTITION_1_NAME='bios-grub'  # the name of the bios_grub partition.
PARTITION_2_NAME='ISO-BOOT'   # the name of the EFI system partition. Used for the filesystem label as well.
PARTITION_3_NAME='Boot-ISO'   # the name of the partition that stores ISO-9660 image files. Used for the filesystem label as well.
ISO_9660_DIRECTORY='isos'     # the directory where bootable ISO-9660 image files are stored.

# The followings are for the Debian system.
# The exact paths might be different on other Linux systems.
CAT_CMD='/bin/cat'
CP_CMD='/bin/cp'
DATE_CMD='/bin/date'
ECHO_CMD='/bin/echo'
GREP_CMD='/bin/grep'
LSBLK_CMD='/bin/lsblk'
MKDIR_CMD='/bin/mkdir'
MKTEMP_CMD='/bin/mktemp'
MOUNT_CMD='/bin/mount'
SED_CMD='/bin/sed'
UMOUNT_CMD='/bin/umount'
WHICH_CMD='/bin/which'
DIRNAME_CMD='/usr/bin/dirname'
NUMFMT_CMD='/usr/bin/numfmt'
PINENTRY_CMD='/usr/bin/pinentry-gtk-2'	# This pinentry command can show/hide the entered text.
PRINTF_CMD='/usr/bin/printf'
REALPATH_CMD='/usr/bin/realpath'
SLEEP_CMD='/usr/bin/sleep'
SUDO_CMD='/usr/bin/sudo'
YAD_CMD='/usr/bin/yad'
FDISK_CMD='/sbin/fdisk'
PARTED_CMD='/sbin/parted'
MKFS_VFAT_CMD='/sbin/mkfs.vfat'
MKFS_EXT2_CMD='/sbin/mkfs.ext2'
GRUB_INSTALL_CMD='/usr/sbin/grub-install'

main() {

    check_required_commands

    check_grub_cfg

    # overall guidance
    dialog_guidance

    # detect the target USB device by plugging it in
    dialog_unplugging
    local devices_bfr
    find_device_plugged devices_bfr
    "${ECHO_CMD}" "detected plugged devices: ${devices_bfr[@]}"

    dialog_plugging
    local devices_aft
    find_device_plugged devices_aft
    "${ECHO_CMD}" "detected plugged devices: ${devices_aft[@]}"

    # take a diff of lsblk before/after plugging in the USB device
    local new_devices
    diff_arrays devices_bfr devices_aft new_devices
    "${ECHO_CMD}" "detected plugged devices: ${devices_aft[@]}"

    # if found more than one new removable block device, exit with an error
    local device
    check_if_uniq new_devices device
    "${ECHO_CMD}" "detected a unique device: ${device}"

    local device_size
    check_device_size "${device}" device_size
    "${ECHO_CMD}" "size of ${device}: ${device_size} bytes"

    local user_password
    dialog_sudo_password user_password
    "${ECHO_CMD}" "user password obtained and being held in the variable user_password"

    confirm_device "${device}" "${device_size}" "${user_password}"
    "${ECHO_CMD}" "device confirmed: ${device}"

    local part_iso_9660_size_mib
    dialog_partition_size "${device}" "${device_size}" part_iso_9660_size_mib
    "${ECHO_CMD}" "size of the partition 3 confirmed: ${part_iso_9660_size_mib}"

    partition_drive "${device}" "${part_iso_9660_size_mib}" "${user_password}"

    grub_install "${device}" "${user_password}"

    mkdir_iso_9660 "${device}" "${user_password}"

    dialog_completion "${device}"
}

# Make sure the full paths to the commands are correct on the system.
check_required_commands() {
    local commands=(
        "${CAT_CMD}"
        "${CP_CMD}"
        "${DATE_CMD}"
        "${ECHO_CMD}"
        "${GREP_CMD}"
        "${LSBLK_CMD}"
        "${MKDIR_CMD}"
        "${MKTEMP_CMD}"
        "${MOUNT_CMD}"
        "${SED_CMD}"
        "${UMOUNT_CMD}"
        "${DIRNAME_CMD}"
        "${NUMFMT_CMD}"
        "${PINENTRY_CMD}"
        "${PRINTF_CMD}"
        "${REALPATH_CMD}"
        "${SLEEP_CMD}"
        "${SUDO_CMD}"
        "${YAD_CMD}"
        "${FDISK_CMD}"
        "${PARTED_CMD}"
        "${MKFS_VFAT_CMD}"
        "${MKFS_EXT2_CMD}"
        "${GRUB_INSTALL_CMD}"
    )
    local cmmd status error
    for cmmd in "${commands[@]}"; do
        "${WHICH_CMD}" "${cmmd}" > /dev/null
        status="$?"
        if [ "${status}" != '0' ]; then
            echo "The command ${cmmd} is not available. Please install the corresponding package in the system."
            error=1
        fi
    done
    if [ "${error}" = 1 ]; then
        exit 1
    fi
}

dialog_guidance() {
    local text0 text1 text2 text3 text4 text5 text6 text7 text8 text9 text10 text11 text12 textend
    text0='<span font-size="11pt">'
    text1="<b>We are going to create a UEFI/BIOS bootable USB drive in the following sequence.</b>\n\n"
    text2="1. Identify the USB device to program on.\n"
    text3="2. Erase all data on the detected device and create a new GPT partition table.\n"
    text4="3. Create the following partitions on the device:\n"
    text5="\t- a very small partition for grub boot loader to boot with legacy BIOS,\n"
    text6="\t- the EFI system partition (which is also used as the grub boot partition as well),\n"
    text7="\t- the partition where live Linux loopback.cfg compatible ISO-9660 images are stored.\n"
    text8="4. Install grub EFI x64 in the EFI and boot partition.\n"
    text9="5. Install grub i386-pc in the MBR and the boot partition.\n\n"
    text10="If you make a mistake in any step you can exit the script and run it again\n"
    text11="to overwrite the previous operations.\n\n"
    text12="Press OK to continue."
    textend="</span>"
    local status
    "${YAD_CMD}" \
        --title "What the script does" \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${text6}${text7}${text8}${text9}${text10}${text11}${text12}${textend}" \
        --button 'OK:0' --button 'Exit:1' --no-escape \
        --image 'dialog-information' --window-icon 'dialog-information' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi
}

# find removable block devices (except device partitions)
find_device_plugged() {
    declare -n devices_ref="$1"

    local output
    output=($("${LSBLK_CMD}" --noheadings -o PATH,TYPE,HOTPLUG | "${GREP_CMD}" -E '[^ ]+ +disk +1 *$' | "${SED_CMD}" -E 's/([^ ]+) +disk +1 *$/\1/'))
    local status="$?"
    devices_ref=("${output[@]}")
}

dialog_unplugging() {
    local text0 text1 text2 text3 text4 text5 textend
    text0='<span font-size="11pt">'
    text1='<b>We are going to find the Linux device name for the USB drive you are going to program.</b>\n\n'
    text2='Please safely eject your target USB device if you have already plugged it in on the current machine.\n'
    text3='Once you have safely un-mounted and ejected the USB drive, please press OK.\n'
    text4='You will be asked to plug in the target USB drive in the next dialog.\n'
    text5="\nIf you haven't plugged in your USB drive yet, just press OK."
    textend="</span>"
    local status
    "${YAD_CMD}" \
        --title "Making sure the device is not plugged yet" \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${textend}" \
        --button='OK:0' --button='Exit:1' --no-escape \
        --image 'dialog-question' --window-icon='dialog-question' \
        --center --fixed --borders=12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi
}

dialog_plugging() {
    local text0 text1 text2 text3 textend
    text0='<span font-size="11pt">'
    text1='<b>We are ready to detect your USB device you are going to program.</b>\n'
    text2='Plug in <b>your target USB drive</b> now.\n'
    text3='Once you have plugged it in, press OK.'
    textend="</span>"
    local status
    "${YAD_CMD}" \
        --title "Preparing to check device" \
        --text "${text0}${text1}${text2}${text3}${textend}" \
        --button 'OK:0' --button 'Exit:1' --no-escape \
        --image 'dialog-question' --window-icon 'dialog-question' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi
}

diff_arrays() {
    declare -n devices_bfr_ref="$1"
    declare -n devices_aft_ref="$2"
    declare -n devices_ref="$3"

    IFS=$'\n'
    bef_sorted=($(sort <<<"${devices_bfr_ref[*]}"))
    aft_sorted=($(sort <<<"${devices_aft_ref[*]}"))
    unset IFS

    local num1=0
    local num2=0
    while  [ ${num1} -lt "${#bef_sorted[@]}" ] && [ ${num2} -lt "${#aft_sorted[@]}" ]; do
        if [ "${bef_sorted[$num1]}" \< "${aft_sorted[$num2]}" ]; then
            echo "missing device: ${bef_sorted[$num1]}"
            # this is unexpected
            num1=$(("${num1}" + 1))
        elif [ "${bef_sorted[$num1]}" \> "${aft_sorted[$num2]}" ]; then
            devices_ref+=("${aft_sorted[$num2]}")
            num2=$(("${num2}" + 1))
        else
            num1=$(("${num1}" + 1))
            num2=$(("${num2}" + 1))
        fi
    done

    if [ ${num1} -lt "${#bef_sorted[@]}" ]; then
        # num1 ${num1} has not reached the end
        :
    fi
    if [ ${num2} -lt "${#aft_sorted[@]}" ]; then
        # num2 ${num2} has not reached the end
        devices_ref+=("${aft_sorted[@]:$num2}")
    fi
}

check_if_uniq() {
    declare -n new_devices_ref="$1"
    declare -n new_device_ref="$2"

    local text1

    if [ "${#new_devices_ref[@]}" -gt 1 ]; then
        text1="<b>More than one</b> new block devices were detected."
        local device
        for device in "${new_devices_ref[@]}"; do
            text1+="\n\t${device}"
        done
        dialog_more_than_one_device "${text1}"
        "${ECHO_CMD}" "Detected more than one newly plugged devices"
        exit 2
    elif [ "${#new_devices[@]}" -eq 0 ]; then
        dialog_no_device
        "${ECHO_CMD}" "No new block device was detected"
        exit 1
    else
        new_device_ref="${new_devices_ref[0]}"
        dialog_unique_device "${new_devices_ref[0]}"
    fi
}

dialog_more_than_one_device() {
    local text1="$1"

    local text0='<span font-size="11pt">'
    local textend="</span>"

    "${YAD_CMD}" \
        --title "Device detection error" \
        --text "${text0}${text1}${textend}" \
        --button 'OK:0' --no-escape \
        --image 'dialog-error' --window-icon 'dialog-error' \
        --center --fixed --borders 12
}

dialog_no_device() {
    local text0='<span font-size="11pt">'
    local textend="</span>"
    local text1
    text1="<b>No new block device was detected.</b>\n"
    "${YAD_CMD}" \
        --title "Device detection error" \
        --text "${text0}${text1}${textend}" \
        --button 'OK:0' --no-escape \
        --image 'dialog-error' --window-icon 'dialog-error' \
        --center --fixed --borders 12
}

dialog_unique_device() {
    local device="$1"
    local text0 text1 text2 text3 textend
    text0='<span font-size="11pt">'
    text1="<b>A unique block device was detected: <span foreground='blue'>${device}</span>\n\n"
    text2="We will show you more info for the detected device\n"
    text3="to make sure it is the correct one.</b>"
    textend="</span>"
    "${YAD_CMD}" \
        --title "Device detected" \
        --text "${text0}${text1}${text2}${text3}${textend}" \
        --button 'OK:0' --no-escape \
        --image 'dialog-information' --window-icon 'dialog-information' \
        --center --fixed --borders 12
}

check_device_size() {
    local device="$1"
    declare -n size_ref="$2"

    "${ECHO_CMD}" "checking the size of device ${device}."
    local output
    local status
    output=$("${LSBLK_CMD}" -n -o TYPE,SIZE --bytes "${device}" | "${GREP_CMD}" 'disk')
    status="$?"
    if [ "${status}" != '0' ]; then
        exit 1
    fi
    local size=$("${ECHO_CMD}" "${output}" | "${SED_CMD}" -e 's/disk *//')
    size_ref="${size}"
}

confirm_device() {
    local device="$1"
    local size="$2"
    local user_password="$3"

    # get the device capacity number with commas
    local gsize=$(LC_NUMERIC=en_US.utf8 "${NUMFMT_CMD}" --grouping "${size}")
    ##local gsize=$(LC_NUMERIC=en_US.utf8 "${PRINTF_CMD}" "%'d" "${size}")  # alternative

    # get fdisk -l output put in an array
    IFS=$'\n'
    local fdisk_list=($("${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${FDISK_CMD}" --list "${device}"))
    unset IFS

    local text0 text1 text2 text3 text4 text5 text6 text7 text8 text9 text10 textend
    text0='<span font-size="11pt">'
    text1="<b>Is this the correct device that you intend to create partitions on?</b>\n"
    text2="\t<b>Device:</b>\t${device}\n"
    text3="\t<b>Capacity:</b>\t${gsize} bytes\n"
    text4="\t<b>fdisk output:</b>\n<tt>"
    text5=$("${PRINTF_CMD}" '\t%s\n' "${fdisk_list[@]}")  # array elements in separate lines
    text6="</tt>\n\n"
    text7="<b><span foreground='red'>Warning:\n"
    text8="Going forward this script will completely erase the data on the device ${device}.\n"
    text9="If you are not 100% sure that the device the script detected is the one\n"
    text10="for your intended USB drive, then press Exit here to stop.</span></b>\n"
    textend="</span>"
    local status
    "${YAD_CMD}" \
        --title "Check Device" \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${text6}${text7}${text8}${text9}${text10}${textend}" \
        --button 'Yes, go ahead:0' --button 'Exit:1' --no-escape \
        --image 'dialog-question' --window-icon 'dialog-question' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling operation."
        exit 1
    fi
}

dialog_partition_size() {
    local device="$1"
    local size="$2"
    declare -n part_mib_ref="$3"

    local size_mib=$(("${size}" /1024/1024))
    local size_remaining=$(( "${size_mib}" - "${PARTITION_1_MIB}" - "${PARTITION_2_MIB}"))
    local minimum_size_mib='2048'
    local maximum_size_mib="${size_remaining}"
    local suggested_size_mib='8192'

    local text0 text1 text2 text3 text4 text5 text6 text7 text8 text9 text10 text11 textend
    text0='<span font-size="11pt">'
    text1="<b>How much space do you want to allocate for the partition 3 to store ISO-9660 images?</b>\n\n"
    text2="To have many live ISO-9660 image files you would want to make it large enough.\n"
    text3="If you are fine with a single ISO-9660 image 6000 MiB would suffice (as of 2023),\n"
    text4="but you need to check the ISO-9660 images first because they vary with Linux distributions.\n\n"
    text5="The total size of the device is: ${size_mib} MiB\n"
    text6="\tPartition 1 will use:\t${PARTITION_1_MIB} MiB\n"
    text7="\tPartition 2 will use:\t ${PARTITION_2_MIB} MiB\n"
    text8="\tPartition 3 suggested minimum size:\t${minimum_size_mib} MiB\n"
    text9="\tPartition 3 maximum size:\t${maximum_size_mib} MiB\n"
    text10="\n<b>You can allocate an adequate amount of space for the partition 3 and the leave the rest\n"
    text11="of the drive space where you can later manually add more partitions for other purposes.</b>\n"
    textend="</span>"
    local status
    local dialog_output=$("${YAD_CMD}" \
            --form \
            --title "ISO-9660 Images Partition Size" \
            --text "${text0}${text1}${text2}${text3}${text4}${text5}${text6}${text7}${text8}${text9}${text10}${text11}${textend}" \
            --field '<b>Size of partition 3 (ISO-9660 images) (MiB)</b>:NUM' "${suggested_size_mib}!${minimum_size_mib}..${maximum_size_mib}!1" \
            --button 'Ok, I entered the size:0' --button 'Exit:1' --no-escape \
            --image 'dialog-question' --window-icon 'dialog-question' \
            --center --fixed --borders 12)
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling partitioning the device."
        exit 1
    fi
    local partition_mib=$("${ECHO_CMD}" "${dialog_output}" | sed -e 's/|$//')

    part_mib_ref="${partition_mib}"
}

# If this function is used while the user password cache (from any previous successful run of sudo) is active
# it will accept any text as the password without an error.
# So the succeeding sudo commands after this function will succeed as long as the password cache is maintained,
# but will fail after the cache expires due to the wrong text the variable password_ref holds (within the memory).
dialog_sudo_password() {
    declare -n password_ref="$1"

    local text0 text1 text2 textend
    text0='<span font-size="11pt">'
    text1='<b>We are going to ask for your user password next.</b>\n'
    text2='It will be used only for running sudo command in this script and will never be written to files.\n'
    text3='You can hide/show the password while typing in the password dialog.\n'
    textend="</span>"
    "${YAD_CMD}" \
        --title "User password for sudo" \
        --text "${text0}${text1}${text2}${text3}${textend}" \
        --button 'Ok:0' --button 'Exit:1' --no-escape \
        --image 'dialog-question' --window-icon 'dialog-question' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling password dialog."
        exit 1
    fi

    local retry=3
    text1=''
    local response error status output
    while [ "${retry}" -gt 0 ]; do
        # get the user login password via PINENTRY
        response=$("${ECHO_CMD}" -e "SETPROMPT Enter your password:\nGETPIN\n" | "${PINENTRY_CMD}")
        password_ref=$("${ECHO_CMD}" "${response}" | "${SED_CMD}" -nr '0,/^D (.+)/s//\1/p')
        error=$("${ECHO_CMD}" "${response}" | "${GREP_CMD}" -E 'Operation cancelled')

        if [ ! -z "${error}" ]; then
            echo "${error}"
            exit 1
        fi

        # test whether the password works
        output=$("${ECHO_CMD}" "${password_ref}" | "${SUDO_CMD}" --stdin "${DATE_CMD}" 2>&1)
        status="$?"
        if [ "${status}" = '0' ]; then
            break
        else
            "${ECHO_CMD}" "sudo failed"
            if [ "${retry}" -eq 0 ]; then
                exit 1
            fi
            retry=$(( "${retry}" - 1 ))
            text1="<b><span foreground='red'>The password did not work.</span> You can retry ${retry} more times.</b>\n"
            "${YAD_CMD}" \
                --title "User password for sudo" \
                --text "${text0}${text1}${text2}${textend}" \
                --button 'OK:0' --button 'Exit:1' --no-escape \
                --image 'dialog-question' --window-icon 'dialog-question' \
                --center --fixed --borders 12
            status="$?"
            if [ "${status}" != '0' ]; then
                "${ECHO_CMD}" "canceling the program."
                exit 1
            fi
        fi
    done
}

partition_drive() {
    local device="$1"
    local part_iso_9660_size_mib="$2"
    local user_password="$3"

    # Partition    Name       filesystem  flags
    # Partition 1  bios-grub  None        bios_grub
    # Partition 2  ISO-BOOT   fat32       esp,boot
    # Partition 3  Boot-ISO   ext2
    #
    local part_1_begin_mib="1"
    local part_1_end_mib=$((1 + "${PARTITION_1_MIB}"))
    local part_2_end_mib=$(("${part_1_end_mib}" + "${PARTITION_2_MIB}"))
    local part_iso_9660_end_mib=$(("${part_2_end_mib}" + "${part_iso_9660_size_mib}"))

    local text0 text1 text2 text3 text4 text5 text6 textend
    local status

    # confirm partitioning
    text0='<span font-size="11pt">'
    text1="<b>We are going to <span foreground='blue'>erase data</span> on the device ${device} and <span foreground='blue'>create new partitions</span> :</b><tt>\n"
    text2="Partition \tName    \tF.system \tStart  \tEnd    \tFlags\n"
    text3="${device}1 \t${PARTITION_1_NAME} \tnone     \t${part_1_begin_mib} MiB  \t${part_1_end_mib} MiB  \tbios_grub\n"
    text4="${device}2 \t${PARTITION_2_NAME} \tfat32    \t${part_1_end_mib} MiB  \t${part_2_end_mib} MiB  \tesp,boot\n"
    text5="${device}3 \t${PARTITION_3_NAME} \text2     \t${part_2_end_mib} MiB  \t${part_iso_9660_end_mib} MiB</tt>\n\n"
    text6="<b>Press OK to continue.</b>"
    textend="</span>"
    "${YAD_CMD}" \
        --title "Create Partitions" \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${text6}${textend}" \
        --button 'OK:0' --button 'Exit:1' --no-escape \
        --image 'dialog-question' --window-icon 'dialog-question' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi

    # create the partition table and partition the drive
    "${ECHO_CMD}" "running ${PARTED_CMD} ${device}
        --script mklabel gpt
        mkpart ${PARTITION_1_NAME} ${part_1_begin_mib}MiB ${part_1_end_mib}MiB
        set 1 bios_grub on
        mkpart ${PARTITION_2_NAME} fat32 ${part_1_end_mib}MiB ${part_2_end_mib}MiB
        set 2 esp on
        set 2 boot on
        mkpart ${PARTITION_3_NAME} ext2 ${part_2_end_mib}MiB ${part_iso_9660_end_mib}MiB"

    local output
    output=$("${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin \
                 "${PARTED_CMD}" \
                 "${device}" \
                 --align optimal \
                 --script mklabel gpt \
                 mkpart "${PARTITION_1_NAME}" "${part_1_begin_mib}"MiB "${part_1_end_mib}"MiB \
                 set 1 bios_grub on \
                 mkpart "${PARTITION_2_NAME}" fat32 "${part_1_end_mib}"MiB "${part_2_end_mib}"MiB \
                 set 2 esp on \
                 set 2 boot on \
                 mkpart "${PARTITION_3_NAME}" ext2 "${part_2_end_mib}"MiB "${part_iso_9660_end_mib}"MiB)
    status="$?"

    # check command exit status
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "error: parted command failed."
        "${ECHO_CMD}" "parted output: ${output}"
        text1="<b>parted failed with exit status: ${status}</b>\n"
        text2="${output}"
        "${YAD_CMD}" \
            --title "Parted error" \
            --text "${text0}${text1}${text2}${textend}" \
            --button 'OK:0' --no-escape \
            --image 'dialog-error' --window-icon 'dialog-error' \
            --center --fixed --borders 12
        exit 2
    fi

    # format the partition 2
    "${SLEEP_CMD}" 3.8   # some old USB flash drives need a delay after the partition table is created, otherwise the command fails.
    # give the filesystem label the same value as the partition name ${PARTITION_2_NAME}
    local partition="${device}2"
    "${ECHO_CMD}" "running mkfs.vfat -n ${PARTITION_2_NAME} ${partition}"
    output=$("${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin \
                "${MKFS_VFAT_CMD}" \
                -n "${PARTITION_2_NAME}" \
                "${partition}")
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "error: mkfs.vfat failed."
        "${ECHO_CMD}" "mkfs.vfat output: ${output}"
        exit 2
    fi

    # format the partition 3
    "${SLEEP_CMD}" 3.8
    # give the filesystem label the same value as the partition name ${PARTITION_3_NAME}
    partition="${device}3"
    "${ECHO_CMD}" "running mkfs.ext2 -L ${PARTITION_3_NAME} ${partition}"
    output=$("${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin \
                "${MKFS_EXT2_CMD}" \
                -L "${PARTITION_3_NAME}" \
                "${partition}")
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "error: mkfs.ext2 failed."
        "${ECHO_CMD}" "mkfs.ext2 output: ${output}"
        exit 2
    fi

    text0='<span font-size="11pt">'
    text1="<b>We have completed partitioning the device ${device}\n"
    text2="and formatted the partitions 2 and 3.\n\n"
    text3="In the next we are going to install grub boot loader\n"
    text4="and our custom grub.cfg.\n"
    text5="Press OK to continue.</b>"
    textend="</span>"
    "${YAD_CMD}" \
        --title "Completed Partitioning" \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${textend}" \
        --button 'OK:0' --button 'Exit:1' --no-escape \
        --image 'dialog-information' --window-icon 'dialog-information' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi
    "${SLEEP_CMD}" 2.8
}

grub_install() {
    local device="$1"
    local user_password="$2"

    # create a mount point
    local mount_point=$("${MKTEMP_CMD}" -d --suffix='-iso_9660_boot')
    "${ECHO_CMD}" "Created a mount point ${mount_point}"

    # mount the partition 2 of "${device}"
    local partition="${device}2"
    "${ECHO_CMD}" "Mounting ${partition} at ${mount_point}"
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${MOUNT_CMD}" "${partition}" "${mount_point}"

    # Install grub for legacy BIOS in MBR and the boot partition.
    "${ECHO_CMD}" "Installing grub for legacy BIOS in the boot partition and MBR."
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${GRUB_INSTALL_CMD}" --target=i386-pc --boot-directory="${mount_point}"/boot --removable "${device}"

    # Install grub for UEFI in the EFI partition and the boot partition.
    # In our case the EFI partition and the boot partition are the same partition 2.
    "${ECHO_CMD}" "Installing grub for UEFI in the EFI partition and the boot partition."
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${GRUB_INSTALL_CMD}" --no-uefi-secure-boot --target=x86_64-efi --boot-directory="${mount_point}"/boot --efi-directory="${mount_point}" --removable

    # write to /boot/grub/grub.cfg
    "${ECHO_CMD}" "Copying grub.cfg to ${mount_point}/boot/grub/grub.cfg"
    copy_grub_cfg "${mount_point}"

    # un-mount the partition 2.
    "${ECHO_CMD}" "Un-mounting the ${partition}"
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${UMOUNT_CMD}" "${mount_point}"
}

check_grub_cfg() {
    local text0 text1 text2 text3 textend
    local scriptpath=`"${REALPATH_CMD}" "${BASH_SOURCE[0]}"`
    local scriptdir=`"${DIRNAME_CMD}" "${scriptpath}"`
    local parentdir=`"${DIRNAME_CMD}" "${scriptdir}"`
    local grub_cfg_file="${parentdir}/grub/grub.cfg"
    if [ ! -f "${grub_cfg_file}" ]; then
        "${ECHO_CMD}" "Error: ${grub_cfg_file} doesn't exist."
        text0='<span font-size="11pt">'
        text1="<b>Error: <tt>${grub_cfg_file}</tt> is missing!</b>\n\n"
        text2="Make sure you have the same directory tree as the source code tree.\n"
        text3="Keep the relative location of files within the source code directory."
        textend="</span>"
        "${YAD_CMD}" \
            --title "File is missing: ${grub_cfg_file}" \
            --text "${text0}${text1}${text2}${text3}${textend}" \
            --button 'OK:0' --no-escape \
            --image 'dialog-error' --window-icon 'dialog-error' \
            --center --fixed --borders 12
        exit 1
    fi
}

copy_grub_cfg() {
    local mount_point="$1"
    local scriptpath=`"${REALPATH_CMD}" "${BASH_SOURCE[0]}"`
    local scriptdir=`"${DIRNAME_CMD}" "${scriptpath}"`
    local parentdir=`"${DIRNAME_CMD}" "${scriptdir}"`
    local grub_cfg_file="${parentdir}/grub/grub.cfg"
    local destdir="${mount_point}/boot/grub"
    if [ ! -d "${destdir}" ]; then
        "${ECHO_CMD}" "error: ${destdir} doesn't exist"
        exit 2
    fi
    if [ -f "${grub_cfg_file}" ]; then
        "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${CP_CMD}" -T "${grub_cfg_file}" "${destdir}/grub.cfg"
    fi
}

mkdir_iso_9660() {
    local device="$1"
    local user_password="$2"

    # create a mount point
    local mount_point=$("${MKTEMP_CMD}" -d --suffix='-boot_iso_9660')
    "${ECHO_CMD}" "Created a mount point ${mount_point}"

    # mount the partition 3 of "${device}"
    local partition="${device}3"
    local status
    "${ECHO_CMD}" "Mounting the ${partition} at ${mount_point}"
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${MOUNT_CMD}" "${partition}" "${mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "${MOUNT_CMD} failed."
        exit 1
    fi

    "${ECHO_CMD}" "Creating the directory ${mount_point}/${ISO_9660_DIRECTORY}"
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${MKDIR_CMD}" "${mount_point}/${ISO_9660_DIRECTORY}"

    # un-mount the partition 3.
    "${ECHO_CMD}" "Un-mounting the ${partition}"
    "${ECHO_CMD}" "${user_password}" | "${SUDO_CMD}" --stdin "${UMOUNT_CMD}" "${mount_point}"
}

dialog_completion() {
    local device="$1"

    local text0 text1 text2 text3 text4 text5 text6 text7 text8 text9 text10 text11 text12 text13 text14 text15 textend
    text0='<span font-size="11pt">'
    text1="<b>We have installed grub for UEFI/BIOS boot and added\n"
    text2="<tt>/boot/grub/grub.cfg</tt> in the boot partition.</b>\n"
    text3="You can check the drive partitions by the command '<tt>fdisk --list ${device}</tt>'\n"
    text4="or by '<tt>gparted ${device}</tt>'.\n\n"
    text5="<b><span foreground='blue'>The only thing remaining is to add some bootable ISO-9660 image files in the\n"
    text6="directory '${ISO_9660_DIRECTORY}' of the partition 3 which has the partition name ${PARTITION_3_NAME}.</span></b>\n\n"
    text7='<b>Example commands to add a bootable OS image file:\n</b>'
    text8='  Make sure to use the correct device name for <b>sdX</b>. (To find the device run the command <tt>lsblk</tt>.)\n'
    text9='<tt>  $ mkdir /tmp/usbmount/\n'
    text10='  $ sudo mount /dev/sdX3 /tmp/usbmount/\n'
    text11="  $ sudo cp live-image.iso /tmp/usbmount/${ISO_9660_DIRECTORY}/\n"
    text12='  $ sudo umount /tmp/usbmount/</tt>\n\n'
    text13='  To safely unplug the USB flash memory:\n'
    text14='<tt>  $ udisksctl power-off --block-device /dev/sdX</tt>\n\n'
    text15='Press OK to finish this script.'
    textend="</span>"

    local text21 text22 text23 text24 text25 text26 text27 text28 text29 text210 text211 text212 text213 text214
    text21="We have installed grub for UEFI/BIOS boot and added "
    text22="/boot/grub/grub.cfg in the boot partition.\n"
    text23="You can check the drive partitions by the command 'fdisk --list ${device}' "
    text24="or by 'gparted ${device}'.\n\n"
    text25="The only thing remaining is to add some bootable ISO-9660 image files in the\n"
    text26="directory '${ISO_9660_DIRECTORY}' of the partition 3 which has the partition name ${PARTITION_3_NAME}.\n\n"
    text27='Example commands to add a bootable OS image file:\n'
    text28='  Make sure to use the correct device name for sdX. (To find the device run the command lsblk.)\n'
    text29='  $ mkdir /tmp/usbmount/\n'
    text210='  $ sudo mount /dev/sdX3 /tmp/usbmount/\n'
    text211="  $ sudo cp live-image.iso /tmp/usbmount/${ISO_9660_DIRECTORY}/\n"
    text212='  $ sudo umount /tmp/usbmount/\n\n'
    text213='  To safely unplug the USB flash memory:\n'
    text214='  $ udisksctl power-off --block-device /dev/sdX\n'
    "${ECHO_CMD}" -e "${text21}${text22}${text23}${text24}${text25}${text26}${text27}${text28}${text29}${text210}${text211}${text212}${text213}${text214}"

    "${YAD_CMD}" \
        --title 'Preparing to check device' \
        --text "${text0}${text1}${text2}${text3}${text4}${text5}${text6}${text7}${text8}${text9}${text10}${text11}${text12}${text13}${text14}${text15}${textend}" \
        --button 'OK:0' --no-escape \
        --image 'dialog-information' --window-icon 'dialog-information' \
        --center --fixed --borders 12
    status="$?"
    if [ "${status}" != '0' ]; then
        "${ECHO_CMD}" "canceling the program."
        exit 1
    fi
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

