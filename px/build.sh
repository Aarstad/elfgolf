#!/data/data/com.termux/files/usr/bin/bash
# build.sh -- assemble px and life next to their sources
D="$(command dirname "$0")"
for p in px life; do
  clang -nostdlib -static -Wl,--build-id=none -o "$D/$p" "$D/$p.s" || exit
done
