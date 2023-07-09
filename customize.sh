# Setup modules
set_perm_recursive "$MODPATH"/modules/bin 0 2000 0755 0755
. "$MODPATH"/modules/lmk.sh

mkdir -p "$NVBASE/meZram"

# Calculate size to use for swap (1/2 of ram)
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')

ui_print ""
ui_print "  Made with ❤ and 🩸 by "
sleep 0.5
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="
sleep 0.5

log_it() {
	log=$(echo "$*" | tr -s " ")
	false && ui_print "  DEBUG: $log"
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
	if [ "$totalmem" -lt 2097152 ]; then
		ui_print "⚠️ Device is low ram. Applying low rm tweaks"
		mv "$MODPATH"/system.props/low-ram-system.prop "$MODPATH"/system.prop
	else
		mv "$MODPATH"/system.props/high-performance-system.prop "$MODPATH"/system.prop
	fi

	# Properties to be removed
	set --
	set "ro.config.low_ram" \
		"ro.lmk.use_psi" \
		"ro.lmk.use_minfree_levels" \
		"ro.lmk.low" "ro.lmk.medium" \
		"ro.lmk.critical" "ro.lmk.critical_upgrade" \
		"ro.lmk.upgrade_pressure" \
		"ro.lmk.downgrade_pressure" \
		"ro.lmk.kill_heaviest_task" \
		"ro.lmk.kill_timeout_ms" \
		"ro.lmk.psi_partial_stall_ms" \
		"ro.lmk.psi_complete_stall_ms" \
		"ro.lmk.thrashing_limit" \
		"ro.lmk.thrashing_limit_decay" \
		"ro.lmk.swap_util_max" \
		"ro.lmk.swap_free_low_percentage" \
		"ro.lmk.debug" "sys.lmk.minfree_levels"
	rm_prop "$@"

	# applying lmkd tweaks
	grep -v '^ *#' <"$MODPATH"/system.prop | while IFS= read -r prop; do
		# log_it "$prop"
		log_it "resetprop ${prop//=/ }"
		resetprop ${prop//=/ }
	done

	tl="ro.lmk.thrashing_limit"
	if [ "$(resetprop ro.miui.ui.version.code)" ]; then
		rm_prop "$tl"
	fi

	resetprop lmkd.reinit 1 && ui_print "> lmkd reinitialized"
	ui_print "> lmkd multitasking tweak applied."
	ui_print "  Give the better of your RAM."
	ui_print "  RAM better being filled with something"
	ui_print "  useful than left unused"
	rm -rf "$MODPATH/system.props"
}

count_SWAP() {
	local one_gb=$((1024 * 1024))
	local totalmem_gb=$(((totalmem / 1024 / 1024) + 1))
	swap_size=$((totalmem / 2))
	count=0

	ui_print "> Please select SWAP size"
	ui_print "  Press VOLUME + to DEFAULT"
	ui_print "  Press VOLUME - to SELECT"
	ui_print "  DEFAULT is $((totalmem / 1024 / 2))MB of SWAP"

	while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 >"$TMPDIR"/events &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events); then
			if [ $count -eq 0 ]; then
				count=$((count + 1))
				swap_size=$((totalmem / 2))
				local swap_in_gb=0
				ui_print "  $count. 50% of RAM ($((swap_size / 1024))MB SWAP)\
				 --> RECOMMENDED"
			elif [ $count -eq 2 ]; then
				count=$((count + 1))
				ui_print "  $count. No SWAP"
				swap_size=0
			elif [ "$swap_in_gb" -lt "$totalmem_gb" ]; then
				count=$((count + 1))
				swap_in_gb=$((swap_in_gb + 1))
				ui_print "  $count. ${swap_in_gb}GB of SWAP"
				swap_size=$((swap_in_gb * one_gb))
			fi
		elif [ "$swap_in_gb" -eq $totalmem_gb ] && [ $count != 0 ]; then
			swap_size=$totalmem
			count=0
		elif (grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR"/events); then
			break
		fi
	done
}

make_swap() {
	dd if=/dev/zero of="$2" bs=1024 count="$1" >/dev/null
	mkswap "$2" >/dev/null
	/system/bin/swapon -p 5 "$2" >/dev/null
	ui_print "- SWAP is running"
}

mount /data >/dev/null

# Check Android SDK
sdk_level=$(resetprop ro.build.version.sdk)
swap_filename=/data/swap_file
free_space=$(df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' |
	sed ':a;N;$!ba;s/\n/ /g' | awk '{print $3}')
log_it "$(df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' |
	sed ':a;N;$!ba;s/\n/ /g')"

if [ -d "/data/adb/modules/meZram" ]; then
	ui_print "> Thank you so much 😊."
	ui_print "  You've installed this module before"
fi

# Making SWAP
if [ ! -f $swap_filename ]; then
	# Ask user how much SWAP they want
	count_SWAP
	log_it "free space = $free_space"
	log_it "swap size = $swap_size"
	log_it "sdk_level = $sdk_level"
	log_it "count = $count"
	# Making SWAP only if enough free space available
	if [ "$free_space" -ge "$swap_size" ] && [ "$swap_size" != 0 ]; then
		ui_print "- Starting making SWAP. Please wait a moment"
		sleep 0.5
		ui_print "  $((free_space / 1024))MB available. $((swap_size / 1024))MB needed"
		make_swap "$swap_size" $swap_filename
	# Handling bug on some devices
	elif [ -z "$free_space" ]; then
		ui_print "> Make sure you have $((swap_size / 1024))MB space available data partition"
		ui_print "  Make SWAP?"
		ui_print "  Press VOLUME + to NO"
		ui_print "  Press VOLUME - to YES"

		while true; do
			timeout 0.5 /system/bin/getevent -lqc 1 2>&1 >"$TMPDIR"/events &
			sleep 0.1
			if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events); then
				ui_print "> Starting making SWAP. Please wait a moment"
				sleep 0.5
				make_swap "$swap_size" $swap_filename
				break
			elif (grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR"/events); then
				cancelled=$(ui_print "> Not making SWAP")
				$cancelled && log_it "$cancelled"
				break
			fi
		done
	# if no SWAP option selected, only pass
	elif [ $count -eq 3 ]; then
		true &&
			ui_print "> Not making any SWAP. Why bro?"
	else
		ui_print "> Storage full. Please free up your storage"
	fi
fi

if [ "$sdk_level" -lt 28 ]; then
	ui_print "> Your android version is not supported. Performance tweaks won't applied."
	ui_print "  Please upgrade your phone to Android 9+"
else
	lmkd_apply
fi

# Updating config
LOGDIR=/data/adb/meZram
CONFIG_OLD_0=$LOGDIR/meZram-config.json
CONFIG_OLD=$LOGDIR/meZram.conf
CONFIG=/sdcard/meZram-config.json

if [ -f $CONFIG_OLD ]; then
	mv -f $CONFIG_OLD /sdcard/$CONFIG_OLD.old &&
		ui_print "> Very old config moved to ${CONFIG_OLD}.old on internal"
fi

# Make the config easier to edit by moving it to internal
if [ -f $CONFIG_OLD_0 ]; then
	/system/bin/mv -f $CONFIG_OLD_0 $CONFIG &&
		ui_print "> Old config moved to internal"
fi

if [ ! -f $CONFIG ]; then
	cp -f "$MODPATH"/meZram-config.json "$CONFIG" &&
		ui_print "> meZram-config is $CONFIG"
fi

# Read config version
log_it "jq version = $("$MODPATH"/modules/bin/jq --version)"
version=$("$MODPATH"/modules/bin/jq '.config_version' "$MODPATH/meZram-config.json")
version_prev=$("$MODPATH"/modules/bin/jq '.config_version' "$CONFIG")

log_it "version = $version"
log_it "version_prev = $version_prev"

# Update if version is higher than previous version
if [ -n "$version_prev" ]; then
	is_update=$(awk -v version="${version}" \
		-v version_prev="${version_prev}" \
		'BEGIN {
			if (version > version_prev) {
				print "true"
			} else {
				print "false"
			}
		}')
else
	log_it "$(ls /sdcard/)"
	rm $CONFIG
	abort
fi

log_it "is_update = $is_update"

if [ -f "$CONFIG" ] && [[ "$is_update" = "true" ]]; then
	# Update config version
	ui_print "> Updating configuration"
	"$MODPATH"/modules/bin/jq \
		'del(.config_version)' "$CONFIG" |
		/system/bin/awk 'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG
	# Slurp entire config
	"$MODPATH"/modules/bin/jq \
		-s '.[0] * .[1]' "$MODPATH"/meZram-config.json $CONFIG |
		/system/bin/awk 'BEGIN{RS="";getline<"-";print>ARGV[1]}' $CONFIG
	mv "$MODPATH/update.json" $CONFIG
	ui_print "> Configuration updated"
fi

# Tweaks already able to be used without restarting,
# that's still not enough if you ask me
ui_print "> Enjoy the speed of a ⚡⚡⚡"
custom_props_apply && ui_print "> Custom props applied. Restarting device is RECOMMENDED"
