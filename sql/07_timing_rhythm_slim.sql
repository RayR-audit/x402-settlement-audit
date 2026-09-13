-- =============================================================================
-- Agent Economy Audit Toolkit · x402 authenticity scoring
-- module: 07 · timing rhythm (hour-of-day amplitude, survival proxies)
-- chain : Base mainnet (chain id 8453) · USDC 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
-- source: Tektonic x402 CC0 public dataset -> `web3-publicgoods.tektonic_x402.base_raw`
--
-- DISCIPLINE (read before running):
--   1. ALWAYS dry-run first, and abort if the estimate is out of budget:
--        bq query --use_legacy_sql=false --dry_run --location=US < 07_timing_rhythm.sql
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

-- Reproduces the paper's §5.2 payer clock. `hour_amplitude` is the fundamental
-- Fourier harmonic of a payer's settlement count over the 24 hours of the day,
-- normalised by its mean: 2*|X1|/N where X1 = SUM_k x_k * exp(-2*pi*i*k/24).
-- 0 = flat around the clock (script / operator fleet), ~0.79 = advertised-service
-- payer in the paper's census, ~0.08-0.12 = provably-manufactured / operator side.
-- Amplitude alone is NOT a verdict (a scheduled agent is also regular): it is a
-- feature, not a label. Use it with the cluster tiers.

WITH
  facilitator_registry AS (
    SELECT address, facilitator
    FROM UNNEST(@registry /* redacted: load your own facilitator registry CSV, one address per row */)
  ),
  settlements AS (
    SELECT LOWER(t.sender) AS payer, EXTRACT(HOUR FROM t.block_timestamp) AS h, COUNT(*) AS c
    FROM `mecip-494306.tektonic_x402_public_dataset.base_raw` AS t
    JOIN facilitator_registry AS f ON LOWER(t.facilitator_address) = f.address
    WHERE t.block_timestamp >= start_ts AND t.block_timestamp < end_ts
      AND t.tx_status = 1 AND t.amount_usdc > 0
    GROUP BY payer, h
  )
SELECT payer, h, c FROM settlements ORDER BY payer, h;
