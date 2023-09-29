# shellcheck disable=SC3010,SC3060,SC3043,SC2086,SC2046
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
totalmem=$(
	free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'
)
zram_size=$((totalmem * 1024 / 2))
lmkd_pid=$(pidof lmkd)

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
		dumpsys activity | $BIN/fgrep -w ResumedActivity |
			awk '{print $4}' | awk -F/ '{print $1}'
	)

	# check if current foreground app is in aggressive
	# mode config
	ag_app=$($BIN/fgrep -wo $fg_app $CONFIG)
}

ag_swapon() {
	# shellcheck disable=SC2016
	swap_path=$(
		$MODBIN/jq -r \
			--arg ag_app $ag_app \
			'.agmode_per_app_configuration[] |
    select(.packages[] == $ag_app) | .swap_path' $CONFIG
	)
	ag_swap=$swap_path

	{
		[ -n "$swap_path" ] && [[ $swap_path != null ]] &&
			swapon $ag_swap 2>&1 | logger &&
			logger "$ag_swap is turned on" &&
			touch /data/tmp/meZram_ag_swapon
	} || {
		# shellcheck disable=SC2016
		swap_size=$(
			$MODBIN/jq \
				--arg ag_app $ag_app \
				'.agmode_per_app_configuration[]
      | select(.packages[] == $ag_app) | .swap' $CONFIG
		)

		length=$(
			$MODBIN/jq \
				'.agmode_per_app_configuration | length' $CONFIG
		)

		for conf_index in $(seq 0 $((length - 1))); do
			# shellcheck disable=SC2016
			$MODBIN/jq --argjson index $conf_index \
				'.agmode_per_app_configuration[$index]' \
				$CONFIG | grep -qw $ag_app && {
				index=$conf_index
				break
			}
		done
		ag_swap="$LOGDIR/${index}_swap"
	}

	[ $swap_path = null ] || [ -z $swap_path ] && {
		[ -n "$swap_size" ] && [[ $swap_size != null ]] && {
			swapoff_pids=$(cat /data/tmp/swapoff_pids)
			# shellcheck disable=SC2116
			for pid in $(echo $swapoff_pids); do
				kill -9 $pid 2>&1 | logger &&
					logger "swapoff_pid $pid killed"
			done
			rm /data/tmp/swapoff_pids

			[ -f $ag_swap ] && {
				ag_swap_size=$(($(wc -c $ag_swap |
					awk '{print $1}') / 1024 / 1024))
				[ $ag_swap_size -ne $swap_size ] && {
					logger "resizing $ag_swap, please wait.."
					logger "aggressive_mode won't work for some time"
					swapoff $ag_swap 2>&1 | logger && rm -f $ag_swap |
						logger && logger "$ag_swap removed"
				}
			}

			# shellcheck disable=SC2005
			swap_list=$(
				echo $($MODBIN/jq -r \
					'.agmode_per_app_configuration[].swap_path' \
					$CONFIG | grep -wv null)
			)

			meZram_tswap=0

			for swap in $swap_list; do
				[ -f $swap ] && {
					size=$((\
						$(wc -c $swap | awk '{print $1}') / 1024 / 1024))
					meZram_tswap=$((meZram_tswap + size))
				}
			done

			logger "ag_swap = $ag_swap"
			logger "swap_size = $swap_size"
			logger "swap_list = $swap_list"
			logger "meZram_tswap = $meZram_tswap"

			[ $swap_size -le $meZram_tswap ] ||
				[ $swap_size -ge $((meZram_tswap + 256)) ] &&
				[ ! -f $ag_swap ] && {
				logger "making $swap_size $ag_swap. please wait..."
				dd if=/dev/zero of="$ag_swap" bs=1M count=$swap_size
				chmod 0600 $ag_swap
				$BIN/mkswap -L meZram-swap $ag_swap 2>&1 | logger
				# shellcheck disable=SC2016
				$MODBIN/jq \
					--arg ag_swap $ag_swap \
					--argjson index $index \
					'.agmode_per_app_configuration[$index].swap_path
          |= $ag_swap' $CONFIG | /system/bin/awk \
					'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG_INT
				cp -f $CONFIG_INT $CONFIG
			}

			[ $swap_size -ge $meZram_tswap ] && {
				for swap in $swap_list; do
					swapon $swap 2>&1 | logger &&
						logger "$swap is turned on" &&
						touch /data/tmp/meZram_ag_swapon
				done
			} || swapon $ag_swap 2>&1 | logger &&
				logger "$ag_swap is turned on" &&
				touch /data/tmp/meZram_ag_swapon
		}

		[ -z $swap_size ] || [ $swap_size = null ] &&
			[ -f $ag_swap ] && {
			rm -f $ag_swap 2>&1 | logger &&
				logger "$ag_swap deleted because of config"
		}
	}
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

logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "zram_size = $zram_size"
logger "lmkd_pid = $lmkd_pid"

# looking for existing zram path
for zram0 in /dev/block/zram0 /dev/zram0; do
	[ "$(ls $zram0)" ] && {
		swapoff $zram0 2>&1 | logger &&
			logger i "$zram0 turned off"
		echo 1 >/sys/block/zram0/reset &&
			logger i "$zram0 RESET"
		# Set up zram size, then turn on both zram and swap
		echo $zram_size >/sys/block/zram0/disksize &&
			logger i "set $zram0 disksize to $zram_size"
		# Set up maxium cpu streams
		logger i \
			"making $zram0 and set max_comp_streams=$NRDEVICES"
		echo $NRDEVICES >/sys/block/zram0/max_comp_streams
		mkswap $zram0
		$BIN/swapon -p 69 "$zram0" && logger i "$zram0 turned on"
		break
	}
done

swapon /data/swap_file 2>&1 | logger &&
	logger i "swap is turned on"

tl=ro.lmk.thrashing_limit

# thrashing limit has no effect in MIUI
while true; do
	[ $(resetprop sys.boot_completed) -eq 1 ] && {
		lmkd_props_clean
		[ $(resetprop ro.miui.ui.version.code) ] && {
			rm_prop $tl &&
				logger i \
					"MIUI not support thrashing_limit customization"
		}
		custom_props_apply
		$BIN/lmkd --reinit &&
			logger i "custom props applied"
		break
	}
	sleep 1
done

logger i "jq_version = $($MODBIN/jq --version)"
# reset states and variables to default
restore_battery_opt
rm /data/tmp/swapoff_pids
rm /data/tmp/meZram_skip_swap

# aggressive mode service starts here
while true; do
	# Read configuration for aggressive mode
	agmode=$(sed -n 's/"agmode": "\(.*\)",/\1/p' $CONFIG)

	[ $agmode = on ] && {
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
			quick_restore=$(
				$MODBIN/jq \
					--arg ag_app $ag_app \
					'.agmode_per_app_configuration[]
            | select(.packages[] == $ag_app)
            | .quick_restore' $CONFIG
			)

			# the logic is to make it only run once after
			# aggressive mode activated
			[ $quick_restore = true ] && {
				touch /data/tmp/meZram_skip_swap
				kill -9 $(resetprop meZram.rescue_service.pid) 2>&1 |
					logger && logger \
					"rescue service killed because quick_restore"
				resetprop meZram.rescue_service.pid dead
			}

			[ ! -f /data/tmp/meZram_skip_swap ] && ag_swapon
			# swap should be turned on first to accomodate lmkd
			apply_aggressive_mode $ag_app &&
				logger i "aggressive mode activated for $fg_app"
			# restart persist_service and some variables
			# if new am app is opened
			kill -9 $persist_pid && logger "persist reset"
			unset restoration persist_pid

			# set current am app
			am=$ag_app
			rescue_service_pid=$(
				resetprop meZram.rescue_service.pid
			)

			# rescue service for critical thrashing
			# calculate total memory + virtual memory
			echo $am >/data/tmp/meZram_am

			[ -z $rescue_service_pid ] ||
				[ $rescue_service_pid = dead ] &&
				[ $quick_restore = null ] && {
				logger "starting rescue_service"
				logger "in case you messed up or i messed up"
				total_swap=$(
					free | $BIN/fgrep Swap | awk '{print $2}'
				)
				totalmem_vir=$((totalmem + total_swap))
				rescue_limit=$($MODBIN/jq .rescue_limit $CONFIG)

				while true; do
					# calculate memory and swap free and or available
					swap_free=$(free | $BIN/fgrep Swap |
						awk '{print $4}')
					mem_available=$(
						free | $BIN/fgrep Mem | awk '{print $7}'
					)
					totalmem_vir_avl=$((swap_free + mem_available))
					mem_left=$((totalmem_vir_avl * 1000 / totalmem_vir))

					{
						[ $mem_left -le $((rescue_limit * 10)) ] &&
							[ -z $rescue ] && {
							logger w \
								"critical event reached, rescue initiated"
							logger \
								"$((totalmem_vir_avl / 1024))MB of memory left"
							restore_props
							meZram_am=$(cat /data/tmp/meZram_am)
							apply_aggressive_mode $meZram_am &&
								logger \
									"aggressive mode activated for $meZram_am"
							rescue=1
						}
					} || unset rescue
					sleep 1
				done &
				resetprop meZram.rescue_service.pid $!
			}
		}

		# check if am is activated
		[ -n "$am" ] && {
			# if theres no am app curently open or in foreground
			# and persist_service is not running
			# then restore states and variables
			! read_agmode_app && {
				persist_ps=$($BIN/ps -p $persist_pid | sed 1d)
				[ $restoration -eq 1 ] && [ -z $persist_ps ] && {
					restore_battery_opt
					restore_props &&
						logger i "aggressive mode deactivated"
					unset am restoration persist_pid
					rm /data/tmp/meZram_skip_swap

					[ -f /data/tmp/meZram_ag_swapon ] && {
						limit_in_kb=51200
						# shellcheck disable=SC2005
						swaps=$($MODBIN/jq -r \
							'.agmode_per_app_configuration[].swap_path' \
							$CONFIG | grep -wv null)
						swap_count=$(echo "$swaps" | wc -l)
						echo $swap_count >/data/tmp/swap_count
						# shellcheck disable=SC2116
						logger "swaps = $(echo $swaps)"
						logger "swap_count = $swap_count"

						while true; do
							# shellcheck disable=SC2116
							for swap in $(echo $swaps); do
								usage=$(
									grep $swap /proc/swaps | awk '{print $4}'
								)

								[ -n "$usage" ] && {
									{
										[ $usage -le $limit_in_kb ] &&
											{
												swapoff $swap 2>&1 | logger &&
													logger "$swap turned off"
												swap_count=$((swap_count - 1))
												echo $swap_count >/data/tmp/swap_count
											} &
										echo $! >>/data/tmp/swapoff_pids
									} || {
										logger "$usage > $limit_in_kb"
										logger "waiting usage to go down. clear your recents for faster swapoff"
									}
								}

								[ -z $usage ] && {
									swap_count=$((\
										$(cat /data/tmp/swap_count) - 1))
									swaps=$(echo "$swaps" | grep -wv $swap)
									echo $swap_count >/data/tmp/swap_count
								}
							done

							[ $(cat /data/tmp/swap_count) -le 0 ] && {
								resetprop meZram.swapoff_service_pid dead
								logger "killing swapoff service"
								rm /data/tmp/meZram_ag_swapon
								break
							}
							sleep 1
						done &
						swapoff_service_pid=$!
						resetprop meZram.swapoff_service_pid \
							$swapoff_service_pid
						kill -9 $(resetprop meZram.rescue_service.pid) |
							logger && logger "rescue_service dead"
						resetprop meZram.rescue_service.pid dead
					}
				}

				# read quick_restore
				# shellcheck disable=SC2016
				quick_restore=$(
					$MODBIN/jq \
						--arg am $am \
						'.agmode_per_app_configuration[]
            | select(.packages[] == $am)
            | .quick_restore' $CONFIG
				)

				# the logic is to make it only run once after
				# aggressive mode activated
				[ -z $quick_restore ] ||
					[ $quick_restore = null ] &&
					[ -n "$(pidof $am)" ] &&
					[ -z $persist_pid ] && {
					logger \
						"wait $am to close before exiting aggressive mode"
					# never use variable for a subshell, i got really
					# annoying trouble because i forgot of this fact
					while true; do
						[ -z $(pidof $am) ] && break
						sleep 1
					done &
					# restore if persist_service is done
					persist_pid=$!
				}
				restoration=1
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
	is_update=$(
		cp -uv /sdcard/meZram-config.json \
			/data/adb/meZram/meZram-config.json
	)

	echo $is_update | $BIN/fgrep -wo ">" &&
		logger i "config updated"
	sleep 1
done &

# save the service pid
# TODO make option to kill all service in agmode command
resetprop meZram.config_sync.pid $!
