#!/usr/bin/env bash
# Build the Mac-side parser harness from the same Swift sources the app uses (no UIKit, no Photos).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun --sdk macosx swiftc -O -target arm64-apple-macos13.0 -o build/pogolens-cli \
  tools/cli/main.swift \
  ios/PogoLens/Sources/Model/GameData.swift ios/PogoLens/Sources/Model/Formula.swift ios/PogoLens/Sources/Model/ScannedPokemon.swift ios/PogoLens/Sources/Model/BoxBuilder.swift \
  ios/PogoLens/Sources/Shared/AppGroup.swift ios/PogoLens/Sources/Scan/TextRecognizer.swift ios/PogoLens/Sources/Scan/ScreenParser.swift ios/PogoLens/Sources/Scan/AppraisalReader.swift
echo "built build/pogolens-cli"
