#!/sbin/sh

# Calculate size to use for swap (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
swap=/data/swap_file
size=$((totalmem / 2))
swap_size=${size}

ui_print ""
ui_print "  Made with pain from "; sleep 2
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="; sleep 2

check_storage_availability() {
    local num_array=()
    for num in $(seq $(df | wc -l)); do
	local available=`df | sed -n ${num}p | awk '{print $4}'`
	num_array+=${available}
    done
    
    local max=0
    for num in $num_array; do
	if [ $num \> $max ]; then
	    max=$num
	fi
    done
    available=$max
}

lmkd_apply() {
    # determine if device is lowram?
    if [ ${totalmem} < 2097152 ]; then
	mv $MODPATH/system.props/low-ram-system.prop $MODPATH/system.prop
    else
	mv $MODPATH/system.props/high-performance-system.prop $MODPATH/system.prop
    fi

    echo '1' > /dev/cpuset/memory_pressure_enabled
    
    # applying lmkd tweaks
    for prop in $(cat $MODPATH/system.prop); do
        resetprop $(echo $prop | sed s/=/' '/)
    done
    ui_print "- lmkd multitasking tweak applied."
    ui_print "  Give the better of your RAM."
    ui_print "  RAM better being filled with something"
    ui_print "  useful than left unused"
}

make_swap() {
    swap_size=${size}
    local count=0
    local mem_in_gb=$(((totalmem/1024/1024)+1))
    local text="Press VOL_UP to change SWAP SIZE up to $((totalmem / 1024))MB"
    local done_text="Press VOL_DOWN if you're done"
    local done=false

    ui_print "- Configure SWAP size"; sleep 1
    ui_print "  Default SWAP size is 50%($((size/1024))MB) of RAM"
    ui_print "  $text"
    ui_print "  Press VOL_DOWN if you're done"
    
    while true; do
	timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events &
	sleep 0.1
	if (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events) && [ ${count} \< ${mem_in_gb} ]; then
	    count=$((count+1))
	    ui_print "  $((count))GB SWAP size"
	    swap_size=$((1024*1024*$count))
	elif [ $swap_size -ge $totalmem ] && [ !$done ]; then
	    swap_size=${totalmem}
	    ui_print "  Maximum value reached."
	    ui_print "  Press VOL_UP to reset SWAP size to default"; sleep 0.5
	    ui_print "  $done_text"

	    while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events0 &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events0); then
		    count=0
		    swap_size=${size}
		    ui_print "- Default SWAP size restored"
		    ui_print "  $text"
		    break
		elif (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events0); then
		    done=true 
		    break
		fi
	    done
	elif (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events); then
	    break
	fi
    done
    mount /data 2> /dev/null
    ui_print "- Making a SWAP, now please wait just a moment."
    dd if=/dev/zero of=$swap bs=1024 count=${swap_size} 2> install_error.txt > /dev/null
    chmod 0600 $swap > /dev/null 
    mkswap $swap > /dev/null
    swapon $swap 2> /dev/null
}

if [ ${available} \> ${swap_size} ]; then
    if [ -f "$swap" ]; then         
	ui_print "- Thank you so much 😊."
	ui_print "  You've installed this module before"
	ui_print "  You have to remove this module first"
	ui_print "  if you mant to change SWAP size."
    else
	# Swap making process
	make_swap
	ui_print "- Checking available storage"; sleep 2
	ui_print "  $((available / 1024))MB is available"; sleep 2
	ui_print "  $((swap_size / 1024))MB needed";sleep 1
	ui_print "- Set up ZRAM size and SWAP size"; sleep 2
	ui_print "  $((size / 1024))MB ZRAM + $((swap_size / 1024))MB SWAP"; sleep 2
	ui_print "  Please reboot to take effect."
    fi

    # Make sure sdk level is 29
    sdk_level=$(grep_get_prop ro.build.version.sdk) 
    if [ ${sdk_level} -ge 28 ]; then
        lmkd_apply
    else
	ui_print "- Your android version is not supported"
	ui_print "  Please upgrade your phone to Android 9+"
    fi
else
    ui_print "- Please free up your storage or choose lower SWAP size"
    abort "! Installation failed"
fi
