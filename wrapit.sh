#!/system/bin/bash

zipfiles=$(cat zip-list.txt)

sed -i "s#v[0-9]\+\.[0-9]\+/meZram-v[0-9]\+\.[0-9]\+_[0-9]\+#v$1/meZram-v$1_$2#g" meZram.json
sed -i "s#\"versionCode\"\: \"[0-9]\+\"#\"versionCode\"\: \"$2\"#g" meZram.json 
sed -i "s#versionCode\=[0-9]\+#versionCode\=$2#g" module.prop
sed -i "s#v[0-9]\+\.[0-9]\+#v$1#g" meZram.json 
sed -i "s#v[0-9]\+\.[0-9]\+#v$1#g" module.prop 

changelog_file=$(ls | grep -o 'meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-changelog\.md')
mv "$changelog_file" "meZram-v$1_$2-changelog.md"

7za a "meZram-v$1_$2.zip" $zipfiles
