#!/usr/bin/env bash
# Compiles the app's UI-free logic (Core/Domain, Core/Models, Core/Support, the songbook logic) together with the
# tests in Tests/LogicTests and runs them. The app package itself has no test target: Swift Playgrounds cannot run one.
#
#   macOS: needs Xcode or the Command Line Tools (swiftc)
#   Linux: needs a Swift toolchain, see https://www.swift.org/install/linux/
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/Agora.swiftpm"
out="${TMPDIR:-/tmp}/agora-logic-tests"
mkdir -p "$out"

flags=(-swift-version 5 -parse-as-library)
# The logic uses Foundation API of macOS 14 / iOS 17 (the app's minimum)
if [[ "$(uname -s)" == "Darwin" ]]; then flags+=(-target "$(uname -m)-apple-macosx14.0"); fi

swiftc "${flags[@]}" -o "$out/logic-tests" \
  "$app"/Core/Domain/*.swift \
  "$app"/Core/Models/*.swift \
  "$app"/Core/Support/*.swift \
  "$app"/Features/Songbook/SongbookLogic.swift \
  "$root"/Tests/LogicTests/*.swift

"$out/logic-tests"
