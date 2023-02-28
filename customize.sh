#!/sbin/sh

# Calculate size to use for swap (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`

ui_print ""
ui_print "  Made with pain from "; sleep 2
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="; sleep 2

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

count_ZRAM() {
    local one_gb=$((1024*1024))
    local totalmem_gb=$(((totalmem/1024/1024)+1))
    local zram_size=$(((totalmem - one_gb) * 1024))
    local count=0
    local zram_in_gb=0
    local done=false

    ui_print "- SELECT ZRAM SIZE"
    ui_print "  Press VOL_DOWN to add ZRAM"
    ui_print "  Press VOL_UP to finish"
    
    while true; do
	timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events &
	sleep 0.1
	if (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events) && [ $zram_in_gb -lt ${totalmem_gb} ]; then
	    if [ ${count} -eq 0 ]; then
		count=$((count + 1))
		ui_print "  $count. Left 1GB for RAM (Default), rest is ZRAM. Finished?"
	    elif [ ${count} -eq 1 ]; then
		count=$((count + 1))
		zram_size=$((totalmem * 50/100 * 1024))
		ui_print "  $count. 50% of RAM $((zram_size/1024/1024))MB ZRAM"
	    elif [ $zram_in_gb -lt ${totalmem_gb} ]; then
		count=$((count + 1))
		zram_in_gb=$((zram_in_gb+1))
		ui_print "  $count. ${zram_in_gb}GB of ZRAM"
		zram_size=$((zram_in_gb * one_gb * 1024))
	    fi
	elif [ $zram_in_gb -eq $totalmem_gb ] && [ !$done ]; then
	    ui_print "  Maximum value reached."; sleep 0.5
	    ui_print "  Press VOL_DOWN to RESET"
	    zram_size=$((totalmem * 1024))
	    while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events0 &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events0); then
		    count=0
		    zram_size=$(((totalmem - $one_gb) * 1024))
		    zram_in_gb=0
		    ui_print "- Default size restored"
		    break
		elif (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events0); then
		    done=true
		    echo $zram_size > $MODPATH/ZRAM-size.txt
		    break 2
		fi
	    done
	elif (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events); then
	    echo $zram_size > $MODPATH/ZRAM-size.txt
	    break
	fi
    done
}

if [ -d "/data/adb/modules/meZram" ]; then
    ui_print "- Thank you so much 😊."
    ui_print "  You've installed this module before"
    # remove old SWAP
    if [ -f /data/swap_file ]; then
	ui_print "- Removing SWAP. Lmkd doesn't support SWAP. Shit 😔"
	unzip -o $MODPATH/meZram-cleaner.zip -d $MODPATH/../meZram-cleaner  > /dev/null 
    fi 
elif [ ${sdk_level} -lt 28 ]; then
    ui_print "- Your android version is not supported"
    abort "  Please upgrade your phone to Android 9+"
fi

count_ZRAM; lmkd_apply
