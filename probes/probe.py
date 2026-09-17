import struct
BASE=0x400000
def movz(rd,i): return 0xD2800000|(i<<5)|rd
def adr(rd,d):  return ((d&3)<<29)|0x10000000|(((d>>2)&0x7FFFF)<<5)|rd
def br(d):      return 0x14000000|((d>>2)&0x3FFFFFF)
SVC=0xD4000001; MSG=b"aarch64\n"

def mk(PH, phnum, poff, pvaddr, filesz=None, soff=0x50, tail_at=0x68, I1=0x28):
    isl0=[movz(2,8), adr(1, soff-0x08), br(I1-0x0c)]
    isl1=[movz(0,1), movz(8,64), br(tail_at-(I1+8))]
    tail=[SVC, movz(0,0), movz(8,93), SVC]
    total=tail_at+4*len(tail)
    sz = total if filesz is None else filesz
    f=bytearray(total)
    f[0:4]=b"\x7fELF"
    f[0x10:0x12]=struct.pack("<H",2); f[0x12:0x14]=struct.pack("<H",183)
    f[0x18:0x20]=struct.pack("<Q",BASE+4)          # e_entry
    f[0x20:0x28]=struct.pack("<Q",PH)              # e_phoff
    f[0x36:0x38]=struct.pack("<H",56)              # e_phentsize
    f[0x38:0x3a]=struct.pack("<H",phnum)           # e_phnum
    # program header, written AFTER so it wins any collision
    f[PH+0x00:PH+0x04]=struct.pack("<I",1)         # p_type
    f[PH+0x04:PH+0x08]=struct.pack("<I",5)         # p_flags
    f[PH+0x08:PH+0x10]=struct.pack("<Q",poff)      # p_offset
    f[PH+0x10:PH+0x18]=struct.pack("<Q",pvaddr)    # p_vaddr
    f[PH+0x20:PH+0x28]=struct.pack("<Q",sz)        # p_filesz
    f[PH+0x28:PH+0x30]=struct.pack("<Q",sz)        # p_memsz
    for off,ins in ((0x04,isl0),(I1,isl1),(tail_at,tail)):
        for k,w in enumerate(ins): f[off+4*k:off+4*k+4]=struct.pack("<I",w)
    f[soff:soff+len(MSG)]=MSG
    return bytes(f)

# t1: PH=0x30 -> 0x38 lands inside p_offset, which must be 0 -> e_phnum forced to 0
open("t1","wb").write(mk(0x30, 0, 0, BASE))
# t2: PH=0x28 -> 0x38 lands inside p_vaddr. Give p_offset nonzero low bits so
#     e_phnum can be 1, keeping (p_vaddr - p_offset) page-congruent.
open("t2","wb").write(mk(0x28, 1, 0x0038000000000001, BASE|1))
# t3: PH=0x38 (known good) but p_filesz/p_memsz = an instruction word (~3.5 GB)
open("t3","wb").write(mk(0x38, 1, 0, BASE, filesz=0xD2800020))
# t4: control — known good
open("t4","wb").write(mk(0x38, 1, 0, BASE))
