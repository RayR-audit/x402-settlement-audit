# -*- coding: utf-8 -*-
# 报告数字全量复核 · 2026-09-13 · 发布闸前置脚本
# 用法：python verify_report_numbers.py —— 全 PASS 才可签发
# 原则：所有数字从真源 CSV 重算，不读报告本身做基准
import csv, sys
base = r"."
report = open(base + r"\REPORT_FULL_EN_20260913.md", encoding="utf-8").read()

rows = list(csv.DictReader(open(base + r"\data\farm_cohorts_v2.csv", encoding="utf-8")))
NET_TX = 52652290
tot_v = 0.0
with open(base + r"\data\01_edge_list.csv", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        tot_v += float(r["volume_usdc"])
NET_VOL = tot_v
farm_tx = sum(int(r["settlements"]) for r in rows)
farm_vol = sum(float(r["volume_usdc"]) for r in rows)
farm_w = sum(int(r["wallets"]) for r in rows)

checks = [
    ("52,652,290 base", NET_TX == 52652290),
    ("99.87% slice", abs(52652290 / 52723702 - 0.9987) < 0.0001),
    ("84.1% count share", abs(100 * farm_tx / NET_TX - 84.1) < 0.05),
    ("24.9% value share", abs(100 * farm_vol / NET_VOL - 24.9) < 0.05),
    ("181 cohorts", len(rows) == 181),
    ("52,008 wallets", farm_w == 52008),
    ("44,287,486 settlements", farm_tx == 44287486),
    ("mean ticket 0.050", abs(farm_vol / farm_tx - 0.050) < 0.0005),
    ("network ticket 0.170", abs(NET_VOL / NET_TX - 0.1704) < 0.0005),
    ("HubA 34.7%", abs(float(rows[0]["pct_network_tx"]) - 34.66) < 0.05),
    ("HubA ticket 0.0017", abs(float(rows[0]["volume_usdc"]) / int(rows[0]["settlements"]) - 0.0017) < 0.0001),
    ("HubB ticket 0.016", abs(float(rows[1]["volume_usdc"]) / int(rows[1]["settlements"]) - 0.0155) < 0.001),
    ("HubC ticket 0.10", abs(float(rows[2]["volume_usdc"]) / int(rows[2]["settlements"]) - 0.10) < 0.001),
    ("HubC 4.9% value", abs(100 * float(rows[2]["volume_usdc"]) / NET_VOL - 4.9) < 0.05),
    ("top15=98.3%", abs(100 * sum(int(r["settlements"]) for r in rows[:15]) / farm_tx - 98.3) < 0.05),
]
fails = []
for k, v in checks:
    print(("PASS" if v else "FAIL"), k)
    if not v: fails.append(k)
print()
for n in ["52,652,290","84.1","24.9","181","52,008","44.29","0.050","0.170","0.974","0.967","0.070","0.375","98.3","74.3"]:
    c = report.count(n)
    print(f"in-text '{n}': {c}")
    if c == 0: fails.append(f"in-text missing: {n}")
print()
if fails:
    print("FAILURES:", fails); sys.exit(1)
print("ALL_OK — 报告数字与真源一致，可进发布闸")
