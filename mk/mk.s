// aarch64 Markov-style rewriter. no libc, no stack, no allocation.
//   source: one rule per line, "lhs->rhs"
//   run:    scan rules top-down; first rule whose lhs occurs in the tape
//           rewrites its leftmost occurrence, then scanning restarts.
//           halt when no rule matches.

        .text
        .global _start
_start:
        adrp    x19, tape
        add     x19, x19, :lo12:tape      // tape base
        adrp    x22, src
        add     x22, x22, :lo12:src       // source base
        mov     x20, #0                   // tape length
.Llen:  ldrb    w9, [x19, x20]
        cbz     w9, .Lrestart
        add     x20, x20, #1
        b       .Llen

.Lrestart:
        mov     x21, x22                  // rule cursor -> top
.Lrule: ldrb    w9, [x21]
        cbz     w9, .Ldone                // end of source: halt

        mov     x10, x21                  // find end of line
.Leol:  ldrb    w9, [x10]
        cbz     w9, .Lsep
        cmp     w9, #10
        b.eq    .Lsep
        add     x10, x10, #1
        b       .Leol

.Lsep:  mov     x11, x21                  // find "->" within the line
.Lsep1: add     x12, x11, #1
        cmp     x12, x10
        b.hs    .Lnext                    // no separator: skip line
        ldrb    w9, [x11]
        cmp     w9, #45                   // '-'
        b.ne    .Lsep2
        ldrb    w9, [x12]
        cmp     w9, #62                   // '>'
        b.eq    .Lgot
.Lsep2: add     x11, x11, #1
        b       .Lsep1

.Lgot:  sub     x23, x11, x21             // llen
        cbz     x23, .Lnext               // empty lhs would never terminate
        add     x24, x11, #2              // rhs
        sub     x25, x10, x24             // rlen

        mov     x2, #0                    // search tape for lhs
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

.Lfound:                                  // splice rhs over [i, i+llen)
        sub     x26, x25, x23             // delta
        cbz     x26, .Lput
        add     x4, x2, x23               // tail start
        sub     x5, x20, x4               // tail length
        add     x20, x20, x26             // new tape length
        tbz     x26, #63, .Lgrow
.Lsh:   mov     x9, #0                    // shrink: copy tail forward
.Lsh1:  cmp     x9, x5
        b.eq    .Lput
        add     x11, x4, x9
        ldrb    w6, [x19, x11]
        add     x12, x11, x26
        strb    w6, [x19, x12]
        add     x9, x9, #1
        b       .Lsh1
.Lgrow: mov     x9, x5                    // grow: copy tail backward
.Lgr1:  cbz     x9, .Lput
        sub     x9, x9, #1
        add     x11, x4, x9
        ldrb    w6, [x19, x11]
        add     x12, x11, x26
        strb    w6, [x19, x12]
        b       .Lgr1

.Lput:  mov     x9, #0                    // write rhs into the gap
.Lcr:   cmp     x9, x25
        b.eq    .Lrestart
        ldrb    w6, [x24, x9]
        add     x11, x2, x9
        strb    w6, [x19, x11]
        add     x9, x9, #1
        b       .Lcr

.Ldone: mov     x0, #1
        mov     x1, x19
        mov     x2, x20
        mov     x8, #64
        svc     #0
        mov     x0, #0
        mov     x8, #93
        svc     #0

        .data
src:    .asciz  "1+->+1\n+->\n"
        .balign 8
tape:   .ascii  "111+11\n"
        .space  512
