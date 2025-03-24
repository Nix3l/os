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

.include "bootloader/common.asm"

load_second_stage:
    # TODO(nix3l)
    jmp hang

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
    call load_second_stage

    # TODO(nix3l): read the root directory and find the second stage

hang:
	jmp hang

msg_greet: .asciz "HELLO IN THE FIRST STAGE!!!!!!\r\n"

.org 510
.word 0xaa55 # magic word
