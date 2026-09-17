import struct, sys
BASE=0x400000
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001
PH, SOFF = 0x38, 0x58          # SOFF == PH+0x20 == p_filesz

def build(msg):
    assert len(msg)==8
    val=struct.unpack("<Q",msg)[0]                  # the string, read as a size
    I0,I1,I2,TAIL = 0x04,0x28,0x50,0x68
    isl0=[movz(2,8), adr(1,SOFF-(I0+4)), br(I1-(I0+8))]   # in e_ident
    isl1=[movz(0,1), movz(8,64), br(I2-(I1+8))]           # in e_shoff/e_flags
    isl2=[SVC, br(TAIL-(I2+4))]                           # in p_paddr
    tail=[movz(0,0), movz(8,93), SVC]                     # over p_align
    total=TAIL+4*len(tail)
    f=bytearray(total)
    f[0:4]=b"\x7fELF"
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",BASE+I0)
    f[0x20:0x28]=struct.pack("<Q",PH)
    f[0x36:0x38]=struct.pack("<H",56)
    f[0x38:0x3a]=struct.pack("<H",1)                # e_phnum == p_type
    f[0x3c:0x3e]=struct.pack("<H",5)                # e_shnum == p_flags
    f[PH+0x10:PH+0x18]=struct.pack("<Q",BASE)       # p_vaddr
    f[PH+0x20:PH+0x28]=msg                          # p_filesz  == the string
    f[PH+0x28:PH+0x30]=msg                          # p_memsz   == the string
    for off,ins in ((I0,isl0),(I1,isl1),(I2,isl2),(TAIL,tail)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    return bytes(f), val

for name,msg in [("f1",b"Hi!\n\0\0\0\0"), ("f2",b"Hey!\n\0\0\0"), ("f3",b"Hello\n\0\0")]:
    data,val=build(msg)
    open(name,"wb").write(data)
    print(f"{name}: msg={msg!r} -> p_filesz={val:#x} ({val/2**30:.1f} GiB)")
