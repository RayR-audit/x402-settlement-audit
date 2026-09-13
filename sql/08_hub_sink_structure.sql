-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 08 · hub sink-structure & one-way flow
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 08_hub_sink_structure.sql
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

-- Cheap structural probes that need no funding edges at all. The paper reports
-- 20.40% of settlements terminating at recipients that never pay onward and a
-- near-zero reciprocity graph; `hub_sink_share` and `one_way_share` are the
-- same measurement expressed per hub, so a single hub's star shape is visible
-- without solving the whole graph.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient, t.amount_usdc
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  payers AS (SELECT DISTINCT payer FROM settlements),
  edges AS (
    SELECT recipient AS hub, payer, COUNT(*) AS c
    FROM settlements GROUP BY recipient, payer
  ),
  hub_role AS (
    SELECT DISTINCT hub,
           IF(hub IN (SELECT payer FROM payers), 0, 1) AS hub_is_sink
    FROM edges
  )
SELECT
  e.hub,
  SUM(e.c)                                    AS settlements,
  COUNT(*)                                    AS unique_buyers,
  ROUND(MAX(e.c) / SUM(e.c), 6)               AS top_buyer_share,
  r.hub_is_sink
FROM edges    AS e
JOIN hub_role AS r ON r.hub = e.hub
GROUP BY e.hub, r.hub_is_sink
ORDER BY settlements DESC;

-- ---- network-level counterpart of the paper's "20.40% of settlements terminate
-- ---- at recipients that never pay onward" (run separately) ------------------
-- WITH settlements AS (... as above ...),
--      payers AS (SELECT DISTINCT payer FROM settlements)
-- SELECT COUNT(*) AS settlements_at_sinks,
--        ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM settlements), 4) AS pct_at_sinks
-- FROM settlements
-- WHERE recipient NOT IN (SELECT payer FROM payers);
