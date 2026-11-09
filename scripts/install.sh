#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
echo "==> Installing to /Applications/Plain.app"
pkill -x Plain 2>/dev/null || true
rm -rf /Applications/Plain.app
cp -R build/Plain.app /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Plain.app
# Make sure plain:// links open the installed copy, not the build folder.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/Plain.app 2>/dev/null || true
open /Applications/Plain.app
echo "Plain is running. Look for Wren in the menu bar. Quick start: ⌃⌥F"
