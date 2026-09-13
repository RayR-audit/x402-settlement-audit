# x402 Settlement Authenticity Audit

Independent, upper-bound analysis of settlement authenticity in the x402 agent-payment protocol on Base.

**Headline.** Behavioral fingerprint clustering over 52,652,290 settlements (Base, Dec 2025 – Apr 2026) identifies 181 coordinated payer cohorts — 52,008 wallets, about two-thirds of all paying addresses — accounting for **at most 84.1% of settlement count but only 24.9% of settled value**. Diurnal-rhythm controls show cohort wallets are systematically machine-shaped; notably, even high-volume payers *outside* cohorts are largely automated. An independent July-2026 census (arXiv:2607.12575) separately reports 84.98% of Base settlement count as operator-internal; our result converges with it from an orthogonal method.

**We do not name addresses and we do not assert intent.** Cohort membership is an upper bound on coordination, not an estimate of fraud. See `REPORT.md` §5 for the three mechanisms public data cannot distinguish.

## Repository layout

| Path | What it is |
|---|---|
| `REPORT.md` | Full report (CC0), with per-section Chinese translations |
| `sql/` | 11 BigQuery SQL scripts, **redacted**: the inline facilitator registry is replaced by a placeholder loader |
| `data_cohorts_anonymized.csv` | Anonymized cohort table (no addresses; hubs labeled A/B/C/…) |
| `SENSITIVITY_V2.csv`, `FARM_TYPING_V2_1*.csv` | Robustness grid and rhythm-stratified typing results |
| `cluster_v2*.py`, `verify_report_numbers.py`, `make_report_figs.py` | Local clustering, typing, verification, figure scripts (stdlib only) |
| `figs/` | Report figures (300 dpi) |

## What is withheld, and why

The facilitator registry — 105 addresses assembled by hand from public announcements and on-chain labeling — is **not published**. Publishing it would name individual services, which our non-naming commitment forbids. Also withheld: the join table between anonymized hub labels and real addresses, and any file containing raw payer or facilitator addresses.

**Reproduction therefore requires your own registry.** We document its size (105), assembly criteria (public announcements + on-chain labeling of gas-sponsoring relayers), and freeze date. Load it into the placeholder in each SQL script.

## Reproduction

1. BigQuery (free tier suffices — full scan ≈ 35 GB processed): run `sql/01…10` in order, substituting your registry and project id.
2. Export the resulting CSVs, then run the local scripts in numeric order (`cluster_v2.py` → typing → `verify_report_numbers.py` regenerates every headline number from the CSVs).
3. Data as of 2026-04-14 (upstream freeze). Figures describe that frozen window, not the live network.

## License

CC0. No funding, nothing for sale.
