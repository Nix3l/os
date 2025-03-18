CC := i686-elf-gcc
ASM := i686-elf-as

LD_SCRIPT := linker.ld

QEMU := qemu-system-i386
VM_FLAGS := -cpu pentium3

all: run

boot.o: bootloader/boot.asm
	${ASM} $^ -o $@

out.bin: boot.o
	${CC} ${CCFLAGS} $^ -o $@

run: out.bin
	${QEMU} ${VM_FLAGS} -hda $<

clean:
	rm *.o *.bin
