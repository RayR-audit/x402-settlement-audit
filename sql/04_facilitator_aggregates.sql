-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 04 · facilitator aggregates
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 04_facilitator_aggregates.sql
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

-- Per-facilitator surface + a round-robin fingerprint check: the paper finds the
-- 129 relayer EOAs of one facilitator landing on *identical* settlement shares
-- (ranks 4-12 each 3.24-3.26%), i.e. one load balancer. `share_rank` + `share_pct`
-- make that pattern visible; near-equal shares across a run of ranks = one operator.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.facilitator_address) AS facilitator_address,
           t.facilitator_name AS facilitator_name,
           LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient,
           t.amount_usdc
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  )
SELECT
  facilitator_address,
  facilitator_name,
  COUNT(*)                          AS tx_count,
  ROUND(SUM(amount_usdc), 8)        AS volume_usdc,
  COUNT(DISTINCT payer)             AS unique_buyers,
  COUNT(DISTINCT recipient)         AS unique_sellers,
  ROUND(AVG(amount_usdc), 8)        AS mean_ticket_usdc,
  SUM(IF(payer = recipient, 1, 0))  AS self_payment_count,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share_pct,
  ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)       AS share_rank
FROM settlements
GROUP BY facilitator_address, facilitator_name
ORDER BY tx_count DESC;
