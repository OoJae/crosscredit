# CrossCredit

**Trustless cross-chain credit reputation and lending on Creditcoin.**

### → **[crosscredit.vercel.app](https://crosscredit.vercel.app)** — live on testnet, no wallet needed to look around

Borrowers build a repayment history on Ethereum Sepolia. CrossCredit proves those transactions to
Creditcoin using the **Attestcoin Protocol's** native block-prover precompile — a Merkle inclusion
proof plus a chain-continuity proof, verified synchronously inside a Creditcoin block. No oracle
operator. No bridge multisig. Verified history becomes an on-chain credit score and a soulbound
Credit Tier NFT, which prices real loans: **Platinum borrows undercollateralized at 85%.**

---

## See it working in 60 seconds

Open [crosscredit.vercel.app](https://crosscredit.vercel.app) and click through the three seeded
borrowers. No wallet, no testnet funds, no setup:

| Borrower | Imported via | Score | Tier | Collateral for 1,000 tUSD |
|---|---|---|---|---|
| `0x8C04C2…22Cf` | **one batch of 9 proofs** | 710 | **Platinum** | **850 tCTC** |
| `0x8ce707…89c6` | 11 separate proofs | 710 | **Platinum** | **850 tCTC** |
| `0x04163f…A0B6` | 2 proofs, one **late** | 0 | Bronze | 1,500 tCTC |

A single late repayment is the whole difference between 850 and 1,500 tCTC of collateral on an
identical loan. The first two borrowers reached the same place by different routes — batch and
proof-by-proof converge on identical state.

## What actually happened on-chain

| | |
|---|---|
| **Whole history in one transaction** | [`0xc8ca57e3…`](https://creditcoin-testnet.blockscout.com/tx/0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b) — 9 Sepolia transactions verified together, Bronze → Platinum |
| **Undercollateralized borrow** | [`0xb6da8c06…`](https://creditcoin-testnet.blockscout.com/tx/0xb6da8c060e8e9c3ff84e17e0399bcc3c844c58507fcb11655de540d82270d833) — 100 tUSD borrowed against 85 tCTC |
| **Replay rejected** | [`0x7c4737ca…`](https://creditcoin-testnet.blockscout.com/tx/0x7c4737cab8f77b699c28906cde9c8b4758a215a850847115702e9a35a0e2a0a5) — status 0, `Query already processed` |

**Batching is 3.4× cheaper**, measured like-for-like on the same registry: **126,146 gas per event**
batched versus ~433,000 proving them one at a time. The saving is structural — verifying a foreign
block means walking a continuity chain back to an attested one, and a batch walks it once for all
nine.

## Deployed contracts

| Contract | Chain | Address |
|---|---|---|
| `LoanBook` | Ethereum Sepolia | [`0xE53a5448…5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events) ✅ Etherscan |
| `CreditRegistry` | Creditcoin CC3 | [`0xB5F3B441…84B2c`](https://creditcoin-testnet.blockscout.com/address/0xB5F3B44113A31B07508464de39d7ddd939184B2c) ✅ Blockscout |
| `CreditTierSBT` | Creditcoin CC3 | [`0x96a68DBe…4B2F6`](https://creditcoin-testnet.blockscout.com/address/0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6) ✅ |
| `LendingPool` | Creditcoin CC3 | [`0xA37a9338…5FDAb`](https://creditcoin-testnet.blockscout.com/address/0xA37a9338b17c20917046E29F23D9d8F796a5FDAb) ✅ |
| `TUSD` | Creditcoin CC3 | [`0x26FEEdEC…3B051`](https://creditcoin-testnet.blockscout.com/address/0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051) ✅ |
| `EvmV1Decoder` (linked library) | Creditcoin CC3 | [`0x2b887101…2EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |

## How it works

```
   ETHEREUM SEPOLIA (chainKey 1)                CREDITCOIN CC3 TESTNET (chainId 102031)
┌──────────────────────────────┐        ┌────────────────────────────────────────────────┐
│ LoanBook.sol                 │        │ BlockProver precompile @ 0x…0FD2               │
│  openLoan / repay /          │        │   ▲ verifyAndEmit (Merkle + continuity)        │
│  addCollateral               │        │   │  ≤10 proofs share one continuity proof     │
│  → emits attestable events   │        │ CreditRegistry.sol  (Attestcoin Smart Contract) │
└───────────┬──────────────────┘        │   replay guard → verify → decode → validate     │
            │ events                    │   → CreditProfile → ScoreLib → tier             │
            ▼                           │        │                    │                   │
┌──────────────────────────────┐        │        ▼                    ▼                   │
│ Oracle Worker  /  the web UI │ proofs │  CreditTierSBT         LendingPool               │
│  wait for attestation →      │───────▶│  (ERC-721 + 5192,      (tier → collateral %,     │
│  fetch proof → dry run →     │        │   on-chain SVG)         Platinum = 85%)          │
│  execute / executeBatch      │        └────────────────────────────────────────────────┘
└──────────────────────────────┘
```

**The precompile proves inclusion and continuity — nothing else.** It explicitly does *not* check
that a transaction succeeded, which chain it came from, or which contract emitted the log. Those
are the registry's job, and each is exercised by a test that fails loudly if removed:

| Check | Attack it stops |
|---|---|
| Replay guard on the derived query id | Resubmitting one genuine repayment to farm score |
| `chainKey == 1` | A look-alike LoanBook on Ethereum Mainnet — CC3 attests that chain too |
| `receipt.receiptStatus == 1` | A **reverted** repayment counting as a successful one |
| Emitter `== LOANBOOK` | Anyone emitting identically-shaped events from their own contract |
| Known `topic0` | Unrelated logs being read as credit events |
| Borrower read from the log topic | A relaying worker crediting reputation to itself |

**Five attacks were rejected on the live chain** — forged merkle root, tampered payload, wrong
source chain, replayed query, oversized batch. Reproduce them for free: `npm run negative-paths`.

## Run it yourself

Needs [Node 20+](https://nodejs.org) and [Foundry](https://getfoundry.sh). Nothing below spends
money or needs a wallet.

```bash
git clone https://github.com/OoJae/crosscredit && cd crosscredit
npm install
forge build && forge test          # 130 tests, no network required
```

To read live testnet state or run the frontend locally:

```bash
cp .env.example .env               # only SEPOLIA_RPC_URL is needed for read-only use
npm run check:chains               # re-derives docs/evidence/supported-chains.json from live CC3
npm run negative-paths             # five attacks, all rejected — free eth_calls

cd web && npm install && npm run dev
```

To prove new history you need a funded test wallet ([`docs/HUMAN_ACTIONS.md`](docs/HUMAN_ACTIONS.md)
has the faucets):

```bash
npm run seed:borrower-c                    # fresh history on Sepolia (~10 min to attest)
npm run worker:batch -- --borrower 0x…     # import it all in ONE transaction
npm run worker:watch                       # or follow the chain head continuously
```

## Layout

```
contracts/       Foundry (solc 0.8.30) — 130 tests
  src/sepolia/     LoanBook — the credit-history source
  src/creditcoin/  CreditRegistry (ASC), ScoreLib, CreditTierSBT, LendingPool, TUSD
  src/vendored/    Attributed upstream base contracts (see below)
  test/            Unit tests, mocks, real captured proof fixtures
worker/          Oracle worker — watch, backfill and batch modes
web/             The frontend deployed at crosscredit.vercel.app
scripts/         check-chains, seed-history, capture-proof, negative-paths, deploy
docs/            BUILD_GUIDE · ATTESTCOIN_INTEGRATION · SCORING · evidence/
```

## Documentation

- **[docs/ATTESTCOIN_INTEGRATION.md](docs/ATTESTCOIN_INTEGRATION.md)** — how the protocol is used,
  what we had to establish ourselves, and where the depth is
- **[docs/SCORING.md](docs/SCORING.md)** — the model, and why every constant is what it is
- **[docs/evidence/](docs/evidence/)** — gate-by-gate proof: G0 round-trip, G2 credit loop,
  G3 batch import, negative paths
- **[PROGRESS.md](PROGRESS.md)** — build log, including the things that went wrong

## Attribution

`contracts/src/vendored/` contains base contracts adapted from Gluwa's official examples,
[`gluwa/usc-testnet-bridge-examples`][examples] pinned at commit `4ff9a3bf`. Each file names its
upstream source and lists every modification. All other code here is original work written from
Aug 13, 2026 onward.

Built for [BUIDL CTC 2026 Fall][hackathon].

## License

MIT

[hackathon]: https://dorahacks.io/hackathon/buidl-ctc-2026-fall/detail
[examples]: https://github.com/gluwa/usc-testnet-bridge-examples
