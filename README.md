# elfgolf

Shrinking a "Hi!\n" aarch64 Linux executable from **992 bytes to 112**, built
and run on the phone. Plus a proof that 112 is the floor for this technique,
and an unrelated Markov rewriter in bare assembly.

```sh
$ ./hello112 ; stat -c %s hello112
Hi!
112
```

## The trick

A static ELF needs an `Elf64_Ehdr` (64 bytes) and one `Elf64_Phdr` (56 bytes).
That is 120 bytes before a single instruction exists — so the instructions have
to live *inside* the headers, in the fields the kernel loader never reads.

Three four-instruction islands are hidden in `e_ident`, `e_shoff`/`e_flags`, and
`p_paddr`, each ending in a `b` to the next, with the `write`/`exit` tail
written over `p_align`. The string doubles as `p_vaddr`: `"Hi!\n\0\0\0\0"` read
as a little-endian u64 is `0x0A216948`, used as the load address, with
`p_offset` set to its low 12 bits to keep the mapping page-congruent. The
message costs no bytes of its own.

That is how the file gets below the 120-byte header minimum: `PH + 56 == 112`,
with the program header's own tail bytes being executable code.

`floor.py` asserts that bound rather than asserting a size — if a future edit
shaves a byte somewhere, the assert says whether it was actually possible.

## Layout

- `hello112` — the artifact, 112 bytes, verified running under Termux on
  Android 16 (it is static and uses raw syscalls, so any aarch64 Linux should
  take it, but that is untested)
- `floor.py` — the final builder, written to prove the floor
- `src/` — the working builders in order: `golf.py` → `golf4.py`, then
  `final.py`; `vaddr.py` for the address/string coincidence, `hello.s` for the
  992-byte starting point
- `stages/` — every intermediate binary kept: 992, 592, 186, 178, 144, 140, 136,
  128, 124, 120, 116, 112
- `probes/` — `probe.py` builds deliberately malformed ELFs to find which header
  fields the kernel actually validates; `t1`–`t4`, `f3` are the survivors

## mk/ — a Markov rewriter

Unrelated to the golfing, from the same sitting. A Markov-style string rewriter
in aarch64 assembly: no libc, no stack, no allocation. Rules are `lhs->rhs`,
one per line; it rewrites the leftmost match of the first matching rule and
restarts, halting when nothing matches.

Every number in this file is either asserted by a row in `mk/test.sh` or
labelled *calculated*. That convention exists because of a bad night's work:
three claims here turned out to be wrong — the block-encoding argument, the
"wider table" remark in `enc.rw`, and the self-application estimate — and all
three were prose, with the test suite green throughout. Tests guard the claims
somebody troubled to turn into tests. Everything else runs unguarded.

A rule written `lhs->.rhs` is *terminal*: it rewrites once and stops, whether
or not anything still matches. That is Markov's own notation, and it buys the
one thing rule order cannot. `first.rw` is the whole argument in a single rule:

```
101->.[101]        # rw progs/first.rw '00101101'  ->  00[101]101
```

The right-hand side contains the left-hand side, so without the dot the rule
brackets its own brackets until the tape overflows. Terminal rules add no
computational power — they add the ability to stop while the tape still
matches, which is what "the first occurrence" needs.

Two front ends. `rw` is an interpreter — it reads a `.rw` rule file and takes
the tape as an argument or on stdin:

```sh
mk/rw mk/progs/add.rw '111+11'        # -> 11111
```

`build.sh` instead assembles a program *into* a binary: it emits the rules and
the tape as a `.data` section and links them with `core.s`, so the result is a
standalone executable with the rewrite rules baked in.

```sh
mk/build.sh /tmp/add '111+11' '1+->+1' '+->'
```

`mk/progs/` holds the rule files:

| | |
|---|---|
| `add` | unary addition, by sliding the `+` rightwards |
| `inc` | binary increment with an explicit carry marker |
| `mul` | unary multiply |
| `sort` | adjacent-swap sort over `{a,b}` |
| `spin` | oscillates forever without growing — exercises the fuel limit |
| `tm` | a Turing machine: the 3-state busy beaver |
| `collatz` | the Collatz map in unary, iterated to 1 |
| `rule110` | the elementary cellular automaton, with its space-time diagram |
| `collide` | two gliders, and what is left where they meet |
| `fetch` | an indexed read, and what one costs |
| `padd` | addition with the operands interleaved, and what that saves |
| `first` | brackets the first `101` and stops — one terminal rule |
| `palin` | palindrome over `{a,b}`, eaten from both ends |
| `rw` | rw itself: a rewriter interpreting a rewriter |
| `enc` | source alphabet in, `{0,1,2}` out, for `rw.rw` |
| `binadd` | binary addition, a column at a time, carry and all |
| `binsub` | binary subtraction, negative answers included |
| `bincmp` | compares two binary numbers: `lt`, `eq` or `gt` |
| `binmul` | binary multiplication, by shift and add |
| `bindiv` | binary long division, quotient and remainder |
| `binsqrt` | integer square root, digit by digit |
| `bingcd` | greatest common divisor, Stein's algorithm |
| `dec2bin` | decimal in |
| `bin2dec` | decimal out |

`tm.rw` is the Turing-completeness argument made concrete. State and head
position live *in* the tape — the head marker sits just left of the cell being
read — so one transition is one local rewrite, `Xs -> tQ` to move right and
`xXs -> Qxt` to move left. Halting is free: no rule mentions the halt state, so
when the head becomes `H` nothing matches and the rewriter stops on its own.

The machine is the 3-state busy beaver champion, `1RB1RH_0RC1RB_1LC1LA`. From
a blank tape it halts after 14 steps with six `1`s, the known BB(3) answer, and
lands on the tape `111H111` — the leading `0` below is a blank the left-edge
rule supplied and the machine never wrote on.

```sh
mk/rw mk/progs/tm.rw '<A>'            # -> <0111H111>
```

`collatz.rw` keeps exactly one marker alive on the tape at any moment, which is
what makes the rule order unambiguous: a parity walk eats the `1`s into `a`s
and toggles even/odd, then either a halving pass or a tripling pass rebuilds
the number and hands the marker back to the left edge.

```sh
mk/rw mk/progs/collatz.rw '<1111111.'  # 7 -> ... -> 1.
```

`27` peaks at 9232. That overran the tape when `TAPEMAX` was 4096 and the
program reported `rw: tape overflow` rather than truncating; at 65536 it fits
and runs to `1.`. The limit is still real and still asserted — `first.rw` with
its dot stripped grows without bound and overflows in a few thousand rewrites.

`rule110.rw` is the second completeness argument in `progs/`: `tm.rw` makes it
by simulation, this one by citation. The awkward part is that on a
one-dimensional tape the old row and the new row want the same span —
overwriting in place destroys the history, and interleaving the two rows only
postpones the problem, since separating them afterwards costs a quadratic
shuffle.

So the new cells are not written where they are computed. The sweep marker
walks rightwards over the old row without touching it, and each cell it
computes is launched as a *traveller* that runs to the far end of the tape and
lands past the row's end, where the next generation assembles itself in order.
Only one traveller is ever in flight: the traveller rules sit above the sweep
rules, so a moving traveller always matches first and freezes the sweep. That
one ordering fact is the whole correctness argument — two travellers in flight
could overtake each other and the row would come out shuffled.

```sh
mk/rw mk/progs/rule110.rw "!$(printf '0%.0s' $(seq 47))1>$(printf '#%.0s' $(seq 24))" \
  | tr / '\n' | tr 01 ' #'
```

```
                                               #
                                              ##
                                             ###
                                            ## #
                                           #####
                                          ##   #
                                         ###  ##
                                        ## # ###
                                       ####### #
                                      ##     ###
                                     ###    ## #
                                    ## #   #####
                                   #####  ##   #
                                  ##   # ###  ##
                                 ###  #### # ###
                                ## # ##  ##### #
                               ######## ##   ###
                              ##      ####  ## #
                             ###     ##  # #####
                            ## #    ### ####   #
                           #####   ## ###  #  ##
                          ##   #  ##### # ## ###
                         ###  ## ##   ######## #
                        ## # ######  ##      ###
                       #######    # ###     ## #
```

`binadd.rw` gets its answer ordering out of the layout. Addition wants to
start at the least significant end, but the two operands end in different
places — one before the `+`, one before the `>` — so each column is run by
turning the last bit of the right operand into a traveller and walking it left
to the carry marker, which sits where the `+` was and holds the carry in its
own identity: `P` for none, `Q` for one.

That marker is also where the answer is built, and each result bit is
deposited immediately to its right. Since columns arrive least significant
first, every new bit lands to the left of the one before it — so the answer
comes out most significant first without anything being reversed.

```sh
mk/rw mk/progs/binadd.rw '<1011+110>'   # 10001
```

Checked against every pair of operands up to 63, and it is only the tape that
limits the width: two 200-bit numbers add fine.

`rw -v` traces every rewrite to stderr as the rule that fired and the tape it
produced, which is how you find a program that stalls rather than fails:

```
$ mk/rw -v mk/progs/palin.rw '<abb>'
<a-><A	<Abb>
Ab->bA	<bAb>
Ab->bA	<bbA>
bA>->W	<bW
bW->W	<W
<W->.no	no
no
```

Only the last line is on stdout, so a trace can be watched while the answer is
still piped somewhere.

`rw -f N` caps the run at `N` rewrites instead of the built-in `FUEL`. That is
what makes a non-halting program cheap to assert: `spin.rw` never stops, and
the test that says so wants the message, not a hundred million rewrites.

```sh
mk/rw -f 1000 mk/progs/spin.rw 'ab'   # -> rw: out of fuel, exit 2
```

The two flags compose in either order. A count that is not a number is a usage
error rather than a silent fall back to the default, on the grounds that a test
meaning to be cheap should fail loudly rather than quietly cost a hundred
million rewrites.

`-f` turned out to be a checkpoint system, which was not why it was added. The
tape is the entire machine state — there are no registers, and the rule pointer
resets after every rewrite — and a run stopped by fuel still emits its tape. So
the output of one slice is a valid input for the next:

```sh
t='<10,01;*1010101010101010>'
while ! out=$(printf '%s\n' "$t" | mk/rw -f 1000 mk/progs/rw.rw); do t=$out; done
```

Thirteen slices of a thousand give the same answer as one run of 12,681, which
`fuel/resumable` asserts. A computation too long to sit through is therefore
resumable rather than unavailable, which matters for anything on the scale of
the section below.

That only works because stdin reads the full tape. It did not, for two commits:
`TAPEMAX` went to 65536 while the stdin read stayed at `BUFSZ`, so a tape past
16K came back silently truncated — the one failure the argv path is explicitly
asserted not to have. One read is also not enough on a pipe, which hands over
what it has rather than what is coming. Both paths now take 65535 symbols and
report overflow above it, and `stdin/width` and `stdin/overflow` hold them
together.

`binsub.rw` is `binadd.rw` with the sign flipped — same layout, same
travellers, `P` and `Q` carrying a borrow instead of a carry. Going negative is
the only part addition never needed: the columns produce the answer modulo two
to the width, so when the borrow falls out of the top what is on the tape is
the two's complement of the answer. `N` walks it flipping every bit and `C`
adds the one back.

The minus sign is not written until the last rewrite: the rule that starts the
program has `-` on its left-hand side, so a sign sitting on the tape any
earlier would be read as another operator.

`bincmp.rw` needs no borrows at all. Walking both numbers from the low end,
each column that disagrees simply overwrites the verdict, and because the walk
ends at the high end the last disagreement is the one that survives — which is
the right answer, since the most significant differing bit decides.

```sh
mk/rw mk/progs/binsub.rw '<110-1011>'   # -101
mk/rw mk/progs/bincmp.rw '<11?1011>'    # lt
```

`binmul.rw` puts an adder inside a loop. For each bit of the multiplier, from
the top, double the accumulator and — if the bit was 1 — add the multiplicand
in. Doubling is free, since it is just appending a 0, so all the work is in
the adding, and this adder cannot eat its operand the way `binadd.rw` does:
the next bit needs the multiplicand again.

```
< multiplicand ^ $ multiplier | accumulator % >
```

Two pointers do it, and each is its own parking space. `^` rests at the
multiplicand's right end and walks left as `@` during an add, emitting one
traveller per bit while stepping over the bit and putting it back. `%` rests
at the accumulator's right end and walks left during an add, holding the
running carry in its own identity — `%` is no carry, `&` is a carry.

There is no program counter anywhere in it. What sequences the phases is rule
order alone: each rule can only fire because everything above it has run out
of matches, and the outer loop sits below the entire add, so it cannot take
another multiplier bit until both pointers have walked home.

```sh
mk/rw mk/progs/binmul.rw '<1011*110>'   # 1000010
```

Checked against every pair of operands up to 31. The ceiling here is the fuel
rather than the tape: 72 bits by 72 bits multiplies, 80 by 80 gives up.

`bindiv.rw` is the first program here that has to *decide*. Everything up to
it could ripple: addition and multiplication commit to each step as they take
it. Long division cannot, because it has to know whether the divisor fits
before it writes anything.

```
< divisor ^ ; quotient | remainder = $ dividend >
```

The divisor comes first because the tape is laid out the way the sum is
written by hand — `11` goes into `1011`. That also puts the dividend at the
far right, next to the remainder, so shifting in the next bit is one rule
rather than a token walking the length of the tape.

Two passes over the divisor, one mechanism. `@` walks it left emitting one
traveller per bit exactly as in `binmul.rw`, and what a traveller does on
arrival depends only on which marker it lands against: `%` and `&` compare, by
doing the subtraction without writing it down and watching for a borrow out
the left end; `:` and `!` subtract for real. A borrow out means the divisor did
not fit, so the quotient bit is 0 and the remainder must be untouched — which
is exactly why the compare pass writes each digit back unchanged.

```sh
mk/rw mk/progs/bindiv.rw '<11)1011>'   # 11r10
```

Checked against every dividend and divisor up to 63, quotient and remainder
both. Dividing by zero is nonsense — the quotient comes out all ones — but it
halts rather than spinning. The ceiling is the fuel again: a 96-bit dividend
divides, 128 gives up.

`binsqrt.rw` is `bindiv.rw`'s shape — compare, subtract if it fits — but the
thing being compared against changes every round. Taking two input bits at a
time, the trial value is `root*4+1`, and the root gains a bit each round, so
the subtrahend grows as the answer does.

The identity that makes it tractable: `root*4+1` in binary is just the root's
bits followed by `01`. So the trial value and the root are *the same region of
tape*, and a round updates it by inserting the new root bit in front of that
trailing `01` — one rule, no arithmetic:

```
01^m->101^     it fit:     the root gains a 1
01^n->001^     it missed:  the root gains a 0
```

At the end the root is that region with its trailing `01` taken off again.
Pairs count from the low end, so an odd-length input needs a leading zero
first; `e` and `o` walk it to find out which, and `p` carries the pad back.

```sh
mk/rw mk/progs/binsqrt.rw '<1010>'   # 11r1 — sqrt 10 is 3, with 1 over
```

Checked against every input below 4096 and random ones up to 40 bits, root and
remainder both. A 160-bit input still roots; 224 runs out of fuel.

`bingcd.rw` is where the tape picks the algorithm. Euclid is the wrong one
here: it needs a `mod`, which is the whole of `bindiv.rw`, hundreds of
thousands of rewrites per round. Stein's binary GCD needs only parity, halving
and subtraction — and with the low end of each number parked against a marker
that never moves, the first two are single local rules. A number is even if a
`0` sits against its marker, and halving it is *deleting that bit*.

```
< A ^ k Z | B % >
```

`Z` banks the twos the pair had in common, as zeros to hang on the answer at
the end. One cycle probes both parities and acts on the four cases in order:
both even (halve both, bank a two), one even (halve it), both odd (compare,
then take the smaller from the larger).

That last case is the one that costs something. The larger is whichever the
compare says, so the subtraction has to run in *either* direction, and every
program before this one had a fixed direction of flow. Rather than swap the
two numbers — a lot of tape to move — there are two mirrored sets of columns:
`@` walks A rightwards into B, or `*` walks B leftwards into A. The travellers
and the ordering discipline are shared; only the direction differs.

```sh
mk/rw mk/progs/bingcd.rw '<1100,1000>'   # 100 — gcd 12 8 is 4
```

Both operands must be nonzero. Checked against every pair up to 63 and random
pairs to 4000. 64-bit operands still work; 96-bit runs out of fuel.

`dec2bin.rw` and `bin2dec.rw` convert between the two. Everything above speaks
binary, so without them the set is only usable by someone willing to convert by
hand.

Both are a single local pass, and for the same reason: the two regions are laid
out so that the ends that are doing the work touch. Going in, the decimal is
halved over and over and the remainders come out least significant first, so
each new bit must land to the *left* of the ones before it — the binary answer
is built on the right of the decimal, growing leftwards from the separator, and
the halving pass ends exactly where the next bit belongs. Going out, the
decimal is doubled and the next bit added, most significant first; doubling
carries leftwards and the bits are taken from the left of the binary, so again
the two active ends are the two sides of the separator. Neither program has a
traveller in it. Nothing is carried anywhere.

`mk/dec.sh` ties them to everything else — the binary programs, driven in
decimal:

```sh
$ mk/dec.sh mul 37 41
1517
$ mk/dec.sh div 1234 56
22 r 2
$ mk/dec.sh sqrt 1234
35 r 9
$ mk/dec.sh gcd 1071 462
21
```

Checked in both directions for every value below 4096, and round-tripped on
random numbers up to 70 bits.

`collide.rw` is `rule110.rw`'s machine with a different physics in it. The
architecture is identical — a sweep marker carrying the left neighbour, one
traveller per cell, the new row assembling itself past the old one — and only
the local rule differs, which is why the machine is written separately from the
rule it runs.

Four cell states: `o` is vacuum, `r` a glider going right, `l` one going left,
and `x` the scar where two of them met. Gliders move a cell per generation and
annihilate on contact; `x` never moves and never decays, so the collision is
still legible when the diagram is finished.

```sh
mk/rw mk/progs/collide.rw '!ooorooooooolooo>########' \
  | tr / '\n' | tr orlx ' \\/|'
```

```
   \       /
    \     /
     \   /
      \ /
       |
       |
       |
       |
       |
```

It also makes the invariant the other programs run on visible: one thing in
flight at a time is here a property of the physics rather than of the rule
order, since two pulses in one place is exactly what `x` records.

Its rule table is generated from the transition function rather than typed,
and checked against an independent implementation over every arrangement of
the four states up to fifteen cells wide.

`fetch.rw` reads the cell at a given address — `<10:314159>` is index 2 of
`314159`, which is `4`. Nothing about a rewriting machine forbids addressing —
it is thirty rules — but it cannot be made to cost nothing, and the cost is
what the program is for.

Rules are local, so a signal moves one cell per rewrite, and reaching a cell
*n* away takes *n* steps however the program is written. Constant-time access
is not available at any rule count: that is a property of a one-dimensional
tape, not a limitation of `rw`.

```
addr    0:   202 rewrites
addr    1:   203            +1
addr    2:   206            +3
addr    4:   211            +5
addr    8:   220            +9
addr   16:   237           +17
addr   32:   270           +33
addr   64:   335           +65
addr  128:   464          +129
```

Each doubling of the address doubles what the read costs — the address itself
plus its own bit-length, for the borrows. The flat two hundred is the memory
being discarded afterwards, since the program returns only the value.

Everything else here is a matter of writing more rules; a constant-time read is
not, and would mean a different machine underneath.

`padd.rw` measures what the travellers cost. Of a 32-bit multiply in
`binmul.rw`, **96.9% of the rewrites are one symbol stepping past another** —
the arithmetic is three percent. Division is 94.8% movement, addition 93.8%.

So `padd.rw` interleaves the two operands instead of keeping them apart. A cell
holds one bit of each, a column is a single symbol, and nothing travels except
the carry, which moves one cell:

```
   bits     binadd     padd    ratio
      8         84       20       4x
     32      1,092       68      16x
    128     16,644      260      64x
    256     66,052      516     128x
```

The ratio is not a constant. Doubling the width
costs `binadd.rw` **3.97x** and `padd.rw` **1.98x** — quadratic against linear.
Separating the operands does not cost a factor; it costs a factor of *the
width itself*.

It does not make `binadd.rw` pointless, because interleaving two numbers that
arrive apart is a quadratic shuffle of its own. It pays when the operands are
already in that shape and stay in it, as in a systolic layout, where a
multiplier is `n` rounds of a linear add instead of `n` rounds of a quadratic
one.

`sort.rw` makes the same point in one rule. `ba->ab` looks like naive bubble
sort, but on a line where the only communication is nearest-neighbour it is the
right algorithm; the asymptotically better ones would spend their savings on
the distance they need.

`palin.rw` is the ordering discipline in miniature. With no
random access and no variables in the rules, the check has to eat the string
from both ends: pick the first letter up into a marker that carries it, walk
that marker to the far end, and see what it meets. Every rule that mentions a
marker sits *above* the two that pick a letter up, because picking one up is
the last resort — get that backwards and a tape like `<bA>` matches `<b` and
grabs a second letter while the first is still in flight. Checked exhaustively
against every string over `{a,b}` up to length 10.

Its `yes` and `no` are written as terminal rules for clarity rather than
necessity: no rule in the program matches the letters of either word, so it
would stop anyway. `first.rw` remains the case where the dot is load-bearing.

`tm.rw` deliberately does *not* use a terminal rule: its halt state is
expressed by no rule mentioning `H`, which is the point of that demo.

### rw.rw — the rewriter, rewritten

`rw.rw` is `rw` written as a set of `rw` rules: 189 of them, interpreting an
object program held on the same tape as the tape it runs on.

```sh
mk/rw mk/progs/rw.rw '<10,01;*1010>'      # -> 0011
```

Input is `<rules*tape>`, a rule being `lhs,rhs;` — or `lhs!rhs;` when it is
terminal. Bootstrap turns that into the working layout, and three markers are
the entire machine state:

```
{ rules... @ rule ... | prefix A marked ^ rest >
```

`@` is the rule pointer, parked left of the rule being tried. `A` is the
anchor, parked left of the candidate occurrence, and `^` is the compare
frontier, with the symbols matched so far sitting between them.

The matching is `binmul.rw`'s courier trick, one level up. `@` steps over one
left-hand-side symbol, marking it so the rule survives to fire again, and
launches a courier rightwards to test the frontier — exactly as `0@->@0T`
steps over a multiplicand bit without consuming it. Rule order is again the
only synchronisation: a courier's arrival outranks the next emission, so
exactly one is ever in flight.

Three walks come home, and they are where the design actually lives. `J`
follows a mismatch: it unmarks the tape, slides the anchor one right, and
rewinds the pointer over its own marks. `V` follows a rule that matched
nowhere: it re-anchors and steps the pointer to the next rule. `K..S..W`
follows a match: it deletes the occurrence, copies the right-hand side in by
courier, and walks both pointers home.

Halting a terminal rule is the part worth stating plainly. `N` runs left and
flips `{` to `[`; at the end of that commit, `[` starts an eater rather than
restoring `@`, so **a terminal rule halts by deleting the program**. That is
what the dot means, made operational.

Checked against `rw` itself on 461 random object programs and every case in
`test.sh`.

### What interpretation costs

Not a constant factor. Every symbol comparison is a courier crossing the whole
program to reach the tape, so the factor grows with the distance:

```
   tape    native     rw.rw    ratio
      2         1       158     158x
      4         3       427     142x
      8        10      1887     189x
     16        36     12681     352x
     24        78     44587     572x
     32       136    114373     841x
```

Against program size it is worse than linear. The same three rewrites, with
dead rules parked in front of them:

```
  rules   symbols     rw.rw    delta
      1         6       427
      2        14      1492     1065
      3        22      2957     1465
      4        30      4822     1865
      5        38      7087     2265
      6        46      9752     2665
```

The second difference is a flat 400, so the cost is quadratic in the program:
`3.125·P² + 70.6·P − 109` reproduces the last row exactly. A rewriter
interpreting a rewriter pays the tape's own geometry twice — which is
`fetch.rw`'s result about addressing and `padd.rw`'s about travellers,
arriving one level up.

### enc.rw, and why the obvious encoding is wrong

`rw.rw` reads an object alphabet of `{0,1,2}`, and the generality claim is that
any `rw` program reaches it by coding each source symbol as a fixed-width
block. As stated that claim is false, and the counterexample is small.

Matching happens at the symbol level and nothing makes a match land on a block
boundary. Take a 6-bit code with `1 -> 000001` and `w -> 100000`. The tape `1w`
is `000001100000`, which contains `000011` at offset 1 — the code for `3`. A
rule for `3` fires on a tape that never held one:

```sh
mk/rw mk/progs/rw.rw '<000011,111111;*000001100000>'   # -> 011111100000
```

Nothing is wrong with the interpreter there; it matched what was on the tape.
The hole is in the encoding, and no amount of testing `rw.rw` against `rw`
would find it, because both are right.

`enc.rw` closes it with the third symbol. Every block ends in a `2`, so the
separators sit at a fixed period, every left-hand side carries its own, and a
match can only align where the periods do — the block boundary. The cost is one
symbol in seven, and about fifty extra rules in `rw.rw` to carry the third
symbol through every courier and every walk.

```sh
mk/rw mk/progs/enc.rw '<ba,ab;*abab>'
# -> <00101120010102,00101020010112;*0010102001011200101020010112>
mk/rw mk/progs/rw.rw  '<00101120010102,00101020010112;*0010102001011200101020010112>'
# -> 0010102001010200101120010112        which decodes to aabb
```

That is `sort.rw` — `ba->ab`, the one-rule bubble sort from the top of this
file — encoded and run under the interpreter, and it is the generality claim
discharged rather than asserted. Checked on 141 random source programs, drawn
from an alphabet containing the aliasing trio, against running them directly.

### Self-application, and what it would cost

An earlier version of this section claimed self-application was "one constant
away, on a machine where that constant is a `movz`/`movk` pair". That was wrong
twice over, and both errors are worth keeping written down.

**It cannot be constructed at all.** `enc.rw` cannot encode `rw.rw`. Thirty-four
of `rw.rw`'s forty-three symbols have no code in the table, and six of those —
`,` `!` `;` `*` `<` `>` — are structure in `enc.rw`'s own input syntax. So this
is not a table that wants widening; the encoder's syntax collides with the
alphabet it would have to encode, and `rw.rw` cannot be written down as an
object program until that is given an escape convention.

**And the figure was for the wrong computation.** `rw.rw` is 1144 raw symbols
over an alphabet of 43, so 8008 encoded symbols, which does fit a 65536-byte
tape. But `2.0 × 10⁸` is the cost of a whole run of *three* object rewrites on a
*four-symbol* tape that happens to use a program the size of encoded `rw.rw`.
Self-application is `rw.rw` simulating the 427 object rewrites that an encoded
`rw.rw` needs in order to sort `1010`:

```
simulate one object rewrite at P = 8008:   66,988,485     calculated
x 427 object rewrites:                     28,604,083,209 calculated
  vs the 2.0e8 first quoted:               143x more
  at the measured 204 us/rewrite:          at least 68 days
```

"At least", and the reason is the axis the first mistake hid. That per-rewrite
figure comes from runs with a **four-symbol** object tape, and a real
self-application carries a doubly-encoded inner tape of around 427. Longer tape
means longer courier trips, so the true cost is above this, not around it.

The two inputs are measured. The rewrite-count quadratic reproduces real runs
to 0.0% at `P = 606`, thirteen times past the range it was fitted on; the 204
µs/rewrite is timed directly at an 8000-symbol tape, using `-f` to fix the
budget so that cost per rewrite is what is being measured. The product of them
is not measured, and is labelled above accordingly.

2.9 × 10¹⁰ is past `2³²`, so the compile-time `FUEL` constant could not hold it
even if the encoding existed — though `-f` could, since it parses into a 64-bit
register. That is the one part of the original claim that survived, and it
survived by accident.

### The interpreter, by the instruction

`rw` is 256 aarch64 instructions in 2800 bytes, static, with no libc — no
`INTERP`, no `DYNAMIC`, no dynamic symbols, five raw syscalls.

| | |
|---:|---|
|  97 | read argv, parse the flags, open the program, load the tape |
|  38 | parse a rule: line, comment, arrow, terminal dot |
|  20 | search the tape for the lhs |
|  40 | splice: shift the tape, write the rhs |
|  24 | trace one rewrite to stderr (-v) |
|  37 | emit, fuel, overflow, usage, exit |
| **256** | **total** |

The lopsided figure is still the search: twenty instructions are the whole
matching engine, against ninety-seven to get the arguments in. The splice is where the real work is, because it has to grow
or shrink the tape in place and so copies in both directions depending on
which way the rule changes the length.

None of that is a compiler. `rw` parses its rules at runtime, so those 37
instructions are a `->` finder, not a front end — `build.sh` is the compiler,
and it is twelve lines of shell that hand the job to clang.

That table is not prose. `rw.s` carries `// -- phase:` markers at the section
boundaries, and `mk/test.sh` re-derives every row from the source and the
total from the built binary. Move an instruction across a boundary and the
suite says which row the README now gets wrong — the total alone would not
notice, since it does not change.

`mk/test.sh` runs every rule file against a known answer, including that
overflow. The Rule 110 cases were checked against an independent
implementation over 46 random widths and generation counts before being
frozen into the suite.
