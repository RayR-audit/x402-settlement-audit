# -*- coding: utf-8 -*-
# 聚类 v2 参数敏感性 · 2026-09-13
# 附录 B 材料：farm 群占比对两个参数的稳健性
#   参数1：群大小阈值 min_wallets ∈ {30, 50, 100}
#   参数2：指纹组合并下限 min_group ∈ {2, 3, 5}
# 全网结算基数 52,652,290（与 v2 一致）
import csv, os, math, collections
data = r".\data"
NET_TX = 52652290

# 一次性构建 (payer,hub) 聚合 + 指纹分组，然后对参数网格重放并查集
ph = collections.defaultdict(lambda: [0, 0.0, "9", ""])
with open(os.path.join(data,"01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = ph[(r["payer"], r["recipient"])]
        a[0]+=int(r["tx_count"]); a[1]+=float(r["volume_usdc"])
        if r["first_seen"]<a[2]: a[2]=r["first_seen"]
        if r["last_seen"]>a[3]: a[3]=r["last_seen"]
def bucket(x): return math.floor(math.log10(x)) if x > 0 else -99
fp = collections.defaultdict(list)
for (payer, hub), (c, v, fs, ls) in ph.items():
    fp[(hub, fs[:10], ls[:10], bucket(c), bucket(v/c))].append(payer)

print("min_group | min_wallets | farm_groups | wallets | settlements | pct_tx | pct_wallets_of_payers")
results=[]
for mg in [2,3,5]:
    parent={}
    def find(x):
        parent.setdefault(x,x)
        while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
        return x
    for key, ws in fp.items():
        if len(ws) >= mg:
            for w in ws[1:]:
                ra,rb=find(ws[0]),find(w)
                if ra!=rb: parent[ra]=rb
    groups = collections.defaultdict(set)
    for w in list(parent): groups[find(w)].add(w)
    for mw in [30,50,100]:
        farms=[m for m in groups.values() if len(m)>=mw]
        n_w=sum(len(m) for m in farms)
        tx=0
        for (payer,hub),(c,v,fs,ls) in ph.items():
            # 钱包属于哪个 farm：逐群判定太慢，用集合
            pass
        fset=set()
        for m in farms: fset|=m
        tx=sum(c for (payer,hub),(c,v,fs,ls) in ph.items() if payer in fset)
        results.append((mg,mw,len(farms),n_w,tx))
        print(f"{mg} | {mw} | {len(farms)} | {n_w:,} | {tx:,} | {100*tx/NET_TX:.1f}% | {100*n_w/len(parent):.1f}%")

with open(os.path.join(data,"SENSITIVITY_V2.csv"),"w",newline="",encoding="utf-8") as f:
    f.write("min_fingerprint_group,min_wallet_threshold,farm_groups,farm_wallets,farm_settlements,pct_network_tx\n")
    for mg,mw,g,w,tx in results:
        f.write(f"{mg},{mw},{g},{w},{tx},{100*tx/NET_TX:.2f}\n")
print("SENSITIVITY_DONE")
