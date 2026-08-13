# CrossCredit — Claude Code Master Prompt

**How to use this file (3 steps):**
1. Create your project folder, drop `CrossCredit_Build_Guide.md` into `docs/BUILD_GUIDE.md`, and save THIS file as **`CLAUDE.md` in the repo root**. Claude Code auto-loads root `CLAUDE.md` at every session start, it survives `/clear` and compaction, so these rules govern every session without re-explaining.
2. Start Claude Code in that folder and paste the **Kickoff Message** (bottom of this file) as your first message.
3. Between phases, run `/clear`, then say: `Read PROGRESS.md and continue with the next phase per CLAUDE.md.`

---

## 1. Mission

You are the sole engineer (with me as operator) building **CrossCredit** for the BUIDL CTC 2026 Fall hackathon. Goal: **Grand Prize ($10k) + CEIP investment fast-track.**

⏰ **Deadline is disputed — we submit Sep 4.** The DoraHacks page prose says Sep 6, 23:59 ET, but the platform's own countdown is configured to **Sep 6, 04:59 UTC (= Sep 6, 00:59 ET)** — the submit button likely locks ~23h before the stated time. Eventbrite lists a third figure. Treat **Sep 4** as the real deadline until an organizer reconciles it.

CrossCredit = trustless cross-chain credit reputation + lending on Creditcoin:
- Users build repayment history in `LoanBook.sol` on **Ethereum Sepolia**.
- An off-chain **Oracle Worker** proves those transactions to Creditcoin via the **Attestcoin Protocol** (Merkle + continuity proofs verified by the native precompile — synchronously, in one CC3 block, no oracle operator, no bridge). Note: the in-block verification is ~15s, but a Sepolia block takes **~8–10 min to be attested** first. Never pitch "15 seconds end-to-end".
- `CreditRegistry.sol` (on **Creditcoin CC3 Testnet**) decodes verified events, updates a `CreditProfile`, computes a deterministic score, and syncs a **soulbound Credit Tier NFT** (ERC-721 + ERC-5192).
- `LendingPool.sol` prices loans by tier — Platinum borrows **undercollateralized (85%)**.

**The #1 judging criterion is depth of Attestcoin Protocol utilization.** Full product spec, architecture, scoring model, phase plan, and demo script live in `docs/BUILD_GUIDE.md` — read it before Phase 0 and re-read the relevant section before each phase.

## 2. Non-negotiables

1. **Never fake the integration in the demo path.** Mocked provers/precompiles are allowed in unit tests only, clearly isolated under `test/mocks/`. Everything user-facing runs against the real precompile on live CC3 testnet.
2. **Verify before trusting names.** §3 was verified against live docs, the npm registry and CC3 RPC probes on Aug 13, 2026 — it is no longer provisional. But the ecosystem is mid-rebrand and mid-migration: **always confirm a symbol against installed typings (`node_modules/@gluwa/usc-sdk/dist/*.d.ts`) or the pinned examples before depending on it.** If reality differs from §3: adapt the code, then update this CLAUDE.md and `docs/BUILD_GUIDE.md` in the same commit. Tutorial videos and blog posts are known-stale — the pinned repo and the live `.md` docs win.
3. **Original work window.** All product code is written from Aug 13 onward with clean, frequent, meaningful commits (conventional commits). Code adapted from official Gluwa examples gets explicit attribution in file headers + README. No copied third-party app code.
4. **Secrets discipline.** Private keys/API URLs only in `.env` (gitignored); maintain `.env.example`; the deployer key is test-only. Never print secrets in logs or commit them — if a secret ever lands in a commit, stop and tell me immediately.
5. **Scope discipline.** When behind schedule, cut UI polish and stretch features — never the verification depth (multi-event decoding, batch path, replay protection, negative tests, in-contract success validation).
6. **Ask, don't assume**, for anything requiring my human action: faucets, wallet funding, Discord questions, DoraHacks form, account signups, or spending anything.

## 3. Verified ground truth (locked Aug 13, 2026 — live docs, npm registry, CC3 RPC probes)

> ⛔ **The pre-2026 architecture is DEAD. Never use it.** `@gluwa/creditcoin-public-prover`,
> `Types.sol`/`Prover.sol`, `ResultSegment[]`, `_onQueryValidated`, `_processOracleResults`,
> `isQueryUsed`/`_markQueryUsed`, precompile `0x0Be9`, escrowed `submitQuery`/`getQueryResult` —
> all belong to the async STARK model that was removed in USC Testnet 2.0. If you see these
> names in a blog post, tutorial video, or older repo, you are reading stale material.

> 📛 **"Attestcoin" is prose-only branding.** Zero npm packages and zero GitHub repos carry the
> name; everything ships as `usc-*`, and the docs say so explicitly. Use "Attestcoin Protocol"
> in the pitch/README; use `usc-*` in every import, path and package name.

**Networks**
- Creditcoin **CC3 Testnet**: RPC `https://rpc.cc3-testnet.creditcoin.network`, EVM chainId **102031** (`0x18e8f`), ~15s blocks, baseFee ~500 gwei, block gasLimit 75M. Explorer `https://creditcoin-testnet.blockscout.com`. Dashboard `https://dashboard.cc3-testnet.creditcoin.network/`. Gas token tCTC via Discord `token-faucet` → `/faucet address:0x…`.
- **Source chains on CC3 testnet — there are TWO**: Ethereum Sepolia (**chainKey 1**) and Ethereum Mainnet (**chainKey 3**). `chainKey` is a Creditcoin-internal id, **not** the EVM chainId — never hardcode it; resolve via `getSupportedChains()` and treat `docs/evidence/supported-chains.json` as law. Our source chain is Sepolia; the registry **must** authenticate chainKey, because a contract at the same address on mainnet could otherwise spoof events.

**The verification primitive**
- **BlockProver precompile @ `0x0000000000000000000000000000000000000FD2`** (docs call this the "Block Prover Precompile"; the Solidity interface is still named `INativeQueryVerifier`):
  - `verify(uint64 chainKey, uint64 height, bytes encodedTransaction, MerkleProof, ContinuityProof) view returns (bool)` — **reverts on failure**, returns true on success. Never write `if (!verify(...))`; that branch is unreachable.
  - `verifyAndEmit(...)` — same args, non-view, emits `TransactionVerified(chainKey, height, txIndex)`. **All official examples use this**, not `verify`.
  - **Batch overload**: `verifyAndEmit(uint64 chainKey, uint64[] heights, bytes[] encodedTxs, MerkleProof[] proofs, ContinuityProof shared)` — **max 10 proofs, and all source blocks must fall within a 1000-block `MAX_BATCH_RANGE`.** That range cap shapes `seed-history.ts`: seeded events must land inside one 1000-block window to fit a single batch.
  - `calculateTxIndex(MerkleProof) view returns (uint64)`.
  - Structs: `MerkleProof { bytes32 root; MerkleProofEntry[] siblings; }`, `MerkleProofEntry { bytes32 hash; bool isLeft; }`, `ContinuityProof { bytes32 lowerEndpointDigest; bytes32[] roots; }`.
- **ChainInfo precompile @ `0x0000000000000000000000000000000000000fd3`**.
- **It does NOT validate transaction success** — docs state this in a danger callout. Our ASC must `require(receipt.receiptStatus == 1)` via `EvmV1Decoder.decodeReceiptFields()`. This is a headline credibility point in the demo.
- **Timing, corrected**: verification is synchronous in one CC3 block (~15s) — but only *after* the source block is attested. **Sepolia attestation lag is ~8–10 minutes** (`waitUntilHeightAttested` polls every 15s, 15min default timeout). The demo must pre-attest; do not claim end-to-end 15s.

**Packages (exact pins)**
- **`@gluwa/usc-sdk@0.18.0`** — TS, ethers `^6.15` as a regular dep. Exports are **namespaces, not flat classes**: `chainInfo.PrecompileChainInfoProvider` (`.getSupportedChains()`), `blockProver.PrecompileBlockProver` (`computeTransactionIndex`, `verifySingle`, `verifyAndEmitSingle`, `verifyBatch`, `verifyAndEmitBatch`), **`proofProvider.service.ProofBuilder(chainKey, proofBuilderUrl)`** (`getProof`, `getBatchProof`; there is no `ProverAPIProofGenerator`), `utils.mergeProofs`, `waitUntilHeightAttested`.
- **`@gluwa/usc-contracts@0.1.2`** — Solidity. `contracts/write-ability/INativeQueryVerifier.sol`, `contracts/decoding/EvmV1Decoder.sol` (a **library** — imported and inlined; the deployed instance at `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` on CC3 is only an off-chain debugging aid).
- **Proof builder API**: `https://prover.cc3-testnet.creditcoin.network` (alias `https://proof-gen-api.cc3-testnet.creditcoin.network/`; swagger at `/api/swagger/`).

**The contract pattern (what we actually implement)**
`USCBase.sol` is **vendored in the examples repo, not shipped in the npm package** — we vendor it into `contracts/src/vendored/` with attribution:
```
execute(uint8 action, uint64 chainKey, uint64 blockHeight, bytes encodedTransaction,
        bytes32 merkleRoot, MerkleProofEntry[] siblings,
        bytes32 lowerEndpointDigest, bytes32[] continuityRoots) external returns (bool)
  → txIndex = VERIFIER.calculateTxIndex(merkleProof)
  → queryId = keccak256(abi.encodePacked(chainKey, blockHeight, txIndex))
  → replay guard: mapping(bytes32 => bool) public processedQueries   (no isQueryUsed helper)
  → VERIFIER.verifyAndEmit(...)
  → hook: _processAndEmitEvent(uint8 action, bytes32 queryId, bytes encodedTransaction) internal virtual
```
Data is decoded **directly from `encodedTransaction`** via `EvmV1Decoder` — there is no prover contract and no async query lifecycle.

**Docs & examples**
- Live docs: `docs.creditcoin.org/attestcoin-protocol` (+ `/architecture`, `/attestcoin-protocol-chains-environments`, `/guided-tutorials`, `/dapp-builder-infrastructure/{attestcoin-smart-contracts, attestcoin-sdk-usc-sdk}`). Every legacy `/creditcoin-usc/*` URL 301s here; the bare `/creditcoin-usc` 404s. **Appending `.md` to any docs URL returns clean markdown** — use that for scripted reads.
- Examples repo: **`gluwa/usc-testnet-bridge-examples`** @ pinned commit `4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b` (actively maintained). Toolchain: **Foundry** (solc 0.8.30, optimizer 200, `via_ir=false`, evm `shanghai`, `libs=["node_modules"]`), yarn 1.22.22, OZ 5.4.0, ethers ^6.17.
  **Four** tutorials in order: **Hello Bridge → Custom Contracts Bridging → Bridge Offchain Worker → Loan Flow**. `loan-flow` (`USCLoanManager.sol`) is architecturally closest to CrossCredit — study it and attribute it, don't copy it.
  `gluwa/ccnext-testnet-bridge-examples` is the superseded predecessor — do not use.
- **Faucet economics: not a constraint.** The examples' README claims "100 tCTC ≈ 9 oracle queries", but that line is stale. A real bridge `execute()` measures **~393k gas at 0.5 gwei ≈ 0.0002 CTC**. Our wallet holds 10,000 tCTC — effectively unlimited queries. Iterate freely on live testnet; do not design around a query budget.

## 4. Repository layout (scaffold in Phase 0)

```
crosscredit/
├─ CLAUDE.md                    # this file
├─ PROGRESS.md                  # session log: done / next / blockers / addresses (update EVERY session end)
├─ docs/
│  ├─ BUILD_GUIDE.md            # full spec (authoritative)
│  ├─ ATTESTCOIN_INTEGRATION.md # REQUIRED submission doc — grows with every integration step
│  ├─ SCORING.md                # scoring constants + rationale
│  └─ evidence/                 # supported-chains.json, screenshots, tx hashes
├─ foundry.toml + remappings.txt # one Foundry project at repo root (solc 0.8.30, evm shanghai)
├─ contracts/
│  ├─ src/sepolia/LoanBook.sol
│  ├─ src/creditcoin/{CreditRegistry.sol, ScoreLib.sol, CreditTierSBT.sol, LendingPool.sol, TUSD.sol}
│  ├─ src/vendored/            # attributed upstream USCBase + verifier interface (pinned 4ff9a3bf)
│  ├─ test/{mocks/, fixtures/, fork/}
│  └─ script/                  # forge deploy scripts
├─ worker/                      # TS + ethers v6 + SDK: watch & backfill(batch) modes, state.json, pretty logs
├─ web/                         # Vite + React + wagmi/viem + Tailwind: Dashboard / Import History / Borrow
├─ scripts/                     # check-chains.ts, seed-history.ts, deploy/*, e2e-smoke.ts
├─ deployments.json             # chain → contract → address (+ explorer links)
└─ .env.example
```

`.env.example` keys: `SEPOLIA_RPC_URL`, `CC3_RPC_URL`, `DEPLOYER_PRIVATE_KEY` (test-only), `PROVER_API_URL`, `LOANBOOK_ADDRESS`, `CREDIT_REGISTRY_ADDRESS`, `TIER_SBT_ADDRESS`, `LENDING_POOL_ADDRESS`, `TUSD_ADDRESS`, `DEMO_BORROWER_ADDRESS`.

## 5. Engineering standards

- **Solidity 0.8.24+**, NatSpec on all public interfaces; OpenZeppelin for ERC-20/721/Ownable/ReentrancyGuard/Pausable; custom errors over strings.
- **TDD for contracts**: write failing tests first. Required negative-test matrix: wrong chainKey / wrong source contract / wrong event sig / replayed queryId / tampered payload → all revert; fuzz ScoreLib caps & floors; Platinum requires `late == 0`; pool reentrancy + pause.
- TypeScript strict; small pure functions in the worker (attest-wait → proof → submit → record), idempotent by txHash, exponential backoff, demo-worthy logs (`✓ attested`, `✓ proof fetched`, `✓ verified on CC3 block #…`).
- Every feature lands with: code + tests green + a line in `docs/ATTESTCOIN_INTEGRATION.md` (if it touches the protocol) + updated `deployments.json` (if it deploys) + a conventional commit.
- Definition of done for the project = every DoraHacks form field in `docs/BUILD_GUIDE.md` §11 has a working asset URL.

## 6. Phase plan & gates (details in BUILD_GUIDE §6 — hold me to the gates)

- **P0 Verify (Aug 13–14):** Verification Protocol below → Tutorial 1 end-to-end → scaffold + CI. **G0: real proof round-trip.**
- **P1 Source (Aug 15–16):** LoanBook + tests → deploy Sepolia → seed 9–10 mixed events. **G1: history on Etherscan.**
- **P2 Core (→ Aug 20):** CreditRegistry single-event loop, live. **G2 (make-or-break): Sepolia repay → verified → score changes on CC3.** If G2 slips: freeze features, cut to the single-event loop + SBT + minimal UI, and tell me to escalate in Discord.
- **P3 Depth (→ Aug 25):** all 3 event types · **batch ≤10** · ScoreLib · SBT (on-chain SVG) · LendingPool tiers · negative-path repro script. **G3: full loop headless.** (Batch API blocked >1 day → sequential fallback, batch stays in narrative.)
- **P4 Frontend/polish (→ Aug 30):** 3 screens vs live testnet · NatSpec/docs pass. **G4: stranger runs demo from README in <10 min; happy path in one take.**
- **P5 Deliverables (→ Sep 2):** demo video per BUILD_GUIDE §9 · deck PDF §10 · README final. **G5: all assets are URLs.**
- **P6 Submit (Sep 4–5):** submit on DoraHacks, verify links incognito + mobile.

## 7. Phase 0 Verification Protocol — ✅ EXECUTED Aug 13, 2026

Findings are locked into §3 above and logged in `PROGRESS.md`. Re-run steps 3–4 if anything on
testnet starts behaving unexpectedly; the rest is settled.

1. ✅ npm registry queried — `@gluwa/usc-sdk@0.18.0` + `@gluwa/usc-contracts@0.1.2` are current; `@gluwa/creditcoin-public-prover` is the dead architecture; no `attestcoin` package exists.
2. ✅ Live docs read — precompile `0x…0FD2`, ChainInfo `0x…0fd3`, prover API URL, batch limits (10 / 1000 blocks), success-validation caveat, four tutorials.
3. ⏳ `scripts/check-chains.ts` → `docs/evidence/supported-chains.json`. **That file is law for source chains.**
4. ✅ CC3 chainId 102031 + explorer confirmed by live RPC probe. ⏳ Wallet funding is an operator action — see `docs/HUMAN_ACTIONS.md`.
5. ✅ Examples pinned at `4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b`; noted in vendored file headers + README.
6. ✅ All ⚠️ replaced. Residual unknowns are drafted as Discord/AMA questions in `PROGRESS.md`.

## 8. Session workflow

- Start: read `PROGRESS.md` → state the phase, gate, and this session's plan in ≤5 bullets → await my "go" only if the plan spends funds or changes scope; otherwise proceed.
- During: run tests/commands yourself; show me failures with your fix, not just errors.
- End: update `PROGRESS.md` (done / next / blockers / new addresses / open ⚠️), commit everything.
- If any live-testnet step fails 3 attempts (faucet dry, RPC down, prover API errors): document in PROGRESS.md with evidence, give me the Discord-ready question, and continue on non-blocked work.

---

## 9. KICKOFF MESSAGE — paste this as your first Claude Code message

```
Read CLAUDE.md fully, then docs/BUILD_GUIDE.md (skim all, read §3, §5, §6, §7 closely).

We are at Phase 0, Day 1 of 23. Execute in this order:

1. Run the Phase 0 Verification Protocol (CLAUDE.md §7). Produce docs/evidence/supported-chains.json and a "verified ground truth" summary table (package names, precompile address, prover API URL, chainKeys, tutorial repo URLs). Replace the ⚠️ marks in CLAUDE.md and docs/BUILD_GUIDE.md with verified values.
2. Tell me exactly what human actions you need from me right now (faucet links for tCTC + Sepolia ETH, wallet setup, anything else), as a short checklist.
3. Scaffold the monorepo per CLAUDE.md §4 (match the toolchain the official Gluwa examples use), with lint + test CI, .env.example, PROGRESS.md, and an initial commit.
4. Clone the official tutorial examples and run Tutorial 1 (Hello Bridge) end-to-end against CC3 testnet with my configured wallet. Capture evidence (tx hashes, logs) into docs/evidence/. This is Gate G0.
5. Finish by updating PROGRESS.md and listing: G0 status, any ⚠️ still unresolved, the drafted Discord questions if needed, and the Phase 1 plan.

Constraints reminder: real testnets only, test-only keys from .env, commit early and often, and if the docs contradict CLAUDE.md — the live docs win, update our files to match.
```
