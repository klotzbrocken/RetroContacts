#!/bin/bash
# Regenerates the README images from the app (demo data, no real contacts): ./docs/make-screenshots.sh
cd "$(dirname "$0")/.."
B="build/RetroContacts.app/Contents/MacOS/RetroContacts"; T=/tmp/rc-shots; mkdir -p $T docs/screenshots
EN='-AppleLanguages (en) -AppleLocale en_US'
shot() { name=$1; shift; "$B" --demo "$@" --snapshot $T/$name.png -AppleLanguages "(en)" -AppleLocale en_US 2>/dev/null; }
shot hero      --mode 0
shot list-card --mode 1
shot card      --mode 2
python3 docs/process-screenshots.py $T
