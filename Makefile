CC := i686-elf-gcc
LD := i686-elf-ld
ASM := i686-elf-as
OBJCOPY := i686-elf-objcopy

LD_SCRIPT := linker.ld

CC_FLAGS := -nostdlib -ffreestanding -T ${LD_SCRIPT} -fno-exceptions -mno-red-zone -Wall -Wextra -Werror -m32

QEMU := qemu-system-i386
VM_FLAGS := -cpu pentium3

BUILD_DIR := build

all: run clean

dirty: clean run

debug: clean bochs

${BUILD_DIR}/boot.o: bootloader/boot.asm
	${ASM} $^ -o ${BUILD_DIR}/boot.o

${BUILD_DIR}/boot.out: ${BUILD_DIR}/boot.o
	${LD} -T ${LD_SCRIPT} $^ -o ${BUILD_DIR}/boot.out

#${BUILD_DIR}/out.bin: ${BUILD_DIR}/boot.o
#	${CC} ${CCFLAGS} $^ -o $@

${BUILD_DIR}/boot.bin: ${BUILD_DIR}/boot.out
	${OBJCOPY} -O binary -j .text $< $@

${BUILD_DIR}/os.img: ${BUILD_DIR}/boot.bin
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F 12 -n "VOLUME" $@
	dd if=$< of=$@ conv=notrunc

run: ${BUILD_DIR}/os.img
	${QEMU} ${VM_FLAGS} -fda $<

bochs: ${BUILD_DIR}/os.img
	bochs -q -f bochs_config -debugger

clean:
	rm -f ${BUILD_DIR}/*.o ${BUILD_DIR}/*.bin ${BUILD_DIR}/*.out
