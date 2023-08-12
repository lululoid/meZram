# shellcheck disable=SC3010,SC3060,SC3043,SC2086,SC2046
MODDIR=${0%/*}
LOGDIR=/data/adb/meZram
CONFIG="$LOGDIR"/meZram-config.json
BIN=/system/bin # magisk restrict the PATH env to only in their busybox, i don't know why
MODBIN=/data/adb/modules/meZram/modules/bin # modules binary
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/') # read the cpu cores
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

# Loading modules
. $MODDIR/modules/lmk.sh

# keep the specified logs no more than 5
logrotate() {
	local count=0

	for log in "$@"; do
		count=$((count + 1))

		if [ "$count" -gt 5 ]; then
			oldest_log=$(ls -tr "$1" | head -n 1)
			rm -rf "$oldest_log"
		fi
	done
}

# look for foreground app that in aggressive mode list
read_agmode_app() {
	fg_app=$(dumpsys activity |
		$BIN/fgrep -w ResumedActivity |
		sed -n 's/.*u[0-9]\{1,\} \(.*\)\/.*/  \1/p' |
		tail -n 1 | sed 's/ //g')
	ag_app=$($BIN/fgrep -wo "$fg_app" "$1")
}

# logging service
while true; do
	lmkd_log_size=$(wc -c <$LOGDIR/lmkd.log | awk '{print $1}')
	meZram_log_size=$(wc -c <$LOGDIR/meZram.log | awk '{print $1}')
	today_date=$(date +%R-%a-%d-%m-%Y)

  # check for loggers pid, if it's don't exist start one
  lmkd_logger_pid=$(/system/bin/ps -p $lmkd_logger_pid 2>/dev/null | sed '1d' | tail -n 1 | awk '{print $2}')
	[ -z $lmkd_logger_pid ] && {
		$BIN/logcat -v time --pid $lmkd_pid --file=$LOGDIR/lmkd.log &
    # save the pid to variable and prop
		lmkd_logger_pid=$!
		resetprop meZram.lmkd_logger.pid $lmkd_logger_pid
	}
  meZram_logger_pid=$(/system/bin/ps -p $meZram_logger_pid 2>/dev/null | sed '1d' | tail -n 1 | awk '{print $2}')
	[ -z $meZram_logger_pid ] && {
		$BIN/logcat -v time -s meZram --file=$LOGDIR/meZram.log &
		meZram_logger_pid=$!
		resetprop meZram.logger.pid $meZram_logger_pid
	}

  # limit log size to ~10MB then restart the service if it's exceed it
	if [ $lmkd_log_size -ge 10485760 ]; then
		kill -9 $lmkd_logger_pid
		mv $LOGDIR/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		resetprop meZram.lmkd_logger.pid dead
	fi

	if [ $meZram_log_size -ge 10485760 ]; then
		kill -9 $meZram_logger_pid
		mv $LOGDIR/meZram.log "$LOGDIR/$today_date-meZram.log"
		resetprop meZram.logger.pid dead
	fi

	logrotate $LOGDIR/*lmkd.log
	logrotate $LOGDIR/*meZram.log
	sleep 1
done &

resetprop meZram.log_rotator.pid $!

logger i "NRDEVICES = $NRDEVICES"
logger i "totalmem = $totalmem"
logger i "zram_size = $zram_size"
logger i "lmkd_pid = $lmkd_pid"

# looking for existing zram path
for zram0 in /dev/block/zram0 /dev/zram0; do
	[ "$(ls $zram0)" ] && {
		swapoff $zram0 && logger i "$zram0 turned off"
		echo 1 >/sys/block/zram0/reset &&
			logger i "$zram0 RESET"
		# Set up zram size, then turn on both zram and swap
		echo $zram_size >/sys/block/zram0/disksize &&
			logger i "set $zram0 disksize to $zram_size"
		# Set up maxium cpu streams
		logger i "making $zram0 and set max_comp_streams=$NRDEVICES"
		echo "$NRDEVICES" >/sys/block/zram0/max_comp_streams
		mkswap "$zram0"
		$BIN/swapon -p 3 "$zram0" && logger i "$zram0 turned on"
		break
	}
done

$BIN/swapon -p 2 /data/swap_file &&
	logger i "swap is turned on"

tl=ro.lmk.thrashing_limit

# wait until boot completed to remove thrashing_limit in MIUI because it has no effect in MIUI
while true; do
	[ "$(resetprop sys.boot_completed)" -eq 1 ] && {
		lmkd_props_clean &&
			logger i "unnecessary lmkd props cleaned"
		if [ "$(resetprop ro.miui.ui.version.code)" ]; then
			rm_prop $tl &&
				logger i "MIUI not support thrashing_limit customization"
		fi
		custom_props_apply
		resetprop lmkd.reinit 1 &&
			logger i "custom props applied"
		break
	}
  sleep 1
done

logger i "jq_version = $($MODBIN/jq --version)"

while true; do
	# Read configuration for aggressive mode
	agmode=$(sed -n 's#"agmode": "\(.*\)".*#\1#p' "$CONFIG" | sed 's/ //g')

	[[ "$agmode" = "on" ]] && {
		read_agmode_app $CONFIG

    # if the foreground app math app in aggressive mode list then activate aggressive mode
		if [ -n "$ag_app" ] && {
      # am stand for aggressive mode, if am is not activated or am is different than the last am then activate aggressive mode
			[ -z "$am" ] || [[ $ag_app != "$am" ]]
		}; then
			apply_aggressive_mode $ag_app &&
				logger i "aggressive mode activated for $fg_app"
			am=$ag_app
		elif [ -z "$ag_app" ] && [ -n "$am" ]; then
			wait_time=$($MODBIN/jq \
				--arg am "$am" \
				'.agmode_per_app_configuration[] | select(.package == $am) | .wait_time' \
				"$CONFIG" | tail -n 1)

			if [[ $wait_time = null ]]; then
				# Wait before quit agmode to avoid lag or forced closed am app
				wait_time=$($MODBIN/jq \
					'.wait_time' $CONFIG)

				[[ ${wait_time//\"/} != 0 ]] && {
					logger i "wait $wait_time before exiting aggressive mode" &&
						sleep "${wait_time//\"/}"
				}
			elif [[ ${wait_time//\"/} != 0 ]]; then
				logger i "wait $wait_time before exiting aggressive mode because of $am" &&
					sleep "${wait_time//\"/}"
			fi

			# make sure we already close the app
			read_agmode_app $CONFIG
			[ -z $ag_app ] && restore_props && logger i "aggressive mode deactivated" && unset am
		fi
	}
	sleep 1
done &

resetprop meZram.aggressive_mode.pid $!

# sync service because i can't read from internal for some reason?
while true; do
	is_update=$(cp -uv /sdcard/meZram-config.json /data/adb/meZram/meZram-config.json)

	echo $is_update | $BIN/fgrep -wo ">" &&
		logger i "config updated"
	sleep 1
done &

# save the service pid
# TODO make option to kill all service in agmode command
resetprop meZram.config_sync.pid $!
