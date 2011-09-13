Floppy disk boot loader
-----------------------

### bootsect.asm

This is a configurable FDD bootloader

First 11 bytes of (FDD)/mgcbean/boot/boot.cfg can contain a name of a file to load.
The default file to load is "kernel". 