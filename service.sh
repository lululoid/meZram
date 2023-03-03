#!/system/bin/sh:
MODDIR=${0%/*}

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
# use maximum 75% of RAM as ZRAM
zram_size=$((totalmem / 2 * 1024))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

for zram0 in /dev/block/zram0 /dev/zram0; do
    if [ ! -z $(ls $zram0) ]; then
	swapoff $zram0
	echo 1 > /sys/block/zram0/reset 2> $MODDIR/error.txt
    
	# Set up zram size, then turn on both zram and swap
	echo ${zram_size} > /sys/block/zram0/disksize 2>> $MODDIR/error.txt
	# Set up maxium cpu streams
	echo ${NRDEVICES} > /sys/block/zram0/max_comp_streams 2>> $MODDIR/error.txt
	mkswap $zram0 2>> $MODDIR/error.txt
	swapon $zram0 2>> $MODDIR/error.txt
	echo "$zram0 succesfully activated" > $MODDIR/success.txt
    else
	echo "$zram0 not exist in this device" >> $MODDIR/error.txt
    fi
done

swapon $MODDIR/swap_file 

echo '1' > /sys/kernel/tracing/events/psi/enable 2>> $MODDIR/error.txt 
resetprop lmkd.reinit 1
logcan -G 5M
logcat --pid ${lmkd_pid} -f $MODDIR/lmkd.log &

rm_prop_reinit(){
    for prop in in $@; do
        [ $(resetprop $prop) ] && resetprop --delete $prop && lmkd --reinit
    done
}

while true; do
    tlc="persist.device_config.lmkd_native.thrashing_limit_critical"
    minfree_l="sys.lmk.minfree_levels"
    err="persist.device_config.lmkd_native.thrashing_limit_"
    rm_prop_reinit $tlc $minfree_l $err
done
