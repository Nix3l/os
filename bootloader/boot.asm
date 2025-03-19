.att_syntax
.code16

.section boot
.text
.org 0x0 # start all addresses at 0x0 TODO(nix3l): shouldnt this be 0x7c00?

.global boot_enter 
boot_enter:
    jmp main
    nop
# https://osdev.wiki/wiki/FAT#BPB_(BIOS_Parameter_Block):
# https://jdebp.uk/FGA/bios-parameter-block.html
# https://averstak.tripod.com/fatdox/bootsec.htm [ <-- this one is the easiest do decipher ]
# https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
# in this case the FAT12 filesystem is used
boot_parameter_block:
    pOEM: 		        .ascii "os      " 	# OEM string, has to occupy 8 bytes
    pSectorSize: 		.word 0x512 		# size of sector (in bytes)
    pClusterSize: 	    .byte 1 		    # sectors per cluster (allocation unit)
    pReservedSectors: 	.word 1 		    # number of reserved sectors
    pFATCount: 		    .byte 2 		    # number of FATs
    pRootSize: 		    .word 224 		    # size of root directory (number of records/entries)
    pSectorCount: 	    .word 2880 		    # number of sectors in the volume
    pMedia: 		    .byte 0xF0 		    # media descriptor byte
    pFATSize: 		    .word 9 		    # size of each FAT
    pSectorsPerTack: 	.word 18 		    # sectors per track
    pHeadCount: 	    .word 2 		    # number of heads
    pHiddenSectors: 	.int  0 			# number of hidden sectors (in this case theres none)
    pSectors32: 	    .int  0 			# number of sectors over 32Mb (large sectors)
    pBootDrive: 	    .byte 0 		    # holds the drive the boot sector came from
			 		    .byte 0 		    # reserved. not sure why. it just is.
    ### EBPB ###
    pBootSign: 		    .byte 0x29 		        # signal start of EBPB
    pVolumeID: 		    .ascii "seri" 		    # volume serial number, doesnt really matter
    pVolumeLabel: 	    .ascii "VOLUME     " 	# volume label
    pFSType: 		    .ascii "FAT12   " 	    # file system type

# NOTE(nix3l): essentially we have to:
#   => reset the floppy disk system TODO(nix3l): ???
#   => find the kernel in the root directory of the floppy disk
#   => read the kernel from disk into memory
#   => enable the A20-line
#   => setup the IDT and GDT tables
#   => switch to protected (32-bit) mode
#   => clear the cpu prefetch queue
#   => pass control over to the kernel

# ds:si => points to string
print_str:
	push %si
	push %ax
	push %bx

.loop:
	lodsb # load next char in ax
	or %al, %al # if char null
	jz .done

	mov $0x0E, %ah
	mov $0, %bh
	int $0x10

.done:
	pop %bx
	pop %ax
	pop %si
	ret

main:
    # ensure that interrupts dont mess up our sector definitions
    cli
    mov %dl, pBootDrive # store our boot drive
    mov %cs, %ax #
    mov %ax, %ds #
    mov %ax, %es # cant set es/ds directly, have to do it using ax
    mov %ax, %ss # sets all these to 0x0, because we cant trust the BIOS
    mov $0x07c00, %sp # set the stack to go down from 0x07c00 (where the boot sector is loaded)
    sti

	mov msg_greet, %si
	call print_str

    # resetting the disk system
    mov pBootDrive, %dl
	xor %ax, %ax
    int $0x13

	# TODO(nix3l): find out how to read the filesystem
	# read the kernel from disk into memory
halt:
	jmp halt

msg_greet: .asciz "HELLO!!!!!!\n"

.org 510
.word 0xaa55 # magic word
