import subprocess,os,sys
O=sys.argv[1]; out="disk.raw"
M=1024*1024
parts=[("super",11274289152,"super.raw"),("metadata",256*M,"metadata.raw"),("userdata",24*1024*M,None)]
for s in "_a","_b":
    parts+=[("vbmeta"+s,M,O+"/vbmeta.img"),("vbmeta_system"+s,M,O+"/vbmeta_system.img"),("vbmeta_vendor"+s,M,O+"/vbmeta_vendor.img"),("boot"+s,201326592,O+"/boot.img"),("vendor_boot"+s,201326592,O+"/vendor_boot.img"),("dtbo"+s,25165824,O+"/dtbo.img"),("recovery"+s,104857600,O+"/recovery.img"),
     ("modem"+s,8*M,None),("dsp"+s,8*M,None),("bluetooth"+s,8*M,None)]
parts+=[("misc",M,None),("persist",64*M,None),("frp",M,None),("logdump",M,None),("modemst1",2*M,None),("modemst2",2*M,None),("fsg",2*M,None),("fsc",M,None)]
if os.path.exists(out): os.remove(out)
tot=sum((p[1]+M) for p in parts)+64*M
open(out,"wb").close(); os.truncate(out,tot)
args=["sgdisk","-a","2048","-o"]
for i,(n,sz,_) in enumerate(parts,1):
    args+=[f"-n{i}:0:+{sz//1024}K",f"-c{i}:{n}"]
subprocess.check_call(args+[out],stdout=subprocess.DEVNULL)
pt=subprocess.check_output(["sgdisk","-p",out],text=True)
st={}
for l in pt.splitlines():
    f=l.split()
    if len(f)>=7 and f[0].isdigit(): st[f[-1]]=int(f[1])*512
for n,sz,src in parts:
    if src: subprocess.check_call(["dd",f"if={src}",f"of={out}","bs=1M","oflag=seek_bytes",f"seek={st[n]}","conv=notrunc,sparse","status=none"])
print(len(parts),"parts; size",tot); 
