#!/system/bin/sh
MODDIR=${0%/*}

# Calculate memory to use for zram (1/2 of ram)
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
mem=$((totalmem * 50 / 100 * 1024))
swap=/data/swap_file
size=$((totalmem / 2))

# Set up maxium cpu streams
echo ${NRDEVICES} > /sys/block/zram0/max_comp_streams

# Set up zram size, then turn on both zram and swap
echo ${mem} > /sys/block/zram0/disksize
mkswap /dev/block/zram0
swapon /dev/block/zram0

if [ -f "$swap" ]; then
	swapon $swap
fi
