#!/system/bin/sh
# Calculate size to use for swap (1/2 of ram)
totalmem=$(free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//')

ui_print ""
ui_print "  Made with pain from "; sleep 0.5
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="; sleep 0.5

logger(){
    true && ui_print "  DEBUG: $*"
}

lmkd_apply() {
    # determine if device is lowram?
    logger "totalmem = $totalmem"
    if [ "$totalmem" -lt 2097152 ]; then
		ui_print "- Device is low ram. Applying low raw tweaks"
		mv "$MODPATH"/system.props/low-ram-system.prop "$MODPATH"/system.prop
    else
		mv "$MODPATH"/system.props/high-performance-system.prop "$MODPATH"/system.prop
    fi

    # local ml=$(resetprop sys.lmk.minfree_levels)
    # echo "sys.lmk.minfree_levels=$ml" >> "$MODPATH"/system.prop
    
    # applying lmkd tweaks
    grep -v '^ *#' < "$MODPATH"/system.prop | while IFS= read -r prop; do
		logger "$prop" 
		resetprop "$(echo "$prop" | sed s/=/' '/)"
    done

    resetprop lmkd.reinit 1 && ui_print "- lmkd reinitialized"
    ui_print "- lmkd multitasking tweak applied."
    ui_print "  Give the better of your RAM."
    ui_print "  RAM better being filled with something"
    ui_print "  useful than left unused"
}

count_SWAP() {
    local one_gb=$((1024*1024))
    local totalmem_gb=$(((totalmem/1024/1024)+1))
    swap_size=$((totalmem / 2))
    count=0

    ui_print "- Please SELECT SWAP SIZE"
	ui_print "  Press VOLUME UP to SELECT"
    ui_print "  Press VOLUME DOWN to CONTINUE"
    ui_print "  DEFAULT is $((totalmem/1024/2))MB of SWAP"
    
    while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > "$TMPDIR"/events &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events); then
			if [ $count -eq 0 ]; then
				count=$((count + 1))
				swap_size=$((totalmem / 2))
				local swap_in_gb=0
				ui_print "  $count. 50% of RAM ($((swap_size/1024))MB SWAP) --> RECOMMENDED"
			elif [ $count -eq 2 ]; then
				count=$((count + 1))
				ui_print "  $count. NO SWAP"
				swap_size=0
			elif [ $swap_in_gb -lt $totalmem_gb ]; then
				count=$((count + 1))
				swap_in_gb=$((swap_in_gb + 1))
				ui_print "  $count. ${swap_in_gb}GB of SWAP"
				swap_size=$((swap_in_gb * one_gb))
			fi
		elif [ $swap_in_gb -eq $totalmem_gb ] && [ $count != 0 ]; then
			swap_size=$totalmem
			count=0
		elif (grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR"/events); then
			break
		fi
	done
}

rm_prop_reinit(){
	for prop in "$@"; do
		[ "$(resetprop "$prop")" ] && resetprop --delete "$prop" && resetprop lmkd.reinit 1 && ui_print "- lmkd reinitialized"
    done
}

make_swap(){
    dd if=/dev/zero of="$2" bs=1024 count="$1" > /dev/null                   
    mkswap "$2" > /dev/null
    swapon "$2" > /dev/null
    ui_print "- SWAP is RUNNING"
}

mount /data > /dev/null

# Check Android SDK
sdk_level=$(resetprop ro.build.version.sdk)
swap_filename=/data/swap_file 
free_space=$(df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' | sed ':a;N;$!ba;s/\n/ /g' | awk '{print $3}')
logger "$(df /data -P | sed -n '2p' | sed 's/[^0-9 ]*//g' | sed ':a;N;$!ba;s/\n/ /g')"

if [ -d "/data/adb/modules/meZram" ]; then
    ui_print "- Thank you so much 😊."
    ui_print "  You've installed this module before"
fi 

if [ ! -f $swap_filename ]; then
    count_SWAP
    logger "free space = $free_space"
    logger "swap size = $swap_size"
    logger "sdk_level = $sdk_level"
    logger "count = $count"
    if [ "$free_space" -ge "$swap_size" ] && [ "$swap_size" != 0 ]; then
        ui_print "- Starting making SWAP. Please wait a moment"; sleep 0.5
		ui_print "  $((free_space/1024))MB available. $((swap_size/1024))MB needed"
		make_swap "$swap_size" $swap_filename
    elif [ -z "$free_space" ]; then
		ui_print "- Make sure you have $((swap_size / 1024))MB space available data partition"
		ui_print "  Make SWAP?"
		ui_print "  Press VOLUME DOWN (YES) or VOLUME UP (NO)"

		while true; do
        	timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > "$TMPDIR"/events &
        	sleep 0.1
			if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events); then
				ui_print "- Starting making SWAP. Please wait a moment"; sleep 0.5
				make_swap "$swap_size" $swap_filename
				break
			elif (grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR"/events); then
				cancelled=$(ui_print "- Making SWAP cancelled by user")
				$cancelled && logger "$cancelled"
            	break
			fi
		done
    elif [ $count -eq 3 ]; then
		true
    else
		ui_print "- Storage full. Please free up your storage"
    fi 
fi

if [ "$sdk_level" -lt 28 ]; then
    ui_print "- Your android version is not supported. Performance tweaks won't applied."
    ui_print "  Please upgrade your phone to Android 9+"
else
    lmkd_apply; tlc='persist.device_config.lmkd_native.thrashing_limit_critical'
    # minfree="sys.lmk.minfree_levels"

    rm_prop_reinit $tlc
fi

ui_print "- Please REBOOT to take effect"
