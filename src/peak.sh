#!/data/data/com.termux/files/usr/bin/bash
# $1 = label ; rest = env assignments passed via caller env
LD=/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
LP=/data/data/com.termux/files/usr/glibc/lib
BIN=/data/data/com.termux/files/usr/bin/claude.glibc
"$LD" --library-path "$LP" "$BIN" --version >/dev/null 2>&1 &
pid=$!
peak=0
while command kill -0 $pid 2>/dev/null; do
  r=$(command awk '/^VmHWM/{print $2}' /proc/$pid/status 2>/dev/null)
  [ -n "$r" ] && [ "$r" -gt "$peak" ] 2>/dev/null && peak=$r
done
wait $pid
echo "$1 peakRSS=$((peak/1024))MB"
