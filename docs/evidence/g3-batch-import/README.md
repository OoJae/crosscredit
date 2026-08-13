# Gate G3 — a whole credit history imported in one transaction ✅

**Aug 13–14, 2026.** A borrower with nothing on Creditcoin had their **entire Ethereum Sepolia
credit history verified in a single Creditcoin transaction**, went from Bronze to Platinum in that
one transaction, minted a soulbound badge, and borrowed **undercollateralized** — all on live
testnet, with no trusted intermediary anywhere in the path.

## The batch import

| | |
|---|---|
| Borrower C | `0x8C04C28894BADcE63d1F00f356AbB126983522Cf` (fresh wallet, nothing on Creditcoin) |
| Source history | 9 events across 9 Sepolia transactions, spanning **9 blocks** |
| Creditcoin transaction | [`0xc8ca57e3…5437b`](https://creditcoin-testnet.blockscout.com/tx/0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b) · block **5305011** |
| Proofs verified | **9, sharing one continuity proof** (13 roots) |
| `HistoryEventIngested` events in that transaction | **9** |
| Result | score **0 → 710**, tier **Bronze → Platinum** |

```
▸ Batch of 9
  ✓ attested        block 11483187 on chainKey 1
  ✓ batch proof     9 transactions, 9-block span, 13 shared continuity roots
  ✓ dry run         precompile accepts the batch (free staticCall)
  → submitted       0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b
  ✓ verified on CC3 block #5305011 — 9 transactions, 1135318 gas (126146 per event)
  ★ 0x8C04C288…22Cf → score 710, tier Platinum
```

### The efficiency claim, measured

Both paths ran against the **same registry** on the **same day**, so this is a like-for-like
comparison rather than an estimate:

| Path | Gas per event | 9 events |
|---|---|---|
| Single proof (`execute`) | ~433,000 | ~3,897,000 |
| **Batch (`executeBatch`)** | **126,146** | **1,135,318** |
| | **3.4× cheaper** | **71% saved** |

The saving is structural, not an optimisation trick. Verifying a foreign block means walking a
continuity chain back to a block Creditcoin has attested; a batch performs that walk **once** and
amortises it across every proof. That is exactly why the precompile requires all source blocks to
sit inside a 1000-block window — the shared walk has to be valid for all of them.

## Then: badge, and undercollateralized credit

| Step | Transaction | Result |
|---|---|---|
| Mint soulbound badge | [`0x55193273…b2211`](https://creditcoin-testnet.blockscout.com/tx/0x551932735f75d5b450b9d76dfc32d36951ff4202bb701ce62f65e98e607b2211) | Token #1, `locked() == true` |
| **Borrow undercollateralized** | [`0xb6da8c06…70d833`](https://creditcoin-testnet.blockscout.com/tx/0xb6da8c060e8e9c3ff84e17e0399bcc3c844c58507fcb11655de540d82270d833) | **100 tUSD borrowed against 85 tCTC** |

Borrower C received more value than they posted. That is the entire thesis in one transaction: an
address that was anonymous to Creditcoin fifteen minutes earlier now borrows on terms no anonymous
address can get, purely because its repayment history on another chain was proven rather than
asserted.

### The badge is genuinely on-chain

`tokenURI(1)` decodes to metadata and an SVG generated inside the contract — no gateway, no
pinning service, nothing to rot:

```json
{ "name": "CrossCredit Platinum #1",
  "attributes": [ {"trait_type":"Tier","value":"Platinum"},
                  {"trait_type":"Score","value":710},
                  {"trait_type":"On-time repayments","value":5},
                  {"trait_type":"Late repayments","value":0},
                  {"trait_type":"Loans closed","value":3} ] }
```

## Three borrowers, one registry

| Borrower | How imported | Score | Tier | Badge | Collateral for 1,000 tUSD |
|---|---|---|---|---|---|
| A `0x8ce707…89c6` | 11 single proofs | 710 | **Platinum** | #2 | **850 tCTC** |
| B `0x04163f…A0B6` | 2 single proofs | 0 | Bronze | #3 | 1,500 tCTC |
| C `0x8C04C2…22Cf` | **1 batch of 9** | 710 | **Platinum** | #1 | **850 tCTC** |

Borrower B's single late repayment is the whole difference between 850 and 1,500 tCTC of
collateral — **650 tCTC**, on an identically-sized loan. A and C arrived at the same place by
different routes, which is the point: batch and single-proof paths converge on identical state.

## Every attack rejected, on the live chain

[`../g3-negative-paths/results.json`](../g3-negative-paths/results.json) — reproduce with
`npm run negative-paths`. All five run as free `eth_call`s against the real precompile and the
deployed registry:

| # | Attack | Rejected by | Reason |
|---|---|---|---|
| 1 | Merkle root replaced with `0xdede…` | block-prover precompile | `Merkle proof validation failed` |
| 2 | Last 4 bytes of `txBytes` altered | block-prover precompile | `Merkle proof validation failed` |
| 3 | Real Sepolia proof claimed as chainKey 3 | precompile (registry's `WrongSourceChain` is the second line) | `Continuity proof does not match attestation or checkpoint` |
| 4 | Resubmitting an ingested transaction | `USCBase` replay guard | `Query already processed` |
| 5 | 11 proofs, one over the limit | `CreditRegistry.BatchTooLarge` | custom error |

The baseline is checked first: the *untampered* proof must verify, or every rejection below it
would be meaningless. On attack 3 we report the layer that actually fired rather than the one we
wrote — the precompile rejects it before our check is reached, and our check is proven separately
in `test_realProof_rejectedWhenChainKeyIsWrong`. Two independent layers refuse the same attack.

## Something we learned the hard way

**Continuity proofs expire.** The first run of the negative-path script failed its own baseline
with `Continuity proof does not match attestation or checkpoint` — using a proof captured hours
earlier. A continuity proof anchors to the attestation state at generation time, and once
attestation advances past that anchor the proof stops verifying, even though the underlying
transaction is unchanged and perfectly valid.

Consequences we have adopted:
- The negative-path script **fetches its baseline proof fresh** every run. A stale baseline would
  have made all five "rejections" meaningless — they would have been rejecting a proof that was
  already invalid.
- Stored proof fixtures are for **decoder** tests only (`RealProof.t.sol`), never for on-chain
  verification.
- A production worker should fetch and submit promptly rather than queue proofs for later.

This is not documented anywhere we could find, and it is the kind of thing that silently breaks a
demo recorded the day before submission.

## Deployed (CC3 testnet)

| Contract | Address |
|---|---|
| `CreditRegistry` (with batch) | [`0xB5F3B441…84B2c`](https://creditcoin-testnet.blockscout.com/address/0xB5F3B44113A31B07508464de39d7ddd939184B2c) |
| `CreditTierSBT` | [`0x96a68DBe…4B2F6`](https://creditcoin-testnet.blockscout.com/address/0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6) |
| `LendingPool` | [`0xA37a9338…5FDAb`](https://creditcoin-testnet.blockscout.com/address/0xA37a9338b17c20917046E29F23D9d8F796a5FDAb) |
| `TUSD` | [`0x26FEEdEC…3B051`](https://creditcoin-testnet.blockscout.com/address/0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051) |
| `EvmV1Decoder` (linked library) | [`0x2b887101…2EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |

The Phase 2 registry (`0xE53a5448…5Cf9c`) predates `executeBatch` and is superseded. Its Gate G2
transactions remain valid historical evidence — they really happened — but all current state lives
on `0xB5F3B441…84B2c`, which carries both borrowers from G2 plus Borrower C.

## Reproducing

```bash
npm run seed:borrower-c                       # fresh borrower, ~10 min to attest
npm run worker:batch -- --borrower 0x…        # imports the whole history in ONE transaction
npm run negative-paths                        # five attacks, all rejected, costs nothing
```
