#!/data/data/com.termux/files/usr/bin/bash
# build.sh OUT INPUT RULE...
D="$(command dirname "$0")"; out=$1; input=$2; shift 2
{ echo '        .data'
  echo '        .global src'
  echo '        .global tape'
  echo 'src:'
  for r in "$@"; do printf '        .ascii "%s\\n"\n' "$r"; done
  echo '        .byte 0'
  echo '        .balign 8'
  echo 'tape:'
  printf '        .ascii "%s\\n"\n' "$input"
  echo '        .space 512'
} > "$D/prog.s"
clang -nostdlib -static -Wl,--build-id=none -o "$out" "$D/core.s" "$D/prog.s"
