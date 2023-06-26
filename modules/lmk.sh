#!/system/bin/sh

# $1 is for the format of the log
# Example -> date +%R:%S:%N_%d-%m-%Y
logger() {
	local log=$(echo "$2" | tr -s " ")
	true && echo "$1 $log" >>"$LOGDIR"/meZram.log
}

rm_prop() {
	for prop in "$@"; do
		resetprop "$prop" >/dev/null && resetprop --delete "$prop" \
		&& logger "$prop deleted"
	done
}

custom_props_apply() {
	# Applying custom prop
	local CONFIG="/data/adb/meZram/meZram-config.json"
	props=$(/data/adb/modules_update/meZram/modules/bin/jq \
	'.custom_props | keys[]' "$CONFIG")

	if [ -z "$props" ]; then 
		props=$(/data/adb/modules/meZram/modules/bin/jq \
		'.custom_props | keys[]' "$CONFIG")
	fi 
	
	if [ -n "$props" ]; then
		for prop in $(echo "$props"); do
			prop_value=$(/data/adb/modules_update/meZram/modules/bin/jq \
			--arg prop "${prop//\"/}" '.custom_props | .[$prop]' "$CONFIG")

			if [ -z "$prop_value" ]; then 
				prop_value=$(/data/adb/modules/meZram/modules/bin/jq \
				--arg prop "${prop//\"/}" '.custom_props | .[$prop]' "$CONFIG")
			fi

			resetprop "${prop//\"/}" "$prop_value"
		done
		resetprop lmkd.reinit 1
	fi
}

lmkd_props_clean() {
	# LMKD props list
	# set "ro.config.low_ram" "ro.lmk.use_psi" \
	# "ro.lmk.use_minfree_levels" "ro.lmk.low" "ro.lmk.medium" \
	# "ro.lmk.critical" "ro.lmk.critical_upgrade"
	# "ro.lmk.upgrade_pressure" "ro.lmk.downgrade_pressure" \
	# "ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" \
	# "ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" \
	# "ro.lmk.thrashing_limit" "ro.lmk.thrashing_limit_decay" \
	# "ro.lmk.swap_util_max" "ro.lmk.swap_free_low_percentage" \
	# "ro.lmk.debug" "sys.lmk.minfree_levels"

	set --
	set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical_upgrade" \
		"ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" \
		"ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" \
		"ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" \
		"sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"
	rm_prop "$@"
}
