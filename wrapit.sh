#!/system/bin/bash

zipfiles=$(cat zip-list.txt)
version=$1
versionCode=$2

if [ -z "$version" ]; then
    version=$(grep -o 'version=v[0-9.]*' module.prop | cut -d'=' -f2 | sed 's/v//')
fi

if [ -z "$versionCode" ]; then
    versionCode=$(grep versionCode module.prop | cut -d "=" -f2)
    versionCode=$((versionCode + 1))
fi

sed -i "s/version=v[0-9.]*-beta-psi/version=v$version-beta-psi/g; s/versionCode=[0-9]*/versionCode=$versionCode/g" module.prop
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$version-beta-psi\"/" meZram.json
sed -i "s/\"versionCode\": \"[^\"]*\"/\"versionCode\": \"$versionCode\"/" meZram.json
sed -i "s#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta-psi/meZram-v[0-9.]*_[0-9]*-beta-psi.zip\",#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta-psi/meZram-v$version\_$versionCode-beta-psi.zip\",#g; s#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta-psi/meZram-v[0-9.]*_[0-9]*-beta-psi-changelog.md\"#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta-psi/meZram-v$version\_$versionCode-beta-psi-changelog.md\"#g" meZram.json

changelog_file=$(ls | grep -o 'meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta-psi-changelog\.md')
mv "$changelog_file" "meZram-v${version}_$versionCode-beta-psi-changelog.md"

7za a "packages/meZram-v${version}_$versionCode-beta-psi.zip" $zipfiles
