# shellcheck disable=SC3010,SC3060,SC3043,SC2086,SC2046
. $MODDIR/modules/lmk.sh

ag_reswapon() {
	local swapf=$1

	! resetprop meZram.ag_swapon.pid && {
		while true; do
			{
				$BIN/swapon -p 68 "$swapf" && {
					logger "$swapf is turned on"
					touch /data/local/tmp/meZram_ag_swapon
					resetprop -d meZram.ag_swapon.pid
					break
				}
			} || {
				! resetprop meZram.swapoff_service_pid &&
					$BIN/swapon -p 68 "$swapf" 2>&1 |
					grep -q busy && {
					resetprop -d meZram.ag_swapon.pid
					break
				}
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
			swapoff_pids=/data/local/tmp/swapoff_pids
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
			echo "" >/data/local/tmp/swapoff_pids

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
					$BIN/swapon -p 68 $swap 2>&1 | logger &&
						logger "$swap is turned on" &&
						touch /data/local/tmp/meZram_ag_swapon
				done
			} || $BIN/swapon -p 68 $ag_swap 2>&1 | logger &&
				logger "$ag_swap is turned on" &&
				touch /data/local/tmp/meZram_ag_swapon
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
	echo $swap_count >/data/local/tmp/swap_count
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

			[ $usage -le $limit_in_kb ] &&
				[ $(cat /data/local/tmp/swap_count) -gt 0 ] && {
				{
					swap_count=$((swap_count - 1))
					echo $swap_count >/data/local/tmp/swap_count
					swapoff $swap 2>&1 | logger &&
						logger "$swap turned off"
				} &
				echo $! >>/data/local/tmp/swapoff_pids
			}

			[ $usage -gt $limit_in_kb ] &&
				[ -z $swapoff_wait ] && {
				logger "$usage > $limit_in_kb"
				logger "waiting usage to go down. clear your recents for faster swapoff"
				swapoff_wait=1
			}

			[ -z $usage ] && {
				echo $(($(cat /data/local/tmp/swap_count) - 1)) \
					>/data/local/tmp/swap_count
				swaps=$(echo "$swaps" | grep -wv $swap)
			}
		done

		[ $(cat /data/local/tmp/swap_count) -le 0 ] && {
			resetprop -d meZram.swapoff_service_pid
			rm /data/local/tmp/meZram_ag_swapon
			unset swapoff_wait
			break
		}
		sleep 1
	done && logger "swapoff service closed" &
	resetprop -n -p meZram.swapoff_service_pid $!
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
			! $BIN/fgrep $ag_app /data/local/tmp/am_apps &&
				echo $ag_app >>/data/local/tmp/am_apps
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
		echo $am >/data/local/tmp/meZram_am

		! resetprop meZram.rescue_service.pid &&
			[ $quick_restore = null ] && {
			logger "starting rescue_service"
			logger "in case you messed up or i messed up"
			rescue_limit=$($MODBIN/jq .rescue_limit $CONFIG)
			rescue_limit=$(($rescue_limit * 1024))

			while true; do
				# calculate memory and swap free and or available
				swap_free=$(free | awk '/Swap:/ {print $4}')
				mem_available=$(free | awk '/Mem:/ {print $7}')
				totalmem_vir_avl=$(((\
					swap_free + mem_available) / 1024))

				[ $mem_available -le $rescue_limit ] && {
					meZram_am=$(cat /data/local/tmp/meZram_am)

					logger w \
						"critical event reached, rescue initiated"
					logger \
						"${totalmem_vir_avl}MB of vir_avl left"
					logger \
						"$((mem_available / 1024))MB of RAM left"

					restore_props
					restore_battery_opt

					while true; do
						if [ $(free | awk '/Mem:/ {print $7}') -gt \
							$rescue_limit ]; then
							agm=1
							break
						elif [[ $(cat /data/local/tmp/meZram_am) != $meZram_am ]]; then
							break
						fi
						sleep 1
					done

					if [ $agm -eq 1 ]; then
						apply_aggressive_mode $meZram_am
						logger \
							"aggressive mode reactivated for $meZram_am"
						unset agm
					fi
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
				for app in $(cat /data/local/tmp/am_apps); do
					[ -z $agp_alive ] &&
						pidof $app && {
						agp_alive=1
						[ -z $agp_log ] && {
							# shellcheck disable=SC2005
							logger \
								"am apps = $(echo $(cat /data/local/tmp/am_apps))"
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
						echo "" >/data/local/tmp/swapoff_pids

						[ -f /data/local/tmp/meZram_ag_swapon ] && {
							swapoff_service
						}

						kill -15 $rescue_service_pid | logger &&
							logger "rescue_service killed"
						resetprop -d meZram.rescue_service.pid
						echo "" >/data/local/tmp/am_apps
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
