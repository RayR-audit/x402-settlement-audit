-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 06 · vanity-suffix batch signals (cluster merge rule 2)
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 06_vanity_cluster_signals.sql
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

-- Paper merge rule 2: addresses created as a batch commonly share an improbable
-- address-vanity pattern. We operationalise it as a shared 4-hex-character suffix
-- (or prefix) inside one hub's payer set. Random collision on 4 hex chars is 1/65536,
-- so a >=3 batch is not chance; require the batch to be single-funder before merging
-- (join file 05) so the signal stays conservative.
-- `suffix_batch_id` is a union-find key for the local clustering step.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, LOWER(t.recipient) AS recipient,
           t.amount_usdc, DATE(t.block_timestamp) AS day
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  hub_payer AS (
    SELECT recipient AS hub, payer, COUNT(*) AS c,
           SUBSTR(payer, -4) AS sfx4, SUBSTR(payer, 3, 4) AS pfx4,
           MIN(day) AS first_day
    FROM settlements GROUP BY recipient, payer, sfx4, pfx4
  )
SELECT
  hub,
  'suffix' AS pattern_kind,
  sfx4 AS pattern,
  COUNT(*) AS wallets_in_batch,
  SUM(c)   AS settlements_from_batch,
  MIN(first_day) AS batch_first_day,
  TO_HEX(MD5(CONCAT(hub, '|suffix|', sfx4))) AS vanity_batch_id
FROM hub_payer
GROUP BY hub, sfx4
HAVING COUNT(*) >= 3
UNION ALL
SELECT hub, 'prefix', pfx4, COUNT(*), SUM(c), MIN(first_day),
       TO_HEX(MD5(CONCAT(hub, '|prefix|', pfx4)))
FROM hub_payer
GROUP BY hub, pfx4
HAVING COUNT(*) >= 3
ORDER BY settlements_from_batch DESC;
