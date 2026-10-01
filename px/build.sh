#!/data/data/com.termux/files/usr/bin/bash
# build.sh -- assemble px next to its source
D="$(command dirname "$0")"
clang -nostdlib -static -Wl,--build-id=none -o "$D/px" "$D/px.s"
