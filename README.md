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

`tm.rw` deliberately does *not* use a terminal rule: its halt state is
expressed by no rule mentioning `H`, which is the point of that demo.

### The interpreter, by the instruction

`rw` is 182 aarch64 instructions in 2456 bytes, static, with no libc — no
`INTERP`, no `DYNAMIC`, no dynamic symbols, five raw syscalls.

| | |
|---:|---|
|  49 | read argv, open the program, load the tape |
|  37 | parse a rule: line, comment, arrow, terminal dot |
|  20 | search the tape for the lhs |
|  39 | splice: shift the tape, write the rhs |
|  37 | emit, fuel, overflow, usage, exit |
| **182** | **total** |

The lopsided figure is the search: twenty instructions are the whole matching
engine. The splice is where the real work is, because it has to grow or shrink
the tape in place and so copies in both directions depending on which way the
rule changes the length.

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
