#!/system/bin/sh
MODDIR=${0%/*}
LOGDIR="/data/adb/meZram"

mkdir -p "$LOGDIR"

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)


logger(){
	local td=$(date +%R:%S:%N)
	log=$(echo "$*" | tr -s " ")
	true && echo "$td $log" >> "$LOGDIR/${td}meZram.log"
}

logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "zram_size = $zram_size"
logger "lmkd_pid = $lmkd_pid"


for zram0 in /dev/block/zram0 /dev/zram0; do
    if [ -n "$(ls $zram0)" ]; then
		swapoff $zram0 && logger "$zram0 turned off"
		echo 1 > /sys/block/zram0/reset
		logger "$zram0 reset"

		# Set up zram size, then turn on both zram and swap
		echo "$zram_size" > /sys/block/zram0/disksize
		logger "set $zram0 disksize to $zram_size"

		# Set up maxium cpu streams
		logger "making $zram0 and set max_comp_streams=$NRDEVICES"
		echo "$NRDEVICES" > /sys/block/zram0/max_comp_streams
		mkswap $zram0
		swapon $zram0
    else
		logger "$zram0 not exist in this device" 
    fi
done

swapon /data/swap_file && logger "swap is turned on"
# echo '1' > /sys/kernel/tracing/events/psi/enable 2>> "$MODDIR"/meZram.log
logcat --pid "$lmkd_pid" -f "$LOGDIR"/lmkd.log -r 10485760 &


rm_prop(){                                
	for prop in "$@"; do
		resetprop "$prop" && resetprop --delete "$prop" && logger "$prop deleted"
	done
}

# set "ro.config.low_ram" "ro.lmk.use_psi" "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" "ro.lmk.debug" "sys.lmk.minfree_levels"

set --
set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"

tl="ro.lmk.thrashing_limit"

while true; do
	if [ "$(resetprop sys.boot_completed)" -eq "1" ]; then
		rm_prop "$@"
		rm_prop $tl
		resetprop lmkd.reinit 1
		break
	fi
done

# Read configuration                                  
if [[ -f "$MODDIR"/meZram.conf ]]; then
	while read conf; do                             
		case "$conf" in
            "agmode="*)                 
				agmode=$(echo "$conf" | sed 's/agmode=//');
				logger "agmode=$agmode";
		esac
	done < "$MODDIR"/meZram.conf
fi

if [[ "$agmode" = "on" ]]; then
	pappcfg=$(sed -n '/#agmode PER APP CONFIGURATION/{n;p;:a;n;p;ba}' "$MODDIR"/meZram.conf)

	logger "pappcfg=$pappcfg"
	for app in $pappcfg; do
		app_pkg=$(echo "$app" | cut -d "=" -f1)
		logger "app_pkg=$app_pkg"
		dpressure=$(echo "$app" | cut -d "=" -f2)
		logger "dpressure=$dpressure"
		while true; do
			if [ "$(pidof "$app_pkg")" ]; then
				resetprop ro.lmk.downgrade_pressure "$dpressure" && resetprop lmkd.reinit 1
				logger "agmode activated for $app"
				am=true
			elif [ "$am" ] && [ -z "$(pidof "$app")" ]; then
				default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "${MODDIR}/system.prop")
				resetprop ro.lmk.downgrade_pressure "$default_dpressure" && resetprop lmkd.reinit 1
				logger "default ro.lmk.downgrade_pressure restored"
				am=false
			fi
			sleep 1
		done &
		resetprop meZram.agmode_svc.pid."$app_pkg" "$!"
	done
fi

