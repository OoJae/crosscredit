# CrossCredit — Claude Code Master Prompt

**How to use this file (3 steps):**
1. Create your project folder, drop `CrossCredit_Build_Guide.md` into `docs/BUILD_GUIDE.md`, and save THIS file as **`CLAUDE.md` in the repo root**. Claude Code auto-loads root `CLAUDE.md` at every session start, it survives `/clear` and compaction, so these rules govern every session without re-explaining.
2. Start Claude Code in that folder and paste the **Kickoff Message** (bottom of this file) as your first message.
3. Between phases, run `/clear`, then say: `Read PROGRESS.md and continue with the next phase per CLAUDE.md.`

---

## 1. Mission

You are the sole engineer (with me as operator) building **CrossCredit** for the BUIDL CTC 2026 Fall hackathon (deadline **Sep 6, 2026, 23:59 ET — we submit Sep 5**). Goal: **Grand Prize ($10k) + CEIP investment fast-track.**

CrossCredit = trustless cross-chain credit reputation + lending on Creditcoin:
- Users build repayment history in `LoanBook.sol` on **Ethereum Sepolia**.
- An off-chain **Oracle Worker** proves those transactions to Creditcoin via the **Attestcoin Protocol** (Merkle + continuity proofs verified by the native precompile, ~15s, no oracle operator, no bridge).
- `CreditRegistry.sol` (on **Creditcoin CC3 Testnet**) decodes verified events, updates a `CreditProfile`, computes a deterministic score, and syncs a **soulbound Credit Tier NFT** (ERC-721 + ERC-5192).
- `LendingPool.sol` prices loans by tier — Platinum borrows **undercollateralized (85%)**.

**The #1 judging criterion is depth of Attestcoin Protocol utilization.** Full product spec, architecture, scoring model, phase plan, and demo script live in `docs/BUILD_GUIDE.md` — read it before Phase 0 and re-read the relevant section before each phase.

## 2. Non-negotiables

1. **Never fake the integration in the demo path.** Mocked provers/precompiles are allowed in unit tests only, clearly isolated under `test/mocks/`. Everything user-facing runs against the real precompile on live CC3 testnet.
2. **Verify before trusting names.** The protocol was recently rebranded (USC → Attestcoin). Every SDK class, package name, precompile address, RPC and API URL in this file is research-derived and marked provisional until Phase 0 confirms it against live docs + installed typings. If reality differs: adapt the code, then update this CLAUDE.md and `docs/BUILD_GUIDE.md` in the same commit.
3. **Original work window.** All product code is written from Aug 13 onward with clean, frequent, meaningful commits (conventional commits). Code adapted from official Gluwa examples gets explicit attribution in file headers + README. No copied third-party app code.
4. **Secrets discipline.** Private keys/API URLs only in `.env` (gitignored); maintain `.env.example`; the deployer key is test-only. Never print secrets in logs or commit them — if a secret ever lands in a commit, stop and tell me immediately.
5. **Scope discipline.** When behind schedule, cut UI polish and stretch features — never the verification depth (multi-event decoding, batch path, replay protection, negative tests, in-contract success validation).
6. **Ask, don't assume**, for anything requiring my human action: faucets, wallet funding, Discord questions, DoraHacks form, account signups, or spending anything.

## 3. Provisional ground truth (confirm in Phase 0, then delete the ⚠️ marks)

- Creditcoin **CC3 Testnet**: RPC `https://rpc.cc3-testnet.creditcoin.network` ⚠️, EVM chainId **102031**, gas token tCTC (Discord faucet), Blockscout explorer ⚠️.
- Source chain: **Ethereum Sepolia**, chainId 11155111, Attestcoin **chainKey 1** ⚠️. Treat Sepolia as the ONLY live source chain unless `getSupportedChains()` proves otherwise.
- Verifier **precompile @ `0x0FD2`** ⚠️: `verify(chainKey, blockHeight, encodedTx, merkleProof, continuityProof) → bool`. Verifies inclusion + continuity ONLY — **it does not check tx success; our contracts must**. Sync, ~1 block (~15s). **Batch: up to 10 queries sharing a continuity proof** ⚠️.
- SDK **`@gluwa/usc-sdk`** ⚠️ (TS, ethers v6): `PrecompileChainInfoProvider.getSupportedChains()`, `ProverAPIProofGenerator` (hosted Prover API — capture base URL from docs), `PrecompileBlockProver`, `waitUntilHeightAttested` (15s poll).
- Solidity base **`@gluwa/creditcoin-public-prover`** ⚠️ (`Types.sol`, `Prover.sol`): Core pattern = `_processOracleResults(proverContract, queryId)` + `isQueryUsed`/`_markQueryUsed` + `_onQueryValidated(...)` hook receiving ABI-encoded `ResultSegment[]` (bytes32 → address/uint/bool).
- Docs: `docs.creditcoin.org/attestcoin-protocol` (new) and `docs.creditcoin.org/creditcoin-usc/{usc-chains-environments, guided-tutorials, dapp-builder-infrastructure/usc-sdk}` (legacy). Official tutorials in order: **Hello Bridge → Custom Contracts Bridging → Bridge Off-chain Worker** (repos: `gluwa/usc-testnet-bridge-examples`, `gluwa/ccnext-testnet-bridge-examples` ⚠️ — search the gluwa org for post-rebrand names).

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
├─ contracts/                   # Hardhat or Foundry — match the official examples (decide Phase 0)
│  ├─ sepolia/LoanBook.sol
│  └─ creditcoin/{CreditRegistry.sol, ScoreLib.sol, CreditTierSBT.sol, LendingPool.sol, TUSD.sol}
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

## 7. Phase 0 Verification Protocol (do this before ANY product code)

1. `npm view @gluwa/usc-sdk` and search npm for `attestcoin` → record real package names + versions.
2. Fetch `docs.creditcoin.org/attestcoin-protocol` + the three legacy USC pages → record today's precompile address, Prover API base URL, contract package names, tutorial repo links.
3. Write + run `scripts/check-chains.ts` against CC3 → commit output to `docs/evidence/supported-chains.json`. **That file is law for source chains.**
4. Confirm CC3 chainId (102031) & explorer; confirm my wallet has tCTC + SepoliaETH (if not, STOP and give me the exact faucet steps).
5. Pin the exact commit of any Gluwa example you fork; note it in file headers.
6. Replace every ⚠️ in this file + BUILD_GUIDE with verified values (single commit: `chore: lock verified attestcoin ground truth`). Anything unresolvable → draft me a precise question for `#buidl-ctc-qna`.

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
