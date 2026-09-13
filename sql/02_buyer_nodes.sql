-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 02 · buyer (payer) node table
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 02_buyer_nodes.sql
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

-- Per-payer authenticity features. `top_recipient_share` is the cheap on-chain
-- structural exclusivity proxy (paper criterion vi): a payer that sends ~all of
-- its settlements to one hub is a fleet wallet; a diversified payer is not.
-- `hour_amplitude` (0 = flat around the clock, higher = diurnal) is derived in
-- 07_timing_rhythm.sql; keep this table orthogonal to it.

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
      t.amount_usdc,
      t.block_timestamp,
      DATE(t.block_timestamp) AS day
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  pair AS (   -- payer x recipient weights: the raw material for exclusivity
    SELECT payer, recipient, COUNT(*) AS c, SUM(amount_usdc) AS v,
           MIN(block_timestamp) AS first_seen, MAX(block_timestamp) AS last_seen
    FROM settlements
    GROUP BY payer, recipient
  ),
  pair_agg AS (   -- one row per payer: no fan-out, every count comes from pair
    SELECT
      payer,
      SUM(c)                                  AS tx_count,
      SUM(v)                                  AS volume_usdc,
      SUM(v) / SUM(c)                         AS mean_ticket_usdc,
      COUNT(*)                                AS distinct_recipients,
      MAX(c) / SUM(c)                         AS top_recipient_share,
      MIN(first_seen)                         AS first_seen,
      MAX(last_seen)                          AS last_seen
    FROM pair
    GROUP BY payer
  ),
  day_agg AS (   -- one row per payer: daily cadence + self-payment accounting
    SELECT
      payer,
      COUNT(DISTINCT day)                                       AS active_days,
      COUNT(DISTINCT facilitator_address)                        AS distinct_facilitators,
      SUM(IF(payer = recipient, 1, 0))                           AS self_payments,
      COUNT(*)                                                   AS n
    FROM settlements
    GROUP BY payer
  )
SELECT
  a.payer,
  a.tx_count,
  ROUND(a.volume_usdc, 8)                     AS volume_usdc,
  ROUND(a.mean_ticket_usdc, 8)                AS mean_ticket_usdc,
  a.distinct_recipients,
  d.distinct_facilitators,
  ROUND(a.top_recipient_share, 6)             AS top_recipient_share,
  d.active_days,
  a.first_seen,
  a.last_seen,
  DATE_DIFF(DATE(a.last_seen), DATE(a.first_seen), DAY) AS span_days,
  IF(d.active_days = 1, 1, 0)                 AS one_shot,
  IF(d.self_payments = d.n, 1, 0)             AS self_pay_only
FROM pair_agg AS a
JOIN day_agg  AS d ON d.payer = a.payer
ORDER BY tx_count DESC;
