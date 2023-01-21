#!/system/bin/sh
MODDIR=${0%/*}

# Calculate memory to use for zram (1/2 of ram)
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
mem=$((totalmem * 50 / 100 * 1024))
swap=/data/swap_file
size=$((totalmem / 2))

for zram0 in /dev/block/zram0 /dev/zram0; do
	if [ ! -z $(ls $zram0) ]; then
		swapoff $zram0
		echo 1 > /sys/block/zram0/reset 2> $MODDIR/error.txt
	
		# Set up zram size, then turn on both zram and swap
		echo ${mem} > /sys/block/zram0/disksize 2>> $MODDIR/error.txt
		# Set up maxium cpu streams
		echo ${NRDEVICES} > /sys/block/zram0/max_comp_streams 2>> $MODDIR/error.txt
		mkswap $zram0 2>> $MODDIR/error.txt
		swapon $zram0 2>> $MODDIR/error.txt
		echo "$zram0 succesfully activated" > $MODDIR/success.txt
	else
		echo "$zram0 not exist in this device" >> $MODDIR/error.txt
	fi
done

if [ -f "$swap" ]; then
	swapon $swap 2>> $MODDIR/error.txt
fi

lmkd --reinit
