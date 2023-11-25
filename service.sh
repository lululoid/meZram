# shellcheck disable=SC3010,SC3060,SC3043,SC2086,SC2046
LOGFILE="/data/local/tmp/meZram.log"
exec 3>&1 1>"$LOGFILE" 2>&1
set -x
MODDIR=${0%/*}
LOGDIR=/data/adb/meZram
CONFIG=$LOGDIR/meZram-config.json
CONFIG_INT=/sdcard/meZram-config.json
# magisk restrict the PATH env to only in their busybox,
# i don't know why
BIN=/system/bin
# this module binary
MODBIN=/data/adb/modules/meZram/modules/bin
# read the cpu cores amount
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$($BIN/free | awk '/^Mem:/ {print $2}')
zram_size=$(awk -v size="$totalmem" \
	'BEGIN { printf "%.0f\n", size * 0.65 }')
lmkd_pid=$(pidof lmkd)

export CONFIG
export MODBIN
export LOGDIR
export CONFIG_INT
export MODDIR
export BIN

# loading modules
. $MODDIR/modules/lmk.sh

# keep the specified logs no more than 5
logrotate() {
	local count=0

	for log in "$@"; do
		count=$((count + 1))

		if [ "$count" -gt 5 ]; then
			# shellcheck disable=SC2012
			oldest_log=$(ls -tr "$1" | head -n 1)
			rm -rf "$oldest_log"
		fi
	done
}

# Extract values from /proc/pressure using sed
read_pressure_value() {
	local pressure_file="$1"
	sed 's/some avg10=\([0-9]*\).*/\1/;2d' $pressure_file
}

# logging service, keeping the log alive bcz system sometimes
# kill them for unknown reason
while true; do
	lmkd_log_size=$(stat -c %s $LOGDIR/lmkd.log)
	meZram_log_size=$(stat -c %s $LOGDIR/meZram.log)
	today_date=$(date +%R-%a-%d-%m-%Y)

	# check for loggers pid, if it's don't exist start one
	! kill -0 $lmkd_logger_pid && {
		$BIN/logcat -v time --pid $lmkd_pid \
			--file=$LOGDIR/lmkd.log &
		# save the pid to variable and prop
		lmkd_logger_pid=$!
		resetprop -n -p meZram.lmkd_logger.pid $lmkd_logger_pid
	}

	! kill -0 $meZram_logger_pid && {
		$BIN/logcat -v time -s meZram --file=$LOGDIR/meZram.log &
		meZram_logger_pid=$!
		resetprop -n -p meZram.logger.pid $meZram_logger_pid
	}

	# limit log size to 10MB then restart the service
	# if it's exceed it
	[ $lmkd_log_size -ge 10485760 ] && {
		kill -15 $lmkd_logger_pid
		mv $LOGDIR/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		resetprop -n -p meZram.lmkd_logger.pid dead
	}

	[ $meZram_log_size -ge 10485760 ] && {
		kill -15 $meZram_logger_pid
		mv $LOGDIR/meZram.log "$LOGDIR/$today_date-meZram.log"
		resetprop -n -p meZram.logger.pid dead
	}

	logrotate $LOGDIR/*lmkd.log
	logrotate $LOGDIR/*meZram.log
	logrotate /data/local/tmp/meZram.log
	sleep 1
done &

# save the pid to a prop
resetprop -n -p meZram.log_rotator.pid $!
# disable miui memory extension
resetprop persist.miui.extm.enable &&
	resetprop persist.miui.extm.enable 0

logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "zram_size = $zram_size"
logger "lmkd_pid = $lmkd_pid"

resize_zram $zram_size
# set_mem_limit
swapon /data/swap_file 2>&1 | logger &&
	logger "swap is turned on"

tl=ro.lmk.thrashing_limit

# thrashing limit has no effect in MIUI
while true; do
	[ $(resetprop sys.boot_completed) -eq 1 ] && {
		lmkd_props_clean
		[ $(resetprop ro.miui.ui.version.code) ] && {
			rm_prop $tl &&
				logger \
					"MIUI not support thrashing_limit customization"
		}
		custom_props_apply
		$BIN/lmkd --reinit &&
			logger "custom props applied"
		break
	}
	sleep 1
done

logger "jq_version = $($MODBIN/jq --version)"
# reset states and variables to default
reset_svs() {
	restore_battery_opt
	echo "" >/data/local/tmp/swapoff_pids
	echo "" >/data/local/tmp/swapping_off
	echo "" >/data/local/tmp/am_apps
}

reset_svs

$MODDIR/meZram.sh
# sync service because i can't read from internal
# for some reason? tell me why please
while true; do
	cp -uv /sdcard/meZram-config.json \
		/data/adb/meZram/meZram-config.json |
		$BIN/fgrep -wo ">" &&
		logger "config updated"
	sleep 1
done &

# save the service pid
# TODO make option to kill all service in agmode command
resetprop meZram.config_sync.pid $!

# lookout for unnecesarry props show up when screen is off
# this happened on MIUI 14 chinese ROM, probably on all
# MIUI 14
while true; do
	eval \
		$($MODBIN/sed -n '/mIsScreenOn/{s/.*= \(.*\)/\1/;p;q}') &&
		resetprop sys.lmk.minfree_levels && {
		restore_props
		logger "fuck MIUI, they're dead anyways"
	}

	if ! kill -0 $(getprop meZram.aggressive_mode.pid); then
		reset_svs
		$MODDIR/meZram.sh
	fi
	sleep 5
done &

resetprop meZram.fuck.miui.pid $!
