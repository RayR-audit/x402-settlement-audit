# -*- coding: utf-8 -*-
# 聚类 v2.1：farm 群行为分型抽查 · 2026-09-13
# 目的：回应「指纹=行为上界，含真人撞指纹」限定。用 per-wallet 节律特征
#       （07_timing_rhythm.csv: hour_amplitude/active_days/one_shot/density）
#       给每个 v2 farm 群打分型：bot_like / mixed / human_like
# 逻辑：真人钱包 = 活跃天数多(one_shot=0) + 有作息节律(hour_amplitude 高)
#       farm 钱包 = 一次性爆发(one_shot=1) + 24h 均匀打(hour_amplitude 低)
# 分型规则（群级，按群内钱包占比）：
#   bot_like   : one_shot 占比 ≥80% 或 median(hour_amplitude) ≤2
#   human_like : one_shot 占比 ≤20% 且 median(hour_amplitude) ≥4
#   mixed      : 其余
import csv, os, time, math, sys, collections, statistics
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
data = r".\data"
t0=time.time()

# 1) 重放 v2 指纹聚类（与 cluster_v2.py 完全一致，多 dump 成员清单）
ph = collections.defaultdict(lambda: [0, 0.0, "9", ""])
with open(os.path.join(data,"01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = ph[(r["payer"], r["recipient"])]
        a[0]+=int(r["tx_count"]); a[1]+=float(r["volume_usdc"])
        if r["first_seen"]<a[2]: a[2]=r["first_seen"]
        if r["last_seen"]>a[3]: a[3]=r["last_seen"]
print(f"(payer,hub) 对：{len(ph)}  ({time.time()-t0:.0f}s)", flush=True)

def bucket(x): return math.floor(math.log10(x)) if x > 0 else -99
parent={}
def find(x):
    parent.setdefault(x,x)
    while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
    return x
fp = collections.defaultdict(list)
for (payer, hub), (c, v, fs, ls) in ph.items():
    key = (hub, fs[:10], ls[:10], bucket(c), bucket(v/c))
    fp[key].append(payer)
for key, wallets in fp.items():
    if len(wallets) >= 3:
        for w in wallets[1:]:
            ra,rb=find(wallets[0]),find(w)
            if ra!=rb: parent[ra]=rb
groups = collections.defaultdict(set)
for w in list(parent): groups[find(w)].add(w)
farms = {root:m for root,m in groups.items() if len(m)>=50}
print(f"farm 群 ≥50 钱包：{len(farms)}  ({time.time()-t0:.0f}s)", flush=True)

# 2) 读 per-wallet 节律特征
rhythm = {}
with open(os.path.join(data,"07_timing_rhythm.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        rhythm[r["payer"]] = (float(r["hour_amplitude"]), int(r["active_days"]),
                              r["one_shot"]=="1", float(r["activity_density"]))
print(f"节律表钱包数：{len(rhythm)}  ({time.time()-t0:.0f}s)", flush=True)

# 3) 逐群分型
rows=[]
for root, members in farms.items():
    amp=[]; one=0; have=0; ad=[]
    for w in members:
        if w in rhythm:
            have+=1
            a,d,os_,de = rhythm[w]
            amp.append(a); ad.append(d)
            if os_: one+=1
    if have < 10:   # 节律覆盖太低的群跳过（诚实处理）
        rows.append([len(members), have, 0.0, "insufficient_coverage", 0.0, 0, 0.0])
        continue
    amp.sort()
    med_amp = statistics.median(amp)
    one_pct = 100.0*one/have
    med_ad  = statistics.median(ad)
    if one_pct >= 80 or med_amp <= 2:       typ="bot_like"
    elif one_pct <= 20 and med_amp >= 4:    typ="human_like"
    else:                                   typ="mixed"
    rows.append([len(members), have, round(one_pct,1), typ, med_amp, med_ad,
                 round(100.0*have/len(members),1)])

rows.sort(key=lambda r:-r[0])
hdr="wallets,rhythm_wallets,one_shot_pct,typology,median_hour_amplitude,median_active_days,rhythm_coverage_pct"
with open(os.path.join(data,"farm_typing_v2_1.csv"),"w",newline="",encoding="utf-8") as f:
    f.write(hdr+"\n"); f.writelines(",".join(map(str,r))+"\n" for r in rows)

# 4) 汇总
cnt=collections.Counter(r[3] for r in rows)
w_by_type=collections.defaultdict(int)
for r in rows: w_by_type[r[3]]+=r[0]
tot_w=sum(r[0] for r in rows)
log=open(os.path.join(data,"FARM_TYPING_V2_1.md"),"w",encoding="utf-8")
def L(m): print(m,flush=True); log.write(m+"\n")
L(f"# v2.1 farm 群行为分型 {time.strftime('%Y-%m-%d %H:%M')}")
L(f"\n181 farm 群 / {tot_w:,} 钱包 分型结果（节律特征来自 07_timing_rhythm.csv）：")
for t in ["bot_like","mixed","human_like","insufficient_coverage"]:
    L(f"- {t}: {cnt.get(t,0)} 群 / {w_by_type.get(t,0):,} 钱包 ({100*w_by_type.get(t,0)/tot_w:.1f}%)")
L("\n## Top 10 群（按钱包数）")
L("wallets | one_shot% | median_amp | median_days | type")
for r in rows[:10]:
    L(f"{r[0]:>5} | {r[2]:>5}% | {r[4]:>4} | {r[5]:>3} | {r[3]}")
L(f"\nDONE ({time.time()-t0:.0f}s)")
log.close()
print("V21_DONE")
