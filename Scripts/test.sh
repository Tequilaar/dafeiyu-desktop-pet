#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/clang-cache .build/module-cache .build/spm-cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
swift test --disable-xctest --enable-swift-testing --build-system native -debug-info-format none --disable-sandbox --scratch-path "$ROOT/.build" --cache-path "$ROOT/.build/spm-cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" --manifest-cache local -Xswiftc -module-cache-path -Xswiftc "$ROOT/.build/module-cache" -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS"
