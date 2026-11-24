#!/usr/bin/env bash
# Creates the Flutter project, drops in the app code, adds dependencies and
# patches the Android config. Run from the folder containing this script:
#   ./setup.sh            -> creates ./wesu1_app
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-wesu1_app}"

flutter create --platforms=android --org dev.wesu1 "$APP"
cd "$APP"

rm -rf lib test
cp -r "$HERE/lib" ./lib

flutter pub add flutter_reactive_ble:^5.4.0 \
                flutter_local_notifications:^19.0.0 \
                permission_handler:^12.0.0 \
                shared_preferences:^2.3.0

python3 "$HERE/tools/patch_android.py" . || echo ">>> Patch step needs manual attention, see README.md"

echo
echo "Done. Plug in your phone (USB debugging on) and run:"
echo "  cd $APP && flutter run"
