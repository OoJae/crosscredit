# CrossCredit

**Trustless cross-chain credit reputation and lending on Creditcoin.**

Borrowers build a repayment history on Ethereum Sepolia. CrossCredit proves those transactions
to Creditcoin using the **Attestcoin Protocol's** native block-prover precompile — a Merkle
inclusion proof plus a chain-continuity proof, verified synchronously inside a Creditcoin block.
No oracle operator. No bridge multisig. Verified history becomes an on-chain credit score and a
soulbound Credit Tier NFT, which prices loans in a lending pool — Platinum borrows
undercollateralized.

> 🚧 **Under active construction** for [BUIDL CTC 2026 Fall][hackathon]. The Creditcoin-side
> contracts, worker and UI land over the coming phases; what is listed below is live now.

## Live on testnet

**The core premise is proven.** On Aug 13, 2026 a transaction on Ethereum Sepolia was verified by
Creditcoin's block-prover precompile and acted upon inside a Creditcoin block — no oracle
operator, no bridge multisig:

| | |
|---|---|
| Sepolia burn | [`0xad717c5c…`](https://sepolia.etherscan.io/tx/0xad717c5c85279de036a321b63ccdb109a6c447e79f47261e52f969bdd20ca28d) (block 11482813) |
| Verified + acted on, Creditcoin | [`0x7ae82162…`](https://creditcoin-testnet.blockscout.com/tx/0x7ae82162d5f8ec24471637d1e545452d24adf3aa0066b42b874890fbf550f872) (block 5304687) |
| End-to-end | **9 min 39 s** · 393,638 gas ≈ 0.000197 CTC |

Full measurements and the two SDK failure modes we hit:
[`docs/evidence/g0-hello-bridge/`](docs/evidence/g0-hello-bridge/README.md).

### Deployed contracts

| Contract | Chain | Address |
|---|---|---|
| `LoanBook` | Ethereum Sepolia | [`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events) — verified on Etherscan |
| `CreditRegistry` | Creditcoin CC3 | [`0xB5F3B44113A31B07508464de39d7ddd939184B2c`](https://creditcoin-testnet.blockscout.com/address/0xB5F3B44113A31B07508464de39d7ddd939184B2c) |
| `CreditTierSBT` | Creditcoin CC3 | [`0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6`](https://creditcoin-testnet.blockscout.com/address/0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6) |
| `LendingPool` | Creditcoin CC3 | [`0xA37a9338b17c20917046E29F23D9d8F796a5FDAb`](https://creditcoin-testnet.blockscout.com/address/0xA37a9338b17c20917046E29F23D9d8F796a5FDAb) |
| `TUSD` | Creditcoin CC3 | [`0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051`](https://creditcoin-testnet.blockscout.com/address/0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051) |
| `EvmV1Decoder` (linked) | Creditcoin CC3 | [`0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |

Seeded with [11 real events](docs/evidence/seeded-history.json) across two borrowers: a clean
9-event record (all on time, spanning 10 blocks — so it fits a **single** batch proof) and a
second borrower with a late repayment, for tier contrast.

**A whole credit history, imported in ONE transaction.** A fresh wallet's 9 Sepolia events were
verified in a single Creditcoin transaction
([`0xc8ca57e3…`](https://creditcoin-testnet.blockscout.com/tx/0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b)),
taking it from Bronze to **Platinum**, minting a soulbound badge, and then
[borrowing 100 tUSD against just 85 tCTC](https://creditcoin-testnet.blockscout.com/tx/0xb6da8c060e8e9c3ff84e17e0399bcc3c844c58507fcb11655de540d82270d833)
— **more value than it posted**, which no anonymous address can do.

| | Gas per event |
|---|---|
| Single proof | ~433,000 |
| **Batch of 9 (one shared continuity proof)** | **126,146 — 3.4× cheaper** |

**Five attacks rejected on the live chain** — forged merkle root, tampered payload, wrong source
chain, replayed query, oversized batch. Reproduce for free: `npm run negative-paths`.

| Borrower | Imported via | Score | Tier | Collateral for 1,000 tUSD |
|---|---|---|---|---|
| A | 11 single proofs | 710 | Platinum | **850 tCTC** |
| B (one late repayment) | 2 single proofs | 0 | Bronze | 1,500 tCTC |
| C | **1 batch of 9** | 710 | Platinum | **850 tCTC** |

One late repayment is the entire difference between 850 and 1,500 tCTC of collateral.

Evidence: [G3 batch import](docs/evidence/g3-batch-import/README.md) ·
[G2 credit loop](docs/evidence/g2-verified-credit-loop/README.md) ·
[scoring model](docs/SCORING.md) ·
[Attestcoin integration](docs/ATTESTCOIN_INTEGRATION.md)

```bash
npm run worker:batch -- --borrower 0x…   # import a whole history in one transaction
npm run worker:backfill -- --from-block N   # or one proof at a time
npm run negative-paths                      # five attacks, all rejected, costs nothing
```

## Quickstart

```bash
npm install
cp .env.example .env      # fill in SEPOLIA_RPC_URL and a test-only DEPLOYER_PRIVATE_KEY
forge test                # 130 tests
npm run check:chains      # re-derives docs/evidence/supported-chains.json from live CC3
```

## Layout

```
contracts/       Foundry project (solc 0.8.30)
  src/sepolia/     LoanBook — the credit-history source
  src/creditcoin/  CreditRegistry (ASC), ScoreLib, CreditTierSBT, LendingPool, TUSD
  src/vendored/    Attributed upstream base contracts (see below)
  test/            Unit tests, mocks, captured proof fixtures, fork tests
worker/          Oracle worker — watch & backfill(batch) modes (TS, ethers v6, @gluwa/usc-sdk)
web/             Frontend — Dashboard / Import History / Borrow
scripts/         check-chains, seed-history, deploy, e2e-smoke
docs/            BUILD_GUIDE (spec) · ATTESTCOIN_INTEGRATION · evidence/
```

## Attribution

`contracts/src/vendored/` contains base contracts adapted from Gluwa's official examples,
[`gluwa/usc-testnet-bridge-examples`][examples] pinned at commit `4ff9a3bf`. Each file carries a
header naming its upstream source and listing every modification we made. All other code in this
repository is original work written from Aug 13, 2026 onward.

## License

MIT

[hackathon]: https://dorahacks.io/hackathon/buidl-ctc-2026-fall/detail
[examples]: https://github.com/gluwa/usc-testnet-bridge-examples
