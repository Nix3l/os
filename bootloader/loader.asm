.att_syntax
.code16

.org 0x0

.global enter
enter:
    jmp main

# not the most portable way but it works
enable_a20:
    cli # TODO(nix3l): is this necessary?
    push %ax
    mov $0xdd, %al
    out %al, $0x64
    pop %ax
    sti
    ret

# prints a string to the screen in 16bit real mode
# INPUTS:
#   si => pointer to string
print_str16:
	push %si
	push %ax
	push %bx

.print_str16_loop:
	lodsb # load next char in ax
	or %al, %al # if char null
	jz .print_str16_done

	mov $0x0e, %ah # teletype output mode
	mov $9, %bx # page 0, color white
	int $0x10

    jmp .print_str16_loop

.print_str16_done:
	pop %bx
	pop %ax
	pop %si
	ret

boot_failure:
    lea msg_boot_fail, %si
    call print_str16
.boot_failure_hang:
    jmp .boot_failure_hang

# FILE IO
pSectorSize: 		.word 512 # size of sector (in bytes)
pClusterSize: 	    .byte 1   # sectors per cluster (allocation unit)
pReservedSectors: 	.word 1   # number of reserved sectors (only boot sector in this case)
pFATCount: 		    .byte 2   # number of FATs
pRootSize: 		    .word 224 # size of root directory (number of records/entries NOT sectors)
pFATSize: 		    .word 9   # size of each FAT
pSectorsPerTrack: 	.word 18  # sectors per cylinder
pHeadCount: 	    .word 2   # number of heads
pHiddenSectors: 	.int  0   # number of hidden sectors (in this case theres none)
pBootDrive: 	    .byte 0   # holds the drive the boot sector came from

.equ FAT_SEGMENT,  0x02c0
.equ FAT_OFFSET,   0x0000

.equ ROOT_SEGMENT, 0x0dad
.equ ROOT_OFFSET,  0x0000

.equ KERNEL_TEMP_SEGMENT, 0x0000
.equ KERNEL_TEMP_OFFSET,  0x3000

.equ KERNEL_TARGET, 0x100000

root_size:  .word 0 # size of root in sectors
root_start: .word 0 # sector of start of root dir
root_end:   .word 0 # sector after end of root dir

kernel_rmode_base: .long KERNEL_TEMP_SEGMENT * 16 + KERNEL_TEMP_OFFSET
kernel_pmode_base: .long KERNEL_TARGET

# NOTE(nix3l): this is almost identical to the boot.asm file io
# so i wont be adding explanations to how this works. just check that file.

# INPUTS:
#   ax => LBA sector
# OUTPUTS:
#   chs_cylinder => cylinder
#   chs_head => head
#   chs_sector => sector 
lba_to_chs:
    push %ax
    push %bx
    push %cx
    push %dx

    xor %dx, %dx
    mov pSectorsPerTrack, %bx
    div %bx # ax = LBA / sectors per track
            # dx = remainder

    inc %dl
    mov %dl, chs_sector # remainder + 1 = sector

    xor %dx, %dx
    mov pHeadCount, %bx
    div %bx # ax = (LBA / sectors per track) / number of heads
            # dx = remainder

    mov %dl, chs_head
    mov %al, chs_cylinder

    pop %dx
    pop %cx
    pop %bx
    pop %ax
    ret

# INPUTS:
#   ax => cluster
# OUTPUTS:
#   ax => sector LBA
get_cluster_lba:
    push %bx
    sub $2, %ax
    xor %bx, %bx
    mov pClusterSize, %bl
    mul %bx
    pop %bx
    add root_end, %ax
    ret

reset_disk:
    push %dx
    push %ax
    mov pBootDrive, %dl
	xor %ax, %ax
    int $0x13
    jc boot_failure
    pop %ax
    pop %dx
    ret

# INPUTS:
#   ax => sector LBA to read
#   cx => number of sectors to read
#   es:bx => memory address to load the memory into
# OUTPUTS:
#   es:bx => the start of the data read 
read_sectors:
.sector_loop:
    push %di
    mov $3, %di # allow 3 retries before failure
    push %ax
    push %cx
    push %dx

    call lba_to_chs

    mov $0x0201, %ax # read function, read one sector
    mov chs_cylinder, %ch # set cylinder
    mov chs_head, %dh # set head
    mov chs_sector, %cl # set sector to read
    mov pBootDrive, %dl # set the drive

.read_retry:
    stc # set the carry bit
    int $0x13
    jnc .sector_done # if the carry bit is cleared, read success

    call reset_disk
    dec %di
    test %di, %di
    jnz .read_retry # retry 3 times before failing

.read_fail:
    jmp boot_failure

.sector_done:
    pop %dx
    pop %cx
    pop %ax
    inc %ax # move to the next sector's LBA
    pop %di
    add pSectorSize, %bx # advance the memory pointer by 1 sector
    loop .sector_loop
    ret

# INPUTS:
#   ax => cluster number
#   es:bx => memory location to read to
# OUTPUTS:
#   es:bx => cluster sector data
load_cluster:
    push %ax
    push %bx
    push %cx

    call get_cluster_lba

    xor %cx, %cx
    mov pClusterSize, %cl
    call read_sectors

    pop %cx
    pop %bx
    pop %ax
    ret

load_root_directory:
    push %ax
    push %bx
    push %cx
    push %dx
    push %es

    # get the root directory size in sectors in cx
    xor %ax, %ax
    xor %dx, %dx
    mov pRootSize, %ax
    mov $32, %bx # 32 bytes per entry
    mul %bx # 32 * [root size] entries
    mov pSectorSize, %bx
    div %bx # (32 * [root size] entries) / [sector size]
    mov %ax, %cx # put result in cx
    mov %cx, root_size

    # get the root directory location in ax
    xor %ax, %ax
    mov pFATCount, %al
    mov pFATSize, %bx
    mul %bx # FAT size * FAT

    add pReservedSectors, %ax # + reserved sectors (bootloader)

    mov %ax, %bx
    mov %bx, root_start
    add %cx, %bx
    mov %bx, root_end

    push $ROOT_SEGMENT
    pop %es
    mov $ROOT_OFFSET, %bx

    call read_sectors

    pop %es
    pop %dx
    pop %cx
    pop %bx
    pop %ax
    ret
    
load_fats:
    push %ax
    push %bx
    push %cx
    push %es

    mov pReservedSectors, %ax
    mov pFATSize, %cx
    push $FAT_SEGMENT
    pop %es
    mov $FAT_OFFSET, %bx

    call read_sectors

    pop %es
    pop %cx
    pop %bx
    pop %ax
    ret

# INPUTS:
#   ds:si => filename
# OUTPUTS:
#   ax => first cluster number
find_file:
    push %cx
    push %di
    push %es

    mov pRootSize, %cx # if we reach 0 entries, not found

    push $ROOT_SEGMENT
    pop %es

    mov $ROOT_OFFSET, %di
.next_entry:
    push %cx
    mov $11, %cx # filenames are all exactly 11 chars long

    push %si
    push %di
    rep cmpsb # check filename
    pop %di
    pop %si

    jz .file_found
    pop %cx
    add $32, %di # move to the next entry
                 # each entry is 32 bytes, so just move the pointer by 32 bytes
    loop .next_entry
    jmp boot_failure # if stage 2 was not found, boot has failed

.file_found:
    mov %es:26(%di), %ax

    pop %cx
    pop %es
    pop %di
    pop %cx
    ret

# INPUTS:
#   ax => starting cluster number
#   es:bx => address to read to
# OUTPUTS:
#   cx => size in sectors
load_file:
    push %ax
    push %dx

    mov %ax, curr_cluster # store the index of the first cluster
    xor %cx, %cx

# read the cluster sectors into memory
.next_cluster:
    mov curr_cluster, %ax
    call load_cluster

    push %bx
    push %es

    inc %cx
    push %cx

    mov %ax, %cx
    mov %ax, %dx
    shr $1, %dx # divide by 2 (shift right)
    add %dx, %cx # cx = offset from fat to the cluster number

    push $FAT_SEGMENT
    pop %es

    mov $FAT_OFFSET, %bx
    add %cx, %bx

    # next cluster in dx
    # gotta load each byte separately though i guess
    # TODO(nix3l): shouldnt these be the other way around?
    mov %es:(%bx), %dl
    mov %es:1(%bx), %dh

    # what using FAT12 does
    # have to mask the number, because we load 16 bits
    # but only use the upper/lower 12 bits
    test $0x0001, %ax
    jnz .odd_cluster

.even_cluster:
    and $0x0fff, %dx
    jmp .load_cluster
.odd_cluster:
    shr $4, %dx

.load_cluster:
    pop %cx
    pop %es
    pop %bx

    mov %dx, curr_cluster
    cmp $0x0ff0, %dx

    jge .finished_loading

    # TODO(nix3l): technically this should be pSectorSize * pClusterSize
    # but every cluster is only 1 sector already and that is never changing so who cares
    add pSectorSize, %bx
    jmp .next_cluster

.finished_loading:
    lea msg_finish_loading, %si
    call print_str16

    pop %dx
    pop %ax
    ret

chs_cylinder: .byte 0
chs_head:     .byte 0
chs_sector:   .byte 0

curr_cluster:    .word 0
file_data_start: .word 0

msg_greet: .asciz "entered second stage\r\n"
msg_boot_fail: .asciz "--------------------\r\n!!! BOOT FAILURE !!!\r\n--------------------\r\n"
msg_finish_loading: .asciz "loaded kernel\r\n"

kernel_filename: .ascii "KERNEL  BIN"
kernel_size: .word 0 # size in sectors

main:
    cli
    mov %cs, %ax
    mov %ax, %ds

    lgdt gdt_pointer
    call enable_a20
    sti

    # change the vga mode
    mov $0x0003, %ax
    int $0x10

    lea msg_greet, %si
    call print_str16

    call load_root_directory
    call load_fats

    lea kernel_filename, %si
    call find_file

    push $KERNEL_TEMP_SEGMENT
    pop %es
    mov $KERNEL_TEMP_OFFSET, %bx
    call load_file
    mov %cx, kernel_size

prepare_32pm:
    # enter 32-bit protected mode
    # we want interrupts off for this or the processor might triple fault
    cli

    # set the first bit in cr0,
    # which informs the cpu that we are going to protected mode
    mov %cr0, %eax
    or $1, %eax
    mov %eax, %cr0

    # far jump into 32bit protected mode
    # this clears the prefetch queue and sets cs to the code descriptor
    ljmp $0x0008, $enter_pm

# GDT
# each descriptor is exactly 8 bytes in size (one quad word)

# NOTE(nix3l): https://wiki.osdev.org/Global_Descriptor_Table
# ngl i barely understand most of this stuff, its a bunch of standards and stuff
# read the link ^^. might help i guess, but all i know is that this kind of segments the memory into
# parts that can either be used as data or as code for execution. protected mode stuff.
# explanation of the layout and usage of the segment descriptors is also in the given link.

start_of_gdt:
gdt_null_descriptor:
# null descriptor
# has to be all 0's
.quad 0

# NOTE(nix3l): since this program has org 0, and is loaded at physical address 0x0500,
# we have to change the base address of the gdt so that it jumps to the correct address
# this feels like a bit of a hacky fix, but im not exactly sure if i can do anything to fix it without changing org 0x0
# we have to however keep the data descriptor base address at 0x0
# and changing org 0x0 will make the file bigger afaik, which i would like to avoid
# see https://stackoverflow.com/questions/9137947/assembler-jump-in-protected-mode-with-gdt?rq=4

gdt_code_descriptor:
# code descriptor
.word 0xffff # limit low
.word 0x0500 # base low
.byte 0 # base middle
.byte 0b10011010 # access
.byte 0b11001111 # granularity
.byte 0 # base high

gdt_data_descriptor:
# data descriptor
.word 0xffff # limit low
.word 0x0000 # base low
.byte 0 # base middle
.byte 0b10010010 # access
.byte 0b11001111 # granularity
.byte 0 # base high
end_of_gdt:

gdt_pointer:
    .word end_of_gdt - start_of_gdt - 1
    # took me a while to figure this out
    # have to change to linear address from segment:offset
    # we know this is loaded at 0x0500 so just add that and we are fine
    .long 0x500 + start_of_gdt

# FROM HERE ON CODE IS IN 32-bit PROTECTED MODE!!!
.code32

.equ VIDEOMEM,      0xb8000
.equ SCREEN_WIDTH,  80
.equ SCREEN_HEIGHT, 25

.equ COL_BLACK,     0x00
.equ COL_BLUE,      0x01
.equ COL_GREEN,     0x02
.equ COL_CYAN,      0x03
.equ COL_RED,       0x04
.equ COL_MAGENTA,   0x05
.equ COL_BROWN,     0x06
.equ COL_LGRAY,     0x07
.equ COL_DGRAY,     0x08
.equ COL_LBLUE,     0x09
.equ COL_LGREEN,    0x0a
.equ COL_LCYAN,     0x0b
.equ COL_LRED,      0x0c
.equ COL_LMAGENTA,  0x0d
.equ COL_LBROWN,    0x0e
.equ COL_WHITE,     0x0f

cursor_x: .word 0
cursor_y: .word 0
background_col: .byte 0

msg_greet32: .asciz "handing over control to the kernel"

# gets the offset to the screen cursor according to cursor_x and cursor_y
# offset = x + y * screen_width
# NOTE(nix3l): theres nothing stopping this from going beyond video memory
# if cursor_x/y is past video memory, so be careful
# OUTPUTS:
#   eax => cursor offset
get_cursor_offset:
    push %ebx
    xor %eax, %eax
    xor %ebx, %ebx

    mov $SCREEN_WIDTH, %ax
    mov cursor_y, %bx
    mul %ebx

    mov cursor_x, %bx
    add %ebx, %eax

    mov $2, %bx
    mul %ebx

    pop %ebx
    ret

# updates the cursor position on the hardware controller 
# INPUTS:
#   cursor_x/y => cursor position
update_hardware_cursor: # FIXME
    push %ax
    push %bx
    push %dx

    call get_cursor_offset
    inc %ax
    mov %ax, %bx
    xor %ax, %ax

    mov $0x03d4, %dx
    mov $0x0f, %al # cursor position (low byte)
    out %al, %dx

    mov $0x03d5, %dx
    mov %bl, %al
    out %al, %dx # data register

    mov $0x03d4, %dx
    mov $0x0e, %al # cursor position (high byte)
    out %al, %dx

    mov $0x03d5, %dx
    mov %bh, %al
    out %al, %dx # data register

    pop %dx
    pop %bx
    pop %ax
    ret

# clears the entire screen to black
clear_screen:
    push %eax # TODO(nix3l): shouldnt this be ecx?
    push %ecx
    push %edi

    mov $0, cursor_x
    mov $0, cursor_y
    call update_hardware_cursor

    # NOTE(nix3l): this should be SCREEN_WIDTH * SCREEN_HEIGHT
    # but im too lazy so i just hard coded it
    mov $2000, %ecx

    mov $VIDEOMEM, %edi
.clear_screen_loop:
    mov $' ', (%edi)
    mov $0x0000, 1(%edi)
    add $2, %edi
    loop .clear_screen_loop

    pop %edi
    pop %ecx
    pop %eax
    ret

# moves the cursor to the right by 1 character
# if it hits the edge of the screen, it loops back around
increment_cursor:
    push %eax
    push %ebx

    xor %eax, %eax
    xor %ebx, %ebx

    mov cursor_x, %ax
    mov cursor_y, %bx

    inc %ax
    cmp $SCREEN_WIDTH, %ax
    jl .increment_cursor_finish

    # at the right edge of the screen, go to next line
    xor %ax, %ax

    inc %bx
    cmp $SCREEN_HEIGHT, %bx
    jl .increment_cursor_finish

    # at bottom left corner, loop back to top left
    xor %eax, %eax
    xor %ebx, %ebx

.increment_cursor_finish:
    mov %ax, cursor_x
    mov %bx, cursor_y
    call update_hardware_cursor

    pop %ebx
    pop %eax
    ret

# prints a character to the screen at the current cursor_x/y
# INPUTS:
#   cursor_x/y => cursor position
#   eax => character to print
#   ebx => text color (see above definitions)
print_ch32:
    push %ebx
    push %edx
    push %edi

    mov $VIDEOMEM, %edi

    push %eax
    call get_cursor_offset
    add %eax, %edi
    pop %eax

    mov %eax, (%edi)  # character byte
    mov %ebx, 1(%edi) # attribute byte

    pop %edi
    pop %edx
    pop %ebx
    ret

# prints a string to the screen starting at the cursor_x/y
# INPUTS:
#   cursor_x/y => cursor position
#   esi => pointer to string to print
#   ebx => color
print_str32:
    push %esi
    push %eax

    xor %eax, %eax

.print_str32_loop:
    # TODO(nix3l): not sure if this is the best idea, but ok
    # probably shouldnt just do this from the code descriptor,
    # but since its a variable i guess theres nothing i can do really??
    mov %cs:(%esi), %al
    cmp $0, %al
    je .print_str32_done
    call print_ch32
    call increment_cursor
    inc %esi
    jmp .print_str32_loop

.print_str32_done:
    pop %eax
    pop %esi
    ret

enter_pm:
    # put the data descriptor into the data segments
    mov $0x0010, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov %ax, %fs
    mov %ax, %gs
    # stack now starts at 0x90000
    mov $0x90000, %esp

    call clear_screen

    # NOTE(nix3l): for some reason if you set cursor_y before cursor_x weird stuff happens
    # im not bothered to fix it honestly

    # move the kernel over to the address we want
    xor %eax, %eax
    xor %ebx, %ebx

    mov %cs:kernel_size, %ax
    mov %cs:pSectorSize, %bx
    mul %bx

    mov $4, %bx # we move 4 bytes at a time, so divide by 4
    div %bx

    cld
    mov %cs:kernel_rmode_base, %esi
    mov %cs:kernel_pmode_base, %edi
    mov %eax, %ecx
    rep movsd

    mov $COL_CYAN, %ebx
    lea msg_greet32, %esi
    call print_str32

hang:
    jmp hang
