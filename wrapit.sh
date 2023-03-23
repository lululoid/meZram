#!/system/bin/bash

zipfiles=$(cat zip-list.txt)

sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi/meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta-psi#v$1-beta-psi/meZram-v$1_$2-beta-psi#g" meZram.json
sed -i "s#\"versionCode\"\: \"[0-9]\+\"#\"versionCode\"\: \"$2\"#g" meZram.json 
sed -i "s#versionCode\=[0-9]\+#versionCode\=$2#g" module.prop
sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi#v$1-beta-psi#g" meZram.json 
sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi#v$1-beta-psi#g" module.prop 

7za a "meZram-v$1_$2-beta-psi.zip" $zipfiles
