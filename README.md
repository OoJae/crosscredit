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
| `LoanBook` | Ethereum Sepolia | [`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events) — source verified |

Seeded with [11 real events](docs/evidence/seeded-history.json) across two borrowers: a clean
9-event record (all on time, spanning 10 blocks — so it fits a **single** batch proof) and a
second borrower with a late repayment, for tier contrast.

## Quickstart

```bash
npm install
cp .env.example .env      # fill in SEPOLIA_RPC_URL and a test-only DEPLOYER_PRIVATE_KEY
forge test                # 31 tests
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
