#! /sbin/sh

MODDIR=${0%/*}
MODSDIR=$(dirname "$MODDIR")
MODULEDIR=/data/adb/modules/meZram-cleaner

mkdir $MODULEDIR
unzip -o $MODSDIR/meZram/meZram-cleaner.zip -d $MODULEDIR