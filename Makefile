CC := i686-elf-gcc
LD := i686-elf-ld
ASM := i686-elf-as

LD_SCRIPT := linker.ld

CC_FLAGS := -nostdlib -ffreestanding -T ${LD_SCRIPT} -fno-exceptions -mno-red-zone -Wall -Wextra -Werror -m32

QEMU := qemu-system-i386
VM_FLAGS := -cpu pentium3

BUILD_DIR := build

all: run clean

${BUILD_DIR}/boot.o: bootloader/boot.asm
	${ASM} $^ -o $@

#${BUILD_DIR}/out.bin: ${BUILD_DIR}/boot.o
#	${CC} ${CCFLAGS} $^ -o $@

${BUILD_DIR}/out.bin: ${BUILD_DIR}/boot.o
	i686-elf-ld -T ${LD_SCRIPT} $^ -o $@

${BUILD_DIR}/os.img: ${BUILD_DIR}/out.bin
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F 12 -n "VOLUME" $@
	dd if=$< of=$@ conv=notrunc
	
run: ${BUILD_DIR}/os.img
	${QEMU} ${VM_FLAGS} -fda $<

clean:
	rm -f ${BUILD_DIR}/*.o ${BUILD_DIR}/*.bin
