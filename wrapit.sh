#!/system/bin/bash

zipfiles=$(cat zip-list.txt)
version=$1
versionCode=$2

if [ -z "$version" ] || [ -z "$versionCode" ]; then
  echo "Please provide both version and versionCode."
  echo "wrapit.sh [version] [versionCode]"
  exit 1
fi

sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi/meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta-psi#v$version-beta-psi/meZram-v$version_$versionCode-beta-psi#g" meZram.json
sed -i "s#\"versionCode\"\: \"[0-9]\+\"#\"versionCode\"\: \"$versionCode\"#g" meZram.json 
sed -i "s#versionCode\=[0-9]\+#versionCode\=$versionCode#g" module.prop
sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi#v$version-beta-psi#g" meZram.json 
sed -i "s#v[0-9]\+\.[0-9]\+-beta-psi#v$version-beta-psi#g" module.prop 

changelog_file=$(ls | grep -o 'meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta-psi-changelog\.md')
mv "$changelog_file" "meZram-v${version}_$versionCode-beta-psi-changelog.md"

7za a "meZram-v$version_$versionCode-beta-psi.zip" $zipfiles
