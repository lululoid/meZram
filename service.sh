#!/system/bin/sh
MODDIR=${0%/*}

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$(((totalmem / 2) * 1024))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

logger(){
    local on=true
    $on && echo "$*" >> "$MODDIR"/meZram.log
}

logger "zram_size = $zram_size"
logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "lmkd_pid = $lmkd_pid"

for zram0 in /dev/block/zram0 /dev/zram0; do
    if [ -n "$(ls $zram0)" ]; then
	swapoff $zram0 2> "$MODDIR"/meZram.log
	echo 1 > /sys/block/zram0/reset 2>> "$MODDIR"/meZram.log 
	# Set up zram size, then turn on both zram and swap
	echo $zram_size > /sys/block/zram0/disksize 2>> "$MODDIR""/meZram."log 
	# Set up maxium cpu streams
	echo "$NRDEVICES" > /sys/block/zram0/max_comp_streams 2>> "$MODDIR"/meZram.log 
	mkswap $zram0 2>> "$MODDIR"/meZram.log 
	swapon $zram0 2>> "$MODDIR"/meZram.log 
	echo "$zram0 succesfully activated" > "$MODDIR"/meZram.log 
    else
	echo "$zram0 not exist in this device" >> "$MODDIR"/meZram.log 
    fi
done

swapon /data/swap_file 2>> "$MODDIR"/meZram.log 

echo '1' > /sys/kernel/tracing/events/psi/enable 2>> "$MODDIR"/meZram.log 
resetprop lmkd.reinit 1

# peaceful logger
while true; do
    logcat -G 10M
    logcat --pid "$lmkd_pid" -t 100 -f "$MODDIR"/lmkd.log &
    sleep 30m
done &

rm_prop_reinit(){
    for prop in "$@"; do
        [ "$(resetprop "$prop")" ] && resetprop --delete "$prop" && resetprop lmkd.reinit 1
    done
}

while true; do
    tlc="persist.device_config.lmkd_native.thrashing_limit_critical"
    err="persist.device_config.lmkd_native.thrashing_limit_"
    minfree="sys.lmk.minfree_levels"
    rm_prop_reinit $tlc $err $minfree 2>> "$MODDIR"/meZram.log 
done
