.att_syntax
.code16

.org 0x0

.global enter
enter:
    jmp main

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

msg_greet: .asciz "second stage loaded\r\n"

main:
    cli
    mov %cs, %ax
    mov %ax, %ds
    sti

    # change the vga mode
    mov $0x0003, %ax
    int $0x10

    lea msg_greet, %si
    call print_str16

    # TODO(nix3l): load the kernel

prepare_32pm:
    # enter 32-bit protected mode
    # we want interrupts off for this or the processor might triple fault
    cli

    lgdt gdt_pointer

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
    .long 0x0500 + start_of_gdt

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

cursor_x: .byte 0
cursor_y: .byte 0
background_col: .byte 0

msg_greet32: .asciz "ayo we printing strings now? in 32 bit pm??? insane"

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

    mov $SCREEN_WIDTH, %al
    mov cursor_y, %bl
    mul %ebx

    mov cursor_x, %bl
    add %ebx, %eax

    mov $2, %bl
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
    push %eax
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
    pop %eax
    ret

# moves the cursor to the right by 1 character
# if it hits the edge of the screen, it loops back around
increment_cursor:
    push %eax
    push %ebx

    xor %eax, %eax
    xor %ebx, %ebx

    mov cursor_x, %al
    mov cursor_y, %bl

    inc %al
    cmp $SCREEN_WIDTH, %al
    jl .increment_cursor_finish

    # at the right edge of the screen, go to next line
    xor %al, %al

    inc %bl
    cmp $SCREEN_HEIGHT, %bl
    jl .increment_cursor_finish

    # at bottom left corner, loop back to top left
    xor %eax, %eax
    xor %ebx, %ebx

.increment_cursor_finish:
    mov %al, cursor_x
    mov %bl, cursor_y
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

# not the most portable way but it works
# TODO(nix3l): if needed, change to something more portable
enable_a20:
    mov $0xdd, %al
    out %al, $0x64
    ret

enter_pm:
    # put the data descriptor into the data segments
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    # TODO(nix3l): fs/gs?
    # stack now starts at 0x90000
    mov $0x90000, %esp

    call enable_a20

    xor %eax, %eax
    xor %ebx, %ebx
    xor %ecx, %ecx
    xor %edx, %edx
    xor %edi, %edi
    xor %esi, %esi

    call clear_screen

    # NOTE(nix3l): for some reason if you set cursor_y before cursor_x weird stuff happens
    # im not bothered to fix it honestly

    mov $COL_CYAN, %ebx
    lea msg_greet32, %esi
    call print_str32

hang:
    jmp hang
