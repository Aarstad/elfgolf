// rw - aarch64 interpreter for a rewriting language. no libc, no stack frames.
//   usage: rw [-v] [-f N] PROG.rw [INPUT]   (INPUT omitted -> read stdin)
//   -v:    trace every rewrite to stderr as "rule<TAB>resulting tape"
//   -f N:  allow N rewrites rather than the built-in FUEL, so that asserting
//          a program does not halt costs N and not a hundred million
//   PROG:  one rule per line, "lhs->rhs"; lines starting with '#' ignored
//   term:  "lhs->.rhs" is a terminal rule -- it rewrites once and halts,
//          whether or not anything still matches
//   run:   scan rules top-down; first rule whose lhs occurs in the tape
//          rewrites its leftmost occurrence, then scanning restarts.

        .set    O_RDONLY, 0
        .set    AT_FDCWD, -100
        .set    SYS_read, 63
        .set    SYS_write, 64
        .set    SYS_openat, 56
        .set    SYS_exit, 93
        .set    BUFSZ, 16384
        .set    TAPEMAX, 65536
        .set    FUEL, 100000000

        .text
        .global _start
// -- phase: read argv, parse the flags, open the program, load the tape
_start:
        ldr     x28, [sp]                 // argc, from the kernel's arg block
        movz    x27, #(FUEL & 0xffff)     // rewrites remaining
        movk    x27, #(FUEL >> 16), lsl #16
        adrp    x19, tape
        add     x19, x19, :lo12:tape
        adrp    x22, src
        add     x22, x22, :lo12:src

        mov     x14, #0                   // tracing?
        mov     x15, #16                  // byte offset of the program argument

// flags, in any order, each shifting the rest along by one
.Lflag: cmp     x28, #2
        b.lt    .Lusage
        add     x9, sp, x15
        ldr     x9, [x9]
        ldrb    w10, [x9]
        cmp     w10, #45                  // '-'
        b.ne    .Largs
        ldrb    w10, [x9, #2]
        cbnz    w10, .Largs               // two characters exactly, or it is a path
        ldrb    w10, [x9, #1]
        add     x15, x15, #8
        sub     x28, x28, #1
        cmp     w10, #118                 // 'v'
        b.ne    .Lsetf
        mov     x14, #1
        b       .Lflag

.Lsetf: cmp     w10, #102                 // 'f', with the count in the next argument
        b.ne    .Lusage
        cmp     x28, #2
        b.lt    .Lusage
        add     x9, sp, x15
        ldr     x9, [x9]
        mov     x27, #0
        mov     x11, #10
        ldrb    w10, [x9]
        cbz     w10, .Lusage              // "-f ''" is not a count
.Lfdig: ldrb    w10, [x9], #1
        cbz     w10, .Lfdon
        sub     w10, w10, #48             // '0'
        cmp     w10, #9
        b.hi    .Lusage
        madd    x27, x27, x11, x10
        b       .Lfdig
.Lfdon: add     x15, x15, #8
        sub     x28, x28, #1
        b       .Lflag

.Largs: cmp     x28, #2
        b.lt    .Lusage
        add     x9, sp, x15
        ldr     x1, [x9]                  // program path
        mov     x0, #AT_FDCWD
        mov     x2, #O_RDONLY
        mov     x3, #0
        mov     x8, #SYS_openat
        svc     #0
        tbnz    x0, #63, .Lerr

        mov     x1, x22                   // read whole program
        mov     x2, #BUFSZ
        mov     x8, #SYS_read
        svc     #0
        tbnz    x0, #63, .Lerr
        strb    wzr, [x22, x0]

        cmp     x28, #3
        b.lt    .Lstdin
        add     x9, sp, x15
        ldr     x9, [x9, #8]              // INPUT -> tape
        mov     x10, #0
        mov     x12, #TAPEMAX
.Lcp:   cmp     x10, x12
        b.hs    .Lovf
        ldrb    w11, [x9, x10]
        strb    w11, [x19, x10]
        cbz     w11, .Lcpd
        add     x10, x10, #1
        b       .Lcp
.Lcpd:  mov     x20, x10
        b       .Lrestart

.Lstdin:                                  // no INPUT: read stdin
        mov     x0, #0
        mov     x1, x19
        mov     x2, #BUFSZ
        mov     x8, #SYS_read
        svc     #0
        tbnz    x0, #63, .Lerr
        mov     x20, x0
        cbz     x20, .Lrestart
        sub     x9, x20, #1               // drop one trailing newline
        ldrb    w10, [x19, x9]
        cmp     w10, #10
        b.ne    .Lrestart
        mov     x20, x9

// -- phase: parse a rule: line, comment, arrow, terminal dot
.Lrestart:
        mov     x21, x22
.Lrule: ldrb    w9, [x21]
        cbz     w9, .Ldone

        mov     x10, x21                  // end of line
.Leol:  ldrb    w9, [x10]
        cbz     w9, .Lchk
        cmp     w9, #10
        b.eq    .Lchk
        add     x10, x10, #1
        b       .Leol
.Lchk:  ldrb    w9, [x21]
        cmp     w9, #35                   // '#' comment
        b.eq    .Lnext

        mov     x11, x21                  // locate "->"
.Lsep1: add     x12, x11, #1
        cmp     x12, x10
        b.hs    .Lnext
        ldrb    w9, [x11]
        cmp     w9, #45
        b.ne    .Lsep2
        ldrb    w9, [x12]
        cmp     w9, #62
        b.eq    .Lgot
.Lsep2: add     x11, x11, #1
        b       .Lsep1

.Lgot:  sub     x23, x11, x21             // llen
        cbz     x23, .Lnext
        mov     x16, x10                  // line end, for -v: the splice eats x10
        add     x24, x11, #2              // rhs
        sub     x25, x10, x24             // rlen
        mov     x13, #0                   // terminal rule?
        cbz     x25, .Lscan
        ldrb    w9, [x24]
        cmp     w9, #46                   // "->." rewrites once, then halts
        b.ne    .Lscan
        mov     x13, #1
        add     x24, x24, #1              // the dot is syntax, not output
        sub     x25, x25, #1

// -- phase: search the tape for the lhs
.Lscan: mov     x2, #0
.Lsrch: add     x3, x2, x23
        cmp     x3, x20
        b.hi    .Lnext
        add     x6, x19, x2
        mov     x4, #0
.Lcmp:  cmp     x4, x23
        b.eq    .Lfound
        ldrb    w5, [x6, x4]
        ldrb    w7, [x21, x4]
        cmp     w5, w7
        b.ne    .Lno
        add     x4, x4, #1
        b       .Lcmp
.Lno:   add     x2, x2, #1
        b       .Lsrch

.Lnext: ldrb    w9, [x10]
        cbz     w9, .Ldone
        add     x21, x10, #1
        b       .Lrule

// -- phase: splice: shift the tape, write the rhs
.Lfound:
        cbz     x27, .Lfuel
        sub     x27, x27, #1
        sub     x26, x25, x23
        add     x9, x20, x26              // length after this rewrite
        mov     x10, #TAPEMAX
        cmp     x9, x10
        b.hi    .Lovf
        cbz     x26, .Lput
        add     x4, x2, x23
        sub     x5, x20, x4
        add     x20, x20, x26
        tbz     x26, #63, .Lgrow
        mov     x9, #0
.Lsh1:  cmp     x9, x5
        b.eq    .Lput
        add     x11, x4, x9
        ldrb    w6, [x19, x11]
        add     x12, x11, x26
        strb    w6, [x19, x12]
        add     x9, x9, #1
        b       .Lsh1
.Lgrow: mov     x9, x5
.Lgr1:  cbz     x9, .Lput
        sub     x9, x9, #1
        add     x11, x4, x9
        ldrb    w6, [x19, x11]
        add     x12, x11, x26
        strb    w6, [x19, x12]
        b       .Lgr1

.Lput:  mov     x9, #0
.Lcr:   cmp     x9, x25
        b.eq    .Lfin
        ldrb    w6, [x24, x9]
        add     x11, x2, x9
        strb    w6, [x19, x11]
        add     x9, x9, #1
        b       .Lcr

.Lfin:  cbnz    x14, .Ltrace
.Lfin2: cbz     x13, .Lrestart            // ordinary rule: rescan from the top
        b       .Ldone                    // terminal rule: stop, however the tape looks

// -- phase: trace one rewrite to stderr (-v)
.Ltrace:                                  // the rule that fired ...
        mov     x0, #2
        mov     x1, x21
        sub     x2, x16, x21
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #2                    // ... a tab ...
        adrp    x1, msg_tab
        add     x1, x1, :lo12:msg_tab
        mov     x2, #1
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #2                    // ... and what the tape became
        mov     x1, x19
        mov     x2, x20
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #2
        adrp    x1, msg_tab
        add     x1, x1, :lo12:msg_tab
        add     x1, x1, #1
        mov     x2, #1
        mov     x8, #SYS_write
        svc     #0
        b       .Lfin2

// -- phase: emit, fuel, overflow, usage, exit
.Ldone: mov     x26, #0
        b       .Lemit
.Lfuel: adrp    x1, msg_fuel
        add     x1, x1, :lo12:msg_fuel
        mov     x2, #msg_fuel_len
        mov     x26, #2
        b       .Lwarn
.Lovf:  adrp    x1, msg_ovf
        add     x1, x1, :lo12:msg_ovf
        mov     x2, #msg_ovf_len
        mov     x26, #3
.Lwarn: mov     x0, #2
        mov     x8, #SYS_write
        svc     #0
.Lemit: mov     w9, #10                   // emit the tape, however we got here
        strb    w9, [x19, x20]
        add     x20, x20, #1
        mov     x0, #1
        mov     x1, x19
        mov     x2, x20
        mov     x8, #SYS_write
        svc     #0
        mov     x0, x26
        b       .Lexit

.Lusage:
        adrp    x1, msg_use
        add     x1, x1, :lo12:msg_use
        mov     x2, #msg_use_len
        b       .Lfail
.Lerr:  adrp    x1, msg_err
        add     x1, x1, :lo12:msg_err
        mov     x2, #msg_err_len
.Lfail: mov     x0, #2
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #1
.Lexit: mov     x8, #SYS_exit
        svc     #0

        .section .rodata
msg_tab: .ascii "\t\n"                    // a tab, then a newline
msg_use: .ascii "usage: rw [-v] [-f N] PROG.rw [INPUT]\n"
        .set    msg_use_len, . - msg_use
msg_err: .ascii "rw: cannot read program\n"
        .set    msg_err_len, . - msg_err
msg_fuel: .ascii "rw: out of fuel\n"
        .set    msg_fuel_len, . - msg_fuel
msg_ovf: .ascii "rw: tape overflow\n"
        .set    msg_ovf_len, . - msg_ovf

        .bss
        .balign 8
src:    .space  BUFSZ + 1
tape:   .space  TAPEMAX + 16
