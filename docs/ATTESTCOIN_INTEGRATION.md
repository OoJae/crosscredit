# Attestcoin Protocol integration

> **Submission document.** BUIDL CTC 2026 Fall requires *"technical documentation detailing your
> setup and explaining how the project uses the Attestcoin Protocol."* This is that document. It
> grows with every integration step; each entry is written while the work is fresh.

CrossCredit's premise is that the Attestcoin Protocol is **load-bearing, not decorative**. Remove
it and there is no product: the entire credit score derives from Ethereum Sepolia transactions
that a Creditcoin contract verified for itself, with no oracle operator and no bridge multisig in
the trust path.

---

## 1. The primitive we build on

The Attestcoin Protocol exposes a **BlockProver precompile** in the Creditcoin runtime at
`0x0000000000000000000000000000000000000FD2` (4050). It answers one question: *did this exact
transaction really occur in a real block of a supported source chain?*

It does so by checking two proofs together:

| Proof | Question it settles |
|---|---|
| **Merkle inclusion proof** | Is this transaction in the block it claims to be in? |
| **Continuity proof** | Is that block genuinely part of the source chain, linked back to a block the decentralized attestor network has attested on Creditcoin? |

A companion **ChainInfo precompile** at `0x…0fd3` reports which source chains are supported and
how far attestation has progressed.

```solidity
function verify(uint64 chainKey, uint64 height, bytes encodedTransaction,
                MerkleProof, ContinuityProof) external view returns (bool);
function verifyAndEmit(...) external returns (bool);            // + emits TransactionVerified
function verifyAndEmit(uint64 chainKey, uint64[] heights, bytes[] encodedTransactions,
                       MerkleProof[], ContinuityProof shared) external returns (bool);  // batch
function calculateTxIndex(MerkleProof) external view returns (uint64);
```

Three properties shape our whole design:

1. **It is synchronous.** Verification completes inside a single Creditcoin block (~15s) — the
   same transaction that verifies a foreign fact can act on it. There is no async query, no
   callback, no result storage.
2. **It does not check transaction success.** This is stated explicitly in the docs, and it is
   the single most important thing to get right: the precompile proves *inclusion*, not
   *outcome*. A reverted Sepolia transaction is still "included". **Our contract must decode the
   receipt and enforce `receiptStatus == 1` itself** — see §3.
3. **It batches.** Up to 10 proofs can share one continuity proof, provided their source blocks
   fall within a 1000-block range. This is what makes "import my entire credit history in one
   transaction" possible.

### Timing, stated honestly

The "~15 seconds" figure is **verification time, not end-to-end time**. Before a Sepolia block
can be proven, it must be attested on Creditcoin, and that lag measures **~8–10 minutes** in
practice. We measure it for real at Gate G0 and publish the number rather than the marketing one.
The honest claim — *a foreign transaction verified, decoded and acted upon inside one Creditcoin
block, with no trusted operator* — is remarkable enough without inflation.

---

## 2. Architecture

```
   ETHEREUM SEPOLIA (chainKey 1)                CREDITCOIN CC3 TESTNET (chainId 102031)
┌──────────────────────────────┐        ┌────────────────────────────────────────────────┐
│ LoanBook.sol                 │        │ BlockProver precompile @ 0x…0FD2               │
│  openLoan / repay /          │        │   ▲ verifyAndEmit(merkle + continuity)         │
│  addCollateral               │        │   │                                             │
│  → emits attestable events   │        │ CreditRegistry.sol  (Attestcoin Smart Contract) │
└───────────┬──────────────────┘        │   replay guard → verify → decode → validate     │
            │ events                    │   → CreditProfile → score → tier                │
            ▼                           │        │                    │                   │
┌──────────────────────────────┐        │        ▼                    ▼                   │
│ Oracle Worker (TS)           │ proofs │  CreditTierSBT         LendingPool               │
│  watch → waitUntilHeight     │───────▶│  (ERC-721 + 5192)      (tier → collateral %)     │
│  Attested → ProofBuilder     │        └────────────────────────────────────────────────┘
│  → execute / executeBatch    │
└──────────────────────────────┘
```

The user signs **once** — the Sepolia transaction. Everything after that is the worker fetching a
proof and the Creditcoin contract verifying it.

---

## 3. Where the depth is

The precompile answering "this transaction happened" is the *start* of the security argument, not
the end. A proof of a real transaction is still worthless if it came from the wrong chain, the
wrong contract, or a call that reverted. `CreditRegistry` therefore enforces five checks in
sequence before a single point of credit score moves:

| # | Check | Attack it stops |
|---|---|---|
| 1 | Replay guard on the derived query id | Resubmitting one genuine repayment to farm score |
| 2 | `chainKey == SOURCE_CHAIN_KEY` | A look-alike contract on Ethereum Mainnet (chainKey 3, also attested by CC3) forging history |
| 3 | `receipt.receiptStatus == 1` | A **reverted** loan repayment counting as a successful one — the precompile does not check this |
| 4 | Emitting contract `== LOANBOOK` | Any other contract emitting an identically-shaped event |
| 5 | `topic0 ∈ {LoanOpened, RepaymentMade, CollateralAdded}` | Unrelated events from our own contract being misread |

Checks 2 and 3 are the ones that require actually understanding the protocol, and both are
demonstrated on camera as rejected transactions.

---

## 4. Integration log

### Aug 13, 2026 — Phase 0: verification and foundations

**Established the real API surface.** The protocol migrated in early 2026 (USC Testnet 2.0):
legacy STARK proving was replaced by the native verifier, which removed prover contracts
entirely. Much published material still describes the old model. Verified against the npm
registry, live docs and CC3 RPC probes that the current stack is `@gluwa/usc-sdk@0.18.0` +
`@gluwa/usc-contracts@0.1.2`, and that the pre-2026 pattern (`@gluwa/creditcoin-public-prover`,
`ResultSegment[]`, `_onQueryValidated`, `_processOracleResults`, precompile `0x0Be9`) is dead.

**Confirmed the source chains on-chain rather than from documentation.**
`scripts/check-chains.ts` queries the ChainInfo precompile directly, and additionally reads each
chain's latest attested height — registration alone does not prove attestors are running.
Committed to [`docs/evidence/supported-chains.json`](evidence/supported-chains.json):

| chainKey | chainId | Name | Latest attested height | Attesting? |
|---|---|---|---|---|
| 1 | 11155111 | Sepolia ethereum | 11,482,570 | ✅ advancing across runs |
| 3 | 1 | Ethereum | 25,748,540 | ✅ advancing across runs |

**This finding changed the contract design.** CC3 attests **two** source chains, not one. Because
`chainKey` is a Creditcoin-internal id rather than an EVM chainId, a contract deployed at the same
address on Ethereum Mainnet could emit events indistinguishable from our Sepolia `LoanBook`'s.
Source-chain authentication is therefore mandatory — which is why we modified the vendored base
(below) to pass `chainKey` into the business-logic hook.

**Vendored the ASC base with attribution.** `USCBase.sol` ships only in the examples repository,
not in the npm package, so `contracts/src/vendored/` carries it pinned to
[`gluwa/usc-testnet-bridge-examples@4ff9a3bf`](https://github.com/gluwa/usc-testnet-bridge-examples/tree/4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b),
with every modification listed in the file header. The verification path and the `_computeQueryId`
assembly are byte-for-byte upstream so the security-critical core stays diffable against the
original. Exactly one functional change: the `chainKey` passthrough described above.

`VerifierInterface.sol` additionally declares the single-query view `verify`, both batch
overloads, and `TransactionVerified` — transcribed from the canonical precompile ABI in
`@gluwa/usc-sdk/dist/block-prover/block_prover.json`. The interface published in
`@gluwa/usc-contracts` is, by its own NatSpec, a "lean vendored copy" carrying only the
single-query view.

**Tested against the real code path.** `MockNativeQueryVerifier` is installed at the precompile's
actual address via `vm.etch`, so unit tests exercise the genuine vendored bytecode rather than a
reimplementation of it. Eight tests pin the behaviour our security rests on, including that a
rejected proof neither runs the hook nor consumes its query id — otherwise a forged submission
could permanently censor a real transaction. **Mocks are confined to `contracts/test/`; every
user-facing path runs against the real precompile on live CC3 testnet.**

**Two corrections found only by running things**, both now reflected in the code:
- The ChainInfo precompile returns `chainName` as hex-encoded bytes, not the plain string the
  SDK's own docstring shows.
- `EvmV1Decoder`'s functions are `public`, not `internal`, making it an **external library that
  requires link-time deployment** (13,261 B runtime) rather than an inlined one. The instance
  already on CC3 at `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` is 9,598 B — a different build —
  so we will deploy and link our own in Phase 2.

**Gate G0 — real proof round-trip:** ⏳ pending testnet funding.

---

## 5. Reproducing this

```bash
npm install
cp .env.example .env          # fill in SEPOLIA_RPC_URL and a test-only DEPLOYER_PRIVATE_KEY
npm run check:chains          # re-derives docs/evidence/supported-chains.json from live CC3
forge test -vvv               # contract suite
```

Deployed addresses land in `deployments.json` and in the README as each phase ships.
