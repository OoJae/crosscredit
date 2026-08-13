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

**All five are implemented and live** in
[`CreditRegistry.sol`](../contracts/src/creditcoin/CreditRegistry.sol), each with a test that
fails loudly if it is removed — see the table in
[`evidence/g2-verified-credit-loop/`](evidence/g2-verified-credit-loop/README.md).

### A sixth property, and why the examples get it wrong

`queryId` is derived from `(chainKey, blockHeight, txIndex)`, so it identifies a **transaction**,
not an event. Gluwa's examples route on the caller-supplied `action` and ingest only the *first*
matching log — which means a transaction emitting two credit events could only ever be submitted
once, and the second event would be lost forever behind the replay guard.

CrossCredit instead ingests **every** recognised `LoanBook` log in the proven transaction,
dispatching each on its own `topic0`. One query id then corresponds exactly to "all credit events
in that transaction": complete, and still perfectly replay-protected. `action` is validated as a
known enum and otherwise unused, because it arrives from the caller and is **not covered by the
proof** — routing on it would mean trusting unattested data.

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

**Gate G0 — real proof round-trip: ✅ PASSED.** Full evidence:
[`docs/evidence/g0-hello-bridge/`](evidence/g0-hello-bridge/README.md).

A Sepolia burn ([`0xad717c5c…`](https://sepolia.etherscan.io/tx/0xad717c5c85279de036a321b63ccdb109a6c447e79f47261e52f969bdd20ca28d),
block 11482813) was proven to Creditcoin and acted upon
([`0x7ae82162…`](https://creditcoin-testnet.blockscout.com/tx/0x7ae82162d5f8ec24471637d1e545452d24adf3aa0066b42b874890fbf550f872),
block 5304687), minting 50 BTKT against QueryId
`0x2bf5346d29ad6628550c1eedca98d2c378b5fd2b20c4cce5363687e6e4750987`.

**Measured, and it corrects two of our own assumptions:**

| Metric | Measured |
|---|---|
| End-to-end | **9 min 39 s** — of which ~8.5 min is attestation and one CC3 block is verification |
| Gas on CC3 | **393,638** at 0.5 gwei ≈ **0.000197 CTC** per verified query |

The second number retires a constraint we had been designing around: Gluwa's README says 100 tCTC
buys ~9 oracle queries; it actually buys roughly half a million. Live-testnet iteration is
effectively free.

Two SDK behaviours were also recorded, because both will shape the Phase 2 worker: the SDK's 10 s
HTTP timeout also governs the attested-height poll and expired mid-attestation on the first
attempt (our scripts use 60 s), and `submit_query.ts` exits 0 even on failure — success must be
gated on output, never on exit code.

### Aug 13, 2026 — Phase 1: the source chain

**`LoanBook.sol` is live on Sepolia** at
[`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events)
(source verified on Sourcify, `exact_match`). It emits the three events that become a borrower's
portable reputation:

| Event | topic0 |
|---|---|
| `LoanOpened(uint256,address,uint256,uint64)` | `0x0d7f8e19afd65be70c0b9ff46dab1702a44ca0e8fcd33448375d7c2690e5866b` |
| `RepaymentMade(uint256,address,uint256,bool,uint64)` | `0x7d64aa0e099ec7ce5a5e95941014b245cf86dd8cd1115dd1ee421d8ec4d04206` |
| `CollateralAdded(address,uint256)` | `0x7dba1be544024070cd5eebfa8bdd80a8b198cea8058c7d3cc1f8dd36e41ab2f7` |

**The event shape is a cross-chain ABI, not an implementation detail.** `CreditRegistry` decodes
these logs out of a proven receipt and can never call back, so `borrower` is indexed in all three
— the registry reads it from a topic, never from `msg.sender`, which on Creditcoin is the worker
relaying the proof. `repay()` is permissionless but always credits `loan.borrower`, so a third
party settling your debt builds *your* reputation. And `onTime` is stamped by the source contract,
because the registry has no access to Sepolia's clock — only to what the proven receipt says.
`contracts/test/LoanBook.t.sol` asserts exact topic counts, topic0 hashes and data widths; those
assertions are the contract between the two halves of the system.

**Seeded history — [evidence](evidence/seeded-history.json), 11 events across two borrowers.**
One address cannot demonstrate both ends of the tier system, since Platinum requires `late == 0`:

| Borrower | Events | Profile |
|---|---|---|
| A `0x8ce70729…` | **9**, all on time, spanning **10 blocks** | Clean record → targets Platinum and the 85% undercollateralized borrow |
| B `0x04163f60…` | 2, including **one late repayment** (`onTime=false`) | Tier contrast — proves the penalty is real on live testnet |

Borrower A's 9 events fit **one batch**: under the 10-proof `MAX_BATCH_SIZE` and far under the
1000-block `MAX_BATCH_RANGE`. That constraint was designed into the seeding script rather than
discovered afterwards — a history spread over more than 1000 blocks could not be imported in a
single transaction, and the batch demo would have been impossible.

**One infrastructure limit found:** Alchemy's free tier caps `eth_getLogs` at a **10-block range**.
The Phase 2 worker must paginate its event scan in 10-block windows or use a different provider —
a naive full-range query fails outright.

---

## 5. Reproducing this

```bash
npm install
cp .env.example .env          # fill in SEPOLIA_RPC_URL and a test-only DEPLOYER_PRIVATE_KEY
npm run check:chains          # re-derives docs/evidence/supported-chains.json from live CC3
forge test -vvv               # contract suite
```

Deployed addresses land in `deployments.json` and in the README as each phase ships.


### Aug 13, 2026 — Phase 2: the credit loop closes (Gate G2)

**`CreditRegistry` is live on CC3** at
[`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://creditcoin-testnet.blockscout.com/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c),
linked against our own `EvmV1Decoder` at
[`0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa).

Ten Sepolia transactions were attested, proven and verified on Creditcoin, moving a borrower's
score **0 → 710, Bronze → Platinum**, at ~403,558 gas (~0.0002 CTC) per ingest. Full run,
per-block score progression and final profiles:
[`evidence/g2-verified-credit-loop/`](evidence/g2-verified-credit-loop/README.md).

**Replay protection demonstrated on-chain**, not just in tests: a forced resubmission reverted
with `Query already processed`
([`0x7c4737ca…`](https://creditcoin-testnet.blockscout.com/tx/0x7c4737cab8f77b699c28906cde9c8b4758a215a850847115702e9a35a0e2a0a5),
status 0) and the score held at 110 instead of doubling.

**Facts are derived, never asserted.** `LoanBook` emits no "loan closed" event, so the registry
reconstructs closure by accumulating proven repayments against a proven principal — and reconciles
out-of-order proofs, since each proof is independent and a repayment can legitimately be verified
before the opening it belongs to. The on-chain `loansClosed = 3` for Borrower A was inferred
entirely from cryptographically verified inputs.

**Tested against real prover output.** `contracts/test/RealProof.t.sol` decodes `txBytes` captured
from the live CC3 prover for transactions that actually happened on Sepolia. Synthetic tests only
prove our decoder agrees with our encoder; these would catch any divergence between our
understanding of the Attestcoin encoding and the real thing. 72 tests total, including the full
negative matrix.

**Three integration findings worth recording:**

1. **`EvmV1Decoder` is an external library.** All 16 functions are `public`, so it compiles to a
   separate 13,261-byte deployable and links by `delegatecall` — it is not inlined. We deploy our
   own rather than linking the pre-existing CC3 instance at `0x731c345d…`, which is a different
   build (9,598 B, solc 0.8.23) of unverified provenance; a library executes in the *calling*
   contract's storage context, so provenance matters.
2. **`forge script` cannot deploy to CC3.** Its simulation panics with
   `header validation error: prevrandao not set` against the Frontier/Substrate EVM. This is
   almost certainly why Gluwa's examples use the two-step `forge create` + `--libraries` flow,
   which we now follow.
3. **Gas estimation must be triaged, not blanket-caught.** When estimation surfaces a
   deterministic `Query already processed` revert, broadcasting anyway just burns gas on a
   transaction that cannot succeed — which is exactly what the examples' fallback does, since it
   fires on any estimation failure. Our worker aborts on that signal and uses a 900k floor
   (sized from the ~400k a real ingest costs) only for genuinely ambiguous failures; the examples'
   formula computes ~70k.
