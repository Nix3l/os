.att_syntax
.code16

.org 0x0

.global enter
enter:
    jmp main

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

main:
    cli
    mov %cs, %ax
    mov %ax, %ds
    sti

    # change the vga mode
    mov $0x0003, %ax
    int $0x10

    lea msg_greet, %si
    call print_str

hang:
    jmp hang

msg_greet: .asciz "AYOO!!! WE IN THE SECND STAGE!!!\r\n"
