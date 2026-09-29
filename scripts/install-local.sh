#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="/Applications/Apple Mail AI Plugin.app"

make -C "$project_dir" install

codesign --verify --deep --strict "$app_path"
requirement="$(codesign -dr - "$app_path" 2>&1)"
if [[ "$requirement" != *'designated => identifier "com.aiMailComposer"'* ]]; then
    print -u2 "Installed app does not have the expected stable local requirement."
    exit 1
fi
print "$requirement"
print "Installed with a stable local identity. Accessibility permission will survive later local rebuilds."
