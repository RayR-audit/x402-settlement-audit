-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 09 · post-clustering validation (inflation factor)  [DEPENDS ON LOCAL CLUSTER TABLE]
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 09_cluster_validation.sql
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

-- !! READ FIRST ---------------------------------------------------------------
-- Do NOT run this before the local clustering step exists. It expects a two-column
-- table you uploaded from the local pipeline (SQLite -> CSV -> BQ load):
--     YOUR_PROJECT.x402_tmp.cluster_map(payer STRING, cluster_id STRING)
-- replacing `YOUR_PROJECT.x402_tmp.cluster_map` below. It reproduces the paper's
-- per-cluster `inflation factor` = settlements / settlements terminating outside
-- the cluster, and the C1 / C2 / C3 tier counts that the authenticity score is
-- built from. An infinite factor = provably closed = C1.
-- ---------------------------------------------------------------------------

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient,
           t.amount_usdc, t.block_timestamp
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  cm AS (SELECT payer, cluster_id FROM `YOUR_PROJECT.x402_tmp.cluster_map`),
  decorated AS (
    SELECT
      s.payer, s.recipient, s.amount_usdc,
      pc.cluster_id AS payer_cluster,
      rc.cluster_id AS recipient_cluster
    FROM settlements AS s
    LEFT JOIN cm AS pc ON pc.payer = s.payer
    LEFT JOIN cm AS rc ON rc.payer = s.recipient
  )
SELECT
  IF(payer_cluster IS NULL, '-', payer_cluster) AS cluster_id,
  COUNT(*) AS settlements,
  ROUND(SUM(amount_usdc), 8) AS volume_usdc,
  SUM(IF(payer = recipient, 1, 0)) AS self_payments,
  SUM(IF(recipient_cluster IS NOT NULL AND recipient_cluster = payer_cluster, 1, 0)) AS internal_settlements,
  SUM(IF(recipient_cluster IS NULL OR recipient_cluster <> payer_cluster, 1, 0)) AS external_settlements,
  SAFE_DIVIDE(COUNT(*),
    SUM(IF(recipient_cluster IS NULL OR recipient_cluster <> payer_cluster, 1, 0))) AS inflation_factor,
  IF(SUM(IF(recipient_cluster IS NULL OR recipient_cluster <> payer_cluster, 1, 0)) = 0,
     'C1_closed', 'C2_internal') AS tier
FROM decorated
GROUP BY cluster_id
ORDER BY settlements DESC;
