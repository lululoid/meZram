# shellcheck disable=SC3043,SC2034,SC2086,SC3060,SC3010,SC2046
SKIPUNZIP=1
totalmem=$(
	free | grep -e "^Mem:" |
		sed -e 's/^Mem: *//' -e 's/  *.*//'
)
MODBIN=$MODPATH/modules/bin

unzip -o $ZIPFILE -x 'META-INF/*' -d $MODPATH >&2
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive $MODPATH/system/bin 0 2000 0755 0755
set_perm_recursive $MODPATH/modules/bin 0 2000 0755 0755
set_perm_recursive $MODPATH/modules/lmk.sh 0 2000 0755 0755
set_perm_recursive $MODPATH/meZram.sh 0 2000 0755 0755

# Setup modules
. $MODPATH/modules/lmk.sh

log_it() {
	log=$(echo "$*" | tr -s " ")
	true && ui_print "  DEBUG: $log"
}

rm_prop() {
	for prop in "$@"; do
		resetprop "$prop" >/dev/null && resetprop --delete "$prop" &&
			log_it "$prop deleted"
	done
}

lmkd_apply() {
	# determine if device is lowram?
	log_it "totalmem = $totalmem"
	if [ $totalmem -lt 2097152 ]; then
		ui_print "⚠️ Device is low ram. Applying low am tweaks"
		mv $MODPATH/system.props/low-ram-system.prop $MODPATH/system.prop
	else
		mv $MODPATH/system.props/high-performance-system.prop $MODPATH/system.prop
	fi

	# Properties to be removed
	set --
	set ro.config.low_ram \
		ro.lmk.use_psi \
		ro.lmk.use_minfree_levels \
		ro.lmk.low ro.lmk.medium \
		ro.lmk.critical \
		ro.lmk.critical_upgrade \
		ro.lmk.upgrade_pressure \
		ro.lmk.downgrade_pressure \
		ro.lmk.kill_heaviest_task \
		ro.lmk.kill_timeout_ms \
		ro.lmk.psi_partial_stall_ms \
		ro.lmk.psi_complete_stall_ms \
		ro.lmk.thrashing_limit \
		ro.lmk.thrashing_limit_decay \
		ro.lmk.swap_util_max \
		ro.lmk.swap_free_low_percentage \
		ro.lmk.debug \
		sys.lmk.minfree_levels
	rm_prop "$@"

	# applying lmkd tweaks
	grep -v '^ *#' <$MODPATH/system.prop |
		while IFS= read -r prop; do
			log_it "resetprop ${prop//=/ }"
			resetprop ${prop//=/ }
		done

	tl=ro.lmk.thrashing_limit
	if [ $(resetprop ro.miui.ui.version.code) ]; then
		rm_prop $tl
	fi

	$BIN/lmkd --reinit && ui_print "> lmkd reinitialized"
	ui_print "> lmkd multitasking tweak applied."
	ui_print "  Give the better of your RAM."
	ui_print "  RAM better being filled with something"
	ui_print "  useful than left unused"
	rm -rf $MODPATH/system.props
}

count_swap() {
	local one_gb=$((1024 * 1024))
	local totalmem_gb=$(((totalmem / 1024 / 1024) + 1))
	count=0
	local swap_in_gb=0
	swap_size=0

	ui_print "> Please select SWAP size"
	ui_print "  Press VOLUME + to DEFAULT"
	ui_print "  Press VOLUME - to SELECT"
	ui_print "  DEFAULT is no SWAP"

	while true; do
		# shellcheck disable=SC2069
		timeout 0.05 /system/bin/getevent -lqc 1 2>&1 \
			>$TMPDIR/events &
		g_event_pid=$!
		sleep 0.05
		(grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events) && {
			count=$((count + 1))

			if [ $count -eq 1 ]; then
				swap_size=0
				ui_print "  $count. No SWAP --> RECOMMENDED"
			elif [ $count -eq 2 ]; then
				swap_size=$((totalmem / 10))
				cat <<EOF
  $count. 10% of RAM ($((swap_size / 1024)))MB SWAP
EOF
			elif [ $count -eq 3 ]; then
				swap_size=$((totalmem / 2))
				cat <<EOF
  $count. 50% of RAM ($((swap_size / 1024)))MB SWAP
EOF
			elif [ $swap_in_gb -lt $totalmem_gb ]; then
				swap_in_gb=$((swap_in_gb + 1))
				cat <<EOF
  $count. ${swap_in_gb}GB of SWAP
EOF
				swap_size=$((swap_in_gb * one_gb))
			fi

			[ $swap_in_gb -ge $totalmem_gb ] && {
				swap_size=$totalmem
				swap_in_gb=0
				count=0
			}
		}
		(grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events) && {
			kill -9 $g_event_pid
			break
		}
	done
}

make_swap() {
	dd if=/dev/zero of="$2" bs=1024 count=$1 >/dev/null
	/system/bin/mkswap -L meZram-swap "$2" >/dev/null
}

config_update() {
	# Updating config
	local LOGDIR=/data/adb/meZram
	local CONFIG=$LOGDIR/meZram-config.json
	local CONFIG_OLD=$LOGDIR/meZram.conf
	local _CONFIG=/sdcard/meZram-config.json
	# shellcheck disable=SC2086,SC2046,SC2155
	local version=$(
		$MODPATH/modules/bin/jq '.config_version' \
			$MODPATH/meZram-config.json
	)
	# shellcheck disable=SC2086,SC2046,SC2155
	local version_prev=$(
		$MODPATH/modules/bin/jq '.config_version' $CONFIG
	)
	local loaded=true

	log_it "config version = $version"
	log_it "config version_prev = $version_prev"
	log_it "jq version = $($MODPATH/modules/bin/jq --version)"

	if [ -f $CONFIG_OLD ]; then
		mv -f $CONFIG_OLD /sdcard/$CONFIG_OLD.old &&
			ui_print "> Config moved to ${CONFIG_OLD}.old on internal"
	fi

	[ ! -f $CONFIG ] && {
		cp $MODPATH/meZram-config.json $CONFIG
		cp $CONFIG $_CONFIG &&
			ui_print "> Config is in internal root"
	}

	# Update if version is higher than previous version
	[ -n "$version_prev" ] && {
		is_update=$(awk -v version="${version}" \
			-v version_prev="${version_prev}" \
			'BEGIN {
			if (version > version_prev) {
				print "true"
			} else {
				print "false"
			}
		}')

		is_less_2=$(awk -v version=2.0 \
			-v version_prev="${version_prev}" \
			'BEGIN {
      if (version_prev < version) {
				print "true"
			} else {
				print "false"
			}
		}')

		is_less_v2dot4=$(awk -v version=2.4 \
			-v version_prev="${version_prev}" \
			'BEGIN {
      if (version_prev < version) {
				print "true"
			} else {
				print "false"
			}
		}')

		is_less_v3dot0=$(awk -v version=3.0 \
			-v version_prev="${version_prev}" \
			'BEGIN {
      if (version_prev < version) {
				print "true"
			} else {
				print "false"
			}
		}')
	}

	log_it "is_update = $is_update"
	log_it "is_less_2 = $is_less_2"
	log_it "is_less_v2dot4 = $is_less_v2dot4"
	log_it "is_less_v3dot0 = $is_less_v3dot0"

	{
		$is_update && {
			# Update config version
			ui_print "> Updating configuration"
			today_date=$(date +%R-%a-%d-%m-%Y)
			cp -f $_CONFIG ${_CONFIG}_$today_date.bcp
			ui_print "> Making backup ${_CONFIG}_$today_date.bcp"

			$is_less_2 && {
				# only do this onece for config version 2.0
				$MODPATH/modules/bin/jq \
					'{agmode: .agmode,
          wait_time: .wait_time,
          config_version: .config_version,
          custom_props: .custom_props,
          agmode_per_app_configuration: .agmode_per_app_configuration
          | group_by(.props)
          | map({
            packages: map(.package),
            props: .[0].props[0],
            wait_time: .[0].wait_time
          })
        }' $CONFIG |
					$MODPATH/modules/bin/jq \
						'del(.. | nulls)' |
					/system/bin/awk \
						'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG
			}

			$is_less_v2dot4 && {
				$MODPATH/modules/bin/jq \
					'del(.agmode_per_app_configuration[].wait_time)
          | del(.wait_time) | del(.rescue_limit)' $CONFIG |
					/system/bin/awk \
						'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG
			}

			$is_less_v3dot0 && {
				cp -f $MODPATH/meZram-config.json $CONFIG
				ui_print "  Sorry but config is reset"
				ui_print "  Your old config is ${_CONFIG}_$today_date.bcp"
				ui_print "  Config for various games is already set"
				ui_print "  Mobile Legends, Ace Racer, Terraria, Minecraft, etc."
				ui_print "  Please check config for more details"
				sleep 1
			}

			$MODPATH/modules/bin/jq \
				'del(.config_version)
        | del(.rescue_limit)
        | del(.rescue_mem_psi_limit)
        | del(.rescue_cpu_psi_limit)
        | del(.agmode)' "$CONFIG" |
				/system/bin/awk \
					'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG
			# Slurp entire config
			$MODPATH/modules/bin/jq \
				-s '.[0] * .[1]' $MODPATH/meZram-config.json $CONFIG |
				/system/bin/awk \
					'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG &&
				ui_print "> Configuration updated"
			ui_print "  Please reboot"
			cp -f $CONFIG $_CONFIG &&
				ui_print "> Config loaded"
		}
	} || {
		cp -u $_CONFIG $CONFIG &&
			$loaded && ui_print "> Config loaded" && unset loaded
	}

	$MODBIN/jq '.config_version' $CONFIG || abort "Update config failed"
}

# start installation
swap_filename=/data/swap_file
free_space=$(
	df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' |
		sed ':a;N;$!ba;s/\n/ /g' | awk '{print $3}'
)
log_it "$(df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' |
	sed ':a;N;$!ba;s/\n/ /g')"

ui_print ""
ui_print " Made with ❤ and 🩸 by "
sleep 0.5
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
sleep 0.5

[ -d "/data/adb/modules/meZram" ] && {
	ui_print "> Thank you so much 😊."
	ui_print "  You've installed this module before"
	[ -f $swap_filename ] && {
		cat <<EOF
  I don't recommend SWAP anymore."
  It's laggy, and increase I/O and mess with lmkd"
  Do you want to delete previous SWAP?"
  Volume + --> No"
  Volume - --> Yes"
EOF
		while true; do
			# shellcheck disable=SC2069
			timeout 0.05 /system/bin/getevent -lqc 1 2>&1 \
				>$TMPDIR/events &
			g_event_pid=$!
			sleep 0.05
			(grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events) && {
				# function to remove previous SWAP
				ui_print "> Removing SWAP in the background"
				sleep 1
				{
					swapoff $swap_filename && rm -f $swap_filename &&
						logger "$swap_filename is removed"
				} &
				break
			}
			(grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events) && {
				ui_print "> Hmm no huh! That's fine"
				kill -9 $g_event_pid
				break
			}
		done
	}
}

[ ! -d $NVBASE/meZram ] && {
	mkdir -p "$NVBASE/meZram" &&
		ui_print "> Folder $NVBASE/meZram is made"
}

# setup SWAP
[ ! -f $swap_filename ] && {
	# Ask user how much SWAP user want
	count_swap
	log_it "free space = $free_space"
	log_it "swap size = $swap_size"
	log_it "count = $count"
	# Making SWAP only if enough free space available
	{
		[ $free_space -ge $swap_size ] &&
			[ $swap_size -gt 0 ] && {
			ui_print "> Starting making SWAP. Please wait a moment"
			sleep 0.5
			cat <<EOF
  $((free_space / 1024))MB available.
  $((swap_size / 1024))MB needed
EOF
			make_swap $swap_size $swap_filename &&
				/system/bin/swapon $swap_filename
		}
	}

	[ $free_space -lt $swap_size ] && {
		ui_print "> Storage full. Please free up your storage"
	}

	# Handling bug on some devices
	[ -z $free_space ] && {
		cat <<EOF
> Make sure you have $((swap_size / 1024))MB of space
  available
  ui_print "  Make SWAP?"
	ui_print "  Volume + --> No"
	ui_print "  Volume - --> Yes"
EOF

		while true; do
			# shellcheck disable=SC2069
			timeout 0.05 /system/bin/getevent -lqc 1 2>&1 \
				>$TMPDIR/events &
			g_event_pid=$!
			sleep 0.05
			(grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events) && {
				ui_print \
					"> Starting making SWAP. Please wait a moment"
				sleep 0.5
				make_swap $swap_size $swap_filename &&
					/system/bin/swapon -p 5 $swap_filename >/dev/null
				ui_print "> SWAP is running"
				break
			}
			(grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events) && {
				cancelled=$(ui_print "> Not making SWAP")
				$cancelled && log_it "$cancelled"
				kill -9 $g_event_pid
				break
			}
		done
	}

	{
		# if no SWAP option selected, only pass
		[ $swap_size -eq 0 ] &&
			ui_print "> Not making any SWAP. Good"
	}
}

android_version=$(getprop ro.build.version.release)
log_it "android_version = $android_version"

{
	[ $android_version -lt 10 ] && {
		ui_print "> Your android version is not supported."
		ui_print "  Performance tweaks won't be applied."
		ui_print "  Please upgrade your phone to Android 10+"
	}
} || {
	lmkd_apply
	config_update
	custom_props_apply &&
		ui_print "> Custom props applied"
}

ui_print "> Enjoy :)"
ui_print "  Reboot and you're ready"
