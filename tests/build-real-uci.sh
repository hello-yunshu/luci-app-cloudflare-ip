#!/usr/bin/env bash
# Build the real CLI in a new isolated prefix. Never installs into the host prefix.
set -euo pipefail
DEST="${1:?new absolute build directory required}"
[[ "$DEST" == /* && ! -e "$DEST" ]] || { echo 'a new absolute build directory is required' >&2; exit 1; }
mkdir -p "$DEST"
fetch_source() {
    local name="$1" commit="$2"
    git init -q "$DEST/$name-source"
    git -C "$DEST/$name-source" remote add origin "https://github.com/openwrt/$name.git"
    git -C "$DEST/$name-source" fetch --depth 1 origin "$commit"
    git -C "$DEST/$name-source" checkout -q --detach FETCH_HEAD
    [[ "$(git -C "$DEST/$name-source" rev-parse HEAD)" == "$commit" ]]
}
fetch_source libubox da2d205a5cf3e877c45a2eec488218cbaf452e7d
fetch_source uci 74f6277aabffc943d026f406df57c22595134c42
cmake -S "$DEST/libubox-source" -B "$DEST/libubox-build" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX="$DEST/prefix"
cmake --build "$DEST/libubox-build" -j 2
cmake --install "$DEST/libubox-build"
cmake -S "$DEST/uci-source" -B "$DEST/uci-build" -DBUILD_LUA=OFF -DCMAKE_PREFIX_PATH="$DEST/prefix" -DCMAKE_INSTALL_PREFIX="$DEST/prefix"
cmake --build "$DEST/uci-build" -j 2
test -x "$DEST/uci-build/uci"
printf 'Real UCI CLI: %s\n' "$DEST/uci-build/uci"
