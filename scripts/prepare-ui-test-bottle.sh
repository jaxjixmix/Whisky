#!/bin/bash
#
# prepare-ui-test-bottle.sh
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Creates a disposable bottle in the app's container so WhiskyUITests does not
# skip every bottle-dependent case on a fresh CI runner.
#
# Usage: WHISKY_CONTAINER_DIR=/tmp/... scripts/prepare-ui-test-bottle.sh

set -euo pipefail

BUNDLE_ID="${WHISKY_UI_TEST_BUNDLE_ID:-com.franke.Whisky}"
CONTAINER="${WHISKY_CONTAINER_DIR:-$HOME/Library/Containers/$BUNDLE_ID}"
BOTTLE="$CONTAINER/Bottles/UITestBottle"

rm -rf "$BOTTLE"
mkdir -p "$BOTTLE/drive_c/Program Files" "$BOTTLE/drive_c/users/crossover"

cat > "$BOTTLE/Metadata.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>fileVersion</key>
	<dict>
		<key>major</key><integer>1</integer>
		<key>minor</key><integer>0</integer>
		<key>patch</key><integer>0</integer>
		<key>preRelease</key><string></string>
		<key>build</key><string></string>
	</dict>
	<key>info</key>
	<dict>
		<key>name</key><string>UITest</string>
		<key>pins</key><array/>
		<key>blocklist</key><array/>
	</dict>
</dict>
</plist>
EOF

cat > "$CONTAINER/BottleVM.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>fileVersion</key>
	<dict>
		<key>major</key><integer>1</integer>
		<key>minor</key><integer>0</integer>
		<key>patch</key><integer>0</integer>
		<key>preRelease</key><string></string>
		<key>build</key><string></string>
	</dict>
	<key>paths</key>
	<array>
		<string>file://$BOTTLE</string>
	</array>
</dict>
</plist>
EOF

plutil -lint "$BOTTLE/Metadata.plist" "$CONTAINER/BottleVM.plist"
echo "Created UI test bottle at $BOTTLE"
