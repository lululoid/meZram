#!/system/bin/sh
# shellcheck disable=SC3043,SC3060,SC2086
export MAGENTA='\033[0;35m'
export TURQUOISE='\033[1;36m'
export LIGHT_BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW_BAD='\033[33m'
export RESET='\033[0m'
export YELLOW='\033[93m'
BIN=/system/bin

# why I create this function?
is_number() {
	case $1 in
	'' | *[!0-9]*)
		return 1
		;;
	*)
		return 0
		;;
	esac
}

# make a line with the character given
liner() {
	printf '%*s' "$2" | tr ' ' "$1"
}

# make and the title in the middle of the line. yay !
titler() {
	text="$*"

	if [ -z "$text" ]; then
		text="Hello World!"
	fi

	text_length=${#text}
	liner_length=$((($(tput cols) / 2) - (text_length / 2) - 1))

	liner0=$(liner "-" "$liner_length")

	printf "%s" "$liner0" "$text" "$liner0"
	echo ""
}

logger() {
	local log=$2
	local p=$1
	true && {
		[ -z $log ] && {
			log="$1" && p=i
		}

		$BIN/log -p "$p" -t meZram "$log"
	}
}

# remove a bunch of props
rm_prop() {
	for prop in "$@"; do
		resetprop "$prop" >/dev/null &&
			resetprop --delete $prop && logger "$prop removed"
	done
}

# applying custom props specified in the config
custom_props_apply() {
	# i read local is more efficient
	local CONFIG=/data/adb/meZram/meZram-config.json
	local props
	local prop_value
	props=$(
		/data/adb/modules_update/meZram/modules/bin/jq \
			'.custom_props | keys[]' $CONFIG | sed 's/"//g'
	)

	# double props is to make sure always use the latest jq
	# my module provided even when just a module update
	if [ -z "$props" ]; then
		props=$(
			/data/adb/modules/meZram/modules/bin/jq \
				'.custom_props | keys[]' $CONFIG | sed 's/"//g'
		)
	fi

	# shellcheck disable=SC2116
	for prop in $(echo "$props"); do
		prop_value=$(
			/data/adb/modules_update/meZram/modules/bin/jq \
				--arg prop $prop \
				'.custom_props | .[$prop]' $CONFIG
		)

		[ -z "$prop_value" ] && {
			prop_value=$(
				/data/adb/modules/meZram/modules/bin/jq \
					--arg prop $prop \
					'.custom_props | .[$prop]' $CONFIG
			)
		}
		resetprop $prop $prop_value &&
			logger "$prop $prop_value applied"
	done
}

# clean safely removable lmkd props, i dont use array because
# magisk doesn't support it
lmkd_props_clean() {
	set --
	set \
		"ro.lmk.low" \
		"ro.lmk.medium" \
		"ro.lmk.critical_upgrade" \
		"ro.lmk.kill_heaviest_task" \
		"ro.lmk.kill_timeout_ms" \
		"ro.lmk.psi_partial_stall_ms" \
		"ro.lmk.psi_complete_stall_ms" \
		"ro.lmk.thrashing_limit_decay" \
		"ro.lmk.swap_util_max" \
		"sys.lmk.minfree_levels" \
		"ro.lmk.upgrade_pressure"
	rm_prop "$@"
}

# restore default battery optimization setting
restore_battery_opt() {
	local packages_list
	local status
	packages_list=$(
		$MODBIN/jq \
			'.agmode_per_app_configuration[].packages[]' \
			$CONFIG | sed 's/"//g'
	)

	# save the list to /data/adb/meZram
	while IFS= read -r pkg; do
		packages_list=$(echo "$packages_list" | grep -wv $pkg)
	done <$default_optimized_list

	for pkg in $packages_list; do
		# shellcheck disable=SC2154
		status=$(dumpsys deviceidle whitelist -$pkg)
		[ -n "$status" ] &&
			logger w "$pkg is battery_optimized"
	done

	unset default_opt_set
}

restore_props() {
	local default_dpressure
	default_dpressure=$(
		sed -n 's/^ro.lmk.downgrade_pressure=//p' $CONFIG
	)

	[ -z $default_dpressure ] && {
		default_dpressure=$(
			sed -n 's/^ro.lmk.downgrade_pressure=//p' \
				$MODDIR/system.prop
		)
	}

	lmkd_props_clean
	resetprop ro.lmk.downgrade_pressure $default_dpressure
	custom_props_apply && resetprop lmkd.reinit 1 &&
		logger "default props restored"
}

apply_aggressive_mode() {
	local ag_app=$1
	local papp_keys
	local value
	# shellcheck disable=SC2016
	papp_keys=$(
		$MODBIN/jq \
			--arg ag_app $ag_app \
			'.agmode_per_app_configuration[]
          | select(.packages[] == $ag_app) 
          | .props | keys[]' \
			$CONFIG | sed 's/"//g'
	)

	# shellcheck disable=SC2016
	battery_optimized=$(
		$MODBIN/jq \
			--arg ag_app $ag_app \
			'.agmode_per_app_configuration[]
          | select(.packages[] == $ag_app)
          | .battery_optimized' \
			$CONFIG
	)

	# shellcheck disable=SC2116
	for key in $(echo "$papp_keys"); do
		# shellcheck disable=SC2016
		value=$(
			$MODBIN/jq \
				--arg ag_app $ag_app \
				--arg key $key \
				'.agmode_per_app_configuration[]
              | select(.packages[] == $ag_app)
              | .props | .[$key]' \
				$CONFIG
		)

		{
			resetprop $key $value &&
				logger i "applying $key $value"
		} || logger w "$value or $key is invalid"
	done

	default_optimized_list=$LOGDIR/default_optimized.txt
	# shellcheck disable=SC3010
	$battery_optimized && [ -n "$battery_optimized" ] &&
		[ -z $default_opt_set ] && {
		dumpsys deviceidle whitelist |
			sed 's/^[^,]*,//;s/,[^,]*$//' \
				>$default_optimized_list
		default_opt_set=1

		dumpsys deviceidle whitelist +$ag_app &&
			logger "$ag_app is excluded from battery_optimized"
	}
	resetprop lmkd.reinit 1
}
