        .data
        .global src
        .global tape
src:
        .ascii "!b->Bc!\n"
        .ascii "!c->c!\n"
        .ascii "!->\n"
        .ascii "B->b\n"
        .ascii "a*->*!\n"
        .ascii "*->\n"
        .ascii "b->\n"
        .byte 0
        .balign 8
tape:
        .ascii "aa*bbb\n"
        .space 512
