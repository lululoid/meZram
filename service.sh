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

ag_reswapon() {
	local swapf=$1

	! resetprop meZram.ag_swapon.pid && {
		while true; do
			swapon $swapf && {
				logger "$swapf is turned on"
				touch /data/tmp/meZram_ag_swapon
				resetprop -d meZram.ag_swapon.pid
				break
			}
			sleep 1
		done &
		resetprop meZram.ag_swapon.pid $!
	}
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
			ag_reswapon "$ag_swap"
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
			swapoff_pids=/data/tmp/swapoff_pids
			# shellcheck disable=SC2116,SC2013
			for pid in $(cat $swapoff_pids); do
				while kill -0 $pid; do
					[ -z $logged ] && {
						logger "waiting swapoff_pid $pid closed"
						logged=1
					}
					sleep 1
				done && unset logged
			done
			echo "" >/data/tmp/swapoff_pids

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
				awk -v swap="$swap" \
					'$1 == swap {print $4}' /proc/swaps
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
			resetprop -d meZram.swapoff_service_pid
			rm /data/tmp/meZram_ag_swapon
			echo "" >/data/tmp/swapping_off
			unset swapoff_wait
			break
		}
		sleep 1
	done && logger "swapoff service killed" &
	resetprop -n -p meZram.swapoff_service_pid $!
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
	sleep 1
done &

# save the pid to a prop
resetprop -n -p meZram.log_rotator.pid $!

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
echo "" >/data/tmp/swapoff_pids
echo "" >/data/tmp/swapping_off
echo "" >/data/tmp/am_apps

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
            | .quick_restore' $CONFIG
		)

		# the logic is to make it only run once after
		# aggressive mode activated
		[ $quick_restore = true ] && {
			restore_battery_opt
			kill -15 $rescue_service_pid 2>&1 | logger && logger \
				"rescue service killed because quick_restore"
			resetprop -d meZram.rescue_service.pid
			swapoff_service

			! kill -0 $no_whitelisting && {
				while pidof $ag_app; do
					sleep 1
				done && resetprop -d meZram.no_whitelisting.pid &

				no_whitelisting=$!
				logger "no_whitelisting because quick_restore"
				resetprop -n -p meZram.no_whitelisting.pid \
					$no_whitelisting
			}
		}

		[ $quick_restore = null ] && {
			! $BIN/fgrep $ag_app /data/tmp/am_apps &&
				echo $ag_app >>/data/tmp/am_apps
		}

		ag_swapon
		# swap should be turned on first to accomodate lmkd
		apply_aggressive_mode $ag_app &&
			logger "aggressive mode activated for $ag_app"
		# reset variables if new am app is opened
		unset restoration agp_log

		# set current am app
		am=$ag_app

		# rescue service for critical thrashing
		echo $am >/data/tmp/meZram_am

		! resetprop meZram.rescue_service.pid &&
			[ $quick_restore = null ] && {
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

				[ $mem_psi -ge $rescue_mem_limit ] ||
					[ $io_psi -ge $rescue_limit ] ||
					[ $cpu_psi -ge $rescue_cpu_limit ] &&
					[ -z $rescue ] && {
					# calculate memory and swap free and or available
					swap_free=$(free | awk '/Swap:/ {print $4}')
					mem_available=$(free | awk '/Mem:/ {print $7}')
					totalmem_vir_avl=$(((\
						swap_free + mem_available) / 1024))
					logger w \
						"critical event reached, rescue initiated"
					logger \
						"${totalmem_vir_avl}MB of memory left"

					pressures=$(head /proc/pressure/*)
					logger "$pressures"
					restore_props
					restore_battery_opt
					rescue=1
				}

				[ $io_psi -lt $((rescue_limit - 1)) ] &&
					[ $mem_psi -lt $((rescue_mem_limit - 1)) ] &&
					[ -n "$rescue" ] && {
					meZram_am=$(cat /data/tmp/meZram_am)
					apply_aggressive_mode $meZram_am &&
						logger \
							"aggressive mode reactivated for $meZram_am"
					unset rescue
				}
				sleep 1
			done &
			rescue_service_pid=$!
			resetprop meZram.rescue_service.pid $rescue_service_pid
		}
	}

	# check if am is activated
	[ -n "$am" ] && {
		# if theres no am app curently open or in foreground
		# then restore states and variables
		! read_agmode_app && {
			[ $restoration -eq 1 ] && {
				# shellcheck disable=SC2013
				for app in $(cat /data/tmp/am_apps); do
					[ -z $agp_alive ] &&
						pidof $app && {
						agp_alive=1
						[ -z $agp_log ] && {
							# shellcheck disable=SC2005
							logger \
								"am apps = $(echo $(cat /data/tmp/am_apps))"
							logger "wait for all am apps closed"
							agp_log=1
						}
					}
				done

				{
					[ -z $agp_alive ] && {
						restore_props
						restore_battery_opt &&
							logger "aggressive mode deactivated"
						logger "am = $am"
						unset am restoration
						echo "" >/data/tmp/swapoff_pids

						[ -f /data/tmp/meZram_ag_swapon ] && {
							swapoff_service
						}

						kill -15 $rescue_service_pid | logger &&
							logger "rescue_service killed"
						resetprop -d meZram.rescue_service.pid
						echo "" >/data/tmp/am_apps
					}
				} || unset agp_alive
			}
			restoration=1
		}
	}
	# after optimizing the code i reduce sleep from 6 to 1 and
	# still don't know why it's has performance issue last time
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
