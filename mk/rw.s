// rw - aarch64 interpreter for a rewriting language. no libc, no stack frames.
//   usage: rw PROG.rw [INPUT]        (INPUT omitted -> read stdin)
//   PROG:  one rule per line, "lhs->rhs"; lines starting with '#' ignored
//   run:   scan rules top-down; first rule whose lhs occurs in the tape
//          rewrites its leftmost occurrence, then scanning restarts.

        .set    O_RDONLY, 0
        .set    AT_FDCWD, -100
        .set    SYS_read, 63
        .set    SYS_write, 64
        .set    SYS_openat, 56
        .set    SYS_exit, 93
        .set    BUFSZ, 4096
        .set    TAPEMAX, 4096
        .set    FUEL, 1000000

        .text
        .global _start
_start:
        ldr     x28, [sp]                 // argc, from the kernel's arg block
        movz    x27, #(FUEL & 0xffff)     // rewrites remaining
        movk    x27, #(FUEL >> 16), lsl #16
        adrp    x19, tape
        add     x19, x19, :lo12:tape
        adrp    x22, src
        add     x22, x22, :lo12:src

        cmp     x28, #2
        b.lt    .Lusage

        ldr     x1, [sp, #16]             // argv[1]
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
        ldr     x9, [sp, #24]             // argv[2] -> tape
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
        add     x24, x11, #2              // rhs
        sub     x25, x10, x24             // rlen

        mov     x2, #0
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
        b.eq    .Lrestart
        ldrb    w6, [x24, x9]
        add     x11, x2, x9
        strb    w6, [x19, x11]
        add     x9, x9, #1
        b       .Lcr

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
msg_use: .ascii "usage: rw PROG.rw [INPUT]\n"
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
