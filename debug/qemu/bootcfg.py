import sys,struct
out,base=sys.argv[1:3]; extra=sys.argv[3:]
d=open(base,'rb').read().rstrip(b"\0\n")
d+=b"\n"+"".join(x+"\n" for x in extra).encode()
d+=b"\0"
c=sum(d)&0xffffffff
open(out,'wb').write(d+struct.pack('<II',len(d),c)+b"#BOOTCONFIG\n")
