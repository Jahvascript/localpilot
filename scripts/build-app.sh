#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -emit-library -emit-module -module-name PilotCore Sources/PilotCore/*.swift -o .build/libPilotCore.dylib -emit-module-path .build/PilotCore.swiftmodule -module-cache-path .build/ModuleCache -Xlinker -install_name -Xlinker @rpath/libPilotCore.dylib
swiftc -O -parse-as-library -I .build -L .build -lPilotCore Sources/LocalPilot/*.swift -o .build/LocalPilot -module-cache-path .build/ModuleCache -Xlinker -rpath -Xlinker @executable_path/../Frameworks
APP="$PWD/LocalPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp .build/LocalPilot "$APP/Contents/MacOS/LocalPilot.new"
mv -f "$APP/Contents/MacOS/LocalPilot.new" "$APP/Contents/MacOS/LocalPilot"
cp .build/libPilotCore.dylib "$APP/Contents/Frameworks/libPilotCore.dylib.new"
mv -f "$APP/Contents/Frameworks/libPilotCore.dylib.new" "$APP/Contents/Frameworks/libPilotCore.dylib"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalPilot</string>
<key>CFBundleIdentifier</key><string>local.localpilot.prototype</string>
<key>CFBundleName</key><string>LocalPilot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSMicrophoneUsageDescription</key><string>Transcribe your command locally while you press Speak. Audio is not saved.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Recognize commands using on-device speech only. No cloud fallback.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Frameworks/libPilotCore.dylib"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
