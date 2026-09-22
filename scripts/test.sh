#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -emit-library -emit-module -module-name PilotCore Sources/PilotCore/*.swift -o .build/libPilotCore.dylib -emit-module-path .build/PilotCore.swiftmodule -module-cache-path .build/ModuleCache -Xlinker -install_name -Xlinker @rpath/libPilotCore.dylib
swiftc -parse-as-library -I .build -L .build -lPilotCore scripts/SmokeTests.swift -o .build/SmokeTests -module-cache-path .build/ModuleCache -Xlinker -rpath -Xlinker @executable_path
.build/SmokeTests
