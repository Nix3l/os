.att_syntax
.code16

.text
.org 0x0 # start all addresses at 0x0
         # this is not at 0x7c00 since thats where the bootloader is loaded in memory
         # not its address in the disk file

second_stage_enter:
    jmp main

.include "bootloader/common.asm"

# gets the position (LBA) of the root directory on disk
# root sector = number of FATs * size of each FAT in sectors +
#               number of reserved sectors
#               number of hidden sectors
# OUTPUTS:
#   ax => root sector LBA
get_root_sector:
    push %bx
    xor %ax, %ax

    mov pFATCount, %al
    mov pFATSize, %bx
    mul %bx # ax = pFATCount * pFATSize

    add pHiddenSectors, %ax # + hidden sectors
    add pReservedSectors, %ax # + reserved sectors
    pop %bx
    ret

# gets the size of the root directory in sectors
# root directory size = (32 * number of entries) / 512
# OUTPUTS:
#   ax => size of the root directory in sectors
get_root_size:
    push %dx
    push %bx

    xor %ax, %ax
    xor %dx, %dx

    mov pRootSize, %ax
    mov $32, %bx
    mul %bx # 32 * root size

    xor %dx, %dx
    mov pSectorSize, %bx
    div %bx # (32 * root size) / 512

    pop %bx
    pop %dx
    ret

# TODO(nix3l): my head hurts what is this

# reads the root directory and looks through all entires for a file
# that has a filename matching the second stage's file name
# INPUTS:
#   ax => sector LBA
#   cx => root directory size in sectors
find_second_stage:
.check_sector:
    push %ecx
    push %ax

    xor %bx, %bx
    call read_sector # read the sector into memory [es:bx]

.check_entry:
    mov $11, %ecx # check the first 11 bytes (filename)
    mov %bx, %di # at the address bx
    lea second_stage_filename, %si
    repz cmpsb
    je .found_second_stage

    add $32, %bx # each entry is 32 bytes, so move up memory by that amount
    cmp %bx, pSectorSize # check if we are done with the current sector
    lea msg_entry_fail, %si
    call print_str
    jne .check_entry # if still in same sector, check next entry

    pop %ax
    inc %ax # check the next sector LBA
    pop %ecx
    lea msg_read_fail, %si
    call print_str
    loopnz .check_sector

    jmp boot_failure # if we were unable to find the kernel fail, boot failed

.found_second_stage:
    lea msg_second_stage_found, %si
    call print_str
    mov %es:+0x1a(%bx), %ax
    mov %ax, second_stage_start # store the memory address
    pop %cx
    pop %bx
    pop %ax
    ret

main:
    # ensure that interrupts dont mess up our sector definitions
    cli
    mov %dl, pBootDrive # store our boot drive
    mov %cs, %ax #
    mov %ax, %ds #
    mov %ax, %es # cant set es/ds directly, have to do it using ax
    mov %ax, %ss # sets all these to 0x0, because we cant trust the BIOS
    mov $0x7c00, %sp # set the stack to go down from 0x7c00 (where the boot sector is loaded)
    sti

    # change the vga mode
    mov $0x3, %ax
    int $0x10

	lea msg_greet, %si
	call print_str

    call reset_disk

    call get_root_sector
    mov %ax, root_start_sector

    call get_root_size
    mov %ax, root_size

    mov root_start_sector, %ax
    mov root_size, %cx

    call find_second_stage

    # TODO(nix3l): read the root directory and find the second stage

hang:
	jmp hang

root_start_sector: .word 0
root_size: .word 0

second_stage_filename: .ascii "STAGE2  BIN"
second_stage_start: .word 0

msg_greet: .asciz "HELLO!!!!!!\r\n"
msg_read_fail: .asciz "read fail\r\n"
msg_entry_fail: .asciz "entry fail\r\n"
msg_second_stage_found: .asciz "found 2nd stage\r\n"
