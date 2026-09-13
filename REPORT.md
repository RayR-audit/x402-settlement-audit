# Settlement Authenticity in the x402 Network: An Upper-Bound Analysis of Coordinated Payer Behavior

**Working draft v1 · 2026-09-13 · Ray (RayR-audit), independent researcher**
> Draft status: working draft. Publication: standalone repo (CC0 report + CC0 SQL), early October.
> Anonymity discipline: no real addresses, no facilitator names anywhere; hubs = Hub A/B/C; figures in data/figs/.

---

## Abstract

We audit settlement authenticity on the x402 agent-payment protocol using only public data. Our dataset is the Base-chain settlement slice of a public BigQuery listing — 52,652,290 settlements routed through 105 known facilitator addresses — and we state its limits plainly: Solana is not covered, and the upstream dataset has not been updated since April 2026. Using behavioral fingerprinting and union-find clustering, we identify 181 coordinated payer cohorts comprising 52,008 wallets — about two-thirds of all paying addresses — that account for **at most 84.1% of settlement count but only 24.9% of settled value** (mean ticket $0.050 vs $0.170 slice-wide). This is an upper bound: fingerprinting captures behavioral similarity, not intent. An independent July-2026 census has separately reported that 84.98% of Base settlement count is operator-internal; our result converges with that finding from a different method. To probe that bound, we compare diurnal activity rhythms across matched volume strata: cohort wallets are systematically flatter around the clock than the rest of the network (median 24-hour Fourier amplitude 0.070 vs 0.375 in the 10³ stratum). Notably, even high-volume payers outside cohorts are largely machine-like, suggesting that genuine, consumption-driven demand is thinner than headline settlement counts imply. We cannot distinguish internal routers, batch escrows, or load tests from public data, and we do not assert intent or name addresses. All SQL is published under CC0; every figure reproduces on BigQuery's free tier.

### 中文对照（摘要）

我们仅用公开数据审计 x402 代理支付协议的结算真实性。数据集是公共 BigQuery 数据集的 Base 链结算切片——经 105 个已知 facilitator 地址路由的 52,652,290 笔结算——并明确陈述其局限：未覆盖 Solana，上游数据自 2026 年 4 月起停止更新。用行为指纹法与并查集聚类，我们识别出 181 个协调付款方群，含 52,008 个钱包——约占全部付款地址的三分之二——它们贡献**至多 84.1% 的结算笔数、但仅 24.9% 的结算金额**。这是上界：指纹捕捉的是行为相似性，不是意图。为收紧上界，我们在匹配的量级分层内对比昼夜活动节律：群内钱包比网络其余部分全天显著更均匀（10³ 分层的 24 小时傅里叶振幅中位数 0.070 vs 0.375）。值得注意的是，即使是群外的高量级付款方也大多是机器形态——这意味着真实的、消费驱动的需求比结算笔数所暗示的更稀薄。我们无法从公开数据区分内部路由、批量托管或负载测试，不断言意图、不点名地址。全部 SQL 以 CC0 发布；每张图都能在 BigQuery 免费层复现。

---

## 1. Motivation

x402 is an HTTP-native payment protocol that lets autonomous agents pay for resources with stablecoin micro-settlements. Its adoption story is increasingly told through one number: how many settlements the network processes. On a permissionless chain, however, settlement count is the cheapest metric to manufacture — a single operator with modest capital can generate millions of protocol-valid settlements that represent no economic demand.

Independent verification is warranted, and the barrier to providing it is low: the raw data is public. Nobody funds this work, and nothing is for sale here. What follows is an attempt to measure how much of the network's settlement activity behaves like coordinated infrastructure rather than like consumption — stated, throughout, as an upper bound rather than a verdict.

### 中文对照（§1）

x402 是一个 HTTP 原生支付协议，让自主代理用稳定币微结算为资源付费。它的采用故事越来越依赖一个数字：网络处理了多少笔结算。但在无许可的链上，结算笔数是最容易被制造的指标——一个资本有限的运营者就能生成数百万笔协议完全有效的、却不代表任何经济需求的结算。

独立核验是必要的，而提供它的门槛很低：原始数据是公开的。没有任何人资助这项工作，这里也没有任何东西出售。以下是对网络结算活动中"有多少表现得像协调的基础设施、而不是像消费"的一次测量——全程表述为上界，而非判决。

---

## 2. Data and Scope

**Source.** The public Analytics Hub listing of raw x402 settlement events on Base (project `web3-publicgoods`, table `tektonic_x402.base_raw`; query shapes adapted from the CC0-licensed ConejoCapital/Tektonicx402 repository). We work from the raw event table (12 columns, ~170M rows across all programs) filtered to x402 settlement activity.

**Facilitator slice.** Settlements are attributed to a hand-maintained registry of 105 facilitator addresses (the services that sponsor gas and route payments). Filtering the raw table to this registry retains **52,652,290 of 52,723,702 rows (99.86%)**. The registry was assembled from public announcements and on-chain labeling; it may be incomplete in both directions, and we treat it as a scope condition, not a ground truth.

**Window.** The events in the slice span **2025-12-05 to 2026-04-14 (UTC, 131 days)** — the period covered by the upstream listing, not a window we chose. Data as of 2026-04-14; this report is published 2026-10-05, so every figure below describes the frozen window, not the live network.

**What this is not.** This is **not** a complete picture of the x402 network: (i) Solana-side settlement is not covered by the listing; (ii) the upstream dataset has not been updated since **April 2026** — a five-month freeze at time of writing; (iii) facilitator-side internal traffic (routing, retries, batching) is indistinguishable from end-customer traffic in the raw events. Every headline number below should be read as "share of the audited slice", never "share of x402".

**Coverage.** The slice contains 38.5% of the settlement count and ~20% of the settled value reported by the prior census of Base (Ling et al., 136.7M settlements / $44.1M). Within our upstream listing the registry filter retains 99.86% of rows, so the gap is upstream coverage — a different extraction — not our selection. A reader comparing the two papers cannot always tell whether a difference is coverage or selection; we flag it wherever it matters.

**Cost.** The full-history scan used for this audit is ~35 GB processed — about 3.4% of BigQuery's monthly free tier. **$0.00.** All figures reproduce on a free account.

### 中文对照（§2）

**来源。** 公共 Analytics Hub 数据集，含 Base 上原始 x402 结算事件（项目 `web3-publicgoods`，表 `tektonic_x402.base_raw`；查询形态改编自 CC0 授权的 ConejoCapital/Tektonicx402 仓库）。我们从原始事件表出发（12 列、全项目约 1.7 亿行），过滤出 x402 结算活动。

**Facilitator 切片。** 结算归属于一份手工维护的 105 个 facilitator 地址注册表（垫 gas 并路由支付的服务机构）。过滤后保留 **52,723,702 行中的 52,652,290 行（99.86%）**。注册表来自公开公告与链上标注，可能双向不全；我们把它当作范围条件，而非真值。

**窗口。** 切片内事件覆盖 **2025-12-05 至 2026-04-14（UTC，131 天）**——这是上游数据集覆盖的时段，不是我们选择的窗口。数据截至 2026-04-14；本报告 2026-10-05 发布，因此下文所有数字描述的是冻结窗口，不是活体网络。

**这不是什么。** 这**不是** x402 网络的完整图景：(i) 数据集不含 Solana 侧结算；(ii) 上游数据自 **2026 年 4 月**起停止更新——写作时已冻结五个月；(iii) 原始事件中无法区分 facilitator 侧内部流量（路由、重试、打包）与终端客户流量。下文所有头条数字都应读作"被审计切片中的占比"，而不是"x402 的占比"。

**覆盖度。** 本切片含先行 Base 普查（Ling 等，1.367 亿笔 / $44.1M）结算笔数的 38.5%、金额的约 20%。在我们自己的上游数据集内，注册表过滤保留了 99.86% 的行——差距来自上游覆盖（不同的提取），不是我们的筛选。读者比较两篇论文时未必能分辨差异是覆盖还是筛选；我们在所有关键处明确标注。

**成本。** 本次审计的全历史扫描约处理 35 GB——约为 BigQuery 每月免费配额的 3.4%。**$0.00。** 所有图表都能在免费账号上复现。

---

## 3. Methodology

### 3.1 Concentration

We compute Gini coefficients over payer-level totals across the slice: **0.974 for settled value and 0.967 for settlement count** (Fig. 1). Both are near the theoretical maximum; note they are different measurements and we report both to avoid label drift. Concentration alone proves nothing — the interesting question is whether the concentrated mass behaves like one operator or like many independent customers.

### 3.2 Behavioral fingerprint clustering

For every (payer, facilitator) edge we build a fingerprint: `(facilitator, first-activity 10-day bucket, last-activity 10-day bucket, log₁₀ transaction-count bucket, log₁₀ mean-ticket bucket)`. Wallets sharing an identical fingerprint at the same facilitator are merged with union-find (merge threshold ≥3 wallets per fingerprint group); groups with ≥50 wallets are reported as **cohorts**.

Result: **181 cohorts covering 52,008 wallets** — roughly two-thirds of all paying addresses in the slice — accounting for **84.1% of settlement count and 24.9% of settled value** (44.29M settlements; mean ticket $0.050 vs the network's $0.170, i.e. ~0.3×). The largest cohort contains ≈1.3k wallets with 85.6% of its settlements on a single dominant facilitator ("Hub A"), representing ≈35% of all settlements in the slice, with a mean ticket of $0.0017 — roughly 1/100 of the slice average.

Fingerprints capture *behavioral similarity*. Real users can collide on a fingerprint — especially in the "same window, small tickets" stratum — so cohort membership is an **upper bound** on coordination, by construction.

### 3.3 Rhythm control (tightening the bound)

To test whether cohort wallets look like coordinated humans or like scripts, we compute each payer's **diurnal amplitude**: the first Fourier harmonic of its 24-hour settlement histogram, normalized by its mean — following the payer-clock method of Ling et al. (arXiv:2607.12575, §5.2). Amplitude 0 means perfectly flat activity around the clock; ~0.79 was reported for advertised-service payers in that census. Amplitude is a *feature*, not a verdict — a scheduled agent is also regular — so we never label wallets with it directly. Instead we compare distributions within matched volume strata (payers with ≥100 settlements). The comparison arm is the part of the network present in ≥3-wallet fingerprint groups but outside ≥50-wallet cohorts; payers with no fingerprint group at all (2,093 of 11,408 payers with ≥100 settlements, 18.3%) are excluded — a conservative exclusion, since ungrouped singletons are the least coordination-like payers:

| Volume stratum | Cohort median amplitude | Cohort flat share (amp < 0.5) | Rest median | Rest flat share |
|---|---|---|---|---|
| 10² | 0.455 | 54.2% (n=2,293) | 0.702 | 40.2% (n=2,831) |
| 10³ | **0.070** | **96.2%** (n=2,201) | 0.375 | 69.0% (n=523) |
| 10⁴ | 0.037 | 99.9% (n=1,452) | 0.056 | 93.3% (n=15) |

Within the cleanest stratum (10³, n=2,724), cohort wallets are overwhelmingly flat-around-the-clock while a meaningful share of the rest retains day–night structure (Fig. 3). The 10⁴ stratum carries a different message: *both* groups are machine-like — at high volume, essentially the whole audited ecosystem is automated.

A methodological note we keep on purpose: our first typing attempt used fixed amplitude thresholds and produced a suspiciously clean "99.5% bot-like" result. A control run showed the thresholds were artifacts (low-volume payers mechanically produce amplitude ≈ 2). We discarded that version and report only the stratified comparison. We think showing this is more useful than hiding it.

### 3.4 Robustness

The cohort share of settlement count is stable across a 3×3 grid of parameters (fingerprint merge threshold ∈ {2,3,5} × cohort-size cutoff ∈ {30,50,100}): **84.1–85.1%** at cutoffs 30/50, and **74.3–74.4%** even at a cutoff of 100 wallets. The merge threshold has negligible effect (Table B1). The headline finding does not depend on parameter tuning.

### 中文对照（§3）

**3.1 集中度。** 对切片内付款方级总额计算基尼系数：**金额 0.974、笔数 0.967**（图 1）。两者都接近理论最大值；注意这是两个不同的测量，为防标签漂移我们同时报告。集中度本身证明不了任何事——有趣的问题在于集中的那部分表现得像一个运营者，还是像许多独立客户。

**3.2 行为指纹聚类。** 对每条 (付款方， facilitator) 边构建指纹：`(facilitator, 首活动 10 日桶， 末活动 10 日桶, log₁₀ 笔数桶, log₁₀ 票均桶)`。在同一 facilitator 上指纹完全相同的钱包用并查集合并（指纹组 ≥3 钱包才合并）；≥50 钱包的组记为**群（cohort）**。

结果：**181 个群、覆盖 52,008 个钱包**——约占切片内全部付款地址的三分之二——占**结算笔数的 84.1%、结算金额的 24.9%**（4,429 万笔；票均 $0.050 vs 全网 $0.170，约 0.3 倍）。最大群含约 1.3k 个钱包，其 85.6% 的结算落在单一主导 facilitator（"Hub A"）上，占切片全部结算笔数约 35%，票均 $0.0017——约为切片均值的 1/100。

指纹捕捉的是*行为相似性*。真人可能撞指纹——尤其在"同窗口、小额"分层——所以按构造，群成员身份是协调行为的**上界**。

**3.3 节律对照（收紧上界）。** 为检验群内钱包像协调的真人还是像脚本，我们计算每个付款方的**昼夜振幅**：其 24 小时结算直方图的首阶傅里叶谐波、按均值归一——沿用 Ling 等（arXiv:2607.12575, §5.2）的付款方时钟方法。振幅 0 = 全天完全均匀；该普查中广告服务类付款方的参照值约 0.79。振幅是*特征*而非判决——定时运行的 agent 同样规律——所以我们从不用它直接给钱包打标，而是在匹配的量级分层内比较分布（≥100 笔的付款方）。对照臂是处于 ≥3 钱包指纹组但不在 ≥50 钱包群内的那部分网络；完全没有指纹组的付款方（≥100 笔的 11,408 个付款方中的 2,093 个，18.3%）被排除——这是保守排除，因为无组单例是最不像协调行为的付款方：

| 量级分层 | 群内中位振幅 | 群内平坦占比 (amp<0.5) | 群外中位 | 群外平坦占比 |
|---|---|---|---|---|
| 10² | 0.455 | 54.2% (n=2,293) | 0.702 | 40.2% (n=2,831) |
| 10³ | **0.070** | **96.2%** (n=2,201) | 0.375 | 69.0% (n=523) |
| 10⁴ | 0.037 | 99.9% (n=1,452) | 0.056 | 93.3% (n=15) |

在最干净的分层（10³，n=2,724），群内钱包绝大多数全天均匀，而群外有相当比例保留昼夜结构（图 3）。10⁴ 分层传递的是另一个信息：*两组*都是机器形态——在高量级上，被审计生态几乎整体是自动化的。

一条有意保留的方法学备注：我们的第一版分型用固定振幅阈值，得出干净得可疑的"99.5% 机器"结果。对照实验显示该阈值是伪影（低量付款方机械地产生振幅 ≈2）。我们废弃了那一版，只报告分层比较。我们认为展示这一点比隐藏更有用。

**3.4 稳健性。** 群占结算笔数比例在 3×3 参数网格（指纹合并阈值 {2,3,5} × 群大小门槛 {30,50,100}）下稳定：门槛 30/50 时 **84.1–85.1%**，即使门槛提高到 100 钱包仍有 **74.3–74.4%**。合并阈值的影响可忽略（表 B1）。头条结论不依赖参数调节。

### 3.5 Relation to prior work

Our audit is independent of, and methodologically complementary to, Ling et al. (arXiv:2607.12575), the first population-scale measurement of x402 on Base. They classify settlements through *funding provenance* — tracing seed funders and wallet-linkage to prove manufacture or closed loops (21.2% fictitious, 63.8% cluster-internal). We arrive from an orthogonal direction: *behavioral* fingerprinting plus rhythm analysis, using no funding graph at all. That two independent methods land on nearly the same headline — they find 84.98% of settlement count is operator-internal; we find at most 84.1% lies in coordinated behavioral cohorts — corroborates the finding at the level of method: both analyses, however, rest on the same underlying evidence (Base on-chain events; our slice is 38.5% of their census by count), so this is convergence of methods, not fully independent replication. We did not use their data or code; all numbers in this report are computed from our own pipeline alone. The rhythm anchors also calibrate against their published values: our cohort median amplitudes (0.070 in the 10³ stratum, 0.037 in 10⁴) sit at or below their operator-cluster baseline (0.12) and their provably-manufactured payer baseline (0.08).

### 中文对照（3.5 与先行工作的关系）

我们的审计独立于——且在方法上与——Ling 等（arXiv:2607.12575，首个 Base 上 x402 全体规模测量）互补。他们通过*资金来源*分类结算——追踪种子出资者和钱包关联来证明制造或闭环（21.2% 虚构、63.8% 群内）。我们从正交方向到达：*行为*指纹加节律分析，完全不使用资金图。两个独立方法落在几乎同一个头条上——他们发现 84.98% 的结算笔数是运营者内部；我们发现至多 84.1% 落在协调行为群内——这在方法层面印证了发现：但两项分析建立在同一底层证据上（Base 链上事件；我们的切片按笔数为其普查的 38.5%），所以这是方法收敛，不是完全独立的复现。我们没有使用他们的数据或代码；本报告所有数字都只来自我们自己的管线。节律锚点也与他们发表的数值互相校准：我们群内的中位振幅（10³ 层 0.070、10⁴ 层 0.037）落在其运营者群基线（0.12）和可证制造付款方基线（0.08）以下或持平。

---

## 4. Results

**Concentration.** Value and count are both extreme-concentrated (Gini ≈ 0.97, Fig. 1), but the head differs: the top 0.1% of payers hold 26.6% of settlement count yet 47.2% of value, and the top 1% hold 62.6% vs 76.2% — value is far more head-concentrated than count.

**Cohort structure.** The 15 largest cohorts alone account for 98.3% of all cohort settlements; they are not one phenomenon but several recognizable shapes (Fig. 2):

- **One-dominant-facilitator cohorts.** Several of the largest cohorts concentrate the overwhelming majority of their settlements on one facilitator each (Hub A: 86%; Hub B and Hub C similar), with hundreds to thousands of wallets sharing one activity window — the same behavioral shape at different price points (mean tickets $0.0017, $0.016, $0.10).
- **One-day bursts across a facilitator tail.** A ~100-wallet cohort carried ~17M settlements in a single one-day activity window in early 2026; it touches many facilitators, but 99.98% of its settlement mass sits on its dominant one — a burst through one venue with marginal touchpoints elsewhere, not a routing layer fanning out across services.
- **Value-dense cohorts.** A cohort of several dozen wallets settled roughly 5% of all value in the slice (~$400k) on a single facilitator over a multi-week window around year-end 2025 — from about 0.1% of paying wallets, with a mean ticket about 0.6× the network average: value concentrated, not value-per-ticket.

**Rhythm.** Within matched volume strata, cohort wallets are systematically flatter than the rest of the network (Fig. 3). The 10³ stratum is the clean separation: 96.2% of cohort wallets never show a day–night cycle, versus 69.0% of comparable non-cohort wallets.

**The uncomfortable finding.** The 10⁴ stratum shows flat rhythms on *both* sides. High-volume payers across the audited slice — inside and outside cohorts — are overwhelmingly automated (n=1,452 cohort vs 15 non-cohort in that stratum). This is not an indictment of x402: machine-to-machine settlement is the protocol's stated purpose. But it does mean the audited slice carries little evidence of genuine, consumption-driven human demand, and headline settlement counts should not be read as if it did.

### 中文对照（§4）

**集中度。** 金额与笔数都是极端集中（基尼 ≈0.97，图 1），但头部不同：前 0.1% 的付款方持有 26.6% 的结算笔数却持有 47.2% 的金额；前 1% 持有 62.6% vs 76.2%——金额比笔数更头部集中。

**群结构。** 仅 15 个最大的群就占全部群结算量的 98.3%；它们不是一种现象，而是几种可辨认的形态（图 2）：

- **单主导 facilitator 群。** 最大的几个群各自把绝大多数结算集中在单一 facilitator 上（Hub A：86%；Hub B、Hub C 类似），数百到数千钱包共享一个活动窗口——同一行为形态，不同价位（票均 $0.0017、$0.016、$0.10）。
- **跨 facilitator 尾部的单日爆发。** 一个约 100 钱包的群在 2026 年初的单个一天活动窗口内完成约 1,700 万笔结算；它触及多个 facilitator，但 99.98% 的结算量集中在主导的那一个——是穿过单一场所的爆发、别处只有边缘触点，不是跨服务扇出的路由层。
- **金额密集群。** 一个数十钱包的群在 2025 年末前后数周窗口内、于单一 facilitator 上结算了约切片全部金额的 5%（约 $400k）——以约 0.1% 的付款钱包数，票均约为全网均值的 0.6 倍：这是金额集中，不是单笔高额。

**节律。** 在匹配的量级分层内，群内钱包比网络其余部分系统性地更平坦（图 3）。10³ 分层是最干净的分离：96.2% 的群内钱包从未显示昼夜周期，对照群外为 69.0%。

**令人不适的发现。** 10⁴ 分层显示*双方*都是平坦节律。被审计切片内的高量级付款方——群内群外——绝大多数是自动化的（该分层 n=1,452 群内 vs 15 群外）。这不是对 x402 的指控：机器对机器结算正是协议的既定目的。但这确实意味着，被审计切片几乎不携带真实的、消费驱动的人类需求证据，头条结算笔数不应被读作相反。

---

## 5. What We Cannot Know

Three mechanisms produce exactly the shapes we observe, and **public data cannot distinguish them**:

1. **Internal routing.** A facilitator's own settlement fan-out (retries, rebalancing, batch confirmation) looks identical to a farm.
2. **Batch escrow.** The protocol's documented batch-settlement patterns aggregate many underlying payments into few on-chain events — or the reverse — with shapes that overlap ours.
3. **Load testing.** Infrastructure testing by the foundation or facilitators is protocol-valid, high-volume, and rhythmless.

We therefore **do not assert intent, and we do not name addresses**. Cohort shares are an upper bound on coordination, not an estimate of fraud. Honestly, this line matters more to us than any headline number: an audit that cannot separate mechanism from misconduct should say so, loudly, and invite the people who can.

This is also why we have requested working-group access (issue #3467): the fastest way to tighten the bound further is to put our aggregates in front of the teams who know which share of this traffic is their own infrastructure — while there is still time to fix our method.

### 中文对照（§5）

三种机制都会产生我们观察到的形态，而**公开数据无法区分它们**：

1. **内部路由。** facilitator 自身的结算扇出（重试、再平衡、批量确认）与农场看起来完全一样。
2. **批量托管。** 协议文档化的批量结算模式把许多底层支付聚合为少数链上事件——或相反——形态与我们的重叠。
3. **负载测试。** 基金会或 facilitator 的基础设施测试协议有效、高量、无节律。

因此我们**不断言意图，也不点名地址**。群占比是协调行为的上界，不是欺诈估计。老实说，这条线对我们比任何头条数字都更重要：一个无法区分机制与不当行为的审计，应该大声说明这一点，并邀请有能力区分的人。

这也是我们申请工作组访问的原因（issue #3467）：进一步收紧上界最快的路径，是把我们的聚合结果放到知道这些流量里多少是自己基础设施的团队面前——趁还来得及修正我们的方法。

---

## 6. Implications

**For the x402 Foundation.** Adoption metrics cited publicly should distinguish *settlement count* from *demand signal*. Two cheap interventions would help everyone: (i) facilitator-side batch/routing disclosure flags, so public data can separate infrastructure from customer traffic; (ii) publishing network-level diurnal rhythm summaries, so third parties can normalize for automation.

**For buyers, researchers, and journalists.** Any claim of the form "x402 processes N settlements" should carry a discount when cited as demand. Our stratified rhythm tables provide a reproducible normalization reference.

**For the ecosystem.** The metric worth watching is not settlement count but **value settled by non-cohort, rhythm-bearing payers** — the closest public-data proxy for genuine consumption. By our measurement, that quantity is small, and its growth is the real adoption curve.

### 中文对照（§6）

**对基金会。** 公开引用的采用指标应区分*结算笔数*与*需求信号*。两个低成本干预对所有人都有帮助：(i) facilitator 侧的批次/路由披露标记，让公开数据能区分基础设施与客户流量；(ii) 发布网络级昼夜节律摘要，让第三方能为自动化归一化。

**对买方、研究者与记者。** 任何形如"x402 处理了 N 笔结算"的主张，在作为需求引用时都应打折扣。我们的分层节律表提供了可复现的归一化参照。

**对生态。** 值得关注的指标不是结算笔数，而是**由无群、有节律的付款方结算的金额**——这是公开数据下最接近真实消费的代理。按我们的测量，这个量很小，而它的增长才是真正的采用曲线。

---

## 7. Limitations

1. **Single chain, single slice.** Base only; no Solana coverage. Findings are shares of the audited slice.
2. **Registry completeness.** The 105-facilitator registry is best-effort; unknown facilitators' traffic is excluded from the denominator.
3. **Fingerprinting is an upper bound.** Human–human collisions are possible; we quantify the bound but cannot eliminate it. The rhythm control narrows the plausible share of genuine users inside cohorts, but no point estimate of "real users" is claimed.
4. **Amplitude is a feature, not a verdict.** Scheduled legitimate agents are rhythmless too. We use amplitude only comparatively.
5. **Upstream freeze.** The dataset stopped updating in April 2026; the audit reflects a frozen window, not the live network.
6. **No intent claims.** We observe shapes; we do not know minds.
7. **Shape-level re-identifiability.** We describe shapes, not identities — but a shape plus a share can be unique: a cohort carrying a third of all settlements on one dominant facilitator is recognizable to anyone with the same public table, addresses or not. Anonymization limits what we publish, not what a determined reader can infer.
8. **Coverage/selection gap.** Our slice is 38.5% of the prior census's settlement count and ~20% of its value; the missing mass reflects upstream coverage, not our selection. The 84.1% vs 84.98% agreement should be read with that gap in the same sentence.
9. **Phase snapshot.** The data freeze ends 2026-04-14, and operator campaigns switch on and off — cohort shares are one phase of a rotating system, not a steady state. Conclusions about the live network should be treated as hypotheses for the next measurement window.

### 中文对照（§7）

1. **单链单切片。** 仅 Base；无 Solana 覆盖。所有发现都是被审计切片内的占比。
2. **注册表完整性。** 105 个 facilitator 的注册表是尽力而为；未知 facilitator 的流量被排除在分母之外。
3. **指纹是上界。** 真人之间可能撞指纹；我们量化了上界但无法消除。节律对照收窄了群内真实用户的合理占比区间，但不声称"真实用户"的任何点估计。
4. **振幅是特征不是判决。** 定时运行的合法 agent 同样无节律。振幅只作比较用途。
5. **上游冻结。** 数据集 2026 年 4 月停止更新；审计反映的是冻结窗口，不是活体网络。
6. **无意图主张。** 我们观察形态；我们不知道想法。
7. **形状级可再识别。** 我们描述形状而非身份——但形状加占比可能唯一：一个在单一主导 facilitator 上承载全网三分之一结算的群，任何拿同一公开表的人都能认出，无论是否给出地址。匿名化限制的是我们发布什么，不是读者能推断什么。
8. **覆盖/筛选差。** 本切片为先行普查结算笔数的 38.5%、金额的约 20%；缺失部分来自上游覆盖差异，不是我们的筛选。84.1% vs 84.98% 的收敛应当带着这个差距一起读。
9. **阶段快照。** 数据冻结止于 2026-04-14，且运营者活动有开关起伏——群占比是旋转系统的一个相位，不是稳态。对活体网络的结论应视为下一个测量窗口的假设。

---

## Appendix A. Reproducibility

All SQL (11 scripts, CC0) and this report (CC0) live at `github.com/RayR-audit/<repo>` *(repo link finalized at publication)*. Pipeline: raw event table → facilitator slice → edge-list aggregation → Gini/concentration → fingerprint clustering → rhythm features → stratified comparison. Every step runs on BigQuery free tier; local clustering steps are pure Python with no dependencies beyond the standard library and run in seconds on the aggregated CSVs.

**Artifact manifest.** To honor the non-naming commitment, the facilitator registry — 105 addresses assembled by hand from public announcements and on-chain labeling — is **withheld**:

- **Published:** the 11 SQL scripts in redacted form (the inline registry is replaced by a placeholder loader that reads the registry from a user-supplied CSV), the anonymized cohort table (wallet counts, settlements, value, share, anonymized hub labels — no addresses), the clustering/rhythm/robustness scripts, and all figures.
- **Withheld:** the facilitator registry (addresses and names), the join table between anonymized hub labels and real addresses, and any derived file containing raw payer or facilitator addresses. Reproduction therefore requires readers to assemble their own registry; we document its size (105), the assembly criteria, and the date it was frozen.

### 中文对照（附录 A·工件清单）

为兑现不点名承诺，facilitator 注册表——105 个地址、由公开公告与链上标注手工整理——**不予发布**：

- **发布**：11 个 SQL 脚本的脱敏版（内联注册表替换为占位加载器，从用户自备的 CSV 读入注册表）、匿名化后的群表（钱包数、结算、金额、占比、匿名 hub 标签——无任何地址）、聚类/节律/稳健性脚本、全部图表。
- **保留**：facilitator 注册表（地址与名称）、匿名 hub 标签与真实地址的对照表、任何含原始付款方或 facilitator 地址的衍生文件。复现需要读者自行整理注册表；我们记录其规模（105）、整理标准与冻结日期。

## Appendix B. Sensitivity

Table B1 — cohort share of settlement count under parameter grid:

| merge threshold \ cohort cutoff | ≥30 wallets | ≥50 wallets | ≥100 wallets |
|---|---|---|---|
| ≥2 | 85.1% | 84.2% | 74.4% |
| ≥3 | 85.0% | **84.1%** | 74.3% |
| ≥5 | 85.0% | 84.1% | 74.3% |

(cohorts: 287 / 181 / ~102; wallets: 55.9–56.4k / 51.7–52.2k / 46.0–46.4k)

### 中文对照（附录 B）

表 B1——参数网格下的群占结算笔数比例（如上表；群数 287 / 181 / 约 102；钱包数 5.59–5.64 万 / 5.17–5.22 万 / 4.60–4.64 万）。

## Appendix C. Figures

- Fig. 1 Lorenz curves, value and count (Gini 0.974 / 0.967) — `figs/fig1_lorenz.png`
- Fig. 2 Largest 15 cohorts by settlement share, hubs anonymized — `figs/fig2_cohorts.png`
- Fig. 3 Diurnal amplitude by volume stratum, cohort vs rest — `figs/fig3_rhythm.png`

### 中文对照（附录 C）
- 图 1 洛伦兹曲线（金额与笔数，基尼 0.974 / 0.967）
- 图 2 最大的 15 个群按结算占比，hub 已匿名
- 图 3 按量级分层的昼夜振幅，群内 vs 群外

---

---

