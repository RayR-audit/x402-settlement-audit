# -*- coding: utf-8 -*-
# v2.1b 对照组：非 farm 付款方按同一把尺子分型 · 2026-09-13
# 目的：99.5% bot_like 若无对照即无效。对全网其余 ~25k 有节律数据的付款方
#       套同一分型规则，得到基线分布。farm vs 非 farm 差距 = 分型有效性。
import csv, os, time, math, sys, collections, statistics
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
data = r".\data"
t0=time.time()

# 1) 重放 v2 聚类得 farm 成员集（与前两个脚本一致）
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
    key = (hub, fs[:10], ls[:10], bucket(c), bucket(v/c))
    fp[key].append(payer)
for key, wallets in fp.items():
    if len(wallets) >= 3:
        for w in wallets[1:]:
            ra,rb=find(wallets[0]),find(w)
            if ra!=rb: parent[ra]=rb
groups = collections.defaultdict(set)
for w in list(parent): groups[find(w)].add(w)
farm_members = set()
for root,m in groups.items():
    if len(m)>=50: farm_members |= m
print(f"farm 成员：{len(farm_members)} / 全部聚类钱包 {len(parent)}  ({time.time()-t0:.0f}s)", flush=True)

# 2) 全网有节律数据的钱包，按 farm/非farm 分桶后套同一规则
typ = collections.defaultdict(collections.Counter)   # bucket -> {type: n_wallets}
tx_by_typ = collections.defaultdict(lambda: [0, 0])  # bucket -> [wallets, settlements]
amp_all = collections.defaultdict(list)
n=0
with open(os.path.join(data,"07_timing_rhythm.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        w=r["payer"]
        if w not in parent:   # 不在聚类范围内的钱包（edge 里没出现的）跳过
            continue
        n+=1
        amp=float(r["hour_amplitude"]); ad=int(r["active_days"]); one=r["one_shot"]=="1"
        is_farm = w in farm_members
        b = "farm" if is_farm else "non_farm"
        if one: t="bot_like"
        elif amp<=2: t="bot_like"
        elif one==False and amp>=4: t="human_like"
        else: t="mixed"
        # 群级规则是群中位数；个体规则近似（对照用途，两边同尺）
        typ[b][t]+=1
        tx_by_typ[b][0]+=1
        amp_all[b].append(amp)
print(f"已分型钱包：{n}  ({time.time()-t0:.0f}s)", flush=True)

log=open(os.path.join(data,"FARM_TYPING_V2_1.md"),"a",encoding="utf-8")
def L(m): print(m,flush=True); log.write(m+"\n")
L(f"\n# v2.1b 对照组（个体级同尺分型，双方同一规则）{time.strftime('%H:%M')}")
L("分桶 | 钱包数 | bot_like% | mixed% | human_like% | median_amp")
for b in ["farm","non_farm"]:
    tot=sum(typ[b].values()); amps=sorted(amp_all[b]); med=statistics.median(amps)
    bl=100*typ[b]["bot_like"]/tot; mx=100*typ[b]["mixed"]/tot; hu=100*typ[b]["human_like"]/tot
    L(f"{b} | {tot:,} | {bl:.1f}% | {mx:.1f}% | {hu:.1f}% | {med:.3f}")
log.close()
print("V21B_DONE")
