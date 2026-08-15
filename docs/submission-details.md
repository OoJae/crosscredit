**A wallet that has never touched Creditcoin gets an undercollateralized credit line on it, on the strength of loans it repaid to Aave on Ethereum.** No signature from that wallet was needed to build or price the line, no oracle we run, no bridge holding funds — a Creditcoin contract verifies the Ethereum transactions itself.

🔗 **[crosscredit.vercel.app](https://crosscredit.vercel.app)** — live on CC3 testnet, no wallet needed to look around
💻 **[github.com/OoJae/crosscredit](https://github.com/OoJae/crosscredit)** · 🎬 demo video: *[YouTube URL]*

---

## A valid proof of the wrong thing is worthless

That sentence is the design. The BlockProver precompile proves a transaction was *included* in a source block — not that it succeeded, came from the contract you think, or hasn't been counted before. Everything CrossCredit adds sits on the far side of that distinction.

Measured, on chain, reproducible:

- **Nine Sepolia proofs verified in one CC3 transaction** — [`0xffad0a92…`](https://creditcoin-testnet.blockscout.com/tx/0xffad0a92eb99ca20d2d58043c92b9d82fc7cd025f789e51a3ed347859312b69b): 1,207,503 gas, **134,167 per event**, against 532,140 for the same ingest one at a time. Batching needs every source block inside one 1000-block window, so it fits dense recent history; mainnet history spanning years imports one proof at a time.
- **Five real Aave V3 mainnet repayments** proven and scored, 0 → 800, Platinum.
- **The negative-path suite rejected live** — forged root, tampered payload, wrong source chain (the precompile); replayed query, oversized batch (the registry). `npm run negative-paths`, free, no wallet: each run first verifies an untampered baseline proof, then records which layer rejected each attack.

### The precompile surface we use

| Primitive | How |
|---|---|
| `verifyAndEmit` (single) | Main ingest, via vendored `USCBase`, pinned `gluwa/usc-testnet-bridge-examples@4ff9a3bf` |
| `verifyAndEmit` (batch) | Up to ten proofs against **one shared continuity proof** — nine in the headline import. No example in the pinned repo exercises this path. The docs state the cap of 10; we confirmed the boundary at the precompile itself, registry bypassed: **ten verifies, an eleventh reverts `heights: Value is too large for length`** ([artifact](https://github.com/OoJae/crosscredit/blob/main/docs/evidence/precompile-batch-ceiling/results.json)). Our registry rejects oversized batches earlier, with a legible `BatchTooLarge` |
| `verify` (read-only) | A free pre-flight: `previewIngest` names the guard that would reject a proof *before* a signature is requested; `dryRunBatch` staticCalls a whole batch so a doomed one costs nothing |
| `calculateTxIndex` | Derives the replay id: `queryId = keccak(chainKey, blockHeight, txIndex)` |
| ChainInfo (`0x…0fd3`) | `getSupportedChains`, attested heights |
| `EvmV1Decoder` | External library, `delegatecall`'d into **our** storage context — so we deploy our own build rather than link a stranger's |

*("Attestcoin Protocol" is prose branding; every package and import is `usc-*`: `@gluwa/usc-sdk@0.18.0`, `@gluwa/usc-contracts@0.1.2`.)*

### Five checks on every proven payload

1. **Replay** — the `queryId` guard, exercised live: resubmitting an ingested transaction reverts `Query already processed`.
2. **Source authentication on the `(chainKey, emitter)` pair**, not either alone. CC3 attests both Sepolia and mainnet, so the same address on the other chain would emit indistinguishable events. This required modifying the vendored `USCBase` to pass `chainKey` into the business hook.
3. **`receiptStatus == 1`**, decoded in-contract via `EvmV1Decoder.decodeReceiptFields` — a *reverted* repayment is still "included", and the precompile does not check success.
4. **Dispatch on the log's own emitter**, never the caller's `action` byte, which arrives outside the proof.
5. **`topic0` must match that source's registered signatures.**

### What we could not find in the docs or examples

- **CC3 attests Ethereum mainnet as chainKey 3**, beside Sepolia's 1. Found in neither the docs nor the examples, and it became the project: real, unaffiliated Aave history instead of self-reported testnet events.
- **`verify()` reverts; it never returns false** — its `returns (bool)` signature invites `require(verify(...))`, an unreachable branch.
- **Continuity proofs expire.** They anchor to attestation state at generation; a negative-path run failed its own baseline on a proof captured hours earlier, so every run now fetches fresh.
- **`getBatchProof` returns a nested Map ordered by height, not input order.** Zip it against your inputs and you silently credit the wrong borrower.
- **`queryId` identifies a transaction, not an event.** The reference pattern takes the first matching log, so a second credit event in the same transaction is lost forever behind the replay guard. We ingest every recognised log — tolerating anonymous zero-topic logs that a naive `topics[0]` read would revert on; log index 4 of our headline mainnet proof is one.

### Timing

End to end, measured: **9 min 39 s** — ~8.5 min waiting for Sepolia attestation, ~15 s (one CC3 block) for the verification itself, at 393,638 gas for that first single-event round trip. Creditcoin's attestor set is in the trust path; the oracle *we* don't run is the part we added nothing to.

---

## Who was the lender?

Our first build read repayments from our own `LoanBook` on Sepolia. Every proof verified — and `openLoan(1 wei) → repay(1 wei)` six times reached the top tier, because history issued to yourself proves nothing. You cannot fake an Aave repayment; the pool is a real counterparty whose capital was at risk. So the registry reads the chain where the lenders are, and self-reported sources are capped below Platinum by construction (`ScoreLib`).

## What verified history buys

Tier sets the **rate**. The credit line above posted collateral is capped by `demonstratedCapacityWei` — the largest single amount provably repaid to a real third-party protocol.

| Borrower (live on the registry) | Score | Tier | Capacity* | Collateral to borrow 1,000 tUSD |
|---|---|---|---|---|
| `0x76f30e…5b1A` — 5 real Aave repayments | 800 | Platinum | 960,145 | **850** |
| `0xe57D6C…dd00` — one Aave repayment, Oct 2024 | 423 | Silver | 1.83 | 1,300 |
| `0x8ce707…` — self-dealt control | 390 | Silver | 0 | 1,300 |
| `0xB82dC3…b52E` — 2 self-dealt, one late | 0 | Bronze | 0 | 1,500 |

*\*Face value in each reserve's own 18-dp units — there is no price feed, by design (a WBTC history would be understated; disclosed in the threat model).*

The Oct-2024 row is the age axis working: one proof scores 423 because time derives from the source block **height** the Merkle proof covers, converted against an owner-registered height↔time anchor — a trusted input we disclose. Five proofs from last week earn zero age points. And a wallet with Platinum's rate but no real history gets no discount at all — pinned by `test_capacityCap_platinumWithoutRealHistoryGetsNoDiscount`; live, self-dealt wallets cannot reach Platinum in the first place.

## Verify it yourself

**Browser** — [crosscredit.vercel.app/explorer](https://crosscredit.vercel.app/explorer), any address above. No wallet.

**Clone, no API key** — `.env.example` ships working public RPCs and the current addresses (CI enforces that they match `deployments.json`):

```bash
git clone https://github.com/OoJae/crosscredit && cd crosscredit
cp .env.example .env && npm install
forge test
npm run negative-paths   # attacks vs the LIVE precompile and registry
```

**Funded wallet** — `npm run prove:mainnet <txHash>`: any real Aave V3 repayment in a registered reserve (USDC, USDT, PYUSD, WBTC, DAI, WETH) becomes a credit line.

## Open problems, disclosed

Twelve items in [`docs/THREAT_MODEL.md`](https://github.com/OoJae/crosscredit/blob/main/docs/THREAT_MODEL.md). The two that matter most: **multi-block wash lending is open** — we closed the same-transaction flash-loan path (each `Repay` is paired against a same-transaction `Borrow` of the same reserve, and one repayment credit per proven transaction), but an attacker lending themselves real capital across blocks is not solved. And **source curation is trusted**: proofs are verified on-chain against Creditcoin's attestor consensus, but *which* contracts count as credit sources is a registry-owner decision.

## Deployed

**CC3** — CreditRegistry [`0x4C4381dB68a1cAAE46a2E6CFc2f667ad22Dddf81`](https://creditcoin-testnet.blockscout.com/address/0x4C4381dB68a1cAAE46a2E6CFc2f667ad22Dddf81) · EvmV1Decoder `0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa` · CreditTierSBT `0x326F8806cBd5ABF413889BfAc0A6622a0AEddD18` (ERC-721 + ERC-5192, on-chain SVG) · LendingPool `0xf27877faC13244a4ad959E83cD9E5a15d919029C`
**Sepolia** — LoanBook [`0x07AdA5C60dFbe5C3A7dC48081B0fa70E14c6d41D`](https://sepolia.etherscan.io/address/0x07AdA5C60dFbe5C3A7dC48081B0fa70E14c6d41D)

Full technical documentation: [`docs/ATTESTCOIN_INTEGRATION.md`](https://github.com/OoJae/crosscredit/blob/main/docs/ATTESTCOIN_INTEGRATION.md)
