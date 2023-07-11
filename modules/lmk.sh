#!/system/bin/sh
export MAGENTA='\033[0;35m'
export TURQUOISE='\033[1;36m'
export LIGHT_BLUE='\033[1;34m'
export GREEN='\033[1;32m'
export YELLOW_BAD='\033[33m'
export RESET='\033[0m'
export YELLOW='\033[93m'

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

liner() {
	printf '%*s' "$2" | tr ' ' "$1"
}

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

# $1 is for the format of the log
# Example -> date +%R:%S:%N_%d-%m-%Y
logger() {
	local log=$(echo "$2" | tr -s " ")
	true && echo "$1 $log" >>"$LOGDIR"/meZram.log
}

rm_prop() {
	for prop in "$@"; do
		resetprop "$prop" >/dev/null && resetprop --delete "$prop" &&
			logger "$prop deleted"
	done
}

custom_props_apply() {
	# Applying custom prop
	local CONFIG=/data/adb/meZram/meZram-config.json
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
	fi
}

lmkd_props_clean() {
	set --
	set "ro.lmk.low" "ro.lmk.medium" "ro.lmk.critical_upgrade" \
		"ro.lmk.kill_heaviest_task" "ro.lmk.kill_timeout_ms" \
		"ro.lmk.psi_partial_stall_ms" "ro.lmk.psi_complete_stall_ms" \
		"ro.lmk.thrashing_limit_decay" "ro.lmk.swap_util_max" \
		"sys.lmk.minfree_levels" "ro.lmk.upgrade_pressure"
	rm_prop "$@"
}
