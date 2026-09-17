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


tmp=$(mktemp) || exit 1; trap 'rm -f "$tmp"' EXIT
rule() { # rule NAME INPUT EXPECTED RULE...
  local name=$1 input=$2 want=$3; shift 3
  printf '%s\n' "$@" > "$tmp"
  local got; got=$(./rw "$tmp" "$input" 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf 'ok   %-18s %s\n' "$name" "$input"
  else
    fail=$((fail+1)); printf 'FAIL %-18s want %s got %s\n' "$name" "$want" "$got"
  fi
}

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

check first/hit    first.rw   '00101101'  '00[101]101'
check first/miss   first.rw   '000'       '000'

check binadd/ex     binadd.rw  '<1011+110>'  '10001'
check binadd/zero   binadd.rw  '<0+0>'       '0'
check binadd/carry  binadd.rw  '<1+1>'       '10'
check binadd/ripple binadd.rw  '<1111+1>'    '10000'
check binadd/left   binadd.rw  '<110+1>'     '111'
check binadd/right  binadd.rw  '<1+110>'     '111'
check binadd/empty  binadd.rw  '<+1>'        '1'
# leading zeros go in but do not come out, and the answer still has to be
# right when the carry ripples the whole way
check binadd/lead   binadd.rw  '<010+001>'   '11'
check binadd/wide   binadd.rw  '<1111111111111111+1>' '10000000000000000'

check binmul/ex     binmul.rw  '<1011*110>'  '1000010'
check binmul/zero   binmul.rw  '<0*0>'       '0'
check binmul/one    binmul.rw  '<1*1>'       '1'
check binmul/pow    binmul.rw  '<100*100>'   '10000'
check binmul/square binmul.rw  '<111*111>'   '110001'
check binmul/longer binmul.rw  '<1*1011>'    '1011'
check binmul/lead   binmul.rw  '<0011*0011>' '1001'
check binmul/empty  binmul.rw  '<101*>'      '0'
check binmul/wide   binmul.rw  '<11111111*11111111>' '1111111000000001'
# regression: with the launch rule above the token-movement rules, a token in
# transit shoved the next multiplier bit back against the $ and launched a
# second one. Anything with a multi-bit multiplier catches it; this returned
# "EF0" rather than failing outright.
check binmul/relaunch binmul.rw '<10*11>'    '110'

check palin/empty  palin.rw   '<>'        'yes'
check palin/one    palin.rw   '<a>'       'yes'
check palin/even   palin.rw   '<abba>'    'yes'
check palin/odd    palin.rw   '<aabaa>'   'yes'
check palin/no     palin.rw   '<abb>'     'no'
check palin/long   palin.rw   '<abaababaaba>' 'yes'
check palin/long-no palin.rw  '<abaababaabb>' 'no'
# rule-order regression: with pick-up above the far-end rules this answered
# "<BA>", having grabbed a second letter while the first was still in flight
check palin/inflight palin.rw '<ab>'      'no'

# terminal rules: "->." rewrites once and stops, even with the tape still
# matching. Each pair below is the same rule, one dot apart.
rule term/once      'aaa' 'Xaa'    'a->.X'
rule term/ordinary  'aaa' 'XXX'    'a->X'
rule term/empty-rhs 'aaa' 'aa'     'a->.'
rule term/grow      'ab'  'aZZZ'   'b->.ZZZ'
rule term/dot-out   'ab'  'a.'     'b->..'
rule term/outranked 'ab'  'cSTOP'  'a->c' 'b->.STOP'
# first.rw's rule contains its own lhs: strip the dot and it eats the tape
printf '101->[101]\n' > "$tmp"
got=$(./rw "$tmp" '00101101' 2>&1 >/dev/null); rc=$?
if [ "$got" = "rw: tape overflow" ] && [ "$rc" -eq 3 ]; then
  pass=$((pass+1)); printf 'ok   %-18s %s\n' "term/selfmatch" "runs away without the dot"
else
  fail=$((fail+1)); printf 'FAIL %-18s rc=%s msg=%s\n' "term/selfmatch" "$rc" "$got"
fi

# 27 peaks at 9232, past the 4096-byte tape. The limit is real, so assert it:
# rw must report overflow and exit 3 rather than quietly truncating.
got=$(./rw progs/collatz.rw "<$(u 27)." 2>&1 >/dev/null); rc=$?
if [ "$got" = "rw: tape overflow" ] && [ "$rc" -eq 3 ]; then
  pass=$((pass+1)); printf 'ok   %-18s %s\n' "collatz/27-ovf" "overflow, exit 3"
else
  fail=$((fail+1)); printf 'FAIL %-18s rc=%s msg=%s\n' "collatz/27-ovf" "$rc" "$got"
fi

# The README quotes rw's instruction count, its size, and a per-phase
# breakdown. Derive all three from the binary and the source rather than
# trusting them. The phase boundaries are marked in rw.s itself
# ("// -- phase: ..."), so moving code between sections moves the count with
# it and this check catches a README that did not follow.
if command -v llvm-objdump >/dev/null 2>&1 && [ -f ../README.md ]; then
  got_n=$(llvm-objdump -d rw | awk '/^ *[0-9a-f]+:/{c++} END{print c}')
  got_b=$(stat -c %s rw)
  want_n=$(sed -n 's/^| \*\*\([0-9]*\)\*\* | \*\*total\*\* |$/\1/p' ../README.md)
  want_b=$(sed -n 's/.*instructions in \([0-9]*\) bytes.*/\1/p' ../README.md)
  if [ "$got_n" = "$want_n" ] && [ "$got_b" = "$want_b" ]; then
    pass=$((pass+1)); printf 'ok   %-18s %s instructions, %s bytes\n' "readme/total" "$got_n" "$got_b"
  else
    fail=$((fail+1)); printf 'FAIL %-18s README says %s instr / %s bytes, rw is %s / %s\n' \
      "readme/total" "$want_n" "$want_b" "$got_n" "$got_b"
  fi

  src_rows=$(awk '
    /^\/\/ -- phase: / { name=substr($0, 14); order[++k]=name; cnt[name]+=0; next }
    { line=$0
      sub(/^[._A-Za-z][A-Za-z0-9_]*:/, "", line)
      if (name != "" && line ~ /^[ \t]+[a-z]/) cnt[name]++ }
    END { for (i=1;i<=k;i++) printf "%d|%s\n", cnt[order[i]], order[i] }' rw.s)
  md_rows=$(sed -n 's/^| *\([0-9]\+\) | \(.*\) |$/\1|\2/p' ../README.md)
  sum=$(printf '%s\n' "$src_rows" | awk -F'|' '{s+=$1} END{print s}')
  if [ "$src_rows" = "$md_rows" ] && [ "$sum" = "$got_n" ]; then
    pass=$((pass+1))
    printf 'ok   %-18s %s rows, summing to %s\n' "readme/phases" \
      "$(printf '%s\n' "$src_rows" | wc -l | tr -d ' ')" "$sum"
  else
    fail=$((fail+1)); printf 'FAIL %-18s rows disagree (sum %s vs %s)\n' "readme/phases" "$sum" "$got_n"
    diff <(printf '%s\n' "$src_rows") <(printf '%s\n' "$md_rows") | sed 's/^/       /'
  fi
fi

printf '\n%d passed, %d failed\n'  "$pass" "$fail"
[ "$fail" -eq 0 ]
