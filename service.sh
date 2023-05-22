#!/system/bin/sh
MODDIR=${0%/*}
LOGDIR="/data/adb/meZram"
CONFIG="$LOGDIR/meZram.conf"

mkdir -p "$LOGDIR"

if [ ! -f "$CONFIG" ]; then
	cp "$MODDIR"/meZram.conf "$LOGDIR"
fi

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)


logger(){
	local td=$(date +%R:%S:%N_%d-%m-%Y)
	log=$(echo "$*" | tr -s " ")
	true && echo "$td $log" >> "$LOGDIR"/meZram.log
}


logrotate(){
	count=0

	for log in $*; do 
		count=$((count+1))
		if [ "$count" -gt 5 ]; then 
			oldest_log=$(ls -tr "$1" | head -n 1)

			rm -rf "$oldest_log"
			logger "oldest_log=$oldest_log"
		fi
	done
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

# rotate lmkd logs
logcat --pid "$lmkd_pid" --file="$LOGDIR"/lmkd.log &
lmkd_logger_pid="$!"

logger "lmkd_logger_pid=$lmkd_logger_pid"
logger "lmkd_log_size=$(wc -c <"$LOGDIR"/lmkd.log)"

while true; do 
	lmkd_log_size=$(wc -c <"$LOGDIR"/lmkd.log)
	meZram_log_size=$(wc -c <"$LOGDIR"/meZram.log)
	today_date=$(date +%R-%a-%d-%m-%Y)

	if [ "$lmkd_log_size" -ge 10485760 ]; then
		kill -9 "$lmkd_logger_pid"
		mv "$LOGDIR"/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		logcat --pid "$lmkd_pid" --file="$LOGDIR"/lmkd.log &

		lmkd_logger_pid="$!"
	fi

	if [ "$meZram_log_size" -ge 10485760 ]; then
		mv "$LOGDIR"/meZram.log "$LOGDIR/$today_date-meZram.log"
	fi

	logrotate "$LOGDIR"/*lmkd.log
	logrotate "$LOGDIR"/*meZram.log
	sleep 1
done &

logger "meZram log count=$count"
logger "log ratator pid=$!"

rm_prop(){                                
	for prop in $*; do
		resetprop "$prop" && resetprop --delete "$prop" && logger "$prop deleted"
	done
}


# set "ro.config.low_ram" "ro.lmk.use_psi" "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" "ro.lmk.debug" "sys.lmk.minfree_levels"

set --
set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical_upgrade" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"

tl="ro.lmk.thrashing_limit"

# wait until boot completed to remove thrashing_limit in MIUI because it's couldn't be changed
while true; do
	if [ "$(resetprop sys.boot_completed)" -eq "1" ]; then
		rm_prop "$@"
		if [ "$(resetprop ro.miui.ui.version.code)" ]; then
			rm_prop "$tl"
		fi
		resetprop lmkd.reinit 1
		break
	fi
done

# Read configuration for aggressive mode
if [[ -f "$CONFIG" ]]; then
	while read conf; do                             
		case "$conf" in
            "agmode="*)                 
				agmode=$(echo "$conf" | sed 's/agmode=//');
				logger "agmode=$agmode";
		esac
	done < "$CONFIG"
fi

# start aggressive mode service
if [[ "$agmode" = "on" ]]; then
	starting_line=$(grep -n "#agmode" "$CONFIG" | cut -d ":" -f1)

	while true; do 
		app_pkgs=$(tail -n +$((starting_line + 1)) "$CONFIG")

		for app in $app_pkgs; do
			app_pkg=$(echo "$app" | cut -d "=" -f1)
			dpressure=$(echo "$app" | cut -d "=" -f2)
			fg_app=$(dumpsys activity recents | grep 'Recent #0' | sed 's/.*:\([^ ]*\).*$/\1/')
			fg_app_=$(pgrep -x "$fg_app")
			running_app=$(pgrep -x "$app_pkg")

			if [ "$running_app" ] && [[ "$fg_app_" = "$running_app" ]] && [ -z "$am" ]; then
				dpressure=$(grep -w "^$app_pkg" "$CONFIG" | cut -d "=" -f2)

				logger "dpressure=$dpressure"
				resetprop ro.lmk.downgrade_pressure "$dpressure" && resetprop lmkd.reinit 1
				logger "agmode activated for $app_pkg"

				am=true

			elif [ -z "$fg_app_" ] && [ "$am" ]; then
				default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "${MODDIR}/system.prop")

				logger "default_dpressure=$default_dpressure"
				resetprop ro.lmk.downgrade_pressure "$default_dpressure" && resetprop lmkd.reinit 1
				logger "default ro.lmk.downgrade_pressure restored"
				unset am
			fi
		done
	done &
	resetprop "meZram.agmode_svc.pid.agmode" "$!"
	# save aggressive mode pid as a prop
	logger "aggressive mode pid is $(resetprop "meZram.agmode_svc.pid.agmode")"
	sleep 1
fi

