// life - Conway's Life on px's framebuffer, sent as a delta. aarch64, no libc.
//   usage: life [FRAMES [SEED]]   (FRAMES omitted -> run until Ctrl-C;
//                                  SEED omitted -> getrandom)
//   board: one cell per pixel, W x H on a torus, W = columns, H = 2 * rows.
//          a cell takes the palette's colour of the generation it is born
//          in and keeps it until it dies, so the frame changes only where
//          something is born or dies, and still lifes keep older colours
//   rain:  every 32 generations a random 12x12 patch of new life lands
//          somewhere, so the board never settles into nothing but still lifes
//   delta: the scanout keeps what it last sent, cell by cell, and only sends
//          cells that differ: a run of unchanged cells becomes one "\e[nC",
//          and a colour already set by the previous cell is not set again.
//          an unchanged frame costs its row breaks and nothing else
//   size:  re-read every frame; a resize reseeds and sends one full frame

        .set    SYS_ioctl, 29
        .set    SYS_write, 64
        .set    SYS_exit, 93
        .set    SYS_nanosleep, 101
        .set    SYS_rt_sigaction, 134
        .set    SYS_getrandom, 278
        .set    TIOCGWINSZ, 0x5413
        .set    SIGINT, 2
        .set    SIGTERM, 15
        .set    MAXW, 512                 // pixels across = columns
        .set    MAXR, 256                 // rows; pixels down = 2 * rows
        .set    CELLS, MAXW * MAXR * 2
        .set    CELLMAX, 48               // bytes one cell can cost, rounded up
        .set    DEAD, 0x140c0a            // a dead pixel, 0x00BBGGRR
        .set    RAIN, 31                  // a patch lands when gen & RAIN == 0
        .set    PATCH, 12

// emit the decimal text of byte LSB of pixel PX, ';' included
        .macro  chan px, lsb
        ubfx    x9, \px, #\lsb, #8
        ldr     x10, [x20, x9, lsl #3]    // text in the low word, length above
        str     w10, [x0]
        add     x0, x0, x10, lsr #32
        .endm

// xorshift64, one step, in place
        .macro  xs r
        eor     \r, \r, \r, lsr #12
        eor     \r, \r, \r, lsl #25
        eor     \r, \r, \r, lsr #27
        .endm

// parse the decimal at [ptr] into dst, or die with the usage
        .macro  num dst, ptr
        mov     \dst, #0
        mov     x11, #10
1:      ldrb    w10, [\ptr], #1
        cbz     w10, 2f
        sub     w10, w10, #48
        cmp     w10, #9
        b.hi    .Lusage
        madd    \dst, \dst, x11, x10
        b       1b
2:
        .endm

        .text
        .global _start
// -- phase: argv, tables, seed, signals, alternate screen
_start:
        ldr     x28, [sp]                 // argc, from the kernel's arg block
        cmp     x28, #3
        b.gt    .Lusage
        mov     x27, #-1                  // frames left: forever, near enough
        adrp    x12, rng
        add     x12, x12, :lo12:rng
        cmp     x28, #2
        b.lt    .Lrand
        ldr     x9, [sp, #16]             // argv[1]
        num     x27, x9
        cmp     x28, #3
        b.lt    .Lrand
        ldr     x9, [sp, #24]             // argv[2]
        num     x13, x9
        str     x13, [x12]
        b       .Lseeded
.Lrand: mov     x0, x12
        mov     x1, #8
        mov     x2, #0
        mov     x8, #SYS_getrandom
        svc     #0
.Lseeded:
        ldr     x13, [x12]
        cbnz    x13, .Ltabs
        mov     x13, #1                   // xorshift's one fixed point
        str     x13, [x12]

// sine: s += e*c; c -= e*s, in 16.16, exactly as px has it
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

// digits: entry n is "n;" in up to four bytes, then its length at byte 4
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
        adrp    x29, gridA                // the board now
        add     x29, x29, :lo12:gridA
        adrp    x30, gridB                // the board next
        add     x30, x30, :lo12:gridB
        mov     x21, #0                   // gen, the frame number
        mov     x28, #0                   // last size seen, rows<<16 | cols

// -- phase: size the frame, and the colour of this generation's births
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
        mul     x8, x24, x26              // W*H, the whole board

        and     x9, x21, #255             // births: the palette at gen
        ldrsb   w14, [x19, x9]
        add     w14, w14, #128
        add     x9, x21, #85
        and     x9, x9, #255
        ldrsb   w10, [x19, x9]
        add     w10, w10, #128
        orr     w14, w14, w10, lsl #8
        add     x9, x21, #170
        and     x9, x9, #255
        ldrsb   w10, [x19, x9]
        add     w10, w10, #128
        orr     w14, w14, w10, lsl #16
        movz    w17, #(DEAD & 0xffff)
        movk    w17, #(DEAD >> 16), lsl #16

        orr     x9, x24, x25, lsl #16
        cmp     x9, x28
        b.eq    .Lstep

// -- phase: a new size: soup, a quarter alive, and a full frame owed
        mov     x28, x9
        adrp    x9, full
        mov     w10, #1
        str     w10, [x9, :lo12:full]
        adrp    x12, rng
        ldr     x13, [x12, :lo12:rng]
        mov     x1, #0
.Lsoup: xs      x13
        lsr     x9, x13, #62              // top two bits clear: alive
        cmp     x9, #0
        cset    w9, eq
        strb    w9, [x29, x1]
        csel    w10, w14, w17, eq
        str     w10, [x22, x1, lsl #2]
        add     x1, x1, #1
        cmp     x1, x8
        b.lt    .Lsoup
        str     x13, [x12, :lo12:rng]
        b       .Lrain

// -- phase: one generation, now -> next, births and deaths into the block
.Lstep: mov     x16, x30                  // next, cursor
        mov     x15, x22                  // pixel, cursor
        mov     x1, #0                    // y
.Ly:    madd    x2, x1, x24, x29          // this row
        sub     x3, x2, x24               // the row above, around the top
        cbnz    x1, 1f
        add     x3, x3, x8
1:      add     x5, x2, x24               // the row below, around the bottom
        add     x9, x1, #1
        cmp     x9, x26
        b.ne    2f
        sub     x5, x5, x8
2:      mov     x4, #0                    // x
.Lx:    sub     x6, x4, #1                // left, around
        sub     x10, x24, #1
        cmp     x4, #0
        csel    x6, x10, x6, eq
        add     x7, x4, #1                // right, around
        cmp     x7, x24
        csel    x7, xzr, x7, eq
        ldrb    w9, [x3, x6]
        ldrb    w10, [x3, x4]
        add     w9, w9, w10
        ldrb    w10, [x3, x7]
        add     w9, w9, w10
        ldrb    w10, [x2, x6]
        add     w9, w9, w10
        ldrb    w10, [x2, x7]
        add     w9, w9, w10
        ldrb    w10, [x5, x6]
        add     w9, w9, w10
        ldrb    w10, [x5, x4]
        add     w9, w9, w10
        ldrb    w10, [x5, x7]
        add     w9, w9, w10
        ldrb    w11, [x2, x4]             // alive now?
        cmp     w9, #3                    // three: alive next, either way
        cset    w12, eq
        cmp     w9, #2                    // two: as it was
        cset    w10, eq
        and     w10, w10, w11
        orr     w12, w12, w10
        strb    w12, [x16], #1
        cmp     w12, w11
        b.eq    3f                        // no change, no pixel written
        cmp     w12, #0
        csel    w10, w14, w17, ne
        str     w10, [x15]
3:      add     x15, x15, #4
        add     x4, x4, #1
        cmp     x4, x24
        b.lt    .Lx
        add     x1, x1, #1
        cmp     x1, x26
        b.lt    .Ly
        mov     x9, x29                   // next becomes now
        mov     x29, x30
        mov     x30, x9

// -- phase: rain, a patch of new life now and then
.Lrain: tst     x21, #RAIN
        b.ne    .Lscan
        adrp    x12, rng
        ldr     x13, [x12, :lo12:rng]
        xs      x13
        udiv    x9, x13, x24
        msub    x4, x9, x24, x13          // x0 = rand % W
        xs      x13
        udiv    x9, x13, x26
        msub    x1, x9, x26, x13          // y0 = rand % H
        mov     x5, #0                    // dy
.Lpy:   add     x9, x1, x5
        udiv    x10, x9, x26
        msub    x2, x10, x26, x9          // (y0+dy) % H
        mul     x2, x2, x24
        mov     x6, #0                    // dx
.Lpx:   xs      x13
        tbz     x13, #63, 1f              // top bit: alive
        add     x9, x4, x6
        udiv    x10, x9, x24
        msub    x9, x10, x24, x9          // (x0+dx) % W
        add     x9, x9, x2
        ldrb    w10, [x29, x9]
        cbnz    w10, 1f                   // alive already keeps its colour
        mov     w10, #1
        strb    w10, [x29, x9]
        str     w14, [x22, x9, lsl #2]
1:      add     x6, x6, #1
        cmp     x6, #PATCH
        b.lt    .Lpx
        add     x5, x5, #1
        cmp     x5, #PATCH
        b.lt    .Lpy
        str     x13, [x12, :lo12:rng]

// -- phase: scanout, only what differs from what was sent
.Lscan: mov     x0, x23
        adrp    x9, full
        ldr     w14, [x9, :lo12:full]
        str     wzr, [x9, :lo12:full]
        cbz     w14, 1f
        movz    w9, #0x5b1b               // "\e[2J", the size changed
        movk    w9, #0x4a32, lsl #16
        str     w9, [x0], #4
1:      movz    w9, #0x5b1b               // "\e[H", stored as four, kept as three
        movk    w9, #0x48, lsl #16
        str     w9, [x0]
        add     x0, x0, #3
        mov     w12, #-1                  // foreground set, none: no pixel
        mov     w13, #-1                  // has a top byte, so none matches
        adrp    x7, prev                  // what the terminal shows, cell by cell
        add     x7, x7, :lo12:prev
        lsl     x3, x24, #2               // one pixel row, in bytes
        mov     x2, x22                   // upper pixel row
        mov     x1, #0
.Lrow:  add     x15, x2, x3               // lower pixel row
        mov     x4, #0
        mov     x11, #0                   // unchanged cells not yet skipped
.Lcell: ldr     w5, [x2, x4, lsl #2]
        ldr     w6, [x15, x4, lsl #2]
        orr     x9, x5, x6, lsl #32
        ldr     x10, [x7]
        cbnz    w14, 1f
        cmp     x9, x10
        b.ne    1f
        add     x11, x11, #1
        b       .Lnext
1:      str     x9, [x7]
        cbz     x11, .Lsgr
2:      mov     x16, #255                 // "\e[nC", n at most 255 a time
        cmp     x11, x16
        csel    x16, x16, x11, hi
        mov     w10, #0x5b1b
        strh    w10, [x0], #2
        ldr     x10, [x20, x16, lsl #3]
        str     w10, [x0]
        add     x0, x0, x10, lsr #32
        mov     w10, #67                  // the ';' becomes the 'C'
        sturb   w10, [x0, #-1]
        subs    x11, x11, x16
        b.ne    2b
.Lsgr:  cmp     w5, w6                    // one colour: a space, background only
        b.ne    .Lpair
        cmp     w6, w13
        b.eq    7f
        mov     w13, w6
        mov     w10, #0x5b1b              // "\e["
        strh    w10, [x0], #2
        movz    x10, #0x3834              // "48;2;"
        movk    x10, #0x323b, lsl #16
        movk    x10, #0x3b, lsl #32
        str     x10, [x0]
        add     x0, x0, #5
        chan    x6, 0
        chan    x6, 8
        chan    x6, 16
        mov     w10, #109                 // the last ';' becomes the 'm'
        sturb   w10, [x0, #-1]
7:      mov     w10, #32
        strb    w10, [x0], #1
        b       .Lnext
.Lpair: mov     w10, #0x5b1b              // "\e[", taken back if nothing follows
        strh    w10, [x0], #2
        mov     x17, x0
        cmp     w5, w12
        b.eq    3f
        mov     w12, w5
        movz    x10, #0x3833              // "38;2;"
        movk    x10, #0x323b, lsl #16
        movk    x10, #0x3b, lsl #32
        str     x10, [x0]
        add     x0, x0, #5
        chan    x5, 0
        chan    x5, 8
        chan    x5, 16
3:      cmp     w6, w13
        b.eq    4f
        mov     w13, w6
        movz    x10, #0x3834              // "48;2;"
        movk    x10, #0x323b, lsl #16
        movk    x10, #0x3b, lsl #32
        str     x10, [x0]
        add     x0, x0, #5
        chan    x6, 0
        chan    x6, 8
        chan    x6, 16
4:      cmp     x0, x17
        b.ne    5f
        sub     x0, x0, #2                // both colours already set
        b       6f
5:      mov     w10, #109                 // the last ';' becomes the 'm'
        sturb   w10, [x0, #-1]
6:      movz    w10, #0x96e2              // "▀", stored as four, kept as three
        movk    w10, #0x80, lsl #16
        str     w10, [x0]
        add     x0, x0, #3
.Lnext: add     x7, x7, #8
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
ts:     .quad   0, 33333333               // a thirtieth: Life is for watching
enter:  .ascii  "\033[?1049h\033[?25l"    // alternate screen, cursor off
enter_end:
leave:  .ascii  "\033[0m\033[?25h\033[?1049l"
leave_end:
usage:  .ascii  "usage: life [FRAMES [SEED]]\n"
usage_end:

        .data
        .balign 8
sigact: .quad   0, 0, 0, 0                // handler, flags, restorer, mask

        .bss
        .balign 16
rng:    .space  8
full:   .space  8
ws:     .space  8
sine:   .space  256
        .balign 16
dtab:   .space  256 * 8
pix:    .space  CELLS * 4
prev:   .space  MAXW * MAXR * 8
gridA:  .space  CELLS
gridB:  .space  CELLS
out:    .space  MAXW * MAXR * CELLMAX + 4096
