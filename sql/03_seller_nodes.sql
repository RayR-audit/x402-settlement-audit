-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 03 · seller (recipient hub) node table
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 03_seller_nodes.sql
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

-- Per-recipient hub features. `payer_hhi` is the buyer-concentration signal
-- (a hub whose settlement mass comes from one funder-linked fleet has a high HHI).
-- `is_sink` = the recipient never pays onward anywhere in the window, which the
-- paper measures at 20.40% of settlements (one-way value, marketplace absent).

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient,
           t.facilitator_name AS facilitator_name, t.amount_usdc,
           t.block_timestamp, DATE(t.block_timestamp) AS day
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  payer_side AS (   -- who ever pays onward (a recipient in here is not a sink)
    SELECT DISTINCT payer FROM settlements
  ),
  hub_payer AS (
    SELECT recipient, payer, COUNT(*) AS c, SUM(amount_usdc) AS v
    FROM settlements GROUP BY recipient, payer
  ),
  weighted AS (   -- window precomputed once: share of a hub's buyers
    SELECT recipient, payer, c, v, c / SUM(c) OVER (PARTITION BY recipient) AS cshare
    FROM hub_payer
  ),
  hub_agg AS (
    SELECT
      recipient,
      SUM(c)               AS tx_count,
      SUM(v)               AS volume_usdc,
      COUNT(*)             AS unique_buyers,
      MAX(cshare)          AS top_buyer_share,
      SUM(POW(cshare, 2))  AS payer_hhi
    FROM weighted
    GROUP BY recipient
  ),
  hub_meta AS (
    SELECT
      recipient,
      MIN(block_timestamp) AS first_seen,
      MAX(block_timestamp) AS last_seen,
      MIN(facilitator_name) AS primary_facilitator,
      IF(recipient IN (SELECT payer FROM payer_side), 0, 1) AS is_sink
    FROM settlements
    GROUP BY recipient
  )
SELECT
  g.recipient                                                        AS seller_address,
  g.tx_count,
  ROUND(g.volume_usdc, 8)                                            AS volume_usdc,
  g.unique_buyers,
  ROUND(g.top_buyer_share, 6)                                        AS top_buyer_share,
  ROUND(g.payer_hhi, 6)                                              AS payer_hhi,
  m.first_seen,
  m.last_seen,
  m.is_sink,
  m.primary_facilitator
FROM hub_agg  AS g
JOIN hub_meta AS m ON m.recipient = g.recipient
ORDER BY tx_count DESC;
