# Gate G2 — the credit loop, verified end to end on live testnet ✅

**Aug 13, 2026.** A borrower's entire Ethereum Sepolia repayment history was proven to Creditcoin
through the Attestcoin Protocol, decoded and validated inside a Creditcoin smart contract, and
turned into a credit score that rose from **0 to 710 — Bronze to Platinum** — without a single
trusted intermediary anywhere in the path.

This is the make-or-break gate. Everything still to come (soulbound tier NFT, lending pool, batch
import, UI) presents this loop; nothing else replaces it.

## Deployed

| Contract | Chain | Address |
|---|---|---|
| `LoanBook` | Sepolia | [`0xE53a5448…5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c) — verified on Etherscan |
| `CreditRegistry` | CC3 | [`0xE53a5448…5Cf9c`](https://creditcoin-testnet.blockscout.com/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c) |
| `EvmV1Decoder` (linked library) | CC3 | [`0x2b887101…2EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |

The registry and LoanBook share an address on different chains — same deployer, same nonce. A
coincidence, but a useful reminder of exactly why the registry authenticates `chainKey`: identical
addresses across chains are normal, not suspicious.

## The score climbing, one verified proof at a time

Ten Sepolia transactions, each independently attested, proven and verified. The worker log:

| CC3 block | Source event | Borrower A score | Tier |
|---|---|---|---|
| 5304859 | RepaymentMade | 0 → **110** | Bronze |
| 5304866 | LoanOpened | 110 | Bronze |
| 5304868 | RepaymentMade | → **260** | **Silver** |
| 5304869 | LoanOpened | 260 | Silver |
| 5304870 | CollateralAdded | → **290** | Silver |
| 5304871 | RepaymentMade | → **450** | Silver |
| 5304872 | LoanOpened | 450 | Silver |
| 5304873 | RepaymentMade | → **560** | **Gold** |
| 5304874 | RepaymentMade | → **710** | **Platinum** |
| 5304875–6 | Borrower B's loan + **late** repayment | 0 | Bronze |

Final on-chain state, read straight from CC3:

```
profileOf(0x8ce707…89c6)  // Borrower A
  totalRepaidWei     6000000000000000   (0.006 ETH)
  totalCollateralWei 3000000000000000   (0.003 ETH)
  onTime 5   late 0   loansOpened 3   loansClosed 3
  score  710  ->  tier 3 (Platinum)

profileOf(0x04163f…A0B6)  // Borrower B
  totalRepaidWei     2000000000000000   (0.002 ETH)
  onTime 0   late 1   loansOpened 1   loansClosed 1
  score  0    ->  tier 0 (Bronze)
```

Two details worth pausing on:

- **710 is exactly what `ScoreLib.t.sol` asserts** for this history. The scoring model was
  calibrated against the real seeded profile before deployment, and the chain agrees with the
  test to the point.
- **`loansClosed = 3` was derived, not reported.** `LoanBook` never emits a "closed" event. The
  registry reconstructs closure by accumulating proven repayments against a proven principal — so
  even that fact is inferred only from cryptographically verified inputs.

## Replay protection, demonstrated live

Re-submitting an already-ingested transaction reverts on-chain:

```
execution reverted: "Query already processed"
```

The forced attempt is on chain as [`0x7c4737ca…`](https://creditcoin-testnet.blockscout.com/tx/0x7c4737cab8f77b699c28906cde9c8b4758a215a850847115702e9a35a0e2a0a5)
— status 0, and Borrower A's score stayed at 110 rather than doubling. The query id binds
`(chainKey, blockHeight, txIndex)`, so one Sepolia transaction can move a score exactly once.

The worker now detects that revert during gas estimation and skips submission rather than
broadcasting a transaction it knows will fail — a trap the reference examples fall into, since
their fallback fires on *any* estimation failure.

## Cost and timing

| Metric | Measured |
|---|---|
| Gas per verified ingest | **~403,558 average** over 10 submissions (396,816 – 407,792) |
| Cost per ingest | ~0.0002 CTC at 0.5 gwei |
| Total for a 10-event history | ~0.002 CTC |
| Attestation wait | none — the seeded blocks were already attested |

Proof sizes grew as expected with distance from the attestation anchor: continuity proofs ranged
from 40 to 59 roots, merkle paths 7–8 siblings.

## What the security actually rests on

The precompile proves inclusion and continuity. It explicitly does **not** prove that the
transaction succeeded, that it came from the chain you think, or that the contract that emitted
the log is the one you trust. Those are the registry's job, and each check is exercised by a test
that fails loudly if removed:

| Check | Attack prevented | Test |
|---|---|---|
| Replay guard on query id | Farming score by resubmitting one genuine repayment | `test_reject_replayedQuery` + demonstrated live above |
| `chainKey == 1` | A look-alike LoanBook on Ethereum Mainnet (chainKey 3, also attested by CC3) | `test_realProof_rejectedWhenChainKeyIsWrong` |
| `receiptStatus == 1` | A **reverted** repayment counting as a successful one | `test_reject_revertedSourceTransaction` |
| emitter `== LOANBOOK` | Anyone emitting identically-shaped events from their own contract | `test_reject_eventFromImpostorContract` |
| known `topic0` | Unrelated logs being misread as credit events | `test_reject_unknownEventSignature` |
| borrower from log topic | A relaying worker crediting reputation to itself | `test_ingest_creditsBorrowerFromTopicNotRelayer` |

## Reproducing

```bash
npm install && forge build
# .env needs SEPOLIA_RPC_URL, CC3_RPC_URL, DEPLOYER_PRIVATE_KEY,
#            LOANBOOK_ADDRESS, CREDIT_REGISTRY_ADDRESS, SOURCE_CHAIN_KEY=1
npm run worker:backfill -- --from-block 11482838     # replays the whole seeded history
npm run worker:backfill -- --tx <sepolia-tx-hash>    # or a single transaction
```

`worker/state.json` makes this idempotent: re-running skips what is already verified rather than
attempting doomed resubmissions.
