# live-iso-multiboot-drive

Create a drive capable of booting multiple live Linux ISO-9660 files on UEFI/BIOS firmware.

## What it does

The purpose of this project is to set up a USB drive
so that it can store multiple bootable live Linux ISO 9660 image files and
boot any of these ISO 9660 image files on UEFI firmware machines as well as on legacy BIOS firmware machines.

We will use the expression an ISO image to mean that the file is formatted with the ISO 9660 filesystem.
[Wikipedia](https://en.wikipedia.org/wiki/ISO_9660).

Once the drive is set up,
you can copy live Linux ISO files as regular files in the specific drive partition
and they will be automatically recognized by the provided grub.cfg.
So adding or removing live system ISO images to the drive is as simple as copying or deleting ISO images files
in the ISO image directory in the ISO image partition.

We provide a shell script that automates the whole process of partitioning the drive, formatting the filesystem,
and installing the grub boot loader.
You can do the same thing manually as well.

## Live system

### Definition of a live system

[The Debian live manual](https://live-team.pages.debian.net/live-manual/html/live-manual/about-manual.en.html)
says:
> "A live system is an operating system that can boot without installation to a hard drive.
> Live systems do not alter local operating system(s) or file(s) if already installed on the computer storage.
> Live systems are typically booted from media such as CDs, DVDs or USB sticks."

### Supported live Linux systems

We support live Linux system images that provide loopback.cfg in their ISO image files.
This makes writing grub.cfg very easy because the loopback.cfg within these live system ISO will take care of all necessary kernel parameters.

[Loopback.cfg](https://supergrubdisk.org/wiki/Loopback.cfg) says:
> A loopback.cfg is basically just a grub.cfg that's designed to be used to boot a live distribution from an iso file on a filesystem rather than an actual physical CD.

The existence of loopback.cfg in the live Linux ISO filesystem is a convention to advertises that
the live system in the ISO image can boot via the grub boot loader from the ISO image file as a regular file on a filesystem
instead of booting from the ISO filesystem written on the whole storage device.

For such an ISO image file our grub.cfg can simply include the loopback.cfg via grub's configfile directive to properly set up its grub menu.

### Tested ISO image files

- Debian Live ISO (official live ISO)
- Custom Debian live ISO (as created by Debian live-build)
- Ubuntu ISO (official live ISO)
- Kali Linux ISO
- Linux Mint ISO
- Puppy Linux ISO

### Other live systems are not supported

It would be possible to tweak grub.cfg so that it can boot some other live Linux systems that don't provide loopback.cfg,
but our project doesn't look at it because there are too many variations.

Also our method doesn't support Windows.

## Let's create a multiboot USB drive

There are two ways to set up a multiboot USB drive.
The manual method is not too difficult and is a good way to understand what exactly is being done.
However with the manual method you might make a small mistake that could potentially be damaging to your Linux host system,
so we recommend using the automated script.
The security of the script is easy to inspect yourself because it is a single file shell script with a lot of descriptive comments.

### Automatic method (easy)

[Run the script to create a USB drive](doc/automated-script.md)

### Manual method

[Manually create a USB drive](doc/manual-build.md)

### Test booting within VirtualBox

[Test run the USB drive on VirtualBox](doc/test-on-virtualbox.md)

## Details of our solution

[Details of our solution](doc/solution.md)

