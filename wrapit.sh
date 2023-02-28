#!/system/bin/bash

zipfiles=$(cat zip-list.txt)

sed -i "s#v[0-9]\+\.[0-9]\+-beta/meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta#v$1-beta/meZram-v$1_$2-beta#g" meZram.json
sed -i "s#versionCode\"\: [0-9]\+#\"versionCode\"\: $2#g" meZram.json 
sed -i "s#versionCode\=[0-9]\+#versionCode\=$2#g" module.prop
sed -i "s#v[0-9]\+\.[0-9]\+-beta#v$1-beta#g" meZram.json 
sed -i "s#v[0-9]\+\.[0-9]\+-beta#v$1-beta#g" module.prop 

echo $zipfiles
7za a "meZram-v$1_$2-beta.zip" $zipfiles
