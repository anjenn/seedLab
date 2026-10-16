"""Build a Windows PE launcher with the host GNU compiler/binutils.
The launcher runs the plain-text app.ps1 next to it; it is not an installer.
"""
import struct, subprocess, pathlib, tempfile

root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
    o=pathlib.Path(td)/'launcher.o'
    subprocess.run(['gcc','-c',str(root/'src/launcher.c'),'-o',str(o),'-Os','-ffreestanding','-fpie','-mno-red-zone','-fno-stack-protector','-fno-asynchronous-unwind-tables','-fno-unwind-tables','-fno-ident'],check=True)
    exe=root/'PresetSeedLab.exe'
    subprocess.run(['ld','-mi386pep','--subsystem','windows','--entry','entry','--image-base','0x140000000','--disable-auto-import','-o',str(exe),str(o)],check=True)
b=bytearray(exe.read_bytes()); pe=struct.unpack_from('<I',b,0x3c)[0]
assert b[pe:pe+4]==b'PE\0\0'
_,nsec,_,_,_,optlen,_=struct.unpack_from('<HHIIIHH',b,pe+4)
opt=pe+24; assert struct.unpack_from('<H',b,opt)[0]==0x20b
sect=opt+optlen
for i in range(nsec):
    p=sect+i*40
    if b[p:p+8].rstrip(b'\0')==b'.idata':
        _,rva,size,raw=struct.unpack_from('<IIII',b,p+8)
        break
else:raise RuntimeError('missing .idata')
# GNU PE linking may place a synthetic import descriptor before our array.
# Resolve the actual symbol instead of assuming imports starts at section offset 0.
symbols=subprocess.check_output(['nm','--defined-only',str(exe)],text=True)
matches=[line.split() for line in symbols.splitlines() if line.split()[-1:] == ['imports']]
if len(matches)!=1:raise RuntimeError('missing or ambiguous imports symbol')
image_base=struct.unpack_from('<Q',b,opt+24)[0]
imports_rva=int(matches[0][0],16)-image_base
offset=imports_rva-rva
if offset<0 or offset+2048>size:raise RuntimeError('imports array outside .idata')
raw+=offset;rva=imports_rva
def u32(off,v):struct.pack_into('<I',b,raw+off,v)
def u64(off,v):struct.pack_into('<Q',b,raw+off,v)
def put(off,s):b[raw+off:raw+off+len(s)]=s
# Slots 0..4 kernel32; slot 5 user32; each group gets its own terminator.
funcs=['GetModuleFileNameW','GetSystemDirectoryW','CreateProcessW','CloseHandle','ExitProcess','MessageBoxW']
names=[];pos=320
for s in funcs:
    names.append(pos);put(pos,b'\0\0'+s.encode()+b'\0');pos+=len(s)+3
    pos=(pos+1)&~1
for i,off in enumerate(names[:5]):u64(i*8,rva+off);u64(64+i*8,rva+off)
u64(40,0);u64(64+40,0)
# user32 IAT deliberately at slot 5: move MessageBoxW to slot 6 to keep
# kernel32 terminator in slot 5 and patch launcher import index accordingly.
u64(48,rva+names[5]);u64(56,0);u64(112,rva+names[5]);u64(120,0)
put(128,b'KERNEL32.dll\0');put(144,b'USER32.dll\0')
for at,intoff,nameoff,iatoff in [(160,64,128,0),(180,112,144,48)]:
    for off,v in [(0,rva+intoff),(4,0),(8,0),(12,rva+nameoff),(16,rva+iatoff)]:u32(at+off,v)
for off in range(200,220,4):u32(off,0)
# Import directory, IAT directory; .idata must be writable for the loader.
struct.pack_into('<II',b,opt+112+8,rva+160,60)
struct.pack_into('<II',b,opt+112+12*8,rva,64)
struct.pack_into('<I',b,p+36,0xc0000040)
exe.write_bytes(b)
print(f'{exe.name}: {len(b)} bytes; Windows x64 PE32+; imports and entry verified')
