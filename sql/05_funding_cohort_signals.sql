-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 05 · funding-cohort signals (cluster merge rule 1)  [SCHEMA UNVERIFIED]
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.base_w3_publicgoods.token_transfers`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 05_funding_cohort_signals.sql
--   2. Keep the block_timestamp predicate. It is the partition filter that keeps
--      this query inside the BigQuery free tier (1 TiB/month, per billing account).
--   3. Sandbox-safe on purpose: pure SELECT/CTE only. No CREATE TEMP TABLE, no
--      INSERT/UPDATE/DELETE, no DDL -> runs in a no-credit-card BigQuery sandbox.
--      (Sandbox blocks DML; the upstream Tektonic SQL uses CREATE TEMP TABLE +
--      INSERT and therefore does NOT run in the sandbox. This file does.)
--   4. If you subscribed to the Analytics Hub listing, replace `web3-publicgoods.base_w3_publicgoods.token_transfers` with
--      `YOUR_PROJECT.tektonic_x402.base_raw`. Column names are unchanged.
--
-- FREE-TIER NOTE: a full-history scan of base_raw (all 12 columns, ~170M rows)
-- is ~35 GB = ~3.4% of the 1 TiB monthly free allowance. Cost $0.00.
-- =============================================================================

DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 280 DAY);
DECLARE end_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

-- !! READ FIRST ---------------------------------------------------------------
-- This file reads the *raw Base ledger*, not the Tektonic extract, because
-- settlement rows carry no funding or sweep edges. Column names below mirror
-- ConejoCapital/Tektonicx402 scripts/hydrate_base.py, which is the only public
-- description of this table; the Tektonic repo never documents the ledger schema.
--
-- VERIFY BEFORE TRUSTING (needs no billing, ~1 min):
--   bq show --schema --format=prettyjson web3-publicgoods:base_w3_publicgoods.token_transfers
--   bq show --schema --format=prettyjson web3-publicgoods:base_w3_publicgoods.receipts
-- If the dataset is not readable, fall back to an RPC/indexer for stage 2
-- (see DATA_PIPELINE_FEASIBILITY_20260912.md §4.3) and keep this as a template.
-- ---------------------------------------------------------------------------
--
-- Reproduces the paper's cluster merge rule 1: two payer wallets join one cluster
-- when they share an exact first funder (often at a fixed amount) AND are activated
-- in the same short window. `cohort_id` is the composite key the local clustering
-- step unions on (union-find over cohort_id + vanity batches from file 06).
-- Cost warning: this is the expensive file. Budget the scan, dry-run it, and prefer
-- a single pass writing to a table over repeated ad-hoc runs.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT DISTINCT LOWER(t.sender) AS payer
    FROM `web3-publicgoods.tektonic_x402.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
  ),
  inbound AS (   -- every inbound USDC transfer to a censused payer
    SELECT
      LOWER(t.to_address)   AS payer,
      LOWER(t.from_address) AS funder,
      t.quantity            AS amount_raw,
      t.block_timestamp     AS fund_ts,
      t.transaction_hash    AS fund_tx_hash,
      ROW_NUMBER() OVER (PARTITION BY LOWER(t.to_address)
                         ORDER BY t.block_timestamp, t.transaction_hash, t.event_index) AS rn
    FROM `web3-publicgoods.base_w3_publicgoods.token_transfers` AS t
    JOIN settlements AS s ON LOWER(t.to_address) = s.payer
    WHERE t.block_timestamp >= TIMESTAMP_SUB(start_ts, INTERVAL 30 DAY)
      AND t.block_timestamp < end_ts
      AND LOWER(t.address) = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913'
      -- held-out opaque boundaries: exchange/router/relayer hubs must not merge
      -- unrelated fleets, so they never act as a seed funder
      AND LOWER(t.from_address) NOT IN (SELECT address FROM facilitator_registry)
  ),
  first_funding AS (
    SELECT payer, funder, amount_raw, fund_ts, fund_tx_hash
    FROM inbound WHERE rn = 1
  )
SELECT
  payer,
  funder,
  amount_raw,
  fund_ts,
  fund_tx_hash,
  DATE(fund_ts) AS cohort_day,
  TO_HEX(MD5(CONCAT(funder, '|', CAST(amount_raw AS STRING)))) AS cohort_id
FROM first_funding
ORDER BY funder, amount_raw, fund_ts;
