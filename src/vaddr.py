import struct
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001
PH,SOFF = 0x38, 0x58
MSG=b"Hi!\n\0\0\0\0"

# p_vaddr must be page-aligned (low 12 bits zero) AND look like an instruction.
# Rd lives in bits 4:0, so the only candidates write to x0.
BASE = movz(0,0)            # 0xD2800000 -> "movz x0, #0", low 12 bits == 0
assert BASE & 0xFFF == 0

def build():
    I0,I1,I2,TAIL = 0x04,0x28,0x50,0x68
    isl0=[movz(2,8), adr(1,SOFF-(I0+4)), br(I1-(I0+8))]
    isl1=[movz(0,1), movz(8,64), br(I2-(I1+8))]
    isl2=[SVC, br(TAIL-(I2+4))]
    tail=[movz(0,0), movz(8,93), SVC]
    total=TAIL+4*len(tail)
    f=bytearray(total)
    f[0:4]=b"\x7fELF"
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",BASE+I0)
    f[0x20:0x28]=struct.pack("<Q",PH)
    f[0x36:0x38]=struct.pack("<H",56)
    f[0x38:0x3a]=struct.pack("<H",1)
    f[0x3c:0x3e]=struct.pack("<H",5)
    f[PH+0x10:PH+0x18]=struct.pack("<Q",BASE)      # p_vaddr == an instruction
    f[PH+0x20:PH+0x28]=MSG                         # p_filesz == the string
    f[PH+0x28:PH+0x30]=MSG                         # p_memsz  == the string
    for off,ins in ((I0,isl0),(I1,isl1),(I2,isl2),(TAIL,tail)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    return bytes(f)

d=build(); open("v1","wb").write(d)
print(f"BASE = p_vaddr = {BASE:#x}  ({BASE/2**30:.2f} GiB)")
print("bytes at 0x48 (p_vaddr low word):", " ".join(f"{b:02x}" for b in d[0x48:0x4c]))
print("bytes at 0x68 (tail instruction):", " ".join(f"{b:02x}" for b in d[0x68:0x6c]))
print("identical:", d[0x48:0x4c]==d[0x68:0x6c])
