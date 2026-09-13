# -*- coding: utf-8 -*-
# 聚类 v2：活动窗口指纹聚类（farm 识别）· 2026-09-13
# 规则：同一 hub 上，两个钱包若共享 ①相同活动窗口(first10,last10) ②相同 tx 量级桶(floor(log10))
#      ③相同票均量级桶(floor(log10(vol/tx)))  → 并查集合并 = 同一 farm 群
# 输出：farm 群清单（≥50 钱包）+ 各群结算统计 + 群占全网份额
import csv, os, time, sqlite3, math, sys, collections
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
data = r".\data"
log = open(os.path.join(data, "CLUSTER_V2_20260913.md"), "w", encoding="utf-8")
def L(m):
    print(m, flush=True); log.write(m+"\n"); log.flush()
t0=time.time()
L(f"# 聚类 v2 · 窗口指纹 farm 识别 {time.strftime('%H:%M:%S')}")

# per (payer,hub): tx, vol, first, last
ph = collections.defaultdict(lambda: [0, 0.0, "9", ""])
with open(os.path.join(data,"01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = ph[(r["payer"], r["recipient"])]
        a[0]+=int(r["tx_count"]); a[1]+=float(r["volume_usdc"])
        if r["first_seen"]<a[2]: a[2]=r["first_seen"]
        if r["last_seen"]>a[3]: a[3]=r["last_seen"]
L(f"(payer,hub) 对：{len(ph)}  ({time.time()-t0:.0f}s)")

def bucket(x):
    return math.floor(math.log10(x)) if x > 0 else -99

parent = {}
def find(x):
    parent.setdefault(x,x)
    while parent[x]!=x:
        parent[x]=parent[parent[x]]; x=parent[x]
    return x
def union(a,b):
    ra,rb=find(a),find(b)
    if ra!=rb: parent[ra]=rb

# 指纹分组（只在同一 hub 内合并）
fp = collections.defaultdict(list)
for (payer, hub), (c, v, fs, ls) in ph.items():
    ticket = v/c
    key = (hub, fs[:10], ls[:10], bucket(c), bucket(ticket))
    fp[key].append(payer)
merged_pairs = 0
for key, wallets in fp.items():
    if len(wallets) >= 3:
        for w in wallets[1:]:
            union(wallets[0], w); merged_pairs += 1
L(f"指纹组≥3钱包：{sum(1 for k,v in fp.items() if len(v)>=3)} / {len(fp)} 组")

groups = collections.defaultdict(set)
for w in list(parent):
    groups[find(w)].add(w)
# 群统计（按群内 (payer,hub) 边聚合）
farm_rows = []
for root, members in groups.items():
    if len(members) < 50: continue
    tot_c=0.0; tot_v=0.0; hubs=collections.Counter(); wins=collections.Counter()
    for (payer, hub), (c, v, fs, ls) in ph.items():
        if payer in members:
            tot_c+=c; tot_v+=v; hubs[hub]+=c
            wins[(fs[:10],ls[:10])]+=1
    top_hub, top_c = hubs.most_common(1)[0]
    top_win, top_wn = wins.most_common(1)[0]
    farm_rows.append([len(members), int(tot_c), f"{tot_v:.2f}", f"{100*tot_c/52652290:.2f}",
                      f"{top_hub:.14}", top_win[0], top_win[1], len(hubs), root[:18]])
farm_rows.sort(key=lambda r:-int(r[1]))
hdr="wallets,settlements,volume_usdc,pct_network_tx,top_hub,top_window,window_wallets,distinct_hubs,root_sample"
with open(os.path.join(data,"farm_cohorts_v2.csv"),"w",newline="",encoding="utf-8") as f:
    f.write(hdr+"\n"); f.writelines(",".join(map(str,r))+"\n" for r in farm_rows)
farm_tx = sum(int(r[1]) for r in farm_rows)
farm_w  = sum(int(r[0]) for r in farm_rows)
L(f"## farm 群（≥50 钱包）：{len(farm_rows)} 个，共 {farm_w:,} 钱包 / {farm_tx:,} settlements（{farm_rows[0][3]}%…）")
for r in farm_rows[:10]:
    L(f"- {r[0]:>5}钱包 | {int(r[1]):>10,} tx ({r[3]}%网) | ${float(r[2]):>10,.2f} | hub {r[4]} | 窗 {r[5]} ({r[6]}人) | hubs={r[7]}")
L(f"## DONE ({time.time()-t0:.0f}s)")
log.close()
print("CLUSTER_V2_DONE")
