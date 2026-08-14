# CrossCredit

**Trustless cross-chain credit reputation and lending on Creditcoin.**

### → **[crosscredit.vercel.app](https://crosscredit.vercel.app)** — live on testnet, no wallet needed to look around

CrossCredit reads a borrower's **real Aave V3 history from Ethereum mainnet** and proves it to
Creditcoin using the **Attestcoin Protocol's** native block-prover precompile — a Merkle inclusion
proof plus a chain-continuity proof, verified synchronously inside a Creditcoin block. Verified
history becomes an on-chain credit score, a soulbound Credit Tier NFT, and a real loan:
**Platinum borrows undercollateralized at 85%.**

Nothing is self-reported and no oracle delivers a number. The score is computed *inside the EVM*
of the chain that verified the evidence, from events that chain checked for itself.

---

## The borrower who had never heard of Creditcoin

`0x76f30e3f…5b1A` is a real Ethereum wallet with a real Aave V3 borrowing record. It has never sent
a transaction to Creditcoin. We proved five of its genuine mainnet repayments — one `execute` each,
no permission from the borrower needed or possible — and watched a credit profile assemble itself:

```
score  0 → 320 → 440 → 560 → 680 → 800        Bronze → Silver → Gold → Platinum
```

It can now borrow **1,000 tUSD against 850 of collateral** on Creditcoin, on the strength of
repayments it made on another chain to a protocol that has never heard of us either.

## Why that is the whole product

An earlier version of this project read only our own `LoanBook` on Sepolia. That contract is
permissionless, escrows nothing and takes a **self-declared** principal — there is no lender. So:

```
openLoan(1 wei) → repay{value: 1 wei}(loanId)     × 6
```

Six wei, twelve transactions, one wallet, and the old model returned **Platinum with 85% LTV**.
Every proof was cryptographically valid. The Merkle proof verified, the continuity proof verified,
the precompile did its job perfectly. We had built a rigorous pipeline for the high-integrity
delivery of worthless data.

The question that exposes it is one sentence: **who was the lender?**

You cannot fake an Aave loan. So the fix was to read the chain where the lenders are, and to make
the arithmetic enforce the distinction:

> The **tier** sets your rate. **`demonstratedCapacityWei`** — the largest single amount you have
> provably repaid to a real third-party protocol — sets how much you may borrow *above what you
> post*. A Platinum wallet with no real history gets the Platinum rate on a fully collateralized
> loan and no discount at all.

Live on the same registry, right now:

| Borrower | History | Score | Tier | Capacity | Collateral for 1,000 tUSD |
|---|---|---|---|---|---|
| `0x76f30e…5b1A` | **5 real Aave V3 repayments** | 800 | **Platinum** | **$960,145** | **850** |
| `0x8C04C2…22Cf` | 9 self-dealt, one batch | 390 | Silver | $0 | 1,300 |
| `0x8ce707…89c6` | 11 self-dealt, proof by proof | 390 | Silver | $0 | 1,300 |
| `0x04163f…A0B6` | 2 self-dealt, one **late** | 0 | Bronze | $0 | 1,500 |

The bottom three are the control group. Their proofs are just as valid; their evidence is not.
Splitting a history across a thousand wallets divides capacity rather than multiplying it, so
sybil resistance here is arithmetic rather than an identity check —
[`test_capacityCap_isInvariantUnderIdentitySplitting`](contracts/test/LendingPool.t.sol) asserts it.

We tried the identity route first, and [measured it
failing](docs/THREAT_MODEL.md#why-not-proof-of-personhood): five real Proof of Humanity
registrations from 2021 all proved to Creditcoin successfully, and **none of those humans are
registered today**. That is the precompile working as documented — it proves that an *event
occurred*, not that a *state holds*. For a repayment those coincide. For an identity they do not.

**[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) states what this still does not solve**, starting
with the fact that there is no enforcement layer.

## What actually happened on-chain

| | |
|---|---|
| **Real mainnet credit** | [`docs/evidence/g5-mainnet-credit/`](docs/evidence/g5-mainnet-credit/results.json) — an Ethereum wallet's Aave history becomes a Creditcoin credit line |
| **Whole history in one transaction** | [`0xc8ca57e3…`](https://creditcoin-testnet.blockscout.com/tx/0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b) — 9 Sepolia transactions verified together for **126,146 gas per event** |
| **Undercollateralized borrow** | [`0xb6da8c06…`](https://creditcoin-testnet.blockscout.com/tx/0xb6da8c060e8e9c3ff84e17e0399bcc3c844c58507fcb11655de540d82270d833) — 100 tUSD borrowed against 85 tCTC |
| **Replay rejected** | [`0x7c4737ca…`](https://creditcoin-testnet.blockscout.com/tx/0x7c4737cab8f77b699c28906cde9c8b4758a215a850847115702e9a35a0e2a0a5) — status 0, `Query already processed` |

**Batching is 3.4× cheaper**, measured like-for-like on the same registry: **126,146 gas per event**
batched versus ~433,000 proving them one at a time. The saving is structural — verifying a foreign
block means walking a continuity chain back to an attested one, and a batch walks it once for all
nine.

## Deployed contracts

### Read from Ethereum mainnet (chainKey 3) — not deployed by us

| Protocol | Address | What it proves |
|---|---|---|
| Aave V3 Pool | [`0x87870Bca…fA4E2`](https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2) | `Repay`, `Borrow`, `LiquidationCall` |
| Sparklend Pool | [`0xC13e21B6…6BE987`](https://etherscan.io/address/0xC13e21B648A5Ee794902342038FF3aDAB66BE987) | Aave V3 fork, identical topic0s |
| ENS Registrar | [`0x59E16fcC…0CE547`](https://etherscan.io/address/0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547) | `NameRegistered`, expiry enforced at ingest |
| Proof of Humanity v2 | [`0xa4780958…3E74b2`](https://etherscan.io/address/0xa478095886659168E8812154fB0DE39F103E74b2) | Implemented; [honestly decorative](docs/THREAT_MODEL.md#why-not-proof-of-personhood) |

### Deployed by us

| Contract | Chain | Address |
|---|---|---|
| `LoanBook` | Ethereum Sepolia | [`0xE53a5448…5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events) ✅ Etherscan |
| `CreditRegistry` | Creditcoin CC3 | [`0x581A7413…6b3D2`](https://creditcoin-testnet.blockscout.com/address/0x581A7413e1fCcB767EC8BA9E837df43fbA06b3D2) ✅ Blockscout |
| `CreditTierSBT` | Creditcoin CC3 | [`0xaaA368cc…3D2F3`](https://creditcoin-testnet.blockscout.com/address/0xaaA368ccD534a24e7A98C375789598835A83D2F3) ✅ |
| `LendingPool` | Creditcoin CC3 | [`0x2FC0D783…0D90d`](https://creditcoin-testnet.blockscout.com/address/0x2FC0D783d7240B5814aBc7A6A464248B5b60D90d) ✅ |
| `TUSD` | Creditcoin CC3 | [`0x26FEEdEC…3B051`](https://creditcoin-testnet.blockscout.com/address/0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051) ✅ |
| `EvmV1Decoder` (linked library) | Creditcoin CC3 | [`0x2b887101…2EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |

## How it works

```
  ETHEREUM MAINNET (chainKey 3)
┌────────────────────────────────┐
│ Aave V3 · Sparklend · ENS      │      CREDITCOIN CC3 TESTNET (chainId 102031)
│  Repay / Borrow /              │   ┌─────────────────────────────────────────────────┐
│  LiquidationCall               │   │ BlockProver precompile @ 0x…0FD2                │
│  → real third-party capital    │   │   ▲ verifyAndEmit (Merkle + continuity)         │
└───────────┬────────────────────┘   │   │  ≤10 proofs share one continuity proof      │
            │                        │                                                  │
  ETHEREUM SEPOLIA (chainKey 1)      │ CreditRegistry.sol  (Attestcoin Smart Contract)  │
┌────────────────────────────────┐   │   replay guard → verify → decode → route on      │
│ LoanBook.sol                   │   │   (chainKey, emitter) → validate                 │
│  openLoan / repay              │   │        │                                          │
│  → self-reported, no lender    │   │        ▼                                          │
└───────────┬────────────────────┘   │   CreditProfile → ScoreLib → tier                │
            │ events                 │        │                    │                     │
            ▼                        │        ▼                    ▼                     │
┌────────────────────────────────┐   │  CreditTierSBT         LendingPool                │
│ Oracle Worker  /  the web UI   │   │  (ERC-721 + 5192,      tier → rate,               │
│  wait for attestation →        │──▶│   on-chain SVG)        capacity → credit line     │
│  fetch proof → dry run →       │prf└─────────────────────────────────────────────────┘
│  execute / executeBatch        │
└────────────────────────────────┘
```

Mainnet history imports **one proof per event** — real history spans years and the prover rejects
a batch wider than 1,000 blocks. Sepolia history, being contemporaneous, keeps the batch path.

**The precompile proves inclusion and continuity — nothing else.** It explicitly does *not* check
that a transaction succeeded, which chain it came from, or which contract emitted the log. Those
are the registry's job, and each is exercised by a test that fails loudly if removed:

| Check | Attack it stops |
|---|---|
| Replay guard on the derived query id | Resubmitting one genuine repayment to farm score |
| `(chainKey, emitter)` is a registered source | A look-alike Aave on a chain we do not trust — routing is per-pair, so a Sepolia address cannot impersonate its mainnet namesake |
| `receipt.receiptStatus == 1` | A **reverted** repayment counting as a successful one |
| Dispatch on the log's own emitter and `topic0` | Anyone emitting identically-shaped events from their own contract. The caller's declared `action` is a hint and is never trusted for routing |
| Reserve must be registered to count | An obscure 0-decimal token inflating capacity — unregistered reserves contribute **zero** |
| Borrower read from the log topic | A relaying worker crediting reputation to itself |

**Five attacks were rejected on the live chain** — forged merkle root, tampered payload, wrong
source chain, replayed query, oversized batch. Reproduce them for free: `npm run negative-paths`.

## Run it yourself

Needs [Node 20+](https://nodejs.org) and [Foundry](https://getfoundry.sh). Nothing below spends
money or needs a wallet.

```bash
git clone https://github.com/OoJae/crosscredit && cd crosscredit
npm install
forge build && forge test          # 164 tests, no network required
```

To read live testnet state or run the frontend locally:

```bash
cp .env.example .env               # only SEPOLIA_RPC_URL is needed for read-only use
npm run check:chains               # re-derives docs/evidence/supported-chains.json from live CC3
npm run negative-paths             # five attacks, all rejected — free eth_calls
npm run poh:negative               # the identity finding: 5/5 proved, 0/5 still valid

cd web && npm install && npm run dev
```

To prove new history you need a funded test wallet ([`docs/HUMAN_ACTIONS.md`](docs/HUMAN_ACTIONS.md)
has the faucets):

```bash
npm run seed:borrower-c                    # fresh history on Sepolia (~10 min to attest)
npm run worker:batch -- --borrower 0x…     # import it all in ONE transaction
npm run worker:watch                       # or follow the chain head continuously
npm run prove:mainnet -- 0x<mainnetTxHash>  # import a REAL Aave repayment from Ethereum mainnet
npm run prove:mainnet -- --find-aave        # find an attested one to try
```

## Layout

```
contracts/       Foundry (solc 0.8.30) — 164 tests
  src/sepolia/     LoanBook — the credit-history source
  src/creditcoin/  CreditRegistry (ASC), ScoreLib, SourceKinds, CreditTierSBT, LendingPool, TUSD
  src/vendored/    Attributed upstream base contracts (see below)
  test/            Unit tests, mocks, real captured proof fixtures
worker/          Oracle worker — watch, backfill and batch modes
web/             The frontend deployed at crosscredit.vercel.app
scripts/         check-chains, seed-history, capture-proof, negative-paths, prove-mainnet,
                 poh-negative, deploy
docs/            ATTESTCOIN_INTEGRATION · SCORING · THREAT_MODEL · BUILD_GUIDE · evidence/
```

## Documentation

- **[docs/ATTESTCOIN_INTEGRATION.md](docs/ATTESTCOIN_INTEGRATION.md)** — how the protocol is used,
  what we had to establish ourselves, and where the depth is
- **[docs/SCORING.md](docs/SCORING.md)** — the model, and why every constant is what it is
- **[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md)** — the flaw that shaped the design, and the five
  things still unsolved
- **[docs/evidence/](docs/evidence/)** — gate-by-gate proof: G0 round-trip, G2 credit loop,
  G3 batch import, G5 real mainnet credit, negative paths
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
