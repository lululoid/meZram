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
resetprop lmkd.reinit 1

# peaceful logger
while true; do
    logcat --pid "$lmkd_pid" -t 100000 -f "$MODDIR"/lmkd.log
    sleep 1m
done &

rm_prop(){                                
	for prop in "$@"; do
		[ "$(resetprop "$prop")" ] && resetprop --delete "$prop" && logger "$prop deleted" 1>> "$MODDIR"/meZram.log
	done
}

if [ ! -d /data/adb/meZram ]; then
	logger "- Trying to make folder"
	mkdir -p /data/adb/meZram 2>> "$MODDIR"/meZram.log
fi

while true; do
	sleep 1m 
	cp "$MODDIR"/*.log /data/adb/meZram 
done &

while true; do
	# prop that need to be removed
	rmt_prop='
	"ro.lmk.low"
	"ro.lmk.medium"
	"ro.lmk.critical"
	"ro.lmk.critical_upgrade"
	"ro.lmk.upgrade_pressure"
	"ro.lmk.downgrade_pressure"
	"ro.lmk.kill_heaviest_task"
	"ro.lmk.kill_timeout_ms"
	"ro.lmk.psi_complete_stall_ms"
	"ro.lmk.thrashing_limit_decay"
	"ro.lmk.thrashing_limit"
	"ro.lmk.swap_util_max"
	"ro.lmk.swap_free_low_percentage"
	"ro.lmk.debug"
	"persist.device_config.lmkd_native.thrashing_limit_critical"
	"mezram_test"'

	printf '%s' "$rmt_prop" |
		while IFS='' read -r prop; do
		grep -v '^ *#' < "$MODPATH"/system.prop | while IFS= read -r prop0; do
			resetprop $(echo "$prop0" | sed s/=/' '/)
			if [ "$prop" != "$prop0" ]; then
				rm_prop "$prop"
			fi
		done
	done

	tl="ro.lmk.thrashing_limit"

	if [ "$(resetprop ro.miui.ui.version.code)" ]; then
		rm_prop $tl 1>> "$MODDIR"/meZram.log
	fi
done &
