#!/system/bin/bash

zipfiles=$(cat zip-list.txt)
version=$1
versionCode=$2

if [ -z "$version" ] && [ -z "$versionCode" ]; then
    version=$(grep -o 'version=v[0-9.]*' module.prop | cut -d'=' -f2 | sed 's/v//')
    versionCode=$(grep versionCode module.prop | cut -d "=" -f2)
    versionCode=$((versionCode + 1))
elif [ -z "$version" ]; then
    version=$(grep -o 'version=v[0-9.]*' module.prop | cut -d'=' -f2 | sed 's/v//')
elif [ -z "$versionCode" ]; then
    versionCode=$(grep versionCode module.prop | cut -d "=" -f2)
    versionCode=$((versionCode + 1))
fi

sed -i "s/version=v[0-9.]*-beta/version=v$version-beta/g; s/versionCode=[0-9]*/versionCode=$versionCode/g" module.prop
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$version-beta\"/" meZram.json
sed -i "s/\"versionCode\": \"[^\"]*\"/\"versionCode\": \"$versionCode\"/" meZram.json
sed -i "s#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta/meZram-v[0-9.]*_[0-9]*-beta.zip\",#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta/meZram-v$version\_$versionCode-beta.zip\",#g; s#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta/meZram-v[0-9.]*_[0-9]*-beta-changelog.md\"#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta/meZram-v$version\_$versionCode-beta-changelog.md\"#g" meZram.json

changelog_file=$(ls | grep -o 'meZram-v[0-9]\+\.[0-9]\+_[0-9]\+-beta-changelog\.md')
mv "$changelog_file" "meZram-v${version}_$versionCode-beta-changelog.md"

7za a "meZram-v${version}_$versionCode-beta.zip" $zipfiles
