import struct
BASE=0x400000
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001; MSG=b"Hello\n"; PH=0x38; SOFF=9
A,B,C = 0x28, 0x50, 0x68           # three code islands

def build(exit0):
    isl_a=[movz(0,1), adr(1,SOFF-(A+4)), br(B-(A+8))]        # hole: e_shoff+e_flags
    isl_b=[movz(2,len(MSG)), br(C-(B+4))]                    # hole: p_paddr
    isl_c=[movz(8,64), SVC] + ([movz(0,0)] if exit0 else []) + [movz(8,93), SVC]
    total=C+4*len(isl_c)
    f=bytearray(total)
    f[0:8]=b"\x7fELF\x02\x01\x01\x00"
    f[SOFF:SOFF+len(MSG)]=MSG                                # string in EI_PAD
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",BASE+A)                    # e_entry
    f[0x20:0x28]=struct.pack("<Q",PH)                        # e_phoff
    f[0x36:0x38]=struct.pack("<H",56)                        # e_phentsize
    f[0x38:0x3a]=struct.pack("<H",1)                         # e_phnum == p_type
    f[0x3c:0x3e]=struct.pack("<H",5)                         # e_shnum == p_flags
    f[PH+0x10:PH+0x18]=struct.pack("<Q",BASE)                # p_vaddr
    f[PH+0x20:PH+0x28]=struct.pack("<Q",total)               # p_filesz
    f[PH+0x28:PH+0x30]=struct.pack("<Q",total)               # p_memsz
    for off,ins in ((A,isl_a),(B,isl_b),(C,isl_c)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    return bytes(f)
open("g9","wb").write(build(True)); open("g10","wb").write(build(False))
