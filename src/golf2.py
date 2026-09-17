import struct
BASE = 0x400000
def movz(rd,imm): return 0xD2800000 | (imm<<5) | rd
def adr(rd,d):    return ((d&3)<<29) | 0x10000000 | (((d>>2)&0x7FFFF)<<5) | rd
def b(d):         return 0x14000000 | ((d>>2) & 0x3FFFFFF)
SVC = 0xD4000001
MSG = b"Hello\n"

def emit(f, off, ins):
    for i, w in enumerate(ins):
        f[off+4*i:off+4*i+4] = struct.pack("<I", w)

def build(align, code_off, split, exit0):
    PH, SOFF = 0x38, 9
    tail = []
    if split:
        # 2 instrs + branch parked in the e_shoff/e_flags hole at 0x28
        head_off = 0x28
        head = [movz(0,1), adr(1, SOFF-(head_off+4)), b(code_off-(head_off+8))]
        tail = [movz(2,len(MSG)), movz(8,64), SVC]
        entry = head_off
    else:
        head = []
        tail = [movz(0,1), adr(1, SOFF-(code_off+4)), movz(2,len(MSG)), movz(8,64), SVC]
        entry = code_off
    if exit0: tail.append(movz(0,0))
    tail += [movz(8,93), SVC]
    total = code_off + 4*len(tail)

    f = bytearray(total)
    f[0:8] = b"\x7fELF\x02\x01\x01\x00"
    f[SOFF:SOFF+len(MSG)] = MSG                     # string hidden in EI_PAD
    f[0x10:0x12] = struct.pack("<H",2)              # ET_EXEC
    f[0x12:0x14] = struct.pack("<H",183)            # EM_AARCH64
    f[0x18:0x20] = struct.pack("<Q", BASE+entry)    # e_entry
    f[0x20:0x28] = struct.pack("<Q", PH)            # e_phoff
    f[0x36:0x38] = struct.pack("<H",56)             # e_phentsize (CHECKED)
    f[0x38:0x3a] = struct.pack("<H",1)              # e_phnum  == p_type lo
    f[0x3c:0x3e] = struct.pack("<H",5)              # e_shnum  == p_flags lo
    f[PH+0x10:PH+0x18] = struct.pack("<Q", BASE)    # p_vaddr
    f[PH+0x20:PH+0x28] = struct.pack("<Q", total)   # p_filesz
    f[PH+0x28:PH+0x30] = struct.pack("<Q", total)   # p_memsz
    f[PH+0x30:PH+0x38] = struct.pack("<Q", align)   # p_align
    if head: emit(f, 0x28, head)
    emit(f, code_off, tail)
    return bytes(f)

for name, kw in [
  ("g5", dict(align=0x1000, code_off=0x70, split=False, exit0=True)),
  ("g6", dict(align=1,      code_off=0x68, split=False, exit0=True)),
  ("g7", dict(align=1,      code_off=0x68, split=True,  exit0=True)),
  ("g8", dict(align=1,      code_off=0x68, split=True,  exit0=False)),
]:
    open(name,"wb").write(build(**kw))
