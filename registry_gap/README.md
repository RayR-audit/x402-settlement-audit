# x402 Registry Gap Ledger · v0.2 (2026-09-27, published 2026-09-29)

> Maintained by RayR-audit (independent auditor). Method + data + reproduction, no accusations.
> Claim: this ledger records a **mechanical fact**: services publicly advertise x402 settlement,
> yet their on-chain settlement path cannot be matched to the public 105-contract facilitator
> registry used by the primary public x402 dataset (Tektonic archive).

## Why this exists

The public narrative of x402 adoption counts settlements. The Tektonic dataset (the primary
public archive) attributes settlements to a 105-contract facilitator registry. Any x402 service
whose settlement does not run through one of those 105 contracts is invisible to that count —
and any consumer of that count (researchers, buyers, press) is measuring a narrower market
than the one being advertised.

This ledger does not claim bad intent. It records the gap between **advertised x402
compatibility** and **verifiable on-chain settlement attribution**, mechanically.

## Gap types

- **Type A (settlement-layer gap)**: a host's 402 challenge names a facilitator/payTo address
  that is not in the 105-contract registry. Detection: active probing of 402 challenges
  (rate-limited, 2s between requests).
- **Type B (disclosure gap)**: a service advertises x402 settlement but publishes **no on-chain
  address** of any kind, so its settlement path cannot be verified at all.

## Registry and scope conditions (v0.1 criteria, frozen 2026-09-27)

- Registry: `registries/base_facilitators.csv` — 105 address→facilitator mappings derived from
  the Tektonic upstream archive (frozen 2026-09-13 batch), Base table.
- **Most important scope condition**: the upstream archive stops at 2026-04-14 (131-day window).
  Facilitator contracts that appeared after that date are not in the registry by construction.
  A gap entry means "not in the public registry", **never** "not on-chain".
- No behavioral labels, no quality judgments; the ledger is settlement-path attribution only.

## Full Type A probe results (2026-09-27, n=617)

Probed all 617 PAYABLE hosts from the csoai/x402-bazaar-conformance snapshot (2026-09-27,
archived at `registry_gap/hosts_snapshot_20260927.jsonl`), 2s rate limit, x402 v1 (header)
and v2 (body JSON) challenge shapes both parsed. Results: `registry_gap/probe_results_v3.csv`.

| metric | value |
|---|---|
| 402 challenge received | 586/617 (95.0%) |
| challenge parsed (payee extractable) | 357 (61.0% of challenged) |
| **payee NOT in 105-contract registry (A_out)** | **357** |
| **payee IN registry (A_in)** | **0** |
| challenge with no extractable payee | 229 |
| challenge shape split | body (x402 v2): 546 · header (v1/other): 38 · unparsed: 2 |
| unique disclosed payees | 194 |

**Headline: of 357 hosts that disclose a settlement payee, 100% settle outside the public
105-contract facilitator registry — the registry the primary public x402 settlement dataset
is built on. Not one match.**

### What this means (and what it does not)

- The public settlement-count narrative is built on 105 facilitator contracts. The live
  payable ecosystem's disclosed payees have zero overlap with that set. Anyone citing
  settlement counts as "adoption" is measuring a market that does not include — by our probe,
  any of — the hosts actually accepting payments today.
- This is a mechanical, re-runnable finding: `registry_gap/probe_type_a_v3.py` ships with this
  ledger. Run it against any host list and the registry CSV (see script header for usage).
- It does NOT claim hosts are dishonest, unregistered, or off-chain. A payee outside the
  105-contract registry may settle through a contract the registry simply never captured.
  The gap is in **attribution coverage**, whatever its cause.

### Methodology corrections kept on record

- v1 probe counted currency contracts (e.g. Base USDC) as settlement addresses — inflated,
  data deleted, correction noted.
- v2 probe missed x402-v2 body-JSON challenges (77% of hosts) — under-extracted, replaced.
- v3 (final): header `request=` decode + body JSON, recursive payTo/recipient extraction,
  known currency contracts excluded. Single-host unit tests: bitrefill (body) ✓,
  onesource (header) ✓.

### Secondary observation

Challenge shape fragmentation (v1 header vs v2 body vs private protocols like `tempo`) is
itself an interoperability finding — 2 challenges could not be parsed at all under either
shape, and the split (89% body / 6% header) shows the ecosystem has moved past the v1
header challenge faster than tooling assumes.

## Type B entries

| Service | Public claim | Registry match | Type | Evidence snapshot |
|---|---|---|---|---|
| MACH Base (api.mach.gallery) | "pay per call with USDC over x402", 17 paid resources, MCP with 17 paid tools | none published — zero on-chain addresses in /.well-known/x402 (snapshot 2026-09-27) | B | [snapshot](../data/snapshots/mach_wellknown_x402_20260927.json) |

*Note: MACH is listed because it surfaced publicly on 2026-09-26 (issue #3467 outreach).
Inclusion is mechanical: well-known document contains zero 0x addresses.*

## Method

1. Self-reported side: services with public `/.well-known/x402` documents or Bazaar listings
   (cross-checked against csoai/x402-bazaar-conformance daily snapshots; the PAYABLE subset
   forms the probe list).
2. Registry side: 105-contract facilitator registry (see `registries/base_facilitators.csv`).
3. Gap = no mechanical match between the service's disclosed settlement addresses and the
   registry (Type A), or no addresses disclosed at all (Type B).
4. Every entry ships with its evidence snapshot (archived at detection time). Corrections
   welcome: open an issue — a service that publishes its facilitator address will be re-checked
   and moved to "resolved" with a dated note.

## Reproducing the Type A probe

```bash
python registry_gap/probe_type_a_v3.py \
  --hosts registry_gap/hosts_snapshot_20260927.jsonl \
  --registry registries/base_facilitators.csv \
  --out my_results.csv --rate 2
```

Re-running today will differ from the archived CSV (hosts change, some go offline); the
archived `probe_results_v3.csv` is the 2026-09-27 record.

## Limitations

- The 105-contract registry itself has coverage limits (see scope conditions above); a gap
  entry means "not in the public registry", never "not on-chain".
- Domain-name heuristics are not used for Type A (settlement layer is address-based only).
- Facilitator and resource-provider are different roles; we only ever claim about the
  settlement path, never about service quality.
- Snapshot discipline: every claim links to an archived snapshot with a date. No live-URL claims.
