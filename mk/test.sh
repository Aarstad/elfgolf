#!/data/data/com.termux/files/usr/bin/bash
# test.sh -- run every rule set in progs/ against a known answer.
D="$(command dirname "$0")"; cd "$D" || exit 1
[ -x ./rw ] || clang -nostdlib -static -Wl,--build-id=none -o rw rw.s || exit 1

pass=0; fail=0
check() { # check NAME PROG INPUT EXPECTED
  local got; got=$(./rw "progs/$2" "$3" 2>&1)
  if [ "$got" = "$4" ]; then
    pass=$((pass+1)); printf 'ok   %-18s %s\n' "$1" "$3"
  else
    fail=$((fail+1)); printf 'FAIL %-18s %s\n       want %s\n       got  %s\n' "$1" "$3" "$4" "$got"
  fi
}

u() { printf '1%.0s' $(seq "$1"); }   # n in unary

check add        add.rw     '111+11'   '11111'
check add/zero   add.rw     '+111'     '111'
check inc        inc.rw     '1011|'    '1100'
check inc/carry  inc.rw     '111|'     '1000'
check mul        mul.rw     'aa*bbb'   'cccccc'
check sort       sort.rw    'bbaabab'  'aaabbbb'
check tm/bb3     tm.rw      '<A>'      '<0111H111>'

# spin never halts; it must hit the fuel limit rather than the tape limit
check spin       spin.rw    'ab'       "$(printf 'rw: out of fuel\nab')"

# collatz: every start below drops to 1
for n in 1 2 3 6 7 9 11 18; do
  check "collatz/$n" collatz.rw "<$(u $n)." '1.'
done
check r110/glider  rule110.rw '!00000001>####' '00000001/00000011/00000111/00001101/00011111'
check r110/one     rule110.rw '!1>###'          '1/1/1/1'
check r110/zero    rule110.rw '!0>##'           '0/0/0'
check r110/pair    rule110.rw '!010>###'        '010/110/110/110'
# a traveller that overtook another would shuffle the row, not lose it, so a
# wide case with a lot of travellers in flight is the one that would catch it
check r110/wide    rule110.rw "!$(printf '0%.0s' $(seq 15))1>########" \
  '0000000000000001/0000000000000011/0000000000000111/0000000000001101/0000000000011111/0000000000110001/0000000001110011/0000000011010111/0000000111111101'

# 27 peaks at 9232, past the 4096-byte tape. The limit is real, so assert it:
# rw must report overflow and exit 3 rather than quietly truncating.
got=$(./rw progs/collatz.rw "<$(u 27)." 2>&1 >/dev/null); rc=$?
if [ "$got" = "rw: tape overflow" ] && [ "$rc" -eq 3 ]; then
  pass=$((pass+1)); printf 'ok   %-18s %s\n' "collatz/27-ovf" "overflow, exit 3"
else
  fail=$((fail+1)); printf 'FAIL %-18s rc=%s msg=%s\n' "collatz/27-ovf" "$rc" "$got"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
