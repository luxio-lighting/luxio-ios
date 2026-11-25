#!/bin/zsh
set -eu
cd "${0:A:h}"
python3 render-ipad.py
profile="$PWD/../../.sdk/ipad-marketing-chrome"
for slug in 01-control 02-colors 03-animations 04-settings 05-matter; do
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
    --headless --disable-gpu --no-first-run --no-default-browser-check \
    --user-data-dir="$profile" --allow-file-access-from-files --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=2752,2064 --virtual-time-budget=3000 \
    --screenshot="$PWD/ipad-13/$slug.png" "file://$PWD/ipad-13/$slug.html"
done
