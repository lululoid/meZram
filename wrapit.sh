#!/bin/bash

version=$1
versionCode=$2

# Check for decimal in arguments
for arg in "$@"; do
	if [[ $arg =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		true
	else
		echo "> Arguments must be number"
		exit 1
	fi
done

last_version=$(grep -o 'version=v[0-9.]*' module.prop | cut -d'=' -f2 | sed 's/v//')

if [ -z "$version" ]; then
    version=$(grep -o 'version=v[0-9.]*' module.prop | cut -d'=' -f2 | sed 's/v//')
fi

if [ -z "$versionCode" ]; then
    versionCode=$(grep versionCode module.prop | cut -d "=" -f2)
    versionCode=$((versionCode + 1))
    if [ "$(echo "$version > $last_version" | bc -l)" -eq 1 ]; then
        first_two=$(echo "$versionCode" | sed -E 's/^([0-9]{2}).*/\1/')
        first_two=$((first_two + 1))
        versionCode=$(echo "$versionCode" | sed -E "s/[0-9]{2}(.*)/$first_two\1/")
    fi
fi

# U think I lazy to type? No, i just really forgetful sometimes
sed -i "s/version=v[0-9.]*-beta-psi/version=v$version-beta-psi/g; s/versionCode=[0-9]*/versionCode=$versionCode/g" module.prop
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$version-beta-psi\"/" meZram.json
sed -i "s/\"versionCode\": \"[^\"]*\"/\"versionCode\": \"$versionCode\"/" meZram.json
sed -i "s#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta-psi/meZram-v[0-9.]*_[0-9]*-beta-psi.zip\",#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta-psi/meZram-v$version\_$versionCode-beta-psi.zip\",#g; s#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*-beta-psi/meZram-v[0-9.]*_[0-9]*-beta-psi-changelog.md\"#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v$version-beta-psi/meZram-v$version\_$versionCode-beta-psi-changelog.md\"#g" meZram.json

changelog_file=$(find . -type f -iname "*changelog*")
mv -f "$changelog_file" "meZram-v${version}_$versionCode-beta-psi-changelog.md"

7za a "packages/meZram-v${version}_$versionCode-beta-psi.zip" . \
    -x!meZram.json \
    -x!meZram*changelog.md \
    -x!wrapit.sh \
    -x!README.md \
    -x!packages \
    -x!.git \
    -x!pic \
    -x!tmp
    -x!vid
