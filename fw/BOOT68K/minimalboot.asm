; Minimig bootloader - Copyright 2008, 2009 by Jakub Bednarski
;
; This file is part of Minimig
;
; Minimig is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 3 of the License, or
; (at your option) any later version.
;
; Minimig is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;
;
; 2008-08-04	- code clean up
; 2008-08-17	- first complete version
; 2009-02-14	- added memory clear command
; 2009-09-11	- changed header signature and updated version number
;
;
;
; how to build:
; 1. assemble using ASM-One and save executable object
; 2. convert to binary form using reloc from WHDLoad
; 3. generate partial Verilog source using bin2vrlg

;------------------------------------------------------------------------------
; global register usage:
; D2 - X position of text cursor (0-79)
; D3 - Y position of text cursor (0-24)
; A3 - text cursor framebuffer pointer
; A6 - $dff000 custom chip base

;------------------------------------------------------------------------------

VPOSR   equ $04
INTREQR equ $1E
DSKPTH  equ $20
DSKLEN  equ $24
LISAID  equ $7C
COP1LCH equ $80
COP1LCL equ $82
COPJMP1 equ $88
DIWSTRT equ $8E
DIWSTOP equ $90
DDFSTRT equ $92
DDFSTOP equ $94
DMACON  equ $96
INTENA  equ $9A
INTREQ  equ $9C
ADKCON  equ $9E
BPLCON0 equ $100
BPLCON1 equ $102
BPLCON2 equ $104
BPL1MOD equ $108
BPL2MOD equ $10A
COLOR0  equ $180
COLOR1  equ $182

; memory allocation map
;
; 000000 +----------------+
;        ; fpga boot rom  ; 2 KB
; 000800 +----------------+
;        ;                ;
;        :                :
;        ;                ;
; 004000 +----------------+
;        ;                ;
;        :                :
;        : disk buffer    : 16 KB
;        :                :
;        ;                ;
; 008000 +----------------+
;        ;                ;
;        :                :
;        : display buffer : ~16 KB
;        :                :
;        ;                ;
; 00C100 +----------------+
;        ; copper list    ;
;        :                :
;        :                : ~16 KB
;        :                :
;        ; stack          ;
; 010000 +----------------+
;
; the last text line in the display buffer is not visible and always empty
; it's used for clearing the last visible text line while srolling up

plane0	    equ $08000
copper	    equ plane0+640/8*208
disk_buffer equ plane0-$4000

;------------------------------------------------------------------------------
	org	0
	dc.l	$00010000	; initial SSP
	dc.l	Start		; initial PC

;------------------------------------------------------------------------------
;fpga_version:
;	dc.b	"AA000000"	; FPGA core version - 8 ASCII characters
;	dc.b	"09091100"	; FPGA core version - 8 ASCII characters

;------------------------------------------------------------------------------
Start:
;------------------------------------------------------------------------------

	lea	$dff000,A6	; custom base

	move.w	#$9000,BPLCON0(A6)	;hires, 1 bitplane
	move.w	#$0000,BPLCON1(A6)	;horizontal scroll = 0
	move.w	#$0000,BPLCON2(A6)
	move.w	#$0000,BPL1MOD(A6)	;modulo = 0
	move.w	#$0000,BPL2MOD(A6)	;modulo = 0

	move.w	#$003C,DDFSTRT(A6)
	move.w	#$00D4,DDFSTOP(A6)
	move.w	#$2c81,DIWSTRT(A6)
	move.w	#$f4c1,DIWSTOP(A6)
;colours
	move.w	#$037f,COLOR0(A6)
	move.w	#$0fff,COLOR1(A6)

;	lea	CopperList,A0
;	lea	copper,A1
;	moveq	#(CopperListEnd-CopperList)/4-1,D0

;CopperListCopyLoop:
;	move.l	(A0)+,(A1)+
;	dbra	D0,CopperListCopyLoop

	move.l	#CopperList,COP1LCH(A6)
	move.w	D0,COPJMP1(A6)		;restart copper

;	move.w	#%1000001110010000,DMACON(A6) ; DMAEN;BPLEN;COPEN;DSKEN
	move.w	#%1000001000010000,DMACON(A6) ; DSKEN
	move.w	#$7FFF,ADKCON(A6)	;disable word sync

;------------------------------------------------------------------------------

	lea	Start-8,A2
	moveq	#8-1,D7

	;Agnus ID is in VPOSR register

	move.b	#$03,$BFE201	; _led and ovl as outputs
	move.b	#$00,$BFE001	; _led active

	move.b	#$FF,$BFD300	; drive control signals as outputs
	move.b	#$F7,$BFD100	; _sel0 active

wait_for_diskchange:
	btst	#2,$BFE001	; _chng active? (disk present)
	beq	wait_for_diskchange

read_cmd:
	move.w	#12,D0		; read size
	bsr	DiskRead

	move.l	#disk_buffer,A0
	cmp.w	#$AA67,(A0)+
	bne	bad_header

	move.w	(A0)+,D0

	cmp.w	#1,D0		; Text command?
	beq	end_cmd

;-------------------------------
cmd_2:
;-------------------------------

	cmp.w	#2,D0		; memory upload command?
	bne	no_cmd_2

	move.l	(A0)+,A4	; memory base
	move.l	A4,A5
	move.l	(A0)+,D4	; memory size
	move.l	D4,D5

	sub.w	#33,D2
	sub.w	#33,A3

upload_loop:
	;move.l	#$4000,D6
	move.l	D5,D6
	lsr.l	#5,D6
	cmp.l	D4,D6
	blt	_no_lt
	move.l	D4,D6
_no_lt:
	move.w	D6,D0
	bsr	DiskRead

	move.w	D6,D0
	lsr.w	#2,D0
	subq.w	#1,D0
copy_loop:
	move.l	(A0)+,(A4)+
	dbra	D0,copy_loop

	bchg.b	#1,$BFE001	; LED

	sub.l	D6,D4
	bgt	upload_loop

	cmpa.l	#$F80000,A5
	bne	no_256KB

	cmp.l	#$40000,D5
	bne	no_256KB

	movea.l	A5,A4
	adda.l	D5,A4
	moveq	#-1,D5
copy256KB_loop:
	move.l	(A5)+,(A4)+
	dbra	D5,copy256KB_loop

no_256KB:

	bra	end_cmd
no_cmd_2:

;-------------------------------
cmd_3:
;-------------------------------

	cmp.w	#3,D0		; exit bootloader command?
	bne	no_cmd_3

	bset.b	#1,$BFE001	; LED off
	tst.b	$BFC000

end_wait:
	bra.s	end_wait

no_cmd_3:

;-------------------------------
cmd_4:
;-------------------------------

	cmp.w	#4,D0		; memory clear command?
	bne	no_cmd_4

	move.l	(A0)+,A4	; memory base
	move.l	(A0)+,D4	; memory size

	moveq	#0,D0
clear_loop:
	move.l	D0,(A4)+

	subq.l	#4,D4		; decrement loop counter
	bgt	clear_loop

	bra	end_cmd

no_cmd_4:

;-------------------------------
;-------------------------------

	move.w	#$0F00,COLOR0(A6)

infinite_loop:
	bra	infinite_loop

bad_header:
	move.w	#$0F00,COLOR0(A6)
	bra	infinite_loop

end_cmd:

	bra	read_cmd

;------------------------------------------------------------------------------
DiskRead:
;------------------------------------------------------------------------------
; Args:
; 	D0 - read size in bytes
; Results:
; 	A0 - disk buffer
; Scratch:
; 	D0

	move.w	#$0002,INTREQ(A6)	;clear disk block finished irq
	movea.l	#disk_buffer,A0
	move.l	A0,DSKPTH(A6)
	lsr.w	#1,D0
	ori.w	#$8000,D0		;set DMAEN
	move.w	D0,DSKLEN(A6)
	move.w	D0,DSKLEN(A6)		;start disk dma

wait_for_diskdma:
	move.w	INTREQR(A6),D0
	btst	#1,D0			;disk block finished
	beq	wait_for_diskdma

	rts


;------------------------------------------------------------------------------
CopperList:
;------------------------------------------------------------------------------

;bitplane pointers
bplptrs:
	dc.w $ffff,$fffe

;------------------------------------------------------------------------------
CopperListEnd:
;------------------------------------------------------------------------------
