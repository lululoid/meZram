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
		dumpsys activity activities |
			$MODBIN/sed -n \
				'/\bResumedActivity\b/s/.*u0 \(.*\)\/.*/\1/p'
	)

	# check if current foreground app is in aggressive
	# mode config
	ag_app=$(
		$BIN/fgrep -wo $fg_app $CONFIG | $BIN/grep -v "^android$"
	)
}

ag_swapon() {
	# shellcheck disable=SC2016
	swap_path=$(
		$MODBIN/jq \
			--arg ag_app $ag_app \
			'.agmode_per_app_configuration[] |
        select(.packages[] == $ag_app) | .swap_path' $CONFIG |
			$MODBIN/jq -r 'select(. != null)'
	)
	ag_swap=$swap_path

	{
		[ -n "$swap_path" ] &&
			swapon $ag_swap 2>&1 | logger &&
			logger "$ag_swap is turned on" &&
			touch /data/tmp/meZram_ag_swapon
	} || {
		# shellcheck disable=SC2016
		swap_size=$(
			$MODBIN/jq \
				--arg ag_app $ag_app \
				'.agmode_per_app_configuration[]
        | select(.packages[] == $ag_app) | .swap' $CONFIG |
				$MODBIN/jq -r 'select(. != null)'
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

	[ -z $swap_path ] && {
		[ -n "$swap_size" ] && {
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
				echo $($MODBIN/jq \
					'.agmode_per_app_configuration[].swap_path' \
					$CONFIG | $MODBIN/jq -r 'select(. != null)')
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

		[ -z $swap_size ] && [ -f $ag_swap ] && {
			rm -f $ag_swap 2>&1 | logger &&
				logger "$ag_swap deleted because of config"
		}
	}
}

swapoff_service() {
	local limit_in_kb swaps swap_count usage
	limit_in_kb=71680
	# shellcheck disable=SC2005
	swaps=$(
		$MODBIN/jq \
			'.agmode_per_app_configuration[].swap_path' \
			"$CONFIG" | $MODBIN/jq -r 'select(. != null)'
	)
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

			! $BIN/fgrep -q "$swap" /data/tmp/swapping_off && {
				[ $usage -le $limit_in_kb ] && {
					{
						swapoff $swap 2>&1 | logger &&
							logger "$swap turned off"
						swap_count=$((swap_count - 1))
						echo $swap_count >/data/tmp/swap_count
					} &
					echo $! >>/data/tmp/swapoff_pids
					echo "$swap" >>/data/tmp/swapping_off
				}

				[ $usage -gt $limit_in_kb ] &&
					[ -z $swapoff_wait ] && {
					logger "$usage > $limit_in_kb"
					logger "waiting usage to go down. clear your recents for faster swapoff"
					swapoff_wait=1
				}
			}

			[ -z $usage ] && {
				echo $(($(cat /data/tmp/swap_count) - 1)) \
					>/data/tmp/swap_count
				swaps=$(echo "$swaps" | grep -wv $swap)
			}
		done

		[ $(cat /data/tmp/swap_count) -le 0 ] && {
			resetprop --delete meZram.swapoff_service_pid
			logger "killing swapoff service"
			rm /data/tmp/meZram_ag_swapon
			echo "" >/data/tmp/swapping_off
			unset swapoff_wait
			break
		}
		sleep 1
	done &
	resetprop -p meZram.swapoff_service_pid $!
}

# Extract values from /proc/pressure using sed
read_pressure_value() {
	local pressure_file="$1"
	sed 's/some avg10=\([0-9.]*\).*/\1/;2d' $pressure_file
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
		resetprop -p meZram.lmkd_logger.pid $lmkd_logger_pid
	}
	meZram_logger_pid=$(/system/bin/ps -p $meZram_logger_pid \
		2>/dev/null | sed '1d' | tail -n 1 | awk '{print $2}')
	[ -z $meZram_logger_pid ] && {
		$BIN/logcat -v time -s meZram --file=$LOGDIR/meZram.log &
		meZram_logger_pid=$!
		resetprop -p meZram.logger.pid $meZram_logger_pid
	}

	# limit log size to 10MB then restart the service
	# if it's exceed it
	[ $lmkd_log_size -ge 10485760 ] && {
		kill -9 $lmkd_logger_pid
		mv $LOGDIR/lmkd.log "$LOGDIR/$today_date-lmkd.log"
		resetprop -p meZram.lmkd_logger.pid dead
	}

	[ $meZram_log_size -ge 10485760 ] && {
		kill -9 $meZram_logger_pid
		mv $LOGDIR/meZram.log "$LOGDIR/$today_date-meZram.log"
		resetprop -p meZram.logger.pid dead
	}

	logrotate $LOGDIR/*lmkd.log
	logrotate $LOGDIR/*meZram.log
	sleep 1
done &

# save the pid to a prop
resetprop -p meZram.log_rotator.pid $!

logger "NRDEVICES = $NRDEVICES"
logger "totalmem = $totalmem"
logger "zram_size = $zram_size"
logger "lmkd_pid = $lmkd_pid"

# looking for existing zram path
for zram0 in /dev/block/zram0 /dev/zram0; do
	[ "$(ls $zram0)" ] && {
		swapoff $zram0 2>&1 | logger &&
			logger "$zram0 turned off"
		echo 1 >/sys/block/zram0/reset &&
			logger "$zram0 RESET"
		# Set up zram size, then turn on both zram and swap
		echo $zram_size >/sys/block/zram0/disksize &&
			logger "set $zram0 disksize to $zram_size"
		# Set up maxium cpu streams
		logger \
			"making $zram0 and set max_comp_streams=$NRDEVICES"
		echo $NRDEVICES >/sys/block/zram0/max_comp_streams
		mkswap $zram0
		$BIN/swapon -p 69 "$zram0" && logger "$zram0 turned on"
		break
	}
done

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
restore_battery_opt
rm /data/tmp/swapoff_pids
echo "" >/data/tmp/swapping_off

# aggressive mode service starts here
while true; do
	# if the foreground app match app in aggressive mode list
	# then activate aggressive mode
	read_agmode_app && [[ $ag_app != "$am" ]] && {
		# am = aggressive mode, if am is not activated or
		# am is different than the last am then
		# activate aggressive mode
		# this is for efficiency reason
		# shellcheck disable=SC2016
		quick_restore=$(
			$MODBIN/jq \
				--arg ag_app $ag_app \
				'.agmode_per_app_configuration[]
            | select(.packages[] == $ag_app)
            | .quick_restore' $CONFIG |
				$MODBIN/jq -r 'select(. != null)'
		)

		# the logic is to make it only run once after
		# aggressive mode activated
		[ $quick_restore ] && {
			resetprop meZram.rescue_service.pid &&
				kill -9 \
					$(resetprop meZram.rescue_service.pid) 2>&1 |
				logger && logger \
				"rescue service killed because quick_restore"
			resetprop --delete meZram.rescue_service.pid
			swapoff_service

			! $MODBIN/ps -p $no_whitelisting && {
				while pidof $ag_app; do
					sleep 1
				done && resetprop -d meZram.no_whitelisting.pid &

				no_whitelisting=$!
				logger "no_whitelisting because quick_restore"
				resetprop -p meZram.no_whitelisting.pid \
					$no_whitelisting
			}
		}

		[ -z $quick_restore ] &&
			resetprop meZram.swapoff_service_pid &&
			kill -9 $(resetprop meZram.swapoff_service_pid) 2>&1 |
			logger && {
			resetprop -d meZram.swapoff_service_pid
			logger "swapoff_service is killed"
		}

		ag_swapon
		# swap should be turned on first to accomodate lmkd
		apply_aggressive_mode $ag_app &&
			logger "aggressive mode activated for $ag_app"
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
		echo $am >/data/tmp/meZram_am

		[ -z $rescue_service_pid ] &&
			[ -z $quick_restore ] && {
			logger "starting rescue_service"
			logger "in case you messed up or i messed up"
			rescue_limit=$($MODBIN/jq .rescue_limit $CONFIG)
			rescue_mem_limit=$(
				$MODBIN/jq .rescue_mem_limit $CONFIG
			)
			rescue_cpu_limit=$(
				$MODBIN/jq .rescue_cpu_limit $CONFIG
			)

			while true; do
				io_psi=$(read_pressure_value /proc/pressure/io)
				mem_psi=$(read_pressure_value /proc/pressure/memory)
				cpu_psi=$(read_pressure_value /proc/pressure/cpu)
				is_io_rescue=$(awk \
					-v rescue_limit="${rescue_limit}" \
					-v io_psi="${io_psi}" \
					'BEGIN {
              if (io_psi >= rescue_limit) {
        				print "true"
        			} else {
        				print "false"
        			}
        	}')
				is_mem_rescue=$(awk \
					-v rescue_mem_limit="${rescue_mem_limit}" \
					-v mem_psi="${mem_psi}" \
					'BEGIN {
              if (mem_psi >= rescue_mem_limit) {
        				print "true"
        			} else {
        				print "false"
        			}
        	}')
				is_cpu_rescue=$(awk \
					-v rescue_cpu_limit="${rescue_cpu_limit}" \
					-v cpu_psi="${cpu_psi}" \
					'BEGIN {
              if (cpu_psi >= rescue_cpu_limit) {
        				print "true"
        			} else {
        				print "false"
        			}
        	}')

				$is_mem_rescue || $is_io_rescue || $is_cpu_rescue &&
					[ -z $rescue ] && {
					# calculate memory and swap free and or available
					swap_free=$(
						free | $BIN/fgrep Swap | awk '{print $4}'
					)
					mem_available=$(
						free | $BIN/fgrep Mem | awk '{print $7}'
					)
					totalmem_vir_avl=$(((\
						swap_free + mem_available) / 1024))
					logger w \
						"critical event reached, rescue initiated"
					logger \
						"${totalmem_vir_avl}MB of memory left"

					pressures=$(head /proc/pressure/*)
					logger "$pressures"
					restore_props && rescue=1
				}

				! $is_io_rescue && ! $is_mem_rescue &&
					[ -n "$rescue" ] && {
					meZram_am=$(cat /data/tmp/meZram_am)
					apply_aggressive_mode $meZram_am &&
						logger \
							"aggressive mode reactivated for $meZram_am"
					unset rescue
				}
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
			[ $restoration -eq 1 ] &&
				! $MODBIN/ps -p $persist_pid && {
				restore_props
				restore_battery_opt &&
					logger i "aggressive mode deactivated"
				logger "am = $am"
				unset am restoration persist_pid
				rm /data/tmp/swapoff_pids

				[ -f /data/tmp/meZram_ag_swapon ] && {
					swapoff_service
				}

				kill -9 $(resetprop meZram.rescue_service.pid) |
					logger && logger "rescue_service dead"
				resetprop --delete meZram.rescue_service.pid
			}

			# read quick_restore
			# shellcheck disable=SC2016
			quick_restore=$(
				$MODBIN/jq -r \
					--arg am $am \
					'.agmode_per_app_configuration[]
            | select(.packages[] == $am)
            | .quick_restore' $CONFIG
			)

			# the logic is to make it only run once after
			# aggressive mode activated
			[ $quick_restore = null ] &&
				[ -z $persist_pid ] && {
				logger \
					"wait $am to close before exiting aggressive mode"
				# never use variable for a subshell, i got really
				# annoying trouble because i forgot of this fact
				while pidof $am; do
					sleep 1
				done &
				# restore if persist_service is done
				persist_pid=$!
			}
			restoration=1
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
	cp -uv /sdcard/meZram-config.json \
		/data/adb/meZram/meZram-config.json |
		$BIN/fgrep -wo ">" &&
		logger "config updated"
	sleep 1
done &

# save the service pid
# TODO make option to kill all service in agmode command
resetprop meZram.config_sync.pid $!
