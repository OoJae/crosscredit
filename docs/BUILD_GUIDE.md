# CrossCredit — Complete Build Guide
### BUIDL CTC 2026 Fall · "BUIDL For The Real World" · Target: Grand Prize + CEIP Fast-Track

> **One-liner:** A trustless, cross-chain credit-reputation and lending protocol on Creditcoin. Borrowers prove their repayment history on Ethereum Sepolia via the Attestcoin Protocol's native verifier precompile; CrossCredit converts verified history into an on-chain credit score + soulbound Credit Tier NFT, which unlocks progressively better (eventually undercollateralized) loan terms in a lending pool on Creditcoin.
>
> **Tracks:** DeFi (primary) + RWA (narrative) · **Team:** solo + Claude Code · **Window:** Aug 13 → Sep 6, 2026 · **we submit Sep 4** (the DoraHacks countdown is configured ~23h earlier than the page's stated deadline — see §6/§11)

---

## ⚠️ Read this first — the two rules that decide everything

1. **Attestcoin depth is a core scoring criterion.** Every architectural decision below exists to make the Attestcoin Protocol *load-bearing*: multiple attested event types, batch verification, in-contract decoding, replay protection, and a visible invalid-proof rejection path. Never cut these. Cut UI polish instead.
2. **Verify before you trust.** ✅ Done — §3 was verified Aug 13, 2026 against live docs, the npm registry and CC3 RPC probes. The verification pass found the original research was describing a **removed** architecture, so §3 and §5.3 were rewritten. Keep the habit: confirm any symbol against installed typings (`node_modules/@gluwa/usc-sdk/dist/*.d.ts`) or the pinned examples repo before depending on it. Tutorial videos and blog posts are known-stale; the pinned repo and live `.md` docs win.

---

## 1. What we're building (and why it wins)

**The problem.** On-chain credit history is trapped per-chain. A borrower with a flawless repayment record on Ethereum is a stranger on Creditcoin — so every protocol demands 150%+ overcollateralization, which locks the underbanked out of DeFi credit entirely. This is precisely the problem Creditcoin was founded to solve (RWA credit for emerging markets — Aella's 100B+ Naira disbursed to 2M+ Nigerians runs on this thesis).

**The insight.** The Attestcoin Protocol makes foreign-chain facts *natively verifiable* inside a Creditcoin smart contract — no oracle operator, no bridge multisig. That means credit reputation can finally become **portable and trustless**. CrossCredit is the cross-chain generalization of Creditcoin's own proven business.

**The demo moment (build everything around this):** a user repays a loan on Sepolia → once that
block is attested, a single Creditcoin block verifies the proof, updates their score, upgrades
their Credit Tier SBT, and visibly drops their collateral requirement. Then: batch-verify 10
historical events in one transaction. Then: watch a forged proof get rejected.

> ⏱️ **Honest timing (verified, and it changes the shot list).** Verification is ~15s — but only
> *after* Sepolia block attestation, which measures **~8–10 minutes**. Record the demo against
> **pre-attested** history: seed and repay well before the take, then show the CC3-side
> verification live. Say "verified in a single Creditcoin block", never "15 seconds end-to-end" —
> a judge who knows the protocol will catch the overclaim, and the real number is still
> extraordinary next to a 6–20 minute STARK flow or a multisig bridge.

**Why judges score it #1:**
- Attestcoin is irreplaceable — remove it and the product ceases to exist (deepest possible "meaningful integration").
- It is *the* Creditcoin mission ("BUIDL for the Real World" + financial inclusion), so it lands with the sponsor.
- It extends Gluwa's own documented credit-verification reference dApp → high polish is achievable solo in 23 days.
- CEIP fit is word-for-word: Credit Labs funds projects that "enhance decentralized credit," "improve financial inclusion," and "leverage Creditcoin's infrastructure for real-world applications."

---

## 2. Day-0 prerequisites checklist (human tasks — do before/alongside Phase 0)

- [ ] Register for the hackathon on DoraHacks (BUIDL CTC 2026 Fall) and note the submission form fields.
- [ ] Join the Creditcoin Discord (`discord.gg/Gu43zTfmtc`) → find the faucet channel + `#buidl-ctc-qna`. Introduce yourself; visibility helps at judging and CEIP.
- [ ] Register for the Online AMA (Aug 18, 07:00 ET) — ask one sharp technical question about Attestcoin batch verification or supported chains. Judges remember names.
- [ ] Create a **fresh test-only wallet** (never reuse a real-funds key). Export the private key into `.env` only.
- [ ] Fund it: **Sepolia ETH** (Alchemy/Infura/Google faucets) and **tCTC** (Creditcoin Discord faucet) on CC3 Testnet.
- [ ] Add networks to MetaMask:
  - **Creditcoin CC3 Testnet** — RPC `https://rpc.cc3-testnet.creditcoin.network`, chainId **102031**, symbol tCTC, explorer `https://creditcoin-testnet.blockscout.com` ✅.
  - **Ethereum Sepolia** — chainId **11155111**.
- [ ] Install locally: Node 20+, npm, Git, **Foundry** ✅ (the live examples are Foundry, not Hardhat — solc 0.8.30, evm shanghai).
- [ ] Clone the reference repo: **`gluwa/usc-testnet-bridge-examples`** @ pinned `4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b` ✅. (`gluwa/ccnext-testnet-bridge-examples` is the superseded predecessor — skip it. No `attestcoin`-named repo exists.)
- [ ] Optional accelerator: install the community **Creditcoin dApp Skill** for Claude Code (`github.com/phamdat721101/creditcoin-dapp-skills`). It's community-built, not official — audit everything it generates.
- [ ] Create the GitHub repo **on Aug 13** and commit the scaffold immediately — a clean commit history starting inside the hackathon window is your originality evidence.

---

## 3. Ground-truth technical reference — ✅ VERIFIED Aug 13, 2026

> ⛔ **The architecture this guide originally described was the pre-2026 one, and it is dead.**
> `@gluwa/creditcoin-public-prover`, `Types.sol`/`Prover.sol`, `ResultSegment[]`,
> `_onQueryValidated`, `_processOracleResults`, `isQueryUsed`/`_markQueryUsed`, precompile
> `0x0Be9`, escrowed `submitQuery`/`getQueryResult` — all removed when USC Testnet 2.0 replaced
> STARK proving with the native verifier. Sections below are the live replacement. Tutorial
> videos and blog posts still show the old model; the pinned repo and live docs win.

### 3.1 Networks
| | Creditcoin CC3 Testnet | Ethereum Sepolia (source chain) |
|---|---|---|
| Role | Where CrossCredit lives (ASC + pool + SBT) | Where credit history happens (LoanBook) |
| EVM chainId | **102031** (`0x18e8f`) | **11155111** |
| Attestcoin chainKey | n/a (destination) | **1** ✅ |
| RPC | `https://rpc.cc3-testnet.creditcoin.network` ✅ live | Alchemy/Infura (public RPCs rate-limit) |
| Explorer | `https://creditcoin-testnet.blockscout.com` ✅ | Etherscan |
| Gas token | tCTC (Discord `token-faucet`) | SepoliaETH |
| Block time / fees | ~15s, baseFee ~500 gwei, gasLimit 75M | ~12s |

**CC3 testnet has TWO registered source chains**: Ethereum Sepolia (chainKey **1**) and Ethereum
Mainnet (chainKey **3**). `chainKey` is a Creditcoin-internal id, **not** the EVM chainId, and its
meaning differs per environment (on mainnet, chainKey 1 *is* Ethereum Mainnet). Never hardcode —
resolve via `getSupportedChains()`; `docs/evidence/supported-chains.json` is law. Consequence for
us: the registry **must authenticate chainKey in-contract**, since a contract at the same address
on Ethereum Mainnet could otherwise spoof our LoanBook's events.

Still true: design for deep single-source integration (many event types), not shallow multi-chain.

### 3.2 The Attestcoin verification primitive
**BlockProver precompile @ `0x0000000000000000000000000000000000000FD2`.** (Docs renamed it from
"Native Query Verifier"; the Solidity interface is still literally `INativeQueryVerifier`.)
A companion **ChainInfo precompile lives at `0x…0fd3`**.

```solidity
// reverts on failure — returns true on success. `if (!verify(...))` is unreachable code.
function verify(uint64 chainKey, uint64 height, bytes calldata encodedTransaction,
                MerkleProof calldata, ContinuityProof calldata) external view returns (bool);

// same args, non-view, emits TransactionVerified(chainKey, height, txIndex).
// EVERY official example uses this one.
function verifyAndEmit(...) external returns (bool);

// batch: max 10 proofs sharing ONE continuity proof, all within a 1000-block MAX_BATCH_RANGE
function verifyAndEmit(uint64 chainKey, uint64[] heights, bytes[] encodedTxs,
                       MerkleProof[] proofs, ContinuityProof shared) external returns (bool);

function calculateTxIndex(MerkleProof calldata) external view returns (uint64);

struct MerkleProof      { bytes32 root; MerkleProofEntry[] siblings; }
struct MerkleProofEntry { bytes32 hash; bool isLeft; }
struct ContinuityProof  { bytes32 lowerEndpointDigest; bytes32[] roots; }
```

- Validates **inclusion** (Merkle proof) + **chain continuity** (link to an on-chain attestation
  by the decentralized attestor network), **synchronously, in one CC3 block**.
- ⚠️ **It does NOT validate transaction success** — stated in a danger callout in the docs. Our
  ASC must decode the receipt and `require(receipt.receiptStatus == 1)`. We demo this
  understanding explicitly; it earns credibility with the judges.
- **Batch has two limits, not one**: ≤ **10** proofs *and* a **1000-block range**. The second one
  shapes `seed-history.ts` — all seeded events must land inside one 1000-block window to fit a
  single batch (Sepolia ~12s blocks → a ~3.3h window, easily satisfied by a single seeding run).
- **Timing, corrected.** The famous "~15 seconds" is *verification only*, after the source block
  is already attested. **Sepolia attestation lag measures ~8–10 minutes.**
  `waitUntilHeightAttested` polls every 15s with a 15-minute default timeout. The demo must
  pre-attest (seed history well before recording). **Never pitch "15 seconds end-to-end."**
- Inbound/read-oriented on testnet — write-ability (attestor signing of outbound messages) is
  documented as *not yet released*. "Writing to" Sepolia = our own off-chain worker sending a
  normal Sepolia tx. **Never claim native outbound messaging in the pitch — it's roadmap.**

### 3.3 SDK & contract packages (exact pins)
- **`@gluwa/usc-sdk@0.18.0`** (TypeScript, ethers `^6.15` as a regular dependency, not a peer).
  **Exports are namespaces, not flat classes:**
  - `chainInfo.PrecompileChainInfoProvider` — `getSupportedChains()`, attestation state.
  - `proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl)` — `getProof(txHash)`,
    `getBatchProof([txHashes])`. **`ProverAPIProofGenerator` does not exist.**
  - `blockProver.PrecompileBlockProver` — `computeTransactionIndex`, `verifySingle`,
    `verifyAndEmitSingle`, `verifyBatch`, `verifyAndEmitBatch`.
  - `waitUntilHeightAttested` — polls every 15s, 15-minute default timeout.
  - `utils.mergeProofs`.
- **`@gluwa/usc-contracts@0.1.2`** (Solidity) — `contracts/write-ability/INativeQueryVerifier.sol`,
  `contracts/decoding/EvmV1Decoder.sol`. `EvmV1Decoder` is a **library** (internal/pure, inlined at
  compile time — no linking). The deployed instance at
  `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` on CC3 is only an off-chain debugging aid.
- **Proof builder API**: `https://prover.cc3-testnet.creditcoin.network`
  (alias `https://proof-gen-api.cc3-testnet.creditcoin.network/`, swagger at `/api/swagger/`).
- **`USCBase.sol` ships in the examples repo, NOT in the npm package** — we vendor it with
  attribution. The pattern:

```
execute(uint8 action, uint64 chainKey, uint64 blockHeight, bytes encodedTransaction,
        bytes32 merkleRoot, MerkleProofEntry[] siblings,
        bytes32 lowerEndpointDigest, bytes32[] continuityRoots) external returns (bool)
  → txIndex = VERIFIER.calculateTxIndex(merkleProof)
  → queryId = keccak256(abi.encodePacked(chainKey, blockHeight, txIndex))   // derived, not assigned
  → replay guard: mapping(bytes32 => bool) public processedQueries          // no isQueryUsed helper
  → VERIFIER.verifyAndEmit(...)
  → hook: _processAndEmitEvent(uint8 action, bytes32 queryId, bytes encodedTransaction) virtual
```

  Cross-chain data is decoded **directly from `encodedTransaction`** via `EvmV1Decoder`. There is
  no prover contract, no query escrow, no async result storage.
- **Pattern:** vendored ASC core + our business-logic contract implementing the hook + an
  **off-chain Oracle Worker** so the end user signs only once.
- **Docs:** `docs.creditcoin.org/attestcoin-protocol` (+ `/architecture`,
  `/attestcoin-protocol-chains-environments`, `/guided-tutorials`,
  `/dapp-builder-infrastructure/{attestcoin-smart-contracts, attestcoin-sdk-usc-sdk}`).
  Legacy `/creditcoin-usc/*` URLs 301 here; bare `/creditcoin-usc` 404s.
  **Appending `.md` to any docs URL returns clean markdown** — use it for scripted reads.
- **Examples:** `gluwa/usc-testnet-bridge-examples` @ `4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b`.
  Foundry (solc 0.8.30, optimizer 200, `via_ir=false`, evm `shanghai`), yarn 1.22.22, OZ 5.4.0.
  **Four** tutorials: **Hello Bridge → Custom Contracts Bridging → Bridge Offchain Worker →
  Loan Flow.** `loan-flow`'s `USCLoanManager.sol` is architecturally closest to CrossCredit —
  study and attribute, don't copy. `gluwa/ccnext-testnet-bridge-examples` is superseded.
- **"Attestcoin" is prose-only branding** — no npm package or GitHub repo carries the name;
  everything ships as `usc-*`, and the docs say so. Attestcoin in the pitch, `usc-*` in imports.
- **Faucet economics**: ~100 tCTC / 24h, ~11 tCTC per oracle query → **~9 live queries per day**.
  Claim daily; treat the query budget as a first-class constraint when iterating on testnet.

---

## 4. System architecture

```
        ETHEREUM SEPOLIA (chainKey 1)                    CREDITCOIN CC3 TESTNET (102031)
┌─────────────────────────────────┐          ┌──────────────────────────────────────────────┐
│  LoanBook.sol                   │          │  BlockProver precompile @ 0x…0FD2             │
│  - openLoan / repay /           │          │        ▲ verify(merkle + continuity)          │
│    addCollateral                │          │        │                                      │
│  - emits rich indexed events    │          │  CreditRegistry.sol (ASC)                     │
└──────────────┬──────────────────┘          │   Core: processOracleResults, replay guard    │
               │ events                      │   Hook: _onQueryValidated → decode segments   │
               ▼                             │   → validate (chainKey, LoanBook addr,        │
┌─────────────────────────────────┐          │     event sig, success) → update profile      │
│  Oracle Worker (TS, ethers v6,  │  proofs  │   → recompute score → sync tier               │
│  @gluwa/usc-sdk)                │─────────▶│        │                    │                 │
│  watch → waitUntilHeightAttested│          │        ▼                    ▼                 │
│  → ProverAPIProofGenerator      │          │  CreditTierSBT.sol     LendingPool.sol        │
│  → PrecompileBlockProver        │          │  (ERC-721 + ERC-5192,  (tier → collateral     │
│  → registry.processOracleResults│          │   Bronze→Platinum)      ratio + APR; borrow   │
│  batch mode: ≤10 per tx         │          │                         tUSD vs tCTC)        │
└─────────────────────────────────┘          └──────────────────────────────────────────────┘
                                   Frontend (Vite + React + wagmi/viem): Dashboard · Import History · Borrow
```

**Data flow (happy path):** user repays on Sepolia → worker detects `RepaymentMade` → waits for block attestation (~15s) → fetches proof from Prover API → submits to `CreditRegistry.processOracleResults` → precompile verifies inclusion+continuity → `_onQueryValidated` decodes segments → contract itself checks (source contract == LoanBook, chainKey == 1, event sig matches, success/on-time flags) → `CreditProfile` updated → score recomputed → `CreditTierSBT` minted/upgraded → `LendingPool` instantly quotes better terms. **User signed once (the Sepolia repay).**

---

## 5. Component specifications

### 5.1 `LoanBook.sol` (Sepolia) — the credit-history source
Purpose-built to emit attestable, information-dense events. Keep it simple and gas-cheap.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract LoanBook {
    struct Loan { address borrower; uint256 principal; uint64 dueDate; uint256 repaid; bool closed; }

    event LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate);
    event RepaymentMade(uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp);
    event CollateralAdded(address indexed borrower, uint256 amount);

    function openLoan(uint256 principal, uint64 duration) external returns (uint256 loanId);
    function repay(uint256 loanId) external payable;           // ETH-denominated for demo simplicity
    function addCollateral() external payable;
}
```

Design notes: `onTime = block.timestamp <= dueDate`; allow partial repayments (more events = richer history = better batch demo); include a `seedDemo()`-friendly design (short durations like 10–60 min so "late" is demoable). Ship with `script/seed-history.ts` that generates **9–10 mixed events** (3 loans, mostly on-time, exactly one late) from the demo wallet — this is the fuel for the batch-verification demo.

### 5.2 Oracle Worker (`/worker`, TypeScript)
- **Watch mode:** subscribe to LoanBook events for registered borrowers → per event: `waitUntilHeightAttested(blockNumber)` → generate proof (`ProverAPIProofGenerator`) → submit (`PrecompileBlockProver`) → call `processOracleResults(proverContract, queryId)` on CreditRegistry → persist `(txHash, queryId, status)` to `worker/state.json`.
- **Backfill mode:** `npm run worker:backfill -- --address 0x... --from-block N` → collect up to 10 unprocessed events **spanning ≤1000 source blocks** → `ProofBuilder.getBatchProof([txHashes])` → one `executeBatch` tx. This powers "Import my history." Both batch limits (10 proofs, 1000-block range) are enforced client-side before submitting.
- Reliability: idempotent by txHash, exponential backoff, clear structured logs (the logs appear in the demo video — make them pretty: `✓ attested`, `✓ proof fetched`, `✓ verified on CC3 in block #…`).
- Config via `.env` only. Never hardcode keys.

### 5.3 `CreditRegistry.sol` (CC3) — the ASC
Inherits our vendored, attributed `USCBase` (upstream `4ff9a3bf`) plus `Ownable`, `Pausable`.
**One deliberate modification to the vendored base**: the hook signature gains `chainKey` —
upstream never passes it through, but CC3 registers two source chains, so source-chain
authentication is impossible without it. Every other line of the vendored core stays
byte-identical to upstream so judges can diff it.

```
CreditRegistry is USCBase, Ownable, Pausable
  uint64  immutable SOURCE_CHAIN_KEY;   // from docs/evidence/supported-chains.json, ctor arg
  address immutable LOANBOOK;           // Sepolia LoanBook, ctor arg
  enum Action { LoanOpened, RepaymentMade, CollateralAdded }
  bytes32 constant × 3                  // topic0 of each event signature

  // ── Single path: vendored USCBase.execute(...) — untouched ──
  //    verifyAndEmit → processedQueries replay guard → _processAndEmitEvent(...) → _ingest

  // ── Batch path: OURS. USCBase.execute is single-proof only, so this is a new entrypoint ──
  executeBatch(uint8[] actions, uint64 chainKey, uint64[] heights, bytes[] encodedTxs,
               MerkleProof[] merkleProofs, ContinuityProof shared)
    · require(1 <= n && n <= 10) and all array lengths equal
    · per item: queryId = keccak256(chainKey, heights[i], VERIFIER.calculateTxIndex(proofs[i]));
      replay-guard EACH one before verifying (a batch must not half-apply)
    · ONE precompile call: VERIFIER.verifyAndEmit(chainKey, heights, encodedTxs, proofs, shared)
    · route every item through the same _ingest()

  // ── _ingest: this is the "depth" judges score ──
    1. require(chainKey == SOURCE_CHAIN_KEY)                    // ← why the hook needs chainKey
    2. EvmV1Decoder.decodeReceiptFields(tx); require(receiptStatus == 1)
       // the precompile deliberately does NOT check success — we do
    3. select logs by topic0 ∈ {LoanOpened, RepaymentMade, CollateralAdded}; require non-empty
    4. require(log.emitter == LOANBOOK)                          // source authentication
    5. decode topics+data → typed struct → update CreditProfile
    6. score = ScoreLib.compute(profile); tierSBT.sync(borrower, tierFor(score, profile))
    7. emit HistoryEventIngested(borrower, action, queryId)
```

- Storage: `mapping(address => CreditProfile)` where `CreditProfile { uint256 totalRepaidWei; uint32 onTime; uint32 late; uint32 loansOpened; uint32 loansClosed; uint64 firstSeen; uint16 score; }`.
- `LendingPool` **pulls** the tier via `registry.tierOf(borrower)` at borrow time — no cross-contract writes inside the verification hook (keeps the hot path cheap and re-entrancy-free).
- **Testing strategy** (the verifier is a live precompile, so):
  `MockNativeQueryVerifier` `vm.etch`'d at `0x…0FD2` — unit tests then exercise the *real*
  vendored `USCBase` byte path, not a reimplementation. Decoder tests run against real
  `encodedTransaction` bytes captured from the prover API. One fork test replays a captured
  golden proof against the live precompile's `verify` view (free — it's a view call).

### 5.4 Scoring model (`ScoreLib.sol` + `docs/SCORING.md`)
Deterministic, tunable, documented — judges must be able to audit it in 60 seconds.

- Range 0–1000. **+60** per on-time repayment (cap 600) · **+1 per 0.01 ETH** repaid (cap 200) · **+20** per loan fully closed (cap 100) · **+community longevity** up to 100 · **−120** per late repayment · floor 0.
- Tiers: **Bronze** < 200 · **Silver** ≥ 200 · **Gold** ≥ 450 · **Platinum** ≥ 700 **and** `late == 0`.
- All constants in one `ScoreParams` library — one file to tweak, one table in the deck.

### 5.5 `CreditTierSBT.sol` (CC3)
ERC-721 + **ERC-5192 (soulbound/locked)**: transfers revert, `Locked` event on mint, one token per address, `tokenURI` returns fully on-chain JSON/SVG badge per tier (nice demo visual, zero infra). Only `CreditRegistry` can mint/upgrade/downgrade.

### 5.6 `LendingPool.sol` (CC3)
Deliberately minimal — the *tier-gated terms* are the product, not a full Aave clone.
- Assets: borrow **tUSD** (our mock ERC-20, owner-mintable) against **tCTC** collateral.
- Terms by tier: Bronze **150%** coll / 14% APR · Silver **130%** / 11% · Gold **110%** / 8% · Platinum **85% (undercollateralized!)** / 6%. Per-tier borrow caps.
- Simple interest, `repay()`, owner-callable `liquidate()` stub (roadmap slide covers real liquidations).
- Reentrancy guards, checks-effects-interactions, pausable.

### 5.7 Frontend (`/web` — Vite + React + wagmi/viem + Tailwind)
Three screens, dark theme, obvious tier colors (bronze/silver/gold/platinum):
1. **Dashboard** — connected wallet's score dial, tier badge (renders the SBT SVG), profile stats, ingested-events table with links to *both* explorers.
2. **Import History** — "Prove my Sepolia history" button → live status stream mirroring worker stages (attested → proof → verified) → confetti on tier-up. This screen IS the demo.
3. **Borrow** — live terms table for *your* tier vs other tiers, collateral calculator, borrow/repay flow.
Include "Add CC3 to wallet" one-click (chainId 102031). No login, no backend beyond the worker.

---

## 6. Build plan — phases, days, decision gates

> Working rhythm: one phase = one or more Claude Code sessions. Test-first for contracts. Commit at every green test. Update `PROGRESS.md` at session end.

### Phase 0 — Verify reality (Days 1–2, Aug 13–14) 🔑
- Run the **Day-1 Verification Protocol** (§7). Lock: real package names, prover API URL, precompile address, supported chains, tutorial repo locations.
- Complete **Tutorial 1 (Hello Bridge)** end-to-end on CC3 with your own wallet. *Deliverable: one verified proof round-trip, screenshot saved to `/docs/evidence/`.*
- Scaffold monorepo, CI (lint + test), commit.
- **Gate G0:** proof round-trip works. If the tutorial itself is broken → post in `#buidl-ctc-qna` immediately (their fix helps every competitor less than it helps you — you're first in line).

### Phase 1 — Source chain (Days 3–4)
- `LoanBook.sol` + full unit tests → deploy Sepolia → verify on Etherscan → run `seed-history.ts` (9–10 events). *Gate G1: seeded history visible on Etherscan.*

### Phase 2 — Core integration, single event (Days 4–8) 🔑
- Tutorials 2–3 → adapt into `CreditRegistry` (Core + hook) → decode **one** event type (`RepaymentMade`) → deploy CC3 → worker watch-mode proves one live repayment → profile updates on-chain.
- **Gate G2 (Day 8, make-or-break): one Sepolia repayment → verified → score changes on CC3, fully live.** If missed: cut scope to exactly this loop + SBT + minimal UI (that alone is a valid, winnable submission) and get help in Discord. Do not proceed to Phase 3 features until G2 is green.

### Phase 3 — Depth (Days 9–13)
- Add remaining event types (LoanOpened, CollateralAdded) with per-type decoding + tests.
- **Batch verification (≤10)** in worker backfill + registry batch path — the differentiator. 
- `ScoreLib` + `CreditTierSBT` (on-chain SVG) + `LendingPool` wired to tiers.
- Negative paths: forged proof rejected, replayed query rejected — with tests AND a scripted on-camera repro.
- *Gate G3 (Day 13): full loop incl. batch + tiers + pool terms working headless (scripts/logs only).* If batch API fights you > 1 day: ship sequential multi-proof ingestion, present batch as "supported by protocol, roadmap for us" — depth score survives.

### Phase 4 — Frontend + polish (Days 14–18)
- Build the 3 screens against live testnet · empty/error/pending states · one-click network add · NatSpec pass on all contracts · `ATTESTCOIN_INTEGRATION.md` written *while it's fresh*.
- *Gate G4 (Day 18): a stranger with the README can run the demo in <10 min; you can run the full happy path on camera in one take.*

### Phase 5 — Deliverables (Days 19–21)
- **Demo video** (§9) — record Day 19, edit Day 20, re-record weak segments Day 21.
- Deck/whitepaper PDF (§10) · README final pass with architecture diagram + all addresses · repo cleanup (no secrets, no dead code, LICENSE, honest attribution of forked example code).
- *Gate G5: every submission-form field has its asset ready as a URL.*

### Phase 6 — Submit early (Days 22–23, Sep 3–4)
- **Submit on DoraHacks Sep 4.** ⚠️ The deadline is genuinely ambiguous: the page prose says **Sep 6, 23:59 ET**, but the platform's own countdown is configured to **Sep 6, 04:59 UTC (= Sep 6, 00:59 ET)** — i.e. the submit button probably locks ~23h *before* the stated time. Eventbrite lists a third figure (Sep 6, 16:00 ET). Ask in `#buidl-ctc-qna` early; submit Sep 4 regardless.
- Verify every link from an incognito window + your phone. Post the project in Discord.

---

## 7. Day-1 Verification Protocol — ✅ EXECUTED Aug 13, 2026

Findings are locked into §3 and §5.3; the full record is in `PROGRESS.md`. Re-run steps 3–4 if
testnet behaviour starts drifting; the rest is settled.

1. ✅ npm registry — `@gluwa/usc-sdk@0.18.0` + `@gluwa/usc-contracts@0.1.2` current. `@gluwa/creditcoin-public-prover` is the dead architecture (last publish Oct 2025). **No package named `attestcoin` exists** — the rebrand is prose-only.
2. ✅ Live docs read — precompile `0x…0FD2` (+ ChainInfo `0x…0fd3`), prover API URL, batch limits (10 proofs / 1000-block range), the "does not validate success" callout, four tutorials. All legacy `/creditcoin-usc/*` URLs 301 to `/attestcoin-protocol/*`.
3. ⏳ `scripts/check-chains.ts` → `/docs/evidence/supported-chains.json`. **This output is law** for which source chains we may use.
4. ✅ CC3 RPC live, chainId 102031 confirmed by probe, explorer confirmed serving current blocks. ⏳ Faucet is an operator action — `docs/HUMAN_ACTIONS.md`.
5. ✅ Examples pinned: `gluwa/usc-testnet-bridge-examples` @ `4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b`, recorded in vendored file headers + README.
6. ✅ Guide, `CLAUDE.md` and `.env.example` updated. Residual unknowns are drafted as Discord/AMA questions in `PROGRESS.md` (deadline reconciliation; batch `verify` view-variant liveness; judging-rubric weights).

---

## 8. Testing, deployment & security

**Tests (Foundry/Hardhat):** ScoreLib math (fuzz the caps/floors) · segment decoding from fixture-encoded `ResultSegment[]` · hook validation matrix (wrong chainKey / wrong contract / wrong event sig / replay → all revert) · tier transitions incl. Platinum's `late == 0` rule · pool terms per tier, reentrancy, pause. A mocked prover is fine **in unit tests only** — the demo path uses the real precompile, always.

**Deploy runbook:** deploy order LoanBook (Sepolia) → tUSD, CreditTierSBT, CreditRegistry(prover, loanbook, chainKey), LendingPool(registry, tUSD) (CC3) → wire roles (registry↔SBT, pool funding) → verify all on both explorers → write `/deployments.json` → smoke-test e2e script → tag `v0.1-testnet`.

**Security checklist (also a deck slide — judges love this):** replay protection (`isQueryUsed`) ✅ · source authentication (chainKey + contract address + event topic) ✅ · in-contract success validation (precompile limitation handled) ✅ · SBT non-transferability enforced ✅ · reentrancy guards + CEI ✅ · pausable ✅ · test-only keys, secrets never committed ✅ · forked example code attributed ✅.

---

## 9. Demo video — shot-by-shot (≤ 3:30, judges decide in the first 30s)

- **0:00–0:20 — Cold open, no logo, no intro.** Split screen: LEFT `repay()` already confirmed on Sepolia Etherscan (**pre-attested** — see the timing note in §1); RIGHT the CreditRegistry event lands on CC3 Blockscout in one block and the tier badge flips Silver→Gold in the UI. Caption: *"A foreign transaction, cryptographically verified and acted on, in one Creditcoin block. No oracle. No bridge."* If you cut between the two, use an honest caption ("~9 min for Sepolia attestation") rather than implying it was instant.
- **0:20–0:50 — Problem.** Credit history is trapped per-chain → everyone posts 150% collateral → the underbanked stay locked out. One line on Creditcoin's mission (Aella, 2M+ borrowers) to show you're extending *their* thesis.
- **0:50–1:20 — How.** Architecture diagram. Say the magic words on camera: *"the native verifier precompile at 0x0FD2 checks a Merkle inclusion proof and a chain-continuity proof against Creditcoin's decentralized attestor network — synchronously, in-contract."*
- **1:20–2:30 — Live demo.** Fresh wallet (Bronze, 150%) → **Import History** → batch-verify 10 Sepolia events in ONE transaction (show the worker log + single CC3 tx) → score dial climbs → Platinum SBT (show the on-chain SVG) → Borrow screen now quotes **85% collateral** — borrow undercollateralized on camera.
- **2:30–2:50 — Trust, proven.** Submit a tampered proof → revert. Replay a used query → revert. *"We validate success and provenance in-contract, because the precompile intentionally doesn't."*
- **2:50–3:20 — Why it matters + ask.** Portable credit = the missing primitive for real-world DeFi. Roadmap: more source chains as attestation coverage grows, credit-delegation, real-asset pools. Close on CEIP framing: *"This is the cross-chain generalization of Creditcoin's proven lending business."*

Rules: everything live on real testnets, tx hashes visible, captions on (judges skim muted), 1080p, cut all dead air. Record terminal + browser at comfortable zoom.

---

## 10. Deck / whitepaper outline (10 slides → export PDF)

1. Title + one-liner + live testnet URL. 2. Problem (trapped credit history; 1.4B underbanked). 3. Why now (Attestcoin live on Creditcoin — trustless cross-chain facts). 4. Product (3 screenshots). 5. **Deep integration** (architecture + precompile call + batch verification + in-contract validation — mirror the judging criterion explicitly). 6. Demo results (real tx hashes, timings). 7. Market (emerging-market credit; Creditcoin's own traction as proof). 8. Business model (origination fee + spread; credit-data network effects). 9. Roadmap (chains, credit delegation, RWA pools, audit). 10. Solo builder + ask (CEIP fast-track).

---

## 11. Submission checklist (DoraHacks form ↔ assets)

Verified against the live DoraHacks form Aug 13, 2026. **Project Information:**

| Form field | Asset | Required? |
|---|---|---|
| Project Name | CrossCredit | ✔ |
| Project Logo (image URL — PNG/SVG/AI) | simple wordmark, GitHub raw | optional |
| Project Sector | DeFi (RWA in the narrative) | ✔ |
| Project Description | 150–250 words | ✔ |
| **Attestcoin Protocol Integration Summary** | §3.2/§5.3 condensed + contract addresses — **this is the field the #1 criterion is scored from; write it last and write it best** | ✔ |
| GitHub Repository URL (**must include a README**) | public repo; README = quickstart, diagram, addresses, demo GIF | ✔ |
| Project Deck or Whitepaper (PDF URL) | §10 exported, hosted (GitHub raw / Drive public) | ✔ |
| Prototype Demo Video URL | §9 on YouTube (unlisted OK) | ✔ |

**Team Information** (per member): First & Last Name · Email · Telegram (opt) · X/Twitter (opt) · LinkedIn (opt) · Résumé PDF URL (opt) · Short Bio · Role · Country of Residence · Country of Citizenship. Solo is explicitly allowed (*"Minimum team size: 1 member"*). Fill the optional social fields — **CEIP due diligence will look**.

**Completeness requirements** (quoted): *"Working Attestcoin Protocol integration code running within your project"* and *"Technical documentation detailing your setup and explaining how the project uses the Attestcoin Protocol"* → that second one is `docs/ATTESTCOIN_INTEGRATION.md`, and it is **mandatory, not optional polish**.

**Rules** (quoted): *"Must be original work created during the hackathon"* (clean Aug-13+ history, forks attributed) · *"Must be deployed on a testnet"* · *"Must integrate the Attestcoin Protocol as a core feature"* · *"Must respect and not infringe on third-party IP rights"* · all submitted info accurate and truthful.

**Prizes:** $15k pool — Grand **$10,000**, 2nd $3,000, 3rd $2,000. **Top three advance directly to CEIP due diligence.** All winners get CertiK benefits (8k audit credits, 3mo Skynet Boost). Grand-prize winner residing outside South Korea gets flight + hotel for CTC Ignition 2026 (Seoul, Sep 28). Winners announced **Sep 18**.

**Judging:** no weighted rubric is published. The only scoring statement on the page is *"Depth of Attestcoin Protocol utilization will be evaluated as one of the core scoring criteria."* Optimise for that sentence.

---

## 12. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rebrand broke docs/SDK names | High | Day-1 Verification Protocol; patterns are stable, adapt names; ask in Discord fast |
| Prover API / testnet flaky | Medium | Build retries early; capture successful runs on video as backup evidence; report outages in Discord (visible diligence) |
| Batch API undocumented/changed | Medium | Fallback: sequential ingestion; keep batch as protocol capability in narrative |
| G2 slips past Day 8 | Medium | Pre-planned scope cut: single-event loop + SBT + minimal UI is still a winnable submission |
| "Credit score looks toy" | Medium | Deterministic documented model + negative-path demo + honest roadmap slide (real underwriting later) |
| Solo burnout | Medium | Gates exist so *any* green-gate state is submittable; sleep before recording the video |

---

## 13. Link vault

- Hackathon: **`dorahacks.io/hackathon/buidl-ctc-2026-fall/detail`** ✅ (the `buidlctc-2026-fall` spelling is wrong) · AMA: `luma.com/buidlctc-fall26-ama` (Aug 18, 07:00 ET — host approval required, register early)
- Docs: `docs.creditcoin.org/attestcoin-protocol` (+ `/architecture`, `/attestcoin-protocol-chains-environments`, `/guided-tutorials`, `/dapp-builder-infrastructure/attestcoin-smart-contracts`, `/dapp-builder-infrastructure/attestcoin-sdk-usc-sdk`). **Append `.md` to any docs URL for clean markdown.** Legacy `/creditcoin-usc/*` 301s here; bare `/creditcoin-usc` 404s.
- RPC `https://rpc.cc3-testnet.creditcoin.network` (chainId 102031) · Explorer `https://creditcoin-testnet.blockscout.com` · Dashboard `https://dashboard.cc3-testnet.creditcoin.network/` · Prover `https://prover.cc3-testnet.creditcoin.network` · Subscan `https://creditcoin3-testnet.subscan.io/`
- Discord: `discord.gg/Gu43zTfmtc` (`token-faucet`, `#buidl-ctc-qna`) · Help: `team@creditcoin.org`
- GitHub: **`github.com/gluwa/usc-testnet-bridge-examples`** @ `4ff9a3bf` ✅ · `gluwa/cc-next-query-builder` (SDK source) · `gluwa/creditcoin3` (node) · Community Claude Code skill: `github.com/phamdat721101/creditcoin-dapp-skills`
- Companion docs in this folder: `CLAUDE_CODE_MASTER_PROMPT.md` (paste into Claude Code / save as CLAUDE.md) · `Winning_Strategy_BUIDL_CTC_2026_Fall.md` (research)

**Now open Claude Code and paste the master prompt. First milestone: Gate G0 — a verified proof round-trip — within 48 hours.**
