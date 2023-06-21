#!/system/bin/bash
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

logger() {
	local td=$(date +%R:%S:%N_%d-%m-%Y)
	log=$(echo "$*" | tr -s " ")
	true && echo "$td $log" >>"$LOGDIR"/meZram.log
}

logrotate() {
	count=0

	for log in "$@"; do
		count=$((count + 1))
		if [ "$count" -gt 5 ]; then
			oldest_log=$(ls -tr "$1" | head -n 1)

			rm -rf "$oldest_log"
		fi
	done
}

custom_props_apply() {
	# applying custom prop
	starting_line=$(grep -nw "# custom props" "$CONFIG" | cut -d ":" -f1)
	end_line=$(grep -n "#" "$CONFIG" | grep -v "# custom props" | head -n 1 | cut -d ":" -f1)
	props=$(tail -n "+$((starting_line + 1))" "$CONFIG" | head -n "$((end_line - starting_line - 2))")

	if [[ "$props" ]]; then
		for prop in $props; do
			prop=${prop//=/ }

			resetprop $prop
		done
	fi
}

logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "zram_size = $zram_size"
logger "lmkd_pid = $lmkd_pid"

for zram0 in /dev/block/zram0 /dev/zram0; do
	if [ "$(ls $zram0)" ]; then
		swapoff $zram0 && logger "$zram0 turned off"
		echo 1 >/sys/block/zram0/reset
		logger "$zram0 RESET"

		# Set up zram size, then turn on both zram and swap
		echo "$zram_size" >/sys/block/zram0/disksize
		logger "set $zram0 disksize to $zram_size"

		# Set up maxium cpu streams
		logger "making $zram0 and set max_comp_streams=$NRDEVICES"
		echo "$NRDEVICES" >/sys/block/zram0/max_comp_streams
		mkswap $zram0 && logger "$zram0 turned on"
		swapon $zram0 && logger "swap turned on"
	fi
done

swapon /data/swap_file && logger "swap is turned on"
# echo '1' > /sys/kernel/tracing/events/psi/enable 2>> "$MODDIR"/meZram.log

# rotate lmkd logs
logcat --pid "$lmkd_pid" --file="$LOGDIR"/lmkd.log &

lmkd_logger_pid="$!"

resetprop "meZram.lmkd_logger.pid" "$!"

while true; do
	lmkd_log_size=$(wc -c <"$LOGDIR"/lmkd.log)
	meZram_log_size=$(wc -c <"$LOGDIR"/meZram.log)
	today_date=$(date +%R-%a-%d-%m-%Y)

	if [ "$lmkd_log_size" -ge 10485760 ]; then
		kill -9 "$lmkd_logger_pid"
		mv "$LOGDIR"/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		logcat --pid "$lmkd_pid" --file="$LOGDIR"/lmkd.log &

		lmkd_logger_pid="$!"

		resetprop "meZram.lmkd_logger.pid" "$!"
	fi

	if [ "$meZram_log_size" -ge 10485760 ]; then
		mv "$LOGDIR"/meZram.log "$LOGDIR/$today_date-meZram.log"
	fi

	logrotate "$LOGDIR"/*lmkd.log
	logrotate "$LOGDIR"/*meZram.log
	sleep 2
done &

resetprop "meZram.log_rotator.pid" "$!"

rm_prop() {
	for prop in "$@"; do
		resetprop "$prop" && resetprop --delete "$prop" && logger "$prop deleted"
	done
}

lmkd_props_clean() {
	set --
	set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical_upgrade" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"
	rm_prop "$@"
}

# List of lmkd props
# set "ro.config.low_ram" "ro.lmk.use_psi" "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" "ro.lmk.debug" "sys.lmk.minfree_levels"

set --
set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical_upgrade" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"

tl="ro.lmk.thrashing_limit"

# wait until boot completed to remove thrashing_limit in MIUI because it has no effect in MIUI
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

custom_props_apply && resetprop "lmkd.reinit" 1 && logger "custom props applied"

# Read configuration for aggressive mode
if [[ -f "$CONFIG" ]]; then
	while read conf; do
		case "$conf" in
		"agmode="*)
			agmode=$(echo "$conf" | sed 's/agmode=//')
			logger "agmode=$agmode"
			;;
		esac
	done <"$CONFIG"
fi

# start aggressive mode service
if [[ "$agmode" = "on" ]]; then
	while true; do
		# Determine foreground_app pkg name
		# Not use + because of POSIX limitation
		fg_app=$(dumpsys activity | grep -w ResumedActivity | sed -n 's/.*u[0-9]\{1,\} \(.*\)\/.*/\1/p')
		papp=$(sed -n "s/^- pac:\($fg_app\).*/\1/p" "$CONFIG")

		if [ "$fg_app" ] && [[ "$fg_app" = "$papp" ]] && [ -z "$am" ]; then
			starting_line=$(grep -n "$fg_app" "$CONFIG" | cut -d ":" -f1)
			end_app=$(tail -n +"$((starting_line + 1))" "$CONFIG" | grep '\- pac' | head -n 1)
			end_line=$(grep -n -- "$end_app" "$CONFIG" | cut -d ":" -f1)

			if [ "$end_app" ]; then
				paprops=$(tail -n +"$((starting_line + 1))" "$CONFIG" | head -n $((end_line - starting_line - 1)))
			else
				paprops=$(tail -n +"$((starting_line + 1))" "$CONFIG")
			fi

			lmkd_props_clean

			for prop in $paprops; do
				prop=$(echo "$prop" | sed 's/^\t//;s/=/ /')

				logger "$fg_app: resetprop $prop"
				resetprop $prop
			done
			resetprop "lmkd.reinit" 1

			am=true

		elif [ -z "$papp" ] && [ "$am" ]; then
			default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "${LOGDIR}/meZram.conf")

			if [ -z "$default_dpressure" ]; then
				default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "${MODDIR}/system.prop")
			fi

			logger "papp=$papp ~ fg_app=$fg_app"
			resetprop ro.lmk.downgrade_pressure "$default_dpressure"
			lmkd_props_clean
			custom_props_apply && logger "custom props applied"
			resetprop lmkd.reinit 1
			unset am
		fi
		sleep 2
	done &
	# save aggressive mode pid as a prop
	resetprop "meZram.agmode_svc.pid.agmode" "$!"
fi
