FAT12 and FAT16 bootloader
---------------------------

### bootsect12.asm

&mdash; a configurable FDD FAT12 bootloader.

The first line of (FDD)/mgcbean/boot/boot.cfg can contain a filename to load.

### bootsect16.asm

&mdash; FAT16 bootloader, may be used with USB flash drives.

Unlike FAT12 bootloader this one is not configurable &mdash; I can't find enough space for it.

As with the FAT12 booloader it loads (bootable HDD)/mgcbean/boot/kernel to 1000:0000 and jumps to it.
