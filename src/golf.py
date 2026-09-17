import struct, sys

BASE = 0x400000

def movz(rd, imm):          return 0xD2800000 | (imm << 5) | rd
def adr(rd, delta):
    imm = delta & 0x1FFFFF
    return ((imm & 3) << 29) | 0x10000000 | (((imm >> 2) & 0x7FFFF) << 5) | rd
SVC = 0xD4000001

def code(str_off, code_off, slen, exit0=True):
    ins = [movz(0,1), adr(1, str_off - (code_off+4)), movz(2,slen),
           movz(8,64), SVC]
    if exit0: ins.append(movz(0,0))
    ins += [movz(8,93), SVC]
    return b"".join(struct.pack("<I", i) for i in ins)

def build(msg, overlap, hide_in_pad, exit0=True):
    s = msg.encode()
    PH = 0x38 if overlap else 0x40          # e_phoff
    end = PH + 56                           # end of program header
    if hide_in_pad:
        assert len(s) <= 7, "EI_PAD is 7 bytes"
        str_off, code_off = 9, end
    else:
        code_off, str_off = end, end + (32 if exit0 else 28)
    body = code(str_off, code_off, len(s), exit0)
    total = code_off + len(body) + (0 if hide_in_pad else len(s))

    f = bytearray(total)
    f[0:8] = b"\x7fELF\x02\x01\x01\x00"
    f[0x10:0x12] = struct.pack("<H", 2)      # e_type  ET_EXEC
    f[0x12:0x14] = struct.pack("<H", 183)    # e_machine EM_AARCH64
    f[0x14:0x18] = struct.pack("<I", 1)      # e_version
    f[0x18:0x20] = struct.pack("<Q", BASE + code_off)   # e_entry
    f[0x20:0x28] = struct.pack("<Q", PH)     # e_phoff
    f[0x36:0x38] = struct.pack("<H", 56)     # e_phentsize  (CHECKED)
    if overlap:
        # the phdr's first 8 bytes are the ehdr's last 8 bytes
        f[0x38:0x3a] = struct.pack("<H", 1)  # e_phnum  == p_type lo
        f[0x3a:0x3c] = struct.pack("<H", 0)  # e_shentsize == p_type hi
        f[0x3c:0x3e] = struct.pack("<H", 5)  # e_shnum  == p_flags lo
        f[0x3e:0x40] = struct.pack("<H", 0)  # e_shstrndx == p_flags hi
    else:
        f[0x38:0x3a] = struct.pack("<H", 1)
        f[PH+0:PH+4] = struct.pack("<I", 1)  # p_type PT_LOAD
        f[PH+4:PH+8] = struct.pack("<I", 5)  # p_flags R+X
    f[PH+0x08:PH+0x10] = struct.pack("<Q", 0)       # p_offset
    f[PH+0x10:PH+0x18] = struct.pack("<Q", BASE)    # p_vaddr
    f[PH+0x20:PH+0x28] = struct.pack("<Q", total)   # p_filesz
    f[PH+0x28:PH+0x30] = struct.pack("<Q", total)   # p_memsz
    f[PH+0x30:PH+0x38] = struct.pack("<Q", 0x1000)  # p_align
    f[code_off:code_off+len(body)] = body
    f[str_off:str_off+len(s)] = s
    return bytes(f)

for name, kw in [
    ("g1", dict(msg="Hello from aarch64 asm on Android\n", overlap=False, hide_in_pad=False)),
    ("g2", dict(msg="Hello from aarch64 asm on Android\n", overlap=True,  hide_in_pad=False)),
    ("g3", dict(msg="Hello\n", overlap=True, hide_in_pad=True)),
    ("g4", dict(msg="Hello\n", overlap=True, hide_in_pad=True, exit0=False)),
]:
    open(name, "wb").write(build(**kw))
