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
| `first` | brackets the first `101` and stops — one terminal rule |
| `palin` | palindrome over `{a,b}`, eaten from both ends |
| `binadd` | binary addition, a column at a time, carry and all |
| `binmul` | binary multiplication, by shift and add |
| `bindiv` | binary long division, quotient and remainder |

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

`27` peaks at 9232, overruns the 4096-byte tape, and reports `rw: tape
overflow` rather than truncating.

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

### The interpreter, by the instruction

`rw` is 226 aarch64 instructions in 2672 bytes, static, with no libc — no
`INTERP`, no `DYNAMIC`, no dynamic symbols, five raw syscalls.

| | |
|---:|---|
|  67 | read argv, open the program, load the tape |
|  38 | parse a rule: line, comment, arrow, terminal dot |
|  20 | search the tape for the lhs |
|  40 | splice: shift the tape, write the rhs |
|  24 | trace one rewrite to stderr (-v) |
|  37 | emit, fuel, overflow, usage, exit |
| **226** | **total** |

The lopsided figure is still the search: twenty instructions are the whole
matching engine. The splice is where the real work is, because it has to grow
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
