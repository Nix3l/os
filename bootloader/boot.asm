.att_syntax
.code16

.text
.org 0x0

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
    pSectorsPerTrack: 	.word 18                # sectors per FAT
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
#   => find the second stage in the root directory of the floppy disk   [DONE]
#   => read the second stage from disk into memory                      [IN PROGRESS]
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
#   chs_cylinder => cylinder
#   chs_head => head
#   chs_sector => sector 
lda_to_chs:
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
    # jmp hang
    int $0x16 # await keypress
    int $0x19 # reboot (warm restart)

# move reading cursor back to the first sector on disk
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

# reads a sector at the given LBA sector
# retries 3 times before failing
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

    call lda_to_chs

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
    lea msg_read_sector_fail, %si
    call print_str
    jmp boot_failure

.sector_done:
    lea msg_read_sector, %si
    call print_str
    pop %dx
    pop %cx
    pop %ax
    inc %ax # move to the next sector's LBA
    pop %di
    add pSectorSize, %bx # advance the memory pointer by 1 sector
    loop .sector_loop

.read_done:
    lea msg_read_finish, %si
    call print_str
    ret

find_second_stage:
    # get the root directory size in sectors in cx
    xor %ax, %ax
    xor %dx, %dx
    mov pRootSize, %ax
    mov $32, %bx # 32 bytes per entry
    mul %bx # 32 * [root size] entries
    mov pSectorSize, %bx
    div %bx # (32 * [root size] entries) / [sector size]
    mov %ax, %cx # put result in cx

    # get the root directory location in ax
    xor %ax, %ax
    mov pFATCount, %al
    mov pFATSize, %bx
    mul %bx # FAT size * FAT
    add pHiddenSectors, %ax # + hidden sectors
    add pReservedSectors, %ax # + reserved sectors (bootloader)
    mov %ax, root_dir_location

    mov $0x0200, %bx # arbitrarily load it at 0x200
    call read_sectors

    mov pRootSize, %cx # if we reach 0 entries, not found
    mov $0x0200, %di # start at 0x0200 in memory
.next_entry: # FIXME
    push %cx
    mov $11, %cx # filenames are all exactly 11 chars long
    lea stage2_filename, %si
    push %di
    rep cmpsb # check filename
    pop %di
    je .stage2_found
    pop %cx
    add $32, %di # move to the next entry
                 # each entry is 32 bytes, so just move the pointer by 32 bytes
    lea msg_check_entry, %si
    call print_str
    loop .next_entry
    jmp boot_failure # if stage 2 was not found, boot has failed

.stage2_found:
    lea msg_stage2_found, %si
    call print_str
    # TODO(nix3l): do something here i guess
    ret

main:
    # ensure that interrupts dont mess up our sector definitions
    # and set up the stack
    cli
    mov %dl, pBootDrive # store our boot drive
    mov %cs, %ax #
    mov %ax, %ds #
    mov %ax, %es # cant set es/ds directly, have to do it using ax
    mov %ax, %ss # sets all these to 0x0, because we cant trust the BIOS
    mov $0xFFFF, %sp # set the stack
                     # TODO(nix3l): ???
    sti

    # change the vga mode
    mov $0x0003, %ax
    int $0x10

	lea msg_greet, %si
	call print_str

    call reset_disk
    call find_second_stage
    # call load_second_stage

hang:
	jmp hang

chs_cylinder: .byte 0
chs_head: .byte 0
chs_sector: .byte 0

root_dir_location: .word 0

stage2_filename: .ascii "STAGE2  BIN"

msg_greet: .asciz "boot start\r\n"
msg_stage2_found: .asciz "found stage 2\r\n"

# TODO(nix3l): remove some of these, wastes space
msg_check_entry: .asciz "next entry...\r\n"
msg_read_sector: .asciz "read sector\r\n"
msg_read_finish: .asciz "read finish\r\n"
msg_boot_fail: .asciz "boot failure. press any key to reboot\r\n"
msg_read_sector_fail: .asciz "read fail\r\n"

.org 510
.word 0xaa55 # magic word
