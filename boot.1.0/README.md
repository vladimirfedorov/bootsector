Floppy disk boot loader
-----------------------

### bootsect.asm 
&mdash; loads the file (FDD)/boot/kernel to 1000:0000 and jumps to it.

### bootsect-com.asm 
&mdash; loads (FDD)/boot/kernel and jumps to 1000:0100; kernel can be a simple .com file.