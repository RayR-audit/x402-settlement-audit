# -*- coding: utf-8 -*-
# 聚类 v2.1 终版：振幅-量级分层对照（farm vs 非 farm）· 2026-09-13
# 方法：hour_amplitude = 24h 结算分布傅里叶基频（UTC），0=全天均匀（脚本特征）
#       前两版阈值分型作废（见 FARM_TYPING_V2_1.md 纠错记录）。
#       终版不做二元打标，按 tx 量级桶分层比振幅分布——避免「振幅=判决」错误。
# 结论（复跑可得）：同 tx 桶内 farm 中位振幅显著更低，10^3 桶 0.070 vs 0.375。
import csv, os, math, statistics, collections
data = r".\data"

# farm 成员集（重放 v2 聚类）
ph = collections.defaultdict(lambda: [0, 0.0, "9", ""])
with open(os.path.join(data,"01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = ph[(r["payer"], r["recipient"])]
        a[0]+=int(r["tx_count"]); a[1]+=float(r["volume_usdc"])
        if r["first_seen"]<a[2]: a[2]=r["first_seen"]
        if r["last_seen"]>a[3]: a[3]=r["last_seen"]
def bucket(x): return math.floor(math.log10(x)) if x > 0 else -99
parent={}
def find(x):
    parent.setdefault(x,x)
    while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
    return x
fp = collections.defaultdict(list)
for (payer, hub), (c, v, fs, ls) in ph.items():
    fp[(hub, fs[:10], ls[:10], bucket(c), bucket(v/c))].append(payer)
for key, ws in fp.items():
    if len(ws) >= 3:
        for w in ws[1:]:
            ra,rb=find(ws[0]),find(w)
            if ra!=rb: parent[ra]=rb
groups = collections.defaultdict(set)
for w in list(parent): groups[find(w)].add(w)
farm=set()
for root,m in groups.items():
    if len(m)>=50: farm|=m

amp_by = collections.defaultdict(lambda: collections.defaultdict(list))
flat_by = collections.defaultdict(lambda: collections.defaultdict(int))
with open(os.path.join(data,"07_timing_rhythm.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        w=r["payer"]
        if w not in parent: continue
        c=int(r["tx_count"]); a=float(r["hour_amplitude"])
        if c < 100: continue
        tb = min(bucket(c),4)
        b = "farm" if w in farm else "non_farm"
        amp_by[b][tb].append(a)
        if a < 0.5: flat_by[b][tb]+=1

out=open(os.path.join(data,"FARM_TYPING_V2_1_FINAL.csv"),"w",newline="",encoding="utf-8")
out.write("tx_bucket,farm_n,farm_median_amp,farm_flat_pct,nonfarm_n,nonfarm_median_amp,nonfarm_flat_pct\n")
for tb in [2,3,4]:
    fa=sorted(amp_by['farm'].get(tb,[])); na=sorted(amp_by['non_farm'].get(tb,[]))
    fm=statistics.median(fa) if fa else ''; nm=statistics.median(na) if na else ''
    ff=100*flat_by['farm'][tb]/len(fa) if fa else ''
    nf=100*flat_by['non_farm'][tb]/len(na) if na else ''
    out.write(f"10^{tb},{len(fa)},{fm},{ff},{len(na)},{nm},{nf}\n")
    print(f"10^{tb} | farm n={len(fa):,} med={fm} flat={ff}% | non_farm n={len(na):,} med={nm} flat={nf}%")
out.close()
print("V21_FINAL_DONE")
