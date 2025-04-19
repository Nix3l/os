.att_syntax
.code16

# TODO(nix3l): move the IO stuff to a separate file so i dont copy-paste the code like an idiot

.org 0x0

.global enter
enter:
    jmp main

print_str16:
	push %si
	push %ax
	push %bx

.print16_loop:
	lodsb # load next char in ax
	or %al, %al # if char null
	jz .print16_done

	mov $0x0e, %ah # teletype output mode
	mov $9, %bx # page 0, color white
	int $0x10

    jmp .print16_loop

.print16_done:
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
# and changing org 0x0 will make the file bigger afaik, which i would like to avoid

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
.word 0x0500 # base low
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
enter_pm:
    # put the data descriptor into the data segments
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    # stack now starts at 0x90000
    mov $0x90000, %esp

hang:
    jmp hang
