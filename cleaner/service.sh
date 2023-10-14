#!/system/bin/sh
MODULEDIR=/data/adb/modules/meZram-cleaner

swap=/data/swap_file
meZram_folder=/data/adb/meZram
rm -rf $swap $meZram_folder
touch $MODULEDIR/remove
