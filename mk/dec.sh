#!/data/data/com.termux/files/usr/bin/bash
# dec.sh OP A [B] -- run the binary programs on decimal numbers.
#
#   dec.sh mul 37 41        1517
#   dec.sh div 1234 56      22 r 2
#   dec.sh sqrt 1234        35 r 9
#   dec.sh gcd 1071 462     21
#
# The programs themselves only speak binary; dec2bin.rw and bin2dec.rw do the
# conversion.
D="$(command dirname "$0")"
rw() { "$D/rw" "$D/progs/$1.rw" "$2"; }
tob() { rw dec2bin "<$1>"; }
tod() { case $1 in -*) printf -- '-%s' "$(rw bin2dec "<${1#-}>")";; *) rw bin2dec "<$1>";; esac; }
# split "QrR" into two decimal numbers
pair() { printf '%s r %s' "$(tod "${1%%r*}")" "$(tod "${1#*r}")"; }

op=$1; a=$(tob "$2"); [ $# -ge 3 ] && b=$(tob "$3")
case $op in
  add)  tod "$(rw binadd "<$a+$b>")";;
  sub)  tod "$(rw binsub "<$a-$b>")";;
  mul)  tod "$(rw binmul "<$a*$b>")";;
  div)  pair "$(rw bindiv "<$b)$a>")";;
  sqrt) pair "$(rw binsqrt "<$a>")";;
  gcd)  tod "$(rw bingcd "<$a,$b>")";;
  cmp)  rw bincmp "<$a?$b>";;
  *)    echo "usage: dec.sh add|sub|mul|div|sqrt|gcd|cmp A [B]" >&2; exit 1;;
esac
