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

# move reading cursor back to the first sector on disk
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
#   es:bx => memory address to load the memory into
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

msg_boot_fail: .asciz "boot failure\r\n"
msg_read_sector_fail: .asciz "read sector fail\r\n"
