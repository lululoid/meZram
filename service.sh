#!/data/adb/modules/meZram/modules/bin/bash
MODDIR=${0%/*}
LOGDIR=/data/adb/meZram
CONFIG="$LOGDIR"/meZram-config.json
BIN=/system/bin
MODBIN=/data/adb/modules/meZram/modules/bin 

# Calculate memory to use for zram
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

# Loading modules
. "$MODDIR"/modules/lmk.sh

log_it() {
	local ms=$(date +%N | cut -c1-3)
	local td=$(date +%R:%S:"${ms}")
	logger "$td" "$1"
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

log_it "NRDEVICES = $NRDEVICES"
log_it "totalmem = $totalmem"
log_it "zram_size = $zram_size"
log_it "lmkd_pid = $lmkd_pid"

for zram0 in /dev/block/zram0 /dev/zram0; do
	if [ "$(ls $zram0)" ]; then
		swapoff $zram0 && log_it "$zram0 turned off"
		echo 1 >/sys/block/zram0/reset
		log_it "$zram0 RESET"

		# Set up zram size, then turn on both zram and swap
		echo "$zram_size" >/sys/block/zram0/disksize
		log_it "set $zram0 disksize to $zram_size"

		# Set up maxium cpu streams
		log_it "making $zram0 and set max_comp_streams=$NRDEVICES"
		echo "$NRDEVICES" >/sys/block/zram0/max_comp_streams
		mkswap "$zram0" && log_it "$zram0 turned on"
		$BIN/swapon -p 10 "$zram0" && log_it "swap turned on"
	fi
done

$BIN/swapon -p 5 /data/swap_file && log_it "swap is turned on"
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
# List of lmkd props
# set "ro.config.low_ram" "ro.lmk.use_psi" "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical" "ro.lmk.critical_upgrade" "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" "ro.lmk.debug" "sys.lmk.minfree_levels"

tl="ro.lmk.thrashing_limit"

# wait until boot completed to remove thrashing_limit in MIUI because it has no effect in MIUI
while true; do
	if [ "$(resetprop sys.boot_completed)" -eq "1" ]; then
		lmkd_props_clean
		if [ "$(resetprop ro.miui.ui.version.code)" ]; then
			rm_prop "$tl"
		fi
		resetprop lmkd.reinit 1
		break
	fi
done

custom_props_apply && resetprop "lmkd.reinit" 1 &&
	log_it "custom props applied"

# Start aggressive mode service
while true; do
	# Read configuration for aggressive mode
	agmode=$(sed -n 's#"agmode": "\(.*\)".*#\1#p' "$CONFIG" | sed 's/ //g')

	if [[ "$agmode" = "on" ]]; then
		# Determine foreground_app pkg name
		# Not use + because of POSIX limitation
		fg_app=$(dumpsys activity | $BIN/fgrep -w ResumedActivity | sed -n 's/.*u[0-9]\{1,\} \(.*\)\/.*/  \1/p' | tail -n 1 | sed 's/ //g')
		ag_app=$($BIN/fgrep -wo "$fg_app" $CONFIG)

		if [ -n "$ag_app" ] && [ -z "$am" ]; then
			papp_keys=$($MODBIN/jq \
				--arg fg_app "$fg_app" \
				'.agmode_per_app_configuration[] | select(.package == $fg_app) | .props[0] | keys[]' \
				"$CONFIG")

			for key in $(echo "$papp_keys"); do
				value=$($MODBIN/jq \
					--arg fg_app "$fg_app" \
					--arg key "${key//\"/}" \
					'.agmode_per_app_configuration[] | select(.package == $fg_app) | .props[0] | .[$key]' \
					"$CONFIG")

				log_it "applying $key $value"
				resetprop "${key//\"/}" "$value"
			done

			resetprop "lmkd.reinit" 1
			log_it "aggressive mode activated for $fg_app"

			am=true
			wait_time=true
		elif [ -z "$ag_app" ] && [ "$am" ]; then
			default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "$CONFIG")

			if [ -z "$default_dpressure" ]; then
				default_dpressure=$(sed -n 's/^ro.lmk.downgrade_pressure=//p' "${MODDIR}/system.prop")
			fi

			lmkd_props_clean
			resetprop ro.lmk.downgrade_pressure "$default_dpressure"
			custom_props_apply && log_it "props restored"
			resetprop lmkd.reinit 1
			log_it "aggressive mode deactivated"
			unset am
		fi
	fi

	if [ $wait_time ]; then
		# Wait before quit agmode to avoid lag
		wait_time=$($MODBIN/jq \
			'.wait_time' $CONFIG)

		log_it "wait $wait_time before exiting aggressive mode"
		sleep "${wait_time//\"/}"
		unset wait_time
	fi
	sleep 6
done &
resetprop "meZram.agmode.pid" "$!"
