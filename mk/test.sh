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

check bindiv/ex     bindiv.rw  '<11)1011>'   '11r10'
check bindiv/one    bindiv.rw  '<1)1>'       '1r0'
check bindiv/exact  bindiv.rw  '<10)110>'    '11r0'
check bindiv/self   bindiv.rw  '<11)11>'     '1r0'
check bindiv/byone  bindiv.rw  '<1)1010>'    '1010r0'
# divisor larger than dividend: the compare must borrow out every time, and
# crucially must leave the remainder alone when it does
check bindiv/toobig bindiv.rw  '<101)10>'    '0r10'
check bindiv/zeroN  bindiv.rw  '<11)0>'      '0r0'
check bindiv/lead   bindiv.rw  '<0011)001011>' '11r10'
check bindiv/wide   bindiv.rw  '<1111)11111111>' '10001r0'
# dividing by zero is nonsense, but it has to halt rather than spin
check bindiv/byzero bindiv.rw  '<0)1011>'    '1111r1011'

check sqrt/nine    binsqrt.rw '<1001>'      '11r0'
check sqrt/ten     binsqrt.rw '<1010>'      '11r1'
check sqrt/zero    binsqrt.rw '<0>'         '0r0'
check sqrt/one     binsqrt.rw '<1>'         '1r0'
check sqrt/two     binsqrt.rw '<10>'        '1r1'
check sqrt/four    binsqrt.rw '<100>'       '10r0'
check sqrt/255     binsqrt.rw '<11111111>'  '1111r11110'
# odd-length input needs a leading 0 so the pairs line up from the low end
check sqrt/oddlen  binsqrt.rw '<11001>'     '101r0'
check sqrt/padded  binsqrt.rw '<0000011001>' '101r0'
# a root that itself ends in 01: the rule stripping the trailing 01 off the
# trial value used to match a second time and eat the root two bits at a time
check sqrt/endsin01 binsqrt.rw '<10101010>' '1101r1'

check binsub/ex     binsub.rw  '<1011-110>'  '101'
check binsub/zero   binsub.rw  '<0-0>'       '0'
check binsub/same   binsub.rw  '<101-101>'   '0'
check binsub/borrow binsub.rw  '<1000-1>'    '111'
# going negative: the digits on the tape are the two's complement, so the
# answer is only right if N and C turn them back into a magnitude
check binsub/neg    binsub.rw  '<110-1011>'  '-101'
check binsub/neg1   binsub.rw  '<1-1000>'    '-111'
check binsub/wide   binsub.rw  '<11111111-1>' '11111110'

check bincmp/gt     bincmp.rw  '<1011?110>'  'gt'
check bincmp/lt     bincmp.rw  '<11?1011>'   'lt'
check bincmp/eq     bincmp.rw  '<0011?11>'   'eq'
check bincmp/zero   bincmp.rw  '<0?0>'       'eq'
# equal length, differing only in a low bit: the verdict has to survive the
# walk up through the bits that agree
check bincmp/lowbit bincmp.rw  '<1010?1011>' 'lt'
# and a shorter number with a bigger top bit still loses on length
check bincmp/length bincmp.rw  '<100000?11111>' 'gt'

check gcd/ex       bingcd.rw  '<1100,1000>' '100'
check gcd/one      bingcd.rw  '<1,1>'       '1'
check gcd/same     bingcd.rw  '<1000,1000>' '1000'
check gcd/divides  bingcd.rw  '<1111,101>'  '101'
check gcd/coprime  bingcd.rw  '<1111,1000>' '1'
# the larger operand can be on either side, and the subtraction has to run in
# whichever direction the compare asks for
check gcd/aboveb   bingcd.rw  '<10101,111>' '111'
check gcd/belowa   bingcd.rw  '<111,10101>' '111'
# both even: the common twos are banked in Z and hung back on the answer
check gcd/twos     bingcd.rw  '<110000,100000>' '10000'
check gcd/lead     bingcd.rw  '<0001100,1000>'  '100'
check gcd/wide     bingcd.rw  '<1111111111,110000>' '11'

check dec2bin/zero dec2bin.rw '<0>'         '0'
check dec2bin/ten  dec2bin.rw '<10>'        '1010'
check dec2bin/255  dec2bin.rw '<255>'       '11111111'
check dec2bin/big  dec2bin.rw '<1234>'      '10011010010'
check dec2bin/lead dec2bin.rw '<000255>'    '11111111'
check bin2dec/zero bin2dec.rw '<0>'         '0'
check bin2dec/ten  bin2dec.rw '<1010>'      '10'
check bin2dec/255  bin2dec.rw '<11111111>'  '255'
check bin2dec/big  bin2dec.rw '<10011010010>' '1234'
check bin2dec/lead bin2dec.rw '<00001010>'  '10'
# every carry in the doubling table gets used by a number with a 9 in it
check bin2dec/nines bin2dec.rw '<1111011011>' '987'

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

# -v traces each rewrite to stderr as "rule<TAB>tape", and leaves stdout alone
out=$(./rw -v progs/palin.rw '<abb>' 2>/dev/null)
trc=$(./rw -v progs/palin.rw '<abb>' 2>&1 >/dev/null)
quiet=$(./rw progs/palin.rw '<abb>' 2>&1 >/dev/null | wc -c | tr -d ' ')
lines=$(printf '%s\n' "$trc" | wc -l | tr -d ' ')
last=$(printf '%s\n' "$trc" | tail -1)
if [ "$out" = "no" ] && [ "$quiet" = "0" ] && [ "$lines" = "6" ] && [ "$last" = "$(printf '<W->.no\tno')" ]; then
  pass=$((pass+1)); printf 'ok   %-18s %s rewrites traced, stdout clean\n' "trace/palin" "$lines"
else
  fail=$((fail+1)); printf 'FAIL %-18s out=%s quiet=%s lines=%s last=%s\n' "trace/palin" "$out" "$quiet" "$lines" "$last"
fi

# the flag must not disturb argument handling either way
rule trace/stdin-off 'aaa' 'Xaa' 'a->.X'
if [ "$(printf '<abba>\n' | ./rw -v progs/palin.rw 2>/dev/null)" = "yes" ]; then
  pass=$((pass+1)); printf 'ok   %-18s reads stdin with -v\n' "trace/stdin"
else
  fail=$((fail+1)); printf 'FAIL %-18s -v broke the stdin path\n' "trace/stdin"
fi


# dec.sh is the point of the converters: the binary programs, driven in
# decimal. Check one of each rather than restating the arithmetic tests.
decs() { # decs NAME ARGS... EXPECTED (expected is the last argument)
  local name=$1; shift
  local want=${@: -1}; set -- "${@:1:$#-1}"
  local got; got=$(./dec.sh "$@" 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf 'ok   %-18s %s\n' "$name" "$*"
  else
    fail=$((fail+1)); printf 'FAIL %-18s %s: want %s got %s\n' "$name" "$*" "$want" "$got"
  fi
}
decs dec/add  add 1234 5678 '6912'
decs dec/sub  sub 100 358   '-258'
decs dec/mul  mul 37 41     '1517'
decs dec/div  div 1234 56   '22 r 2'
decs dec/sqrt sqrt 1234     '35 r 9'
decs dec/gcd  gcd 1071 462  '21'
decs dec/cmp  cmp 99 100    'lt'

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
