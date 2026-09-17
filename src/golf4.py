import struct
BASE=0x400000
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001
MSG=b"aarch64\n"          # must be 8 bytes: the magic-word instruction says so
PH,SOFF = 0x38, 0x50      # string hides in p_paddr

# The instruction living inside e_ident[4..7].
# bytes 4,5 are FORCED: 0x02 ELFCLASS64, 0x01 ELFDATA2LSB -> low half = 0x0102
# bytes 6,7 are ours:   EI_VERSION, EI_OSABI
MAGIC_INSN = movz(2, len(MSG))
assert MAGIC_INSN & 0xFFFF == 0x0102, hex(MAGIC_INSN)
print("e_ident[4:8] =", " ".join(f"{b:02x}" for b in struct.pack("<I",MAGIC_INSN)),
      f"-> movz x2, #{len(MSG)}")

def build(exit0):
    I0, I1, TAIL = 0x04, 0x28, 0x68
    isl0=[MAGIC_INSN, adr(1, SOFF-(I0+4)), br(I1-(I0+8))]     # in e_ident
    isl1=[movz(0,1), movz(8,64), br(TAIL-(I1+8))]             # in e_shoff/e_flags
    tail=[SVC] + ([movz(0,0)] if exit0 else []) + [movz(8,93), SVC]
    total=TAIL+4*len(tail)
    f=bytearray(total)
    f[0:4]=b"\x7fELF"                                          # bytes 4-7 written below
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",BASE+I0)                     # e_entry points into e_ident
    f[0x20:0x28]=struct.pack("<Q",PH)
    f[0x36:0x38]=struct.pack("<H",56)
    f[0x38:0x3a]=struct.pack("<H",1)                           # e_phnum == p_type
    f[0x3c:0x3e]=struct.pack("<H",5)                           # e_shnum == p_flags
    f[PH+0x10:PH+0x18]=struct.pack("<Q",BASE)
    f[PH+0x20:PH+0x28]=struct.pack("<Q",total)
    f[PH+0x28:PH+0x30]=struct.pack("<Q",total)
    for off,ins in ((I0,isl0),(I1,isl1),(TAIL,tail)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    f[SOFF:SOFF+len(MSG)]=MSG
    return bytes(f)
open("m1","wb").write(build(True)); open("m2","wb").write(build(False))
