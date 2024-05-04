## Test on VirtualBox

We can test the resulting multiboot USB drive on VirtualBox to see how it boots

First copy some of your live Linux ISO images in the ISO directory of the multiboot USB drive.

This is the test I ran a while ago but I used the following ISO images in my test:
- ubuntu-22.04.2-desktop-amd64.iso
- custom Debian Live Bullseye
- debian-live-12.0.0-amd64-lxde.iso
- kali-linux-2023.2-live-amd64.iso
- linuxmint-21.1-xfce-64bit.iso

When finished copying ISO files, un-mount all of the multiboot drive partitions.
Keep the multiboot USB drive plugged in a USB slot.

### Create a virtual guest Linux

Create a virtual guest Linux OS on VirtualBox and set the necessary setting items.
You don't need to allocate a storage device for this purpose because we are booting from a USB external device.

### Click Settings of the guest Linux OS

![virtualbox-guest-settings](image/01_virtualbox-guest-settings.png)

### Enable EFI under System

![virtualbox-guest-enable-efi-large-memory](image/02_virtualbox-guest-enable-efi-large-memory.png)

### Add a USB device filter under USB

![virtualbox-guest-attach-usb2-device](image/03_virtualbox-guest-attach-usb2-device.png)

### In case the USB drive is not recognized

![virtualbox-guest-attach-usb2-device_error](image/04_virtualbox-guest-attach-usb2-device_error.png)

Try USB 3 if you have a USB recognition problem.

![virtualbox-guest-attach-usb3-device](image/05_virtualbox-guest-attach-usb3-device.png)

### Start the virtual guest

![virtualbox-guest-start](image/06_virtualbox-guest-start.png)

### A VirtualBox error that can be ignored

![virtualbox-guest-init](image/07_virtualbox-guest-init.png)

### grub is scanning all ISO image files

![grub-step1-messages-scanning-isos](image/08_grub-step1-messages-scanning-isos.png)

### grub has listed compatible ISO image files

![grub-step1-select-iso-file](image/09_grub-step1-select-iso-file-3.png)

Select one of them and press enter.

### A custom Debian Live grub menu

![grub-step2-custom-debian-live-menu](image/10_grub-step2-custom-debian-live-menu.png)

### Booting the custom Debian Live

![grub-step2-custom-debian-live-booting](image/11_grub-step2-custom-debian-live-booting.png)

### Booted the custom Debian Live

![grub-step2-custom-debian-live-booted](image/12_grub-step2-custom-debian-live-booted.png)

### The custom Debian Live app menu

![grub-step2-custom-debian-live-logging-off](image/13_grub-step2-custom-debian-live-logging-off.png)

### Shutting down the custom Debian Live

![grub-step2-custom-debian-live-shutting-down](image/14_grub-step2-custom-debian-live-shutting-down.png)

### The official Debian Live grub menu

![grub-step2-debian-live-12-menu](image/20_grub-step2-debian-live-12-menu.png)

### Booting Debian Live

![grub-step2-debian-live-12-booting-begins](image/21_grub-step2-debian-live-12-booting-begins.png)

### Booting Debian Live continuing

![grub-step2-debian-live-12-booting](image/22_grub-step2-debian-live-12-booting.png)

### Booted Debian Live

![grub-step2-debian-live-12-booted](image/23_grub-step2-debian-live-12-booted.png)

### Shutdown menu of Debian Live

![grub-step2-debian-live-12-shutdown](image/24_grub-step2-debian-live-12-shutdown.png)

### Booting Ubuntu

![ubuntu-booting](image/31_ubuntu-booting.png)

### Booting Ubuntu 2

![ubuntu-booting-2](image/31_ubuntu-booting-2.png)

### Booted Ubuntu ISO

![ubuntu-booted](image/32_ubuntu-booted.png)

### Ubuntu live or installation

![ubuntu-live](image/33_ubuntu-live.png)

### Booted Ubuntu live

![ubuntu-live-booted](image/34_ubuntu-live-booted.png)

### Ubuntu shutdown

![ubuntu-shutdown](image/35_ubuntu-shutdown.png)

### Kali Linux grub menu

![kali-grub-menu](image/41_kali-grub-menu.png)

### Booting Kali Linux

![kali-booting](image/42_kali-booting.png)

### Booted Kali Linux

![kali-booted](image/43_kali-booted.png)

### Kali applications menu

![kali-apps-menu](image/44_kali-apps-menu.png)

### Kali shutdown

![kali-shutdown](image/45_kali-shutdown.png)

### Puppy Linux grub menu

![puppylinux-grub-menu](image/60_puppylinux-grub-menu.png)

### Puppy Linux booting

![puppylinux-booting](image/61_puppylinux-booting.png)

### Puppy Linux booted

![puppylinux-booted](image/62_puppylinux-booted.png)

### Puppy Linux guide

![puppylinux-guide](image/63_puppylinux-guide.png)

### Puppy Linux shutdown

![puppylinux-shutdown](image/64_puppylinux-shutdown.png)

### Linux Mint grub menu

![mint-grub-menu](image/70_mint-grub-menu.png)

### Linux Mint booting

![mint-booting](image/71_mint-booting.png)

### Linux Mint booted

![mint-booted](image/72_mint-booted.png)
