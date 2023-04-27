#!/system/bin/sh
MODDIR=${0%/*}

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$(((totalmem / 2) * 1024))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

logger(){
    true && echo "$*" >> "$MODDIR"/meZram.log
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

swapon /data/swap_file >> "$MODDIR"/meZram.log 

# echo '1' > /sys/kernel/tracing/events/psi/enable 2>> "$MODDIR"/meZram.log 

# peaceful logger
while true; do
    logcat --pid "$lmkd_pid" -f "$MODDIR"/lmkd.log
done &

rm_prop(){                                
	for prop in "$@"; do
		[ "$(resetprop "$prop")" ] && resetprop --delete "$prop" && logger "$prop deleted" >> "$MODDIR"/meZram.log
	done
}

if [ ! -d /data/adb/meZram ]; then
	logger "- Trying to make folder"
	mkdir -p /data/adb/meZram 2>> "$MODDIR"/meZram.log
fi

set --

# set "ro.config.low_ram" "ro.lmk.use_psi" "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" "ro.lmk.debug" "sys.lmk.minfree_levels"

set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit_decay" "sys.lmk.minfree_levels" "ro.lmk.critical_upgrade" "ro.lmk.swap_free_low_percentage"

tl="ro.lmk.thrashing_limit"

resetprop lmkd.reinit 1

for i in $(seq 2); do
	rm_prop "$@"
	if [ "$(resetprop ro.miui.ui.version.code)" ]; then
		rm_prop $tl
	fi
	resetprop lmkd.reinit 1
	sleep 2m
done &

while true; do
	sleep 1m 
	cp "$MODDIR"/*.log /data/adb/meZram 
done &
