#!/bin/bash
# Typecheck the app target without Xcode.
#
# Command Line Tools has no Sparkle package and no SwiftUI Preview macro
# plugin. Stub Sparkle and strip #Preview blocks, then typecheck every app
# source file against the WhiskyKit module built by SwiftPM.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STUB=$(mktemp -d)
SRC=$(mktemp -d)
trap 'rm -rf "$STUB" "$SRC"' EXIT

cat > "$STUB/Sparkle.swift" <<'SWIFT'
import Foundation

public final class SPUUpdater: NSObject {
    @objc dynamic public var canCheckForUpdates: Bool = true
    public override init() { super.init() }
    public func checkForUpdates() {}
}

public final class SPUStandardUpdaterController: NSObject {
    public let updater = SPUUpdater()
    public init(startingUpdater: Bool, updaterDelegate: AnyObject?, userDriverDelegate: AnyObject?) {
        super.init()
        _ = startingUpdater
        _ = updaterDelegate
        _ = userDriverDelegate
    }
}
SWIFT

SDK=$(xcrun --show-sdk-path)
swiftc -emit-module -parse-as-library -module-name Sparkle \
    -sdk "$SDK" -target arm64-apple-macos14.0 \
    -o "$STUB/Sparkle.swiftmodule" "$STUB/Sparkle.swift"

BIN=$(cd "$ROOT/WhiskyKit" && swift build --show-bin-path)

cd "$ROOT"
find Whisky -name '*.swift' -print0 | while IFS= read -r -d '' f; do
    mkdir -p "$SRC/$(dirname "$f")"
    python3 - "$f" "$SRC/$f" <<'PY'
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
out = []
i = 0
while True:
    j = text.find('#Preview', i)
    if j == -1:
        out.append(text[i:])
        break
    out.append(text[i:j])
    k = text.find('{', j)
    if k == -1:
        break
    depth = 0
    n = k
    while n < len(text):
        if text[n] == '{':
            depth += 1
        elif text[n] == '}':
            depth -= 1
            if depth == 0:
                n += 1
                break
        n += 1
    while n < len(text) and text[n] == '\n':
        n += 1
    i = n
open(dst, 'w').write(''.join(out))
PY
done

find "$SRC/Whisky" -name '*.swift' -print0 | xargs -0 swiftc -typecheck \
    -swift-version 5 -sdk "$SDK" -target arm64-apple-macos14.0 \
    -I "$BIN/Modules" -I "$STUB"

echo "App typecheck OK"
