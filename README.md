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

- `hello112` — the artifact, 112 bytes, runs on Android/bionic and on Linux
- `floor.py` — the final builder, written to prove the floor
- `src/` — the working builders in order: `golf.py` → `golf4.py`, then
  `final.py`; `vaddr.py` for the address/string coincidence, `hello.s` for the
  992-byte starting point
- `stages/` — every intermediate binary kept: 992, 592, 186, 178, 144, 140, 136,
  128, 124, 120, 116, 112
- `probes/` — `probe.py` builds deliberately malformed ELFs to find which header
  fields the kernel actually validates; `t1`–`t4`, `f3` are the survivors

## mk/ — a Markov rewriter

Unrelated to the golfing, from the same sitting. `mk` is a Markov-style string
rewriter in aarch64 assembly: no libc, no stack, no allocation. Rules are
`lhs->rhs`, one per line; it rewrites the leftmost match of the first matching
rule and restarts, halting when nothing matches.

```sh
mk/build.sh /tmp/add '111+11' '1+->+1' '+->'   # unary addition -> 11111
```

`mk/progs/` has `add`, `inc`, `mul`, `sort` and `spin` as `.rw` rule files.
Programs are assembled *into* the binary — `build.sh` emits the rules and the
tape as a `.data` section and links them with `core.s`.
