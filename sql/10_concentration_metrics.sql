-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 10 · concentration metrics (Gini / Nakamoto / HHI)
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 10_concentration_metrics.sql
--   2. Keep the block_timestamp predicate. It is the partition filter that keeps
--      this query inside the BigQuery free tier (1 TiB/month, per billing account).
--   3. Sandbox-safe on purpose: pure SELECT/CTE only. No CREATE TEMP TABLE, no
--      INSERT/UPDATE/DELETE, no DDL -> runs in a no-credit-card BigQuery sandbox.
--      (Sandbox blocks DML; the upstream Tektonic SQL uses CREATE TEMP TABLE +
--      INSERT and therefore does NOT run in the sandbox. This file does.)
--   4. If you subscribed to the Analytics Hub listing, replace `web3-publicgoods.tektonic_x402.base_raw` with
--      `YOUR_PROJECT.tektonic_x402.base_raw`. Column names are unchanged.
--
-- FREE-TIER NOTE: a full-history scan of base_raw (all 12 columns, ~170M rows)
-- is ~35 GB = ~3.4% of the 1 TiB monthly free allowance. Cost $0.00.
-- =============================================================================

DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 280 DAY);
DECLARE end_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- The paper's RQ1 headline: payer, recipient and value Gini all above 0.98,
-- facilitator Nakamoto 1 on both chains. Exact Gini on the census
-- (G = (2*SUM(i*x_i))/(n*SUM(x_i)) - (n+1)/n over x sorted ascending).
-- These three numbers are the cheapest possible authenticity smoke test: if a
-- window reports a low facilitator Nakamoto or a Gini near 0, the pipeline is
-- broken, not the ecosystem.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient,
           LOWER(t.facilitator_address) AS facilitator_address, t.amount_usdc
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  payer_w AS (SELECT payer, COUNT(*) AS w, SUM(amount_usdc) AS v FROM settlements GROUP BY payer),
  recip_w AS (SELECT recipient, COUNT(*) AS w FROM settlements GROUP BY recipient),
  fac_w   AS (SELECT facilitator_address, COUNT(*) AS w FROM settlements GROUP BY facilitator_address),
  ranked_p AS (SELECT w, ROW_NUMBER() OVER (ORDER BY w) AS i, COUNT(*) OVER () AS n FROM payer_w),
  ranked_r AS (SELECT w, ROW_NUMBER() OVER (ORDER BY w) AS i, COUNT(*) OVER () AS n FROM recip_w),
  ranked_v AS (SELECT v, ROW_NUMBER() OVER (ORDER BY v) AS i, COUNT(*) OVER () AS n FROM payer_w),
  fac_ranked AS (   -- window functions are illegal in WHERE, so the running share is
                    -- materialised here (defect found and fixed 2026-09-12)
    SELECT w, ROW_NUMBER() OVER (ORDER BY w DESC) AS rk,
           SUM(w) OVER () AS tot,
           SUM(w) OVER (ORDER BY w DESC ROWS UNBOUNDED PRECEDING) AS cum
    FROM fac_w)

SELECT
  'payer_count_gini'  AS metric,
  ROUND(2 * SUM(i * w) / (MAX(n) * SUM(w)) - (MAX(n) + 1) / MAX(n), 6) AS value
FROM ranked_p
UNION ALL
SELECT 'recipient_count_gini',
  ROUND(2 * SUM(i * w) / (MAX(n) * SUM(w)) - (MAX(n) + 1) / MAX(n), 6) FROM ranked_r
UNION ALL
SELECT 'payer_value_gini',
  ROUND(2 * SUM(i * v) / (MAX(n) * SUM(v)) - (MAX(n) + 1) / MAX(n), 6) FROM ranked_v
UNION ALL
SELECT 'facilitator_nakamoto',
  MIN(rk) FROM fac_ranked WHERE cum > tot / 2
UNION ALL
SELECT 'facilitator_hhi',
  ROUND(SUM(POW(100 * w / tot, 2)), 2) FROM fac_ranked;
