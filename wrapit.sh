#!/system/bin/bash

zipfiles=$(cat zip-list.txt)

echo $zipfiles
7za a $1 $zipfiles
