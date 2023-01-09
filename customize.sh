#!/sbin/sh

# Calculate size to use for swap (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
swap=/data/swap_file
size=$((totalmem / 2))

ui_print "- Set up zram size"

if [ -f "$swap" ]; then
	swapon $swap 2> /dev/null
else
	dd if=/dev/zero of=$swap bs=1024 count=${size}
	chmod 0600 $swapz
	mkswap $swap
fi