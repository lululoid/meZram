# shellcheck disable=SC3010,SC3060,SC3043,SC2086,SC2046
MODDIR=${0%/*}
LOGDIR=/data/adb/meZram
CONFIG=$LOGDIR/meZram-config.json
# magisk restrict the PATH env to only in their busybox,
# i don't know why
BIN=/system/bin
# this modules binary
MODBIN=/data/adb/modules/meZram/modules/bin
# read the cpu cores amount
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(getprop init.svc_debug_pid.lmkd)

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

# look for foreground app that in aggressive mode list
# specified in the config
read_agmode_app() {
	fg_app=$(
		dumpsys activity |
			$BIN/fgrep -w ResumedActivity |
			sed -n 's/.*u[0-9]\{1,\} \(.*\)\/.*/  \1/p' |
			tail -n 1 | sed 's/ //g'
	)

	[ -z $ag_apps ] && {
		ag_apps=$(
			$MODBIN/jq \
				'.agmode_per_app_configuration[].packages[]' \
				$CONFIG | sed 's/"//g'
		)
	}
	# check if current foreground app is in aggressive
	# mode config
	ag_app=$(echo "$ag_apps" | sed -n "/^$fg_app$/p")
	{
		[ -n "$ag_app" ] && true
	} || false
}

convert() {
	local num m
	num=$(echo $1 | sed 's/[^0-9]//g')
	m=$(
		echo $1 | sed 's/[0-9]//g;s/m/60/g'
	)
	[ -n "$m" ] && echo $((num * m)) || echo $1
}

# logging service, keeping the log alive bcz system sometimes
# kill them for unknown reason
while true; do
	lmkd_log_size=$(wc -c <$LOGDIR/lmkd.log | awk '{print $1}')
	meZram_log_size=$(wc -c <$LOGDIR/meZram.log |
		awk '{print $1}')
	today_date=$(date +%R-%a-%d-%m-%Y)

	# check for loggers pid, if it's don't exist start one
	lmkd_logger_pid=$(/system/bin/ps -p $lmkd_logger_pid \
		2>/dev/null | sed '1d' | tail -n 1 | awk '{print $2}')
	[ -z $lmkd_logger_pid ] && {
		$BIN/logcat -v time --pid $lmkd_pid \
			--file=$LOGDIR/lmkd.log &
		# save the pid to variable and prop
		lmkd_logger_pid=$!
		resetprop meZram.lmkd_logger.pid $lmkd_logger_pid
	}
	meZram_logger_pid=$(/system/bin/ps -p $meZram_logger_pid \
		2>/dev/null | sed '1d' | tail -n 1 | awk '{print $2}')
	[ -z $meZram_logger_pid ] && {
		$BIN/logcat -v time -s meZram --file=$LOGDIR/meZram.log &
		meZram_logger_pid=$!
		resetprop meZram.logger.pid $meZram_logger_pid
	}

	# limit log size to 10MB then restart the service
	# if it's exceed it
	[ $lmkd_log_size -ge 10485760 ] && {
		kill -9 $lmkd_logger_pid
		mv $LOGDIR/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		resetprop meZram.lmkd_logger.pid dead
	}

	[ $meZram_log_size -ge 10485760 ] && {
		kill -9 $meZram_logger_pid
		mv $LOGDIR/meZram.log "$LOGDIR/$today_date-meZram.log"
		resetprop meZram.logger.pid dead
	}

	logrotate $LOGDIR/*lmkd.log
	logrotate $LOGDIR/*meZram.log
	sleep 1
done &

# save the pid to a prop
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
		echo $NRDEVICES >/sys/block/zram0/max_comp_streams
		mkswap $zram0
		$BIN/swapon -p 69 "$zram0" && logger i "$zram0 turned on"
		break
	}
done

{
	swapon /data/swap_file &&
		logger i "swap is turned on"
} || logger f "swap is missing"

tl=ro.lmk.thrashing_limit

# thrashing limit has no effect in MIUI
while true; do
	[ $(resetprop sys.boot_completed) -eq 1 ] && {
		lmkd_props_clean &&
			logger i "unnecessary lmkd props cleaned"
		[ $(resetprop ro.miui.ui.version.code) ] && {
			rm_prop $tl &&
				logger i \
					"MIUI not support thrashing_limit customization"
		}
		custom_props_apply
		resetprop lmkd.reinit 1 &&
			logger i "custom props applied"
		break
	}
	sleep 1
done

logger i "jq_version = $($MODBIN/jq --version)"
# for saving wait_time state, exist if wait_time is on
sltemp=/data/tmp/sltemp
# reset states and variables to default
rm $sltemp
restore_battery_opt

# aggressive mode service starts here
while true; do
	# Read configuration for aggressive mode
	agmode=$(sed -n 's#"agmode": "\(.*\)".*#\1#p' "$CONFIG" | sed 's/ //g')

	[[ $agmode = on ]] && {
		# if the foreground app match app in aggressive mode list
		# then activate aggressive mode
		read_agmode_app && {
			# am = aggressive mode, if am is not activated or
			# am is different than the last am then
			# activate aggressive mode
			# this is for efficiency reason
			[ -z "$am" ] || [[ $ag_app != "$am" ]]
		} && {
			# shellcheck disable=SC2016
			swap_size=$(
				$MODBIN/jq \
					--arg am $am \
					'.agmode_per_app_configuration[]
            | select(.packages[] == $am) | .swap' \
					$CONFIG | sed 's/[^0-9]*//g'
			)

			{
				[ -n "$swap_size" ] && [[ $swap_size != null ]] && {
					length=$(
						$MODBIN/jq \
							'.agmode_per_app_configuration | length' \
							$CONFIG
					)

					for conf_index in $(seq 0 $((length - 1))); do
						# shellcheck disable=SC2016
						$MODBIN/jq --argjson index $conf_index \
							'.agmode_per_app_configuration[$index]' \
							$CONFIG | grep -qw $am && index=$conf_index
					done

					ag_swap="$LOGDIR/${index}_swap"

					[ ! -f $ag_swap ] && {
						dd if=/dev/zero of="$ag_swap" bs=1M \
							count=$swap_size
						chmod 0600 $ag_swap
						$BIN/mkswap -L meZram-swap $ag_swap
					}

					kill -9 $swapoff_pid
					swapon $ag_swap && logger "SWAP is turned on"
				}
			} || [ $swap_size = null ] && [ -f $ag_swap ] && {
				rm -f $ag_swap &&
					logger "$ag_swap deleted because of config"
			}

			apply_aggressive_mode $ag_app &&
				logger i "aggressive mode activated for $fg_app"

			prev_waitt=$(convert $(cat $sltemp))
			# restart wait_time and some variables
			# if new am app is opened
			kill -9 $sleep_pid && logger "sleep started over"
			unset restoration sleep_pid

			# set current am app
			am=$ag_app
			# shellcheck disable=SC2016
			# read wait_time per app from the config
			# wait_time is intended to prevent app from being closed
			# by system while doing multitasking
			wait_time=$(
				$MODBIN/jq \
					--arg am "$am" \
					'.agmode_per_app_configuration[]
          | select(.packages[] == $am) | .wait_time' \
					$CONFIG | sed 's/"//g'
			)

			# if wait_time per app is not set the read wait_time
			[[ $wait_time = null ]] ||
				[ -z $wait_time ] && {
				wait_time=$(
					$MODBIN/jq \
						'.wait_time' $CONFIG | sed 's/"//g'
				)
			}

			current_waitt=$(convert $wait_time)

			[ $current_waitt -gt $prev_waitt ] && {
				rm $sltemp
				echo $wait_time >$sltemp
			}

			[ ! -f $sltemp ] && echo $wait_time >$sltemp
		}

		# check if am is activated
		[ -n "$am" ] && {
			# if theres no am app curently open or in foreground
			# and wait_time is not running
			# then restore states and variables
			! read_agmode_app && {
				[ $restoration -eq 1 ] && [ ! -f $sltemp ] && {
					restore_battery_opt
					restore_props &&
						logger i "aggressive mode deactivated"
					unset am restoration sleep_pid ag_apps
					{
						swapoff $ag_swap && logger "$ag_swap turned off"
					} &
					swapoff_pid=$!
				}

				# the logic is to make it only run once after
				# aggressive mode activated
				[ -f $sltemp ] && [ -z $sleep_pid ] &&
					[ $(cat $sltemp) != 0 ] && {
					logger \
						"wait $(cat $sltemp) before exiting aggressive mode"
					# never use variable for a subshell, i got really
					# annoying trouble because i forgot of this fact
					{
						sleep $(cat $sltemp) && rm $sltemp
					} &
					# restore if wait_time is done
					sleep_pid=$!
					restoration=1
				}
			}
		}
	}
	# after optimizing the code i reduce sleep from 6 to 1 and
	# still don't know why it's has performance issue last time
	# big idiot big smile :) big brain
	sleep 1
done &

resetprop meZram.aggressive_mode.pid $!

# sync service because i can't read from internal
# for some reason? tell me why please
while true; do
	is_update=$(cp -uv /sdcard/meZram-config.json /data/adb/meZram/meZram-config.json)

	echo $is_update | $BIN/fgrep -wo ">" &&
		logger i "config updated"
	sleep 1
done &

# save the service pid
# TODO make option to kill all service in agmode command
resetprop meZram.config_sync.pid $!
