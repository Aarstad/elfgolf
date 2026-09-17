// aarch64 Linux/Android — no libc, raw syscalls
        .section .rodata
msg:    .ascii  "Hello from aarch64 asm on Android\n"
        .set    len, . - msg

        .section .text
        .global _start
_start:
        mov     x0, #1                  // fd = stdout
        adrp    x1, msg                 // page of msg
        add     x1, x1, :lo12:msg       // + page offset
        mov     x2, #len                // byte count
        mov     x8, #64                 // __NR_write
        svc     #0

        mov     x0, #0                  // status
        mov     x8, #93                 // __NR_exit
        svc     #0
