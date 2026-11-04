import os,sys,shutil
base,out,dl=sys.argv[1:4]
rv=base+"/rd_vendor/lib/modules"
def rd(d,n):
    p=f"{d}/{n}"; return [l.strip() for l in open(p)] if os.path.exists(p) else []
norm=lambda n:os.path.basename(n).replace(".ko","").replace("-","_")
dep={}; where={}
for d in (dl,rv):  # ramdisk copy wins
    for f in os.listdir(d):
        if f.endswith(".ko"): where[norm(f)]=f"{d}/{f}"
    for l in rd(d,"modules.dep"):
        if ":" not in l: continue
        a,b=l.split(":",1); dep[norm(a)]=[norm(x) for x in b.split()]
block=set()
for d in (rv,dl):
    for l in rd(d,"modules.blocklist"):
        if l.startswith("blocklist"): block.add(norm(l.split()[1]))
order=[];seen=set();blocked=[];missing=[]
def add(n):
    if n in seen: return
    seen.add(n)
    if n not in where: missing.append(n); return
    for d in dep.get(n,[]): add(d)
    order.append(n)
stage=[]
for tag,lst in (("ramdisk",rd(rv,"modules.load")),("dlkm",rd(dl,"modules.load"))):
    for l in lst:
        n=norm(l)
        if not n: continue
        if n in block: blocked.append(n); continue
        add(n)
os.makedirs(out+"/m",exist_ok=True)
for n in order: shutil.copy(where[n],f"{out}/m/{n}.ko")
open(out+"/order.txt","w").write("".join(n+".ko\n" for n in order))
print("order",len(order),"blocked",len(blocked),"known",len(where),"missing",missing,"unlisted",sorted(set(where)-set(order)-set(blocked)))
print("blocked:",*blocked)
