# -*- coding: utf-8 -*-
# 报告图表三件套 + hub 匿名映射 · 2026-09-13
# 图1 Gini Lorenz 曲线（金额+笔数）
# 图2 farm 群份额条形图（top 15 + 其余归并）
# 图3 振幅分层箱线图（farm vs 非farm × tx桶）
# 输出 data/figs/*.png（报告用，300dpi）+ hub_anon_map.csv（内部真源）
import csv, os, math, collections, statistics
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

data = r".\data"
figd = os.path.join(data, "figs")
os.makedirs(figd, exist_ok=True)

# ---- 图1: Lorenz 曲线（用 buyer_nodes 金额分布近似 + 笔数）----
# 需要每 payer 的总金额/笔数：从 01_edge_list 聚合
pv = collections.defaultdict(lambda: [0, 0.0])
with open(os.path.join(data, "01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = pv[r["payer"]]
        a[0] += int(r["tx_count"]); a[1] += float(r["volume_usdc"])
txs = sorted(a[0] for a in pv.values())
vols = sorted(a[1] for a in pv.values())

def lorenz(vals):
    cum = 0.0; out = [0.0]
    tot = sum(vals)
    for v in vals:
        cum += v; out.append(cum / tot)
    n = len(vals)
    return [i / n for i in range(n + 1)], out

def gini(vals):
    n = len(vals); s = sum(vals)
    return (2 * sum((i + 1) * v for i, v in enumerate(vals)) / (n * s)) - (n + 1) / n

fig, ax = plt.subplots(figsize=(6.5, 5))
for vals, lab, g in [(vols, "Volume (USDC)", gini(vols)), (txs, "Settlement count", gini(txs))]:
    x, y = lorenz(vals)
    ax.plot(x, y, label=f"{lab}  Gini={g:.3f}", lw=2)
ax.plot([0, 1], [0, 1], "k--", lw=1, label="Equality")
ax.set_xlabel("Cumulative share of payers")
ax.set_ylabel("Cumulative share")
ax.set_title("Concentration of x402 settlements (Base slice)")
ax.legend(loc="upper left", fontsize=9)
fig.tight_layout(); fig.savefig(os.path.join(figd, "fig1_lorenz.png"), dpi=300); plt.close(fig)

# ---- hub 匿名映射（内部真源）----
farm = list(csv.DictReader(open(os.path.join(data, "farm_cohorts_v2.csv"), encoding="utf-8")))
hub_rank = collections.Counter()
for r in farm:
    hub_rank[r["top_hub"]] += int(r["settlements"])
anon = {hub: f"Hub {chr(65+i)}" for i, (hub, _) in enumerate(hub_rank.most_common())}
with open(os.path.join(data, "hub_anon_map.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["real_hub", "anon_label", "farm_settlements"])
    for hub, s in hub_rank.most_common():
        w.writerow([hub, anon.get(hub, f"Hub {len(anon)+1}+"), s])

# ---- 图2: farm 群份额（top 15，匿名 hub 标注）----
top = farm[:15]
labels = [f"{int(r['wallets'])}w @{anon.get(r['top_hub'],'?')}" for r in top][::-1]
vals = [float(r["pct_network_tx"]) for r in top][::-1]
fig, ax = plt.subplots(figsize=(7.5, 6))
ax.barh(labels, vals, color="#c0392b")
ax.set_xlabel("Share of network settlements (%)")
ax.set_title("Largest fingerprint cohorts (upper bound; hubs anonymized)")
fig.tight_layout(); fig.savefig(os.path.join(figd, "fig2_cohorts.png"), dpi=300); plt.close(fig)

# ---- 图3: 振幅分层箱线图 ----
# 复用 v2.1 逻辑取 (farm, bucket, amp)
ph = collections.defaultdict(lambda: [0, 0.0, "9", ""])
with open(os.path.join(data, "01_edge_list.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        a = ph[(r["payer"], r["recipient"])]
        a[0] += int(r["tx_count"]); a[1] += float(r["volume_usdc"])
        if r["first_seen"] < a[2]: a[2] = r["first_seen"]
        if r["last_seen"] > a[3]: a[3] = r["last_seen"]
def bucket(x): return math.floor(math.log10(x)) if x > 0 else -99
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
    return x
fp = collections.defaultdict(list)
for (payer, hub), (c, v, fs, ls) in ph.items():
    fp[(hub, fs[:10], ls[:10], bucket(c), bucket(v/c))].append(payer)
for key, ws in fp.items():
    if len(ws) >= 3:
        for w in ws[1:]:
            ra, rb = find(ws[0]), find(w)
            if ra != rb: parent[ra] = rb
groups = collections.defaultdict(set)
for w in list(parent): groups[find(w)].add(w)
fset = set()
for m in groups.values():
    if len(m) >= 50: fset |= m
amp = collections.defaultdict(list)   # (group,bucket)->amps
with open(os.path.join(data, "07_timing_rhythm.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        w = r["payer"]
        if w not in parent: continue
        c = int(r["tx_count"])
        if c < 100: continue
        b = min(bucket(c), 4)
        g = "farm" if w in fset else "non-farm"
        amp[(g, b)].append(float(r["hour_amplitude"]))
buckets = [2, 3, 4]
data_box = []; positions = []; colors = []
pal = {"farm": "#c0392b", "non-farm": "#2c3e50"}
for i, b in enumerate(buckets):
    for j, g in enumerate(["farm", "non-farm"]):
        a = amp.get((g, b), [])
        if a:
            data_box.append(a); positions.append(i * 3 + j); colors.append(pal[g])
fig, ax = plt.subplots(figsize=(7, 4.5))
bp = ax.boxplot(data_box, positions=positions, showfliers=False, patch_artist=True, widths=0.6)
for p, c in zip(bp["boxes"], colors): p.set_facecolor(c)
ax.set_xticks([i * 3 + 0.5 for i in range(len(buckets))])
ax.set_xticklabels([f"{10**b}–{10**(b+1)} tx" for b in buckets])
ax.set_xlabel("Volume bucket (settlements per payer)")
ax.set_ylabel("Diurnal amplitude (24h Fourier)")
ax.set_title("Payer activity rhythm by volume bucket (cohort vs rest)")
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color=pal["farm"], label="fingerprint cohort"), Patch(color=pal["non-farm"], label="rest of network")], fontsize=9)
fig.tight_layout(); fig.savefig(os.path.join(figd, "fig3_rhythm.png"), dpi=300); plt.close(fig)
print("FIGS_DONE", os.listdir(figd))
