; SIMPLE BOOT MANAGER
; fd boot sector
;
; 0-400h - IVT
; 400h-500h - bios data area
; <- 7bff - stack
; 7c00-7dff - 512 b boot sector
; 7E00 - 9000 FAT (9*512 b)
; 9000 - A000 1pg dir (/boot)
; 10000 -> kernel startup code (cs=1000h)
;
; compile with fasm

	org	7c00h

	jmp	word start
	nop

; BIOS Parameter Block (BPB)

oeminf	db	'SBM 1.00'	; OEM info (8)
	dw	200h		; sec. size
	db	1		; sectors per cluster
	dw	1		; # of reserved sectors
	db	2		; # of FATs
rootent dw	00E0h		; # of entries in the root directory
	dw	0B40h		; # of sectors in volume
	db	0F0h		; media description
spfat	dw	09h		; # of sectors per fat
sptrack dw	12h		; # of sectors per track
heads	dw	2		; # of heads
	dd	0		; # of hidden sectors
	dd	0		; big total # of sectors
bootdrv db	0		; drive #
	db	0		; reserved
	db	29h		; extended boot rec. signature
	dd	0		; serial number
	db	'NONAME     '	; volume label (11)
	db	'FAT12   '	; file system (8)

start:
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, 7bfeh	; stack

	mov	[bootdrv], dl	; boot drive

; look for the kernel

	mov	bx, 7e00h	     ; fat
	mov	ax, 1
	movzx	bp, byte [spfat]
	call	readsect

	mov	bx, 9000h	     ; root ent
	mov	ax, 19
	movzx	bp, byte [rootent]
	shr	bp, 4
	call	readsect

	mov	di, fboot	; 'cd /boot'
	call	finddir
	cmp	ax, -1
	jne	.f0
	mov	si, noboot
	call	write
	jmp	$

  .f0:	mov	bx, 0900h
	mov	cx, 8
	call	loadfile

; scan fd root directory for 'KERNEL     '

	mov	di, fkernel
	call	findfile
	cmp	ax, -1
	jne	.f1

	mov	si, nokernel
	call	write
	jmp	$

  .f1:	mov	bx, 1010h
	mov	cx, -1
	call	loadfile

	mov	ax, 1000h
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	xor	sp, sp
	push	10h		; int 20h

	jmp	far 1000h:0100h ; boot up


; ----------------
; readsec - read sector
; in: es:bx - buffer for a sector
;     ax - LBA # of sector (0-2879)
;     bp - number of sectors to read (1-255)


readsect:
	pusha
	mov	di, 3  ; retry 3 times

  .try: push	di

	call	reset
	xor	dx, dx
	div	word [sptrack] ; ax=lba/sptrack, dx=sec. number
	mov	cx, dx	; cl=sec. number
	inc	cx
	xor	dx, dx
	div	word [heads] ; dx - head, ax - cylinder
	mov	ch, al
	mov	dh, dl
	mov	dl, [bootdrv]
	mov	ax, bp ; al = bp
	mov	ah, 2
	int	13h
	pop	di

	jnc	.r_ok

	dec	di
	jnz	.try

	mov	si, readerr
	call	write
	jmp	$
 .r_ok: popa
	ret

; ----------------
; returns next file cluster or 0fffh in ax if EOF
; IN: ax - 1st cluster of a file
; OUT: ax - next file cluster, or  0fffh if EOF

getnextcluster:
	push	bx
	push	dx
	push	si
	push	ds
	mov	bx, 07e0h
	mov	ds, bx
	mov	bx, 2
	xor	dx, dx
	div	bx
	mov	bx, 3
	mul	bl
	mov	si, ax
	lodsw
	ror	eax, 16
	lodsb
	rol	eax, 16
	or	dx, dx
	jz	.exit
	shr	eax, 12
 .exit: and	eax, 00000fffh
	pop	ds
	pop	si
	pop	dx
	pop	bx
	ret

; ----------------
; find file
; IN:  es:di - file name
; OUT: ax = 1st cluster or ax=0FFFFh if file not found
;      si - file entry
finddir:
	mov	byte[findfile.cond], 74h ; jnz = 74h
	jmp	findfile.find
findfile:
	mov	byte[.cond], 75h ; jz = 45h
 .find: push	cx
	mov	cx, 4096/32 ; - max # of files
	mov	si, 9000h
 .scan: push	di
	push	si
	push	cx
	mov	cx, 0bh
	repe	cmpsb
	pop	cx
	pop	si
	pop	di
	je	.found
 .c1:	add	si, 20h     ; go to the next entry
	cmp	byte[si],0  ; last dir entry
	je	.notfnd
	loop	.scan
 .notfnd:
	mov	ax, 0ffffh
	jmp	.exit

 .found:
	test	byte[si+0bh],10h ; subdirectory bit
 .cond: jz	.c1		; jz = 74h, jnz = 75h
	mov	ax, [si+1ah]	; 1st cluster of the file
				; ax - 1st cluster of file
 .exit:
	pop	cx
	ret

; ----------------
; Load file into memory
; IN: ax - 1st cluster
;     bx - where to load (seg)
;     cx - # of secs - 1 to read (within); 1 - 1 sect, 0 - 64k sect.

loadfile:

	push	es
	push	cx
	mov	es, bx
	xor	bx, bx
	mov	bp, 1
.readf: push	ax
	add	ax, 31
	call	readsect
	pop	ax
	call	getnextcluster
	add	bx, 200h

	cmp	bx, 0
	jne	.c1
	mov	bx, es
	add	bx, 1000h
	mov	es, bx
	xor	bx, bx
   .c1: cmp	ax, 0ff8h
	jae	.exit
	loop	.readf
 .exit: pop	cx
	pop	es
	ret


; ----------------
write:
	lodsb
	or	al, al
	jz	.msgend
	mov	ah, 0eh
	mov	bx, 0007h
	int	10h
	jmp	write
    .msgend:
	ret

reset:
	pusha
	xor ax, ax  ; reset disk
	movzx bx, [bootdrv]
	int 13h
	popa
	ret

; ----------------
nokernel	db "KERNEL not found",0
noboot		db "fd0/BOOT not found",0
readerr 	db "Disk read error",0
fkernel 	db "KERNEL     "
fboot		db "BOOT       "

; end of sector:

 times 510+7c00h-$ db 0
	dw    0AA55h  ; boot signature
