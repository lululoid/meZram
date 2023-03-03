#!/sbin/sh

# Calculate size to use for swap (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`

ui_print ""
ui_print "  Made with pain from "; sleep 0.5
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="; sleep 0.5

lmkd_apply() {
    # determine if device is lowram?
    if [ ${totalmem} < 2097152 ]; then
	mv $MODPATH/system.props/low-ram-system.prop $MODPATH/system.prop
    else
	mv $MODPATH/system.props/high-performance-system.prop $MODPATH/system.prop
    fi
    
    # applying lmkd tweaks
    for prop in $(cat $MODPATH/system.prop); do
        resetprop $(echo $prop | sed s/=/' '/)
    done
    resetprop lmkd.reinit 1

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
    local done=false

    ui_print "- SELECT ZRAM SIZE"
    ui_print "  Press VOL_DOWN to continue"
    ui_print "  Press VOL_UP to skip and select Default"
    ui_print "  Default is $((totalmem/1024))MB of SWAP"
    
    while true; do
	timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events &
	sleep 0.1
	if (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events) && [ $swap_in_gb -lt ${totalmem_gb} ]; then
	    if [ ${count} -eq 0 ]; then
		count=$((count + 1))
		swap_size=$((totalmem / 2))
		ui_print "  $count. 50% of RAM $((swap_size/1024))MB SWAP"
	    elif [ $swap_in_gb -lt ${totalmem_gb} ]; then
		count=$((count + 1))
		swap_in_gb=$((swap_in_gb + 1))
		ui_print "  $count. ${swap_in_gb}GB of SWAP"
		swap_size=$((swap_in_gb * one_gb))
	    fi
	elif [ $swap_in_gb -eq $totalmem_gb ] && [ !$done ]; then
	    ui_print "  Maximum value reached."; sleep 0.5
	    ui_print "  Press VOL_DOWN to RESET"
	    swap_size=$totalmem
	    while true; do
		timeout 0.5 /system/bin/getevent -lqc 1 2>&1 > $TMPDIR/events0 &
		sleep 0.1
		if (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMPDIR/events0); then
		    count=0
		    swap_size=$((totalmem / 2))
		    swap_in_gb=0
		    ui_print "- Default size restored"
		    break
		elif (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events0); then
		    done=true
		    break 2
		fi
	    done
	elif (grep -q 'KEY_VOLUMEUP *DOWN' $TMPDIR/events); then
	    break
	fi
    done
}

rm_prop_reinit(){
    for prop in in $@; do
	[ $(resetprop $prop) ] && resetprop --delete $prop && lmkd --reinit
    done                                            
}

mount /data > /dev/null

# Check Android SDK
sdk_level=$(resetprop ro.build.version.sdk)
swap_filename=$MODPATH/swap_file 
free_space=`df /data/ | sed -n 2p | awk '{print $4}'`
count_SWAP 

if [ -d "/data/adb/modules/meZram" ]; then
    ui_print "- Thank you so much 😊."
    ui_print "  You've installed this module before"
fi

swapoff /data/swap_file > /dev/null 
rm -rf /data/swap_file  > /dev/null 

if [ ${free_space} -ge ${swap_size} ] && [ ! -f /data/adb/modules/meZram/swap_file ]; then
    ui_print "- Starting making SWAP. Please wait a moment"; sleep 0.5
    ui_print "  $((free_space/1024))MB available. $((swap_size/1024))MB needed"
    dd if=/dev/zero of=$swap_filename bs=1024 count=${swap_size} 2> install_error.txt > /dev/null
    chmod 0600 $swap_filename > /dev/null
    mkswap $swap_filename > /dev/null
    swapon $swap_filename > /dev/null
    ui_print "  SWAP turned on"
fi

if [ ${sdk_level} -lt 28 ]; then
    ui_print "- Your android version is not supported"
    abort "  Please upgrade your phone to Android 9+"
else
    lmkd_apply
    tlc='persist.device_config.lmkd_native.thrashing_limit_critical'
    minfree_l='sys.lmk.minfree_levels'

    rm_prop_reinit $tlc $minfree_l
fi
