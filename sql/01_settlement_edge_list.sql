-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 01 · settlement edge list (payment-graph edges, aggregated)
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 01_settlement_edge_list.sql
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

-- One row per (payer -> recipient) directed payment edge, per facilitator.
-- ~7e5 rows over the 280-day window (arXiv:2607.12575 reports 718,668 edges,
-- 536,690 nodes). Small enough to export whole and cluster locally.
-- This is the graph fuel: weighted label propagation, reciprocity, bipartivity,
-- k-core, co-payer Jaccard all run off this table.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT
      LOWER(t.sender)    AS payer,
      LOWER(t.recipient) AS recipient,
      LOWER(t.facilitator_address) AS facilitator_address,
      t.facilitator_name AS facilitator_name,
      t.amount_usdc,
      t.block_timestamp,
      CASE WHEN LOWER(t.sender) = LOWER(t.recipient) THEN 1 ELSE 0 END AS is_self_payment
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f
      ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1                -- receipt_status = 1: reverted txs never emit Transfer
      AND t.amount_usdc > 0              -- exclude zeroed / failed rows
  )
SELECT
  payer,
  recipient,
  facilitator_name,
  COUNT(*)                    AS tx_count,
  ROUND(SUM(amount_usdc), 8)  AS volume_usdc,
  SUM(is_self_payment)        AS self_payment_count,
  MIN(block_timestamp)        AS first_seen,
  MAX(block_timestamp)        AS last_seen
FROM settlements
GROUP BY payer, recipient, facilitator_name
ORDER BY tx_count DESC;
