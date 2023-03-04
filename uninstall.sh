MODDIR=${0%/*}
MODSDIR=$(dirname "$MODDIR")
MODULEDIR=$MODSDIR/meZram-cleaner

mkdir $MODULEDIR
unzip -o $MODSDIR/meZram/meZram-cleaner.zip -d $MODULEDIR