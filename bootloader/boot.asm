.att_syntax
.code16

.text
.org 0x0 # start all addresses at 0x0
         # this is not at 0x7c00 since thats where the bootloader is loaded in memory
         # not its address in the disk file

.global boot_enter 
boot_enter:
    jmp main
    nop

# https://osdev.wiki/wiki/FAT#BPB_(BIOS_Parameter_Block):
# https://jdebp.uk/FGA/bios-parameter-block.html
# https://averstak.tripod.com/fatdox/bootsec.htm [ <-- this one is the easiest to decipher ]
# https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
# in this case the FAT12 filesystem is used
boot_parameter_block:
    pOEM: 		        .ascii "nix3l   " 	    # OEM string, has to occupy 8 bytes
    pSectorSize: 		.word 0x512 		    # size of sector (in bytes)
    pClusterSize: 	    .byte 1 		        # sectors per cluster (allocation unit)
    pReservedSectors: 	.word 1 		        # number of reserved sectors (only boot sector in this case)
    pFATCount: 		    .byte 2 		        # number of FATs
    pRootSize: 		    .word 224 		        # size of root directory (number of records/entries NOT sectors)
    pSectorCount: 	    .word 2880              # number of sectors in the volume
    pMedia: 		    .byte 0xf0              # media descriptor byte
    pFATSize: 		    .word 9                 # size of each FAT
    pSectorsPerTrack: 	.word 18                # sectors per track
    pHeadCount: 	    .word 2                 # number of heads
    pHiddenSectors: 	.int  0                 # number of hidden sectors (in this case theres none)
    pSectors32: 	    .int  0                 # number of sectors over 32Mb (large sectors)
    pBootDrive: 	    .byte 0                 # holds the drive the boot sector came from
			 		    .byte 0                 # reserved. not sure why. it just is.
    ### EBPB ###
    pBootSign: 		    .byte 0x29 		        # signal start of EBPB
    pVolumeID: 		    .ascii "seri" 		    # volume serial number, doesnt really matter
    pVolumeLabel: 	    .ascii "VOLUME     " 	# volume label
    pFSType: 		    .ascii "FAT12   " 	    # file system type

# NOTE(nix3l): essentially we have to:
#   => reset the floppy disk system TODO(nix3l): ???                    [DONE]
#   => find the kernel in the root directory of the floppy disk         [IN PROGRESS]
#   => read the kernel from disk into memory                            [PENDING]
#   => enable the A20-line                                              [PENDING]
#   => setup the IDT and GDT tables                                     [PENDING]
#   => switch to protected (32-bit) mode                                [PENDING]
#   => clear the cpu prefetch queue                                     [PENDING]
#   => pass control over to the kernel                                  [PENDING]

# converts from LBA (logical block addressing) to CHS (cylinder, head, sector)
# so it can actually be used for read/write operations
#
#   cylinder = (LBA / sectors per track) / number of heads
#       head = (LBA / sectors per track) mod number of heads
#     sector = (LBA mod sectors per track) + 1
#
# INPUTS:
#   ax => LBA sector
# OUTPUTS:
#   ax => cylinder
#   bl => head
#   cx => sector 
lda_to_chs:
    push %dx

    xor %dx, %dx
    mov pSectorsPerTrack, %bx
    div %bx # ax = LBA / sectors per tracl
            # dx = remainder

    inc %dx
    mov %dx, %cx # remainder + 1 = sector

    xor %dx, %dx
    mov pHeadCount, %bx
    div %bx # ax = (LBA / sectors per track) / number of heads
            # dx = remainder

    mov %dl, %bl

    pop %dx
    ret

# prints a string to the console
# INPUTS:
#   si => points to string
print_str:
	push %si
	push %ax
	push %bx

.print_loop:
	lodsb # load next char in ax
	or %al, %al # if char null
	jz .print_done

	mov $0x0e, %ah # teletype output mode
	mov $9, %bx # page 0, color white
	int $0x10

    jmp .print_loop

.print_done:
	pop %bx
	pop %ax
	pop %si
	ret

# called whenever we fail to find the kernel
boot_failure:
    lea msg_boot_fail, %si
    call print_str
    jmp hang

# resets the disk
reset_disk:
    push %dx
    push %ax
    mov pBootDrive, %dl
	xor %ax, %ax
    int $0x13
    pop %ax
    pop %dx
    ret

# reads a sector at the given LBA sector
# retries 3 times before failing
# INPUTS:
#   ax => sector LBA to read
# OUTPUTS:
#   es:bx => the 512 bytes of the read sector
read_sector:
    push %ax
    push %bx
    push %cx
    push %dx
    push %di

    call lda_to_chs

    mov %al, %ch # set cylinder to al
    mov %bl, %dh # set the head to bl
    mov pBootDrive, %dl # set the drive

    pop %bx
    mov %ax, 0x0201 # sets ah to 0x02 and al to 0x01
                    # function 2 (read) and 1 sector to read

    mov $3, %di # allow 3 retries before failure

.read_retry:
    pusha # save all registers to stack, dont know what will happen to them
    stc # set the carry bit

    int $0x13
    jnc .read_done # if the carry bit is cleared, read success

    popa # otherwise, restore all registers
    call reset_disk

    dec %di
    test %di, %di
    jnz .read_retry # retry 3 times before failing

.read_fail:
    lea msg_read_sector_fail, %si
    call print_str
    jmp hang

.read_done:
    popa
    pop %di
    pop %dx
    pop %cx
    pop %ax
    ret

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
# that has a filename matching the kernels file name
# INPUTS:
#   ax => sector LBA
#   cx => root directory size in sectors
find_kernel_file:
.check_sector:
    push %ecx
    push %ax

    xor %bx, %bx
    call read_sector # read the sector into memory [es:bx]

.check_entry:
    mov $11, %ecx # check the first 11 bytes (filename)
    mov %bx, %di # at the address bx
    lea kernel_filename, %si
    repz cmpsb
    je .found_kernel_file # if the filename is equal to the kernels filename

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

.found_kernel_file:
    lea msg_kernel_found, %si
    call print_str
    mov %es:+0x1a(%bx), %ax
    mov %ax, kernel_start # store the memory address in kernel_start
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

    call find_kernel_file

    # TODO(nix3l): read the root directory and find the kernel file
    #              OR i could just assume its the first file in the filesystem

hang:
	jmp hang

root_start_sector: .word 0
root_size: .word 0

kernel_filename: .ascii "kernel.bin"
kernel_start: .word 0

msg_greet: .asciz "HELLO!!!!!!\r\n"
msg_read_sector_fail: .asciz "read sector fail\r\n"
msg_read_fail: .asciz "read fail\r\n"
msg_entry_fail: .asciz "entry fail\r\n"
msg_boot_fail: .asciz "boot failure\r\n"
msg_kernel_found: .asciz "found kernel\r\n"

.org 510
.word 0xaa55 # magic word
