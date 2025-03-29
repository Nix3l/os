#!/bin/sh
# $1: disk image
# $2: mount directory
mount --source $1 --target $2 -t msdos -o "fat=12"
cd $2
touch STAGE2.BIN
umount $2
