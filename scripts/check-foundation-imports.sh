#!/bin/sh
# HARKit must not import full Foundation except as the fallback of
# `#if canImport(FoundationEssentials)` (see CONSTRAINTS.md).
set -eu
status=0
for file in $(grep -rl '^import Foundation$' Sources/HARKit || true); do
    if ! grep -B3 '^import Foundation$' "$file" | grep -q '#else'; then
        echo "$file: 'import Foundation' outside the FoundationEssentials fallback"
        status=1
    fi
done
if grep -rn 'import FoundationNetworking' Sources/HARKit; then
    echo "HARKit must not import FoundationNetworking"
    status=1
fi
exit "$status"
