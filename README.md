# CrossCredit

**Trustless cross-chain credit reputation and lending on Creditcoin.**

Borrowers build a repayment history on Ethereum Sepolia. CrossCredit proves those transactions
to Creditcoin using the **Attestcoin Protocol's** native block-prover precompile — a Merkle
inclusion proof plus a chain-continuity proof, verified synchronously inside a Creditcoin block.
No oracle operator. No bridge multisig. Verified history becomes an on-chain credit score and a
soulbound Credit Tier NFT, which prices loans in a lending pool — Platinum borrows
undercollateralized.

> 🚧 **Phase 0 — under active construction** for [BUIDL CTC 2026 Fall][hackathon].
> Quickstart, deployed addresses, architecture diagram and demo land as the phases complete.

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
