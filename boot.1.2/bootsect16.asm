; SIMPLE BOOT LOADER
;
; 0-400h - IVT
; 400h-500h - bios data area
; <- 7bff - stack
; 7c00-7dff - 512 b boot sector
; 7E00 - 9000 FAT (9*512 b)
; 9000 - A000 1pg dir (/mgcbean/boot)
; 10000 -> kernel startup code (cs=1000h)
;
; compile with fasm
;
use16
	org	7c00h

	jmp	word start
	nop

; BIOS Parameter Block (BPB)

oeminf	db	'SBM 1.2 '	; OEM info (8)
	dw	200h		; sec. size
secpcl	db	40h		; sectors per cluster
ressecs dw	6		; # of reserved sectors
	db	2		; # of FATs
rootent dw	200h		; # of entries in the root directory
	dw	0		; # of sectors in volume
	db	0F8h		; media description
spfat	dw	0F5h		; # of sectors per fat
sptrack dw	3Fh		; # of sectors per track
heads	dw	0FFh		; # of heads
sbpart	dd	20h		; # of hidden sectors
	dd	03d3fdeh	; big total # of sectors
bootdrv db	80h		; drive #
	db	0		; reserved
	db	29h		; extended boot rec. signature
	dd	0		; serial number
	db	'NONAME     '	; volume label (11)
	db	'FAT16   '	; file system (8)

start:
	xor	eax, eax
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, 7bfeh		; stack
	mov	[bootdrv], dl		; boot drive

	mov	si, oeminf
	call	write
	mov	si, crlf
	call	write

	mov	bx, 7e00h		; Load FAT
	mov	ax, [ressecs]
	add	eax, [sbpart]
	mov	bp, 9 ; [spfat]         ; 7e000...9000 = 9*512
	call	readsect

	xor	eax, eax
	mov	ax, [spfat]
	shl	ax, 1
	add	ax, [ressecs]		; ax = root directory
	add	eax, [sbpart]

	mov	bx, [rootent]
	shr	bx, 4
	add	bx, ax
	mov	[diskdata], bx		; file data 1st sector

	mov	bx, 9000h		; Load root directory
	;movzx   bp, byte [rootent]
	;shr     bp, 4
	mov	bp, 8			; 9000...a000 = 8*512
	call	readsect

	mov	di, d1
	mov	bx, 0900h
	call	chdir			; cd mgcbean

	mov	di, d2
	mov	bx, 0900h
	call	chdir			; cd boot

	mov	bx, 1000h
	mov	di, kernelfname
	call	openfile

	jmp	far 1000h:0000h ; boot up


; ----------------
; readsec - read sector
; in: es:bx - buffer for a sector
;     eax   - LBA# of sector
;     bp    - number of sectors to read (1-127)

readsect:
	push	cx
	push	si
	push	dx
 .read:
	mov	cx, 5		; try to read 5 times
 .try:
	push	eax

	push	di		; create parameter block in the stack
	mov	di, sp
	push	0
	push	0
	push	eax
	push	es
	push	bx
	push	1
	push	16

	mov	si, sp
	mov	dl, [bootdrv]
	mov	ah, 42h 	; read sector
	int	13h

	mov	sp, di
	pop	di

	pop	eax
	jnc	.r_ok
				; some error, reset
	push	ax
	xor	ah, ah
	int	13h
	pop	ax

	dec	cx
	jnz	.try

	mov	si, strerr
	call	write
	jmp	$

 .r_ok:
	inc	eax
	add	bx, 512
	jnc	.r_nc
	mov	dx, es
	add	dh, 10h
	mov	es, dx
 .r_nc:
	dec	bp
	jnz	.read

	pop	dx
	pop	si
	pop	cx

	ret


; ----------------
; IN: di = file/folder name
;     bx = segment to load to
chdir:
	mov	word [openfile.f1+1], 8 ; 8 sectors for directory
	call	finddir
	jmp	openfile.f0
openfile:
	mov	word [openfile.f1+1], (80000h/512)
	call	findfile
    .f0:
	cmp	ax, -1
	jne	.f1

	mov	si, di			; file not found
	call	write
	mov	si, nofile
	call	write
	hlt
	jmp	$
    .f1:
	mov	cx, (80000h/512)	; 1024 sectors for free space 10000h..8FFFFh
	call	loadfile
	ret

; ----------------
; returns next file cluster or 0ffffh in ax if EOF
; IN: ax - 1st cluster of a file
; OUT: ax - next file cluster, or 0ffffh if EOF

getnextcluster:
	push	si
	push	ds
	push	07e0h
	pop	ds
	mov	si, ax
	sub	si, 2
	lodsw
	pop	ds
	pop	si
	ret

; ----------------
; Load file into memory
; IN: ax - 1st cluster
;     bx - where to load (seg)
;     cx - # of secs - 1 to read; 1 - 1 sect, 0 - 64k sect.

loadfile:
	push	es
	push	cx
	mov	es, bx
	xor	bx, bx
	movzx	bp, [secpcl]
.readf: push	ax
	mov	dx, bp
	sub	ax, 2
	mul	dx
	add	eax, dword [diskdata]	; logical disk file data start + (cluster - 2) * sectors per cluster
	call	readsect
	pop	ax
	call	getnextcluster

   .c1: cmp	ax, 0fff8h
	jae	.exit
	loop	.readf
 .exit: pop	cx
	pop	es
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
	mov	byte[.cond], 75h	; jz = 45h
 .find: push	cx
	mov	cx, 4096/32		; - max # of files
	mov	si, 9000h
 .scan:
	pusha
	mov	cx, 0bh
	repe	cmpsb
	popa

	je	.found
 .c1:	add	si, 20h 		; go to the next entry
	cmp	byte[si], 0		; last dir entry
	je	.notfnd
	loop	.scan
 .notfnd:
	mov	ax, 0ffffh
	jmp	.exit

 .found:
	test	byte[si+0bh], 10h	; subdirectory bit
 .cond: jz	.c1			; condition
	mov	ax, [si+1ah]		; 1st cluster of the file
					; ax - 1st cluster of file
 .exit:
	pop	cx
	ret


; ----------------
write:
	pusha
    .nextb:
	lodsb
	or	al, al
	jz	.msgend
	mov	ah, 0eh
	mov	bx, 0007h
	int	10h
	jmp	.nextb
    .msgend:
	popa
	ret



; ----------------

diskdata	dw 0, 0


crlf		db 13,10,0

;                   12345678901
d1		db "MGCBEAN    ",0
d2		db "BOOT       ",0
;configfname     db "BOOT    CFG",0
kernelfname	db "KERNEL32   ",0

strerr		db "ERR",0
nofile		db " not found",0


; end of sector:

 times 510+7c00h-$ db 0
	dw    0AA55h  ; boot signature
