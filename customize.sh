#!/sbin/sh

# Calculate size to use for swap (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
swap=/data/swap_file
size=$((totalmem / 2))

if $BOOTMODE; then
    available=`df | grep -e "^/data" | sed -n 1p | awk '{print $4}'`
else
    available=`df | grep /data | sed -n 1p | awk '{print $4}'`
fi

ui_print ""
ui_print "  Made with pain from "; sleep 2
ui_print " █▀▀ █▀▀█ █░░░█ ░▀░ █▀▀▄ ▀▀█ █▀▀ █▀▀█ █▀▀█"
ui_print " █▀▀ █▄▄▀ █▄█▄█ ▀█▀ █░░█ ▄▀░ █▀▀ █▄▄▀ █▄▀█"
ui_print " ▀▀▀ ▀░▀▀ ░▀░▀░ ▀▀▀ ▀░░▀ ▀▀▀ ▀▀▀ ▀░▀▀ █▄▄█"
ui_print " ==================:)====================="; sleep 2
    
lmkd_apply() {
    for prop in $(cat $MODDIR/system.prop); do
        resetprop $(echo $prop | sed s/=/' '/)
    done
    ui_print "- lmkd multitasking tweak applied."
    ui_print "  Give the better of your RAM."
    ui_print "  RAM better being filled with something"
    ui_print "  useful than left unused"
}

make_swap() {
	if [ -f "$swap" ]; then
		swapon $swap 2> /dev/null
	else
        mount /data 2> /dev/null
		dd if=/dev/zero of=$swap bs=1024 count=${size} 2> install_error.txt 1> /dev/null
		chmod 0600 $swap
		mkswap $swap
	fi
}

ui_print "- Checking available storage"; sleep 2
ui_print "  $((available / 1024))MB is available"; sleep 2
ui_print "  $((size / 1024))MB needed";sleep 2
if [ ${available} > ${size} ]; then
		make_swap; lmkd_apply
		ui_print "- Set up ZRAM size and SWAP size"; sleep 2
		ui_print "  $((size / 1024))MB ZRAM + $((size / 1024))MB SWAP"; sleep 2
		ui_print "- If this your first installation."
		ui_print "  Please reboot to take effect."
	else
		ui_print "- Please free up your storage"
		ui_print "! Installation failed"
	fi