.att_syntax
.code16

.text
.org 0x0

.global enter
enter:
    jmp main
    nop

# https://osdev.wiki/wiki/FAT#BPB_(BIOS_Parameter_Block):
# https://jdebp.uk/FGA/bios-parameter-block.html
# https://averstak.tripod.com/fatdox/bootsec.htm [ <-- this one is the easiest to decipher ]
# https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
# in this case the FAT12 filesystem is used
boot_parameter_block:
    pOEM: 		        .ascii "nix3l   " 	    # OEM string, has to occupy 8 bytes
    pSectorSize: 		.word 512 		        # size of sector (in bytes)
    pClusterSize: 	    .byte 1 		        # sectors per cluster (allocation unit)
    pReservedSectors: 	.word 1 		        # number of reserved sectors (only boot sector in this case)
    pFATCount: 		    .byte 2 		        # number of FATs
    pRootSize: 		    .word 224 		        # size of root directory (number of records/entries NOT sectors)
    pSectorCount: 	    .word 2880              # number of sectors in the volume
    pMedia: 		    .byte 0xf0              # media descriptor byte
    pFATSize: 		    .word 9                 # size of each FAT
    pSectorsPerTrack: 	.word 18                # sectors per cylinder
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

# gets the cluster sector LBA
# the formula is LBA = (cluster - 2) * sectors per cluster
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
    add data_start, %ax
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

# called whenever we fail to find the second stage
boot_failure:
    lea msg_boot_fail, %si
    call print_str
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

    # finished reading
    # lea msg_read_finish, %si
    # call print_str
    ret

# loads a cluster into memory at es:bx
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

# loads the second stage from the disk
# OUTPUTS:
#   bx => address to the start of the second stage in memory
load_second_stage:
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

    add pReservedSectors, %ax # + reserved sectors (bootloader)

    mov %ax, %bx
    add %cx, %bx
    mov %bx, data_start

    mov $0x0200, %bx
    call read_sectors

    mov pRootSize, %cx # if we reach 0 entries, not found
    mov $0x0200, %di # start at 0x0200 in memory
.next_entry:
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
    loop .next_entry
    jmp boot_failure # if stage 2 was not found, boot has failed

.stage2_found:
    mov 26(%di), %ax
    mov %ax, cluster # store the index of the first cluster

    # read the FAT into memory
    mov pFATSize, %cx # get size in cx
    # get location of FAT in ax
    # both tables are located immedately after all the reserved sectors
    # so we can start reading from there
    mov pReservedSectors, %ax

    mov $0x0200, %bx # read it to 0x0200
    call read_sectors

    # read the cluster sectors into memory
    # reading to address 0x0000 segment 0x0050
    mov $0x0000, %bx
.next_cluster:
    mov $0x0050, %ax
    mov %ax, %es
    mov cluster, %ax
    call load_cluster
    push %bx
    mov %ax, %cx
    mov %ax, %dx
    shr $1, %dx # divide by 2 (shift right)
    add %dx, %cx # cx = offset from 0x0200 to the cluster number

    push %ax
    mov $0x0000, %ax
    mov %ax, %es
    pop %ax # TODO(nix3l): this is stupid
    # next cluster in dx
    mov $0x0200, %bx
    add %cx, %bx
    # gotta load each byte separately though i guess
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
    pop %bx

    mov %dx, cluster
    cmp $0x0ff0, %dx

    jge .finished_loading

    # TODO(nix3l): technically this should be pSectorSize * pClusterSize
    # but every cluster is only 1 sector already and that is never changing so who cares
    add pSectorSize, %bx
    jmp .next_cluster

.finished_loading:
    lea msg_greet, %si
    call print_str

    # hand over control to stage 2
    push $0x0050
    push $0x0000
    retf # TODO(nix3l): ???

main:
    # ensure that interrupts dont mess up our sector definitions
    # and set up the stack
    cli
    mov %dl, pBootDrive # store our boot drive
    mov %cs, %ax #
    mov %ax, %ds #
    mov %ax, %es # cant set es/ds directly, have to do it using ax
    mov %ax, %ss # sets all these to 0x0, because we cant trust the BIOS
    mov $0xffff, %sp # set the stack
                     # TODO(nix3l): ???
    sti

    # change the vga mode
    mov $0x0003, %ax
    int $0x10

	lea msg_greet, %si
	call print_str

    call reset_disk
    jmp load_second_stage

hang:
	jmp hang

chs_cylinder: .byte 0
chs_head: .byte 0
chs_sector: .byte 0

data_start: .word 0
cluster: .word 0

stage2_filename: .ascii "LOADER  BIN"

msg_greet: .asciz "boot start\r\n"
msg_boot_fail: .asciz "failure\r\n"

.org 510
.word 0xaa55 # magic word
