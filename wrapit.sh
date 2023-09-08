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
sed -i "s/version=v[0-9.]*/version=v$version/g; s/versionCode=[0-9]*/versionCode=$versionCode/g" module.prop
sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$version\"/" meZram.json
sed -i "s/\"versionCode\": \"[^\"]*\"/\"versionCode\": \"$versionCode\"/" meZram.json
sed -i "s#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*/meZram-v[0-9.]*_[0-9]*.zip\",#\"zipUrl\": \"https://github.com/lululoid/meZram/releases/download/v$version/meZram-v$version\_$versionCode.zip\",#g; s#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v[0-9.]*/meZram-v[0-9.]*_[0-9]*-changelog.md\"#\"changelog\": \"https://github.com/lululoid/meZram/releases/download/v$version/meZram-v$version\_$versionCode-changelog.md\"#g" meZram.json

module_name=$(sed -n 's/id=\(.*\)/\1/p' module.prop)
changelog_file=$(find . -type f -iname "*changelog.md")

mv "$changelog_file" "$module_name-v${version}_$versionCode-changelog.md"
7za a "packages/$module_name-v${version}_$versionCode.zip" . \
	-x!meZram.json \
	-x!meZram*changelog.md \
	-x!wrapit.sh \
	-x!README.md \
	-x!packages \
	-x!.git \
	-x!pic \
	-x!tmp \
  -x!test*
