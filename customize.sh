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
    local on=true
    $on && ui_print "  DEBUG: $*"
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

    local ml=$(resetprop sys.lmk.minfree_levels)
    # echo "sys.lmk.minfree_levels=$ml" >> "$MODPATH"/system.prop
    
    # applying lmkd tweaks
    grep -v '^ *#' < "$MODPATH"/system.prop | while IFS= read -r prop; do
	logger "$prop" 
	resetprop $(echo "$prop" | sed s/=/' '/)
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
    local count=0
    local swap_in_gb=0

    ui_print "- SELECT ZRAM SIZE"
    ui_print "  Press VOL_DOWN to continue"
    ui_print "  Press VOL_UP to skip and select Default"
    ui_print "  Default is $((totalmem/1024/2))MB of SWAP"
    
    while true; do
	timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > "$TMPDIR"/events &
	sleep 0.1
	if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events) && [ $swap_in_gb -lt $totalmem_gb ]; then
	    if [ $count -eq 0 ]; then
		count=$((count + 1))
		swap_size=$((totalmem / 2))
		ui_print "  $count. 50% of RAM $((swap_size/1024))MB SWAP"
	    elif [ $count -eq 2 ]; then
		count=$((count + 1))
		ui_print "  $count. No SWAP"
		unset swap_size
		unset free_space
	    elif [ $swap_in_gb -lt $totalmem_gb ]; then
		count=$((count + 1))
		swap_in_gb=$((swap_in_gb + 1))
		ui_print "  $count. ${swap_in_gb}GB of SWAP"
		swap_size=$((swap_in_gb * one_gb))
	    fi
	elif [ $swap_in_gb -eq $totalmem_gb ]; then
	    ui_print "  Maximum value reached."; sleep 0.5
	    ui_print "  Press VOL_DOWN to RESET"
	    swap_size=$totalmem
	    while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > "$TMPDIR"/events0 &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR"/events0); then
		    count=0
		    swap_size=$((totalmem / 2))
		    swap_in_gb=0
		    ui_print "- Default size restored"
		    break
		elif (grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR"/events0); then
		    break 2
		fi
	    done
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
    ui_print "  SWAP turned on"
}

mount /data > /dev/null

# Check Android SDK
sdk_level=$(resetprop ro.build.version.sdk)
swap_filename=/data/swap_file 
free_space=$(df /data | sed -n '2{s/^[^ ]* *[^ ]* *[^ ]* *\([^ ]*\).*/\1/p}')

if [ -d "/data/adb/modules/meZram" ]; then
    ui_print "- Thank you so much 😊."
    ui_print "  You've installed this module before"
fi 

if [ ! -f $swap_filename ]; then
    count_SWAP
    logger "free space = $free_space"
    logger "swap size = $swap_size"
    logger "sdk_level = $sdk_level"
    if [ "$free_space" -ge "$swap_size" ]; then
        ui_print "- Starting making SWAP. Please wait a moment"; sleep 0.5
	ui_print "  $((free_space/1024))MB available. $((swap_size/1024))MB needed"
	swapon $swap_size $swap_filename
    elif [ -z "$free_space" ]; then
	if [ -n "$swap_size" ]; then
	    ui_print "- Make sure you had $((swap_size / 1024))MB available"
	    ui_print "- Starting making SWAP. Please wait a moment"; sleep 0.5
	    swapon $swap_size $swap_filename
	else:
	    swapon $swap_size $swap_filename 
	fi 
    else
	ui_print "- Storage full. Please free up your storage"
    fi 
fi

if [ "$sdk_level" -lt 28 ]; then
    ui_print "- Your android version is not supported. Performance tweaks won't applied."
    ui_print "  Please upgrade your phone to Android 9+"
else
    lmkd_apply; tlc='persist.device_config.lmkd_native.thrashing_limit_critical'
    minfree="sys.lmk.minfree_levels"

    rm_prop_reinit $tlc
fi
