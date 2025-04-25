CC := i686-elf-gcc
LD := i686-elf-ld
ASM := i686-elf-as
OBJCOPY := i686-elf-objcopy

# CC_FLAGS := -nostdlib -ffreestanding -T ${LD_SCRIPT} -fno-exceptions -mno-red-zone -Wall -Wextra -Werror -m32

QEMU := qemu-system-i386
VM_FLAGS := -cpu pentium3

LD_SCRIPT_DIR := linker
BUILD_DIR := build

all: run clean

dirty: clean run

debug: clean bochs

${BUILD_DIR}/boot.o: bootloader/boot.asm
	${ASM} $^ -o $@

${BUILD_DIR}/boot.out: ${BUILD_DIR}/boot.o
	${LD} -T ${LD_SCRIPT_DIR}/boot.ld $^ -o $@

${BUILD_DIR}/boot.bin: ${BUILD_DIR}/boot.out
	${OBJCOPY} -O binary -j .text $< $@

${BUILD_DIR}/loader.o: bootloader/loader.asm
	${ASM} $^ -o $@

${BUILD_DIR}/loader.out: ${BUILD_DIR}/loader.o
	${LD} -T ${LD_SCRIPT_DIR}/loader.ld $^ -o $@

${BUILD_DIR}/loader.bin: ${BUILD_DIR}/loader.out
	${OBJCOPY} -O binary -j .text $^ $@

${BUILD_DIR}/kernel.bin:
	echo "yes this is totally the kernel guys trust meiuspnnpvdsnjsvdknjdvsknjsvdknjvdsnkjsvdnkjvsnjpkvdsknjvdsnkjdvsnjpvdsnjdvsjpksvdnkpjvdsnkpjdvsnkjdvsnkjdvsnkjpdvsnkjpdvsnjpkdvsnpkjvdsnjpkvdsnpkjvdsnjpkvdsnjpkvdsnjpkvdsjnpkvdsnjpkvdsjnpkvdsjnpkvdsnjpkdvsnjpkdvsjnpvdsnjpdvsjnpkdvsjnpkdvsjnpkdvsnjpkdvsnjdvsnjpkdvsnjpkvdsnjpkdvsnjpkdvsnjkdvsnjpkvdsnjpkvdsnjpkdvsnjkpvdsnjpkdvsnjpkvdsnjpkvdsnjpkdvsnjpkdvsnjpkdvsnjdvsnjpkvdsnjpkdvsjnpdvsnjpkvdsnjpkdvsnjpkvdsnjpkvdsnjpkvdsnjpkvdsnjpkvdsnjpkvdsnjpkdvsnjpkdvsnjpkvdsnjpkdvsnjkpdvsnjvdsnjkpdvnjpkvdsnjdvsnjpkvdsnpkjvdsnpkjdsvnjpkvdsnjpkvdsnjpkdvsnjpkdvsnjpkdsvnjdsvnjpkdvsnjpkdvsjnpkdsvnjpkdvsnjpkdvsjnsdvnjpkdsvnjpkdsvnjpkdsvnjsdnjksdnjpksdvnpdsvnjkjndvsnjdvsnjpkdvsjnpdvsnjsdnpkjsvdnkjsdvnjjdnpkvnjkpvdsnjskpvdnjdsvjnkvdsjndsvnjpdsvnjjndvsjnpkvdspnjsvdnjpkdvsnjpdsvnpjdsvnjndpvsnjpkdvsnjdsvnjkdsvnjkdsnvkjppndksvjnjpkdvsnjpkdsvnjdnsjdsvjnnjdsvnjdpkvsjndvsnjndvsjsvdpknjnvdskjpsdnpsjdknvspjkdnvskdpjnvspkjdnvkpsndvpsjndvspjkndvjspkdnvspkjdnvspkjndvspkjdnvspkndv" > $@

${BUILD_DIR}/disk.img: ${BUILD_DIR}/boot.bin ${BUILD_DIR}/loader.bin ${BUILD_DIR}/kernel.bin
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F12 -n "VOLUME" $@
	mcopy -i $@ ${BUILD_DIR}/loader.bin "::loader.bin"
	mcopy -i $@ ${BUILD_DIR}/kernel.bin "::kernel.bin"
	dd if=$< of=$@ conv=notrunc # when this is done, for some reason it stops being considered a fat12 fs??? idk
								# doing it after copying the files works so i dont really care to fix it

run: ${BUILD_DIR}/disk.img
	${QEMU} ${VM_FLAGS} -fda $<

bochs: ${BUILD_DIR}/disk.img
	bochs -q -f bochs_config -debugger

clean:
	rm -f ${BUILD_DIR}/*.o ${BUILD_DIR}/*.bin ${BUILD_DIR}/*.out
