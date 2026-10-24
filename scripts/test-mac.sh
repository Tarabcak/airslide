#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -D AIRSLIDE_TESTING -parse-as-library macos/AirSlide.swift macos/Tests/BehaviorTests.swift -o build/airslide-tests -framework SwiftUI -framework CoreMotion
build/airslide-tests
