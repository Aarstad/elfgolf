import struct
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001
PH=0x38
MSG=b"Hi!\n\0\0\0\0"
SOFF=PH+0x10                      # 0x48 == p_vaddr: the string doubles as the load address
VADDR=struct.unpack("<Q",MSG)[0]  # 0x0A216948
POFF=VADDR & 0xFFF                # 0x948 : p_offset must match p_vaddr mod page size
PAGE=VADDR-POFF                   # file offset F  ->  address PAGE+F

def build():
    A,B,C,TAIL = 0x04,0x28,0x50,0x68
    isl_a=[movz(2,8), adr(1,SOFF-(A+4)), br(B-(A+8))]     # e_ident
    isl_b=[movz(0,1), movz(8,64), br(C-(B+8))]            # e_shoff / e_flags
    isl_c=[SVC, movz(0,0), br(TAIL-(C+8))]                # p_paddr + p_filesz low word
    tail =[movz(8,93), SVC]                               # p_align
    total=TAIL+4*len(tail)                                # == PH+56 : the floor for this technique
    assert total==PH+56
    f=bytearray(total)
    f[0:4]=b"\x7fELF"
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",PAGE+A)                 # e_entry
    f[0x20:0x28]=struct.pack("<Q",PH)
    f[0x36:0x38]=struct.pack("<H",56)
    f[0x38:0x3a]=struct.pack("<H",1)                      # e_phnum == p_type
    f[0x3c:0x3e]=struct.pack("<H",5)                      # e_shnum == p_flags
    f[PH+0x08:PH+0x10]=struct.pack("<Q",POFF)             # p_offset
    f[PH+0x10:PH+0x18]=struct.pack("<Q",VADDR)            # p_vaddr == the string
    for off,ins in ((A,isl_a),(B,isl_b),(C,isl_c),(TAIL,tail)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    fsz=struct.unpack("<Q",bytes(f[PH+0x20:PH+0x28]))[0]  # whatever the branch encodes
    f[PH+0x28:PH+0x30]=struct.pack("<Q",fsz)              # p_memsz = same
    return bytes(f),fsz

d,fsz=build(); open("z1","wb").write(d)
print(f"p_offset = {POFF:#x}   p_vaddr = {VADDR:#x} ({MSG!r})")
print(f"load page = {PAGE:#x}   entry = {PAGE+4:#x}")
print(f"p_filesz = {fsz:#x} ({fsz/2**20:.0f} MiB)  <- this is a 'b' instruction")
