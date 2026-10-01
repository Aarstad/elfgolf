// px - a framebuffer you can look at. aarch64, no libc, no stack frames.
//   usage: px [FRAMES]          (FRAMES omitted -> run until Ctrl-C)
//   frame: one contiguous block of 0x00BBGGRR pixels in .bss, W x H with
//          W = terminal columns and H = twice the rows. the render pass walks
//          it top to bottom writing a plasma; the scanout pass walks it again
//          and turns each vertical pixel pair into one "▀" cell, foreground
//          the upper pixel and background the lower, in 24-bit colour
//   show:  the whole frame leaves in one write(2) -- the terminal is the
//          display controller, and the escape stream is its scanout
//   size:  re-read with TIOCGWINSZ every frame, so resizing just works;
//          a pipe gets 80x24
//   sine:  no float, no libm: a 256-entry table from Minsky's circle
//          algorithm, two multiplies a step

        .set    SYS_ioctl, 29
        .set    SYS_write, 64
        .set    SYS_exit, 93
        .set    SYS_nanosleep, 101
        .set    SYS_rt_sigaction, 134
        .set    TIOCGWINSZ, 0x5413
        .set    SIGINT, 2
        .set    SIGTERM, 15
        .set    MAXW, 512                 // pixels across = columns
        .set    MAXR, 256                 // rows; pixels down = 2 * rows
        .set    CELLMAX, 48               // bytes one cell can cost, rounded up

// emit the decimal text of byte LSB of pixel PX, ';' included
        .macro  chan px, lsb
        ubfx    x9, \px, #\lsb, #8
        ldr     x10, [x20, x9, lsl #3]    // text in the low word, length above
        str     w10, [x0]
        add     x0, x0, x10, lsr #32
        .endm

        .text
        .global _start
// -- phase: argv, tables, signals, alternate screen
_start:
        ldr     x28, [sp]                 // argc, from the kernel's arg block
        mov     x27, #-1                  // frames left: forever, near enough
        cmp     x28, #2
        b.lt    .Ltabs
        b.gt    .Lusage
        ldr     x9, [sp, #16]             // argv[1]
        mov     x27, #0
        mov     x11, #10
.Lnum:  ldrb    w10, [x9], #1
        cbz     w10, .Ltabs
        sub     w10, w10, #48
        cmp     w10, #9
        b.hi    .Lusage
        madd    x27, x27, x11, x10
        b       .Lnum

// sine: s += e*c; c -= e*s, in 16.16. e = 1608/65536 makes the period
// 256 steps to within a hair; the orbit's peak is 120*(1+e/4), so int8 holds
.Ltabs: adrp    x19, sine
        add     x19, x19, :lo12:sine
        mov     x9, #0                    // s
        movz    x10, #120, lsl #16        // c
        mov     x11, #1608
        mov     x12, #0
.Lsin:  asr     x13, x9, #16
        strb    w13, [x19, x12]
        mul     x13, x10, x11
        add     x9, x9, x13, asr #16
        mul     x13, x9, x11
        sub     x10, x10, x13, asr #16
        add     x12, x12, #1
        cmp     x12, #256
        b.lt    .Lsin

// digits: entry n is "n;" in up to four bytes, then its length at byte 4,
// so emitting a channel is one load, one store, one add
        adrp    x20, dtab
        add     x20, x20, :lo12:dtab
        mov     x12, #0
        mov     x13, #100
        mov     x14, #10
.Ldig:  add     x17, x20, x12, lsl #3
        mov     x16, x17
        udiv    x9, x12, x13              // hundreds
        msub    x10, x9, x13, x12
        udiv    x11, x10, x14             // tens
        msub    x10, x11, x14, x10        // ones
        cbz     x9, 1f
        add     w9, w9, #48
        strb    w9, [x16], #1
        b       2f                        // a hundreds digit forces the tens
1:      cbz     x11, 3f
2:      add     w11, w11, #48
        strb    w11, [x16], #1
3:      add     w10, w10, #48
        strb    w10, [x16], #1
        mov     w9, #59                   // ';'
        strb    w9, [x16], #1
        sub     x9, x16, x17
        strb    w9, [x17, #4]
        add     x12, x12, #1
        cmp     x12, #256
        b.lt    .Ldig

// Ctrl-C and kill both land in .Lquit, which never returns, so no restorer
        adrp    x1, sigact
        add     x1, x1, :lo12:sigact
        adr     x9, .Lquit
        str     x9, [x1]
        mov     x0, #SIGINT
        mov     x2, #0
        mov     x3, #8                    // sizeof(sigset_t), the kernel's
        mov     x8, #SYS_rt_sigaction
        svc     #0
        mov     x0, #SIGTERM
        svc     #0

        adr     x1, enter
        mov     x2, #(enter_end - enter)
        mov     x0, #1
        mov     x8, #SYS_write
        svc     #0

        adrp    x22, pix
        add     x22, x22, :lo12:pix
        adrp    x23, out
        add     x23, x23, :lo12:out
        mov     x21, #0                   // t, the frame number
        mov     x28, #0                   // last size seen, rows<<16 | cols

// -- phase: size the frame
.Lframe:
        cbz     x27, .Lquit
        sub     x27, x27, #1
        mov     x24, #80                  // columns
        mov     x25, #24                  // rows
        mov     x0, #1
        mov     x1, #TIOCGWINSZ
        adrp    x2, ws
        add     x2, x2, :lo12:ws
        mov     x8, #SYS_ioctl
        svc     #0
        cbnz    x0, 1f                    // not a tty: keep 80x24
        ldrh    w9, [x2]                  // ws_row
        ldrh    w10, [x2, #2]             // ws_col
        cbz     w9, 1f                    // some ptys report 0x0
        cbz     w10, 1f
        mov     x25, x9
        mov     x24, x10
1:      mov     x9, #MAXW
        cmp     x24, x9
        csel    x24, x9, x24, hi
        mov     x9, #MAXR
        cmp     x25, x9
        csel    x25, x9, x25, hi
        lsl     x26, x25, #1              // H, pixel rows

// -- phase: render, top to bottom over the one block
// v = S[4y+3t] + S[3x+t] + S[2(x+y)-2t] + S[(dx²+dy²)/16 - 4t], about a
// centre that wanders; colour is three phases of S[v+t], 85 apart
        ubfiz   x9, x21, #1, #7           // 2t, mod 256
        ldrsb   x5, [x19, x9]             // S[2t]
        mul     x5, x5, x24
        add     x5, x24, x5, asr #8
        asr     x5, x5, #1                // cx = W/2 + S[2t]*W/512
        add     x9, x21, x21, lsl #1
        add     x9, x9, #64
        and     x9, x9, #255
        ldrsb   x6, [x19, x9]             // S[3t+64]
        mul     x6, x6, x26
        add     x6, x26, x6, asr #8
        asr     x6, x6, #1                // cy = H/2 + S[3t+64]*H/512

        mov     x2, x22                   // pixel cursor
        mov     x1, #0                    // y
.Ly:    add     x9, x21, x21, lsl #1
        add     x9, x9, x1, lsl #2
        and     x9, x9, #255
        ldrsb   x3, [x19, x9]             // the row's own term
        sub     x7, x1, x6
        mul     x7, x7, x7                // dy²
        mov     x4, #0                    // x
.Lx:    add     x9, x4, x4, lsl #1
        add     x9, x9, x21
        and     x9, x9, #255
        ldrsb   x10, [x19, x9]
        add     x9, x4, x1
        sub     x9, x9, x21
        lsl     x9, x9, #1
        and     x9, x9, #255
        ldrsb   x11, [x19, x9]
        sub     x9, x4, x5
        madd    x9, x9, x9, x7            // dx² + dy²
        lsr     x9, x9, #4
        sub     x9, x9, x21, lsl #2
        and     x9, x9, #255
        ldrsb   x12, [x19, x9]
        add     x10, x10, x3
        add     x10, x10, x11
        add     x10, x10, x12
        add     x10, x10, x21             // v + t
        and     x9, x10, #255
        ldrsb   w13, [x19, x9]
        add     w13, w13, #128            // r
        add     x9, x10, #85
        and     x9, x9, #255
        ldrsb   w14, [x19, x9]
        add     w14, w14, #128            // g
        add     x9, x10, #170
        and     x9, x9, #255
        ldrsb   w15, [x19, x9]
        add     w15, w15, #128            // b
        orr     w13, w13, w14, lsl #8
        orr     w13, w13, w15, lsl #16
        str     w13, [x2], #4
        add     x4, x4, #1
        cmp     x4, x24
        b.lt    .Lx
        add     x1, x1, #1
        cmp     x1, x26
        b.lt    .Ly

// -- phase: scanout, the block to one escape stream
        mov     x0, x23
        orr     x9, x24, x25, lsl #16
        cmp     x9, x28
        b.eq    1f
        mov     x28, x9                   // resized: clear what no longer fits
        movz    w9, #0x5b1b               // "\e[2J"
        movk    w9, #0x4a32, lsl #16
        str     w9, [x0], #4
1:      movz    w9, #0x5b1b               // "\e[H", stored as four, kept as three
        movk    w9, #0x48, lsl #16
        str     w9, [x0]
        add     x0, x0, #3
        movz    x12, #0x5b1b              // "\e[38;2;" -- eight stored, seven kept
        movk    x12, #0x3833, lsl #16
        movk    x12, #0x323b, lsl #32
        movk    x12, #0x3b, lsl #48
        movz    x13, #0x3834              // "48;2;", the ';' before it from the table
        movk    x13, #0x323b, lsl #16
        movk    x13, #0x3b, lsl #32
        movz    w14, #0xe26d              // "m▀": 6d e2 96 80
        movk    w14, #0x8096, lsl #16
        lsl     x3, x24, #2               // one pixel row, in bytes
        mov     x2, x22                   // upper pixel row
        mov     x1, #0
.Lrow:  add     x15, x2, x3               // lower pixel row
        mov     x4, #0
.Lcell: ldr     w5, [x2, x4, lsl #2]
        ldr     w6, [x15, x4, lsl #2]
        str     x12, [x0]
        add     x0, x0, #7
        chan    x5, 0
        chan    x5, 8
        chan    x5, 16
        str     x13, [x0]
        add     x0, x0, #5
        chan    x6, 0
        chan    x6, 8
        chan    x6, 16
        sub     x0, x0, #1                // the last ';' becomes the 'm'
        str     w14, [x0], #4
        add     x4, x4, #1
        cmp     x4, x24
        b.lt    .Lcell
        add     x2, x2, x3, lsl #1        // two pixel rows to the cell row
        add     x1, x1, #1
        cmp     x1, x25
        b.ge    .Lshow
        mov     w9, #0x0a0d               // "\r\n" -- never after the last row,
        strh    w9, [x0], #2              // or the screen scrolls a line
        b       .Lrow

// -- phase: show, pace, next
.Lshow: mov     x1, x23
        sub     x2, x0, x23
        mov     x8, #SYS_write
.Lput:  mov     x0, #1
        svc     #0
        cmp     x0, #0
        b.le    .Lquit                    // reader gone
        add     x1, x1, x0
        subs    x2, x2, x0
        b.ne    .Lput

        adr     x0, ts
        mov     x1, #0
        mov     x8, #SYS_nanosleep
        svc     #0
        add     x21, x21, #1
        b       .Lframe

// -- phase: leave the terminal as we found it
.Lquit: mov     x0, #1
        adr     x1, leave
        mov     x2, #(leave_end - leave)
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #0
        b       .Lexit
.Lusage:
        mov     x0, #2
        adr     x1, usage
        mov     x2, #(usage_end - usage)
        mov     x8, #SYS_write
        svc     #0
        mov     x0, #2
.Lexit: mov     x8, #SYS_exit
        svc     #0

        .balign 8
ts:     .quad   0, 16666666               // a sixtieth; the tty sets the real pace
enter:  .ascii  "\033[?1049h\033[?25l"    // alternate screen, cursor off
enter_end:
leave:  .ascii  "\033[0m\033[?25h\033[?1049l"
leave_end:
usage:  .ascii  "usage: px [FRAMES]\n"
usage_end:

        .data
        .balign 8
sigact: .quad   0, 0, 0, 0                // handler, flags, restorer, mask

        .bss
        .balign 16
sine:   .space  256
dtab:   .space  256 * 8
ws:     .space  8
pix:    .space  MAXW * MAXR * 2 * 4
out:    .space  MAXW * MAXR * CELLMAX + 4096
