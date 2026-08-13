# CrossCredit — Complete Build Guide
### BUIDL CTC 2026 Fall · "BUIDL For The Real World" · Target: Grand Prize + CEIP Fast-Track

> **One-liner:** A trustless, cross-chain credit-reputation and lending protocol on Creditcoin. Borrowers prove their repayment history on Ethereum Sepolia via the Attestcoin Protocol's native verifier precompile; CrossCredit converts verified history into an on-chain credit score + soulbound Credit Tier NFT, which unlocks progressively better (eventually undercollateralized) loan terms in a lending pool on Creditcoin.
>
> **Tracks:** DeFi (primary) + RWA (narrative) · **Team:** solo + Claude Code · **Window:** Aug 13 → Sep 6, 2026 (submit Sep 5)

---

## ⚠️ Read this first — the two rules that decide everything

1. **Attestcoin depth is a core scoring criterion.** Every architectural decision below exists to make the Attestcoin Protocol *load-bearing*: multiple attested event types, batch verification, in-contract decoding, replay protection, and a visible invalid-proof rejection path. Never cut these. Cut UI polish instead.
2. **Verify before you trust.** The USC → Attestcoin Protocol rebrand is recent. Every identifier marked ⚠️ in this guide (package names, class names, precompile address, RPC URLs, prover API) comes from the research pass and **must be re-verified against the live docs and installed package typings on Day 1** before any code depends on it. The *patterns* are stable; the *names* may have shifted.

---

## 1. What we're building (and why it wins)

**The problem.** On-chain credit history is trapped per-chain. A borrower with a flawless repayment record on Ethereum is a stranger on Creditcoin — so every protocol demands 150%+ overcollateralization, which locks the underbanked out of DeFi credit entirely. This is precisely the problem Creditcoin was founded to solve (RWA credit for emerging markets — Aella's 100B+ Naira disbursed to 2M+ Nigerians runs on this thesis).

**The insight.** The Attestcoin Protocol makes foreign-chain facts *natively verifiable* inside a Creditcoin smart contract — no oracle operator, no bridge multisig. That means credit reputation can finally become **portable and trustless**. CrossCredit is the cross-chain generalization of Creditcoin's own proven business.

**The demo moment (build everything around this):** a user repays a loan on Sepolia → ~15 seconds later, in a single Creditcoin block, the proof verifies, their score updates, their Credit Tier SBT upgrades, and their collateral requirement visibly drops. Then: batch-verify 10 historical events in one transaction. Then: watch a forged proof get rejected.

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
  - **Creditcoin CC3 Testnet** — RPC `https://rpc.cc3-testnet.creditcoin.network`, chainId **102031**, symbol tCTC, explorer: Creditcoin Blockscout (⚠️ confirm exact explorer URL from docs).
  - **Ethereum Sepolia** — chainId **11155111**.
- [ ] Install locally: Node 20+, pnpm, Git, Foundry *and/or* Hardhat (final choice in Phase 0 — match whatever the official example repos use, likely Hardhat + TypeScript).
- [ ] Clone reference repos: `gluwa/usc-testnet-bridge-examples`, `gluwa/ccnext-testnet-bridge-examples` (⚠️ names may have moved post-rebrand — search the `gluwa` GitHub org for "attestcoin" too).
- [ ] Optional accelerator: install the community **Creditcoin dApp Skill** for Claude Code (`github.com/phamdat721101/creditcoin-dapp-skills`). It's community-built, not official — audit everything it generates.
- [ ] Create the GitHub repo **on Aug 13** and commit the scaffold immediately — a clean commit history starting inside the hackathon window is your originality evidence.

---

## 3. Ground-truth technical reference (verify ⚠️ items Day 1)

### 3.1 Networks
| | Creditcoin CC3 Testnet | Ethereum Sepolia (source chain) |
|---|---|---|
| Role | Where CrossCredit lives (ASC + pool + SBT) | Where credit history happens (LoanBook) |
| EVM chainId | **102031** | **11155111** |
| Attestcoin chainKey | n/a (destination) | **1** ⚠️ |
| RPC | `https://rpc.cc3-testnet.creditcoin.network` ⚠️ | Any Sepolia RPC (Alchemy/Infura) |
| Gas token | tCTC (Discord faucet) | SepoliaETH |

**Sepolia is the only source chain confirmed live.** Design for deep single-source integration (many event types). If `getSupportedChains()` reveals more live chains on Day 1, a second source chain is a stretch goal only after the Sepolia path is flawless.

### 3.2 The Attestcoin verification primitive
- Native verifier **precompile at `0x0FD2`** ⚠️ on Creditcoin. Canonical call: `verify(chainKey, blockHeight, encodedTx, merkleProof, continuityProof) → bool`.
- It validates **inclusion** (Merkle proof) + **chain continuity** (link to on-chain attestation by the decentralized attestor network). It executes **synchronously, in one block (~15s)**.
- **It does NOT validate transaction success.** Your contract must decode the payload and enforce success/semantics itself. (We demo this understanding explicitly — it earns credibility.)
- **Batch verification: up to 10 queries sharing one continuity proof** ⚠️ — our "import your whole history in one tx" feature.
- Inbound/read-oriented on testnet. "Writing to" Sepolia = our own off-chain worker sending a normal Sepolia tx. **Never claim native outbound messaging in the pitch — it's roadmap.**

### 3.3 SDK & contract packages (⚠️ all names need Day-1 verification against npm + live docs)
- **`@gluwa/usc-sdk`** (TypeScript, requires **ethers v6**):
  - `PrecompileChainInfoProvider` — query supported chains / attestation state (`getSupportedChains()`).
  - `ProverAPIProofGenerator` — fetch pre-computed proofs from the hosted Prover API (recommended path; note the API base URL from docs into `.env`).
  - `PrecompileBlockProver` — submit proofs on-chain.
  - `waitUntilHeightAttested` — poll (default 15s) until a source block is attested.
- **`@gluwa/creditcoin-public-prover`** Solidity package — `Types.sol`, `Prover.sol`; the Core-contract pattern:
  - `_processOracleResults(address proverContract, uint256 queryId)` entrypoint
  - `isQueryUsed` / `_markQueryUsed` replay protection
  - `_onQueryValidated(...)` hook receiving an array of ABI-encoded **`ResultSegment`s** (`bytes32` values you decode to `address`/`uint256`/`bool`)
  - `MintableUSCBridge` extension exists (reference only; we don't need it).
- **Pattern:** a Core ASC contract (inherits the Gluwa base) + a Business-Logic contract implementing the hook + an **off-chain Oracle Worker** so the end user signs only once.
- Docs entry points: `docs.creditcoin.org/attestcoin-protocol` (new) and `docs.creditcoin.org/creditcoin-usc/*` (legacy: chains-environments, guided-tutorials, usc-sdk). Follow the three official tutorials in order: **Hello Bridge → Custom Contracts Bridging → Bridge Off-chain Worker.**

---

## 4. System architecture

```
        ETHEREUM SEPOLIA (chainKey 1)                    CREDITCOIN CC3 TESTNET (102031)
┌─────────────────────────────────┐          ┌──────────────────────────────────────────────┐
│  LoanBook.sol                   │          │  Attestcoin verifier precompile @ 0x0FD2 ⚠️   │
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
- **Backfill mode:** `pnpm worker:backfill --address 0x... --from-block N` → collect up to 10 unprocessed events → **batch proof** (shared continuity proof ⚠️ verify SDK batch API shape) → one submission tx. This powers "Import my history."
- Reliability: idempotent by txHash, exponential backoff, clear structured logs (the logs appear in the demo video — make them pretty: `✓ attested`, `✓ proof fetched`, `✓ verified on CC3 in block #…`).
- Config via `.env` only. Never hardcode keys.

### 5.3 `CreditRegistry.sol` (CC3) — the ASC core
- Inherits/adapts the Gluwa Core pattern (`_processOracleResults`, `isQueryUsed`/`_markQueryUsed`, `_onQueryValidated`).
- **In-hook validation (this is the "depth" judges score):**
  1. `chainKey == 1` (Sepolia) — reject anything else.
  2. Emitting contract == immutable `LOANBOOK` address.
  3. Event signature ∈ {LoanOpened, RepaymentMade, CollateralAdded} topic hashes.
  4. Decode `ResultSegment[]` → typed struct; **enforce success semantics in-contract** (precompile doesn't).
  5. Replay-guard the query id; emit `HistoryEventIngested(borrower, kind, txHash)`.
- Storage: `mapping(address => CreditProfile)` where `CreditProfile { uint256 totalRepaidWei; uint32 onTime; uint32 late; uint32 loansOpened; uint32 loansClosed; uint64 firstSeen; uint16 score; }`.
- After each ingest: `score = ScoreLib.compute(profile)` → `tierSBT.sync(borrower, tierFor(score, profile))`.

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

### Phase 6 — Submit early (Days 22–23, Sep 4–5)
- Submit on DoraHacks **Sep 5** (treat the listed Sep 6, 23:59 ET deadline as buffer, and re-check the countdown on the DoraHacks page itself — platform headers render in local time).
- Verify every link from an incognito window + your phone. Post the project in Discord.

---

## 7. Day-1 Verification Protocol (run before writing any product code)

1. `npm view @gluwa/usc-sdk` (+ search npm for `attestcoin`) → lock real package names/versions.
2. Fetch `docs.creditcoin.org/attestcoin-protocol` and the three legacy `creditcoin-usc` URLs → note renames; record the **Prover API base URL** and **precompile address** as documented *today*.
3. Script `scripts/check-chains.ts`: connect to CC3 RPC → `getSupportedChains()` → commit the JSON output to `/docs/evidence/supported-chains.json`. **This output is law** for which source chains you may use.
4. Confirm CC3 RPC + chainId 102031 + explorer URL; confirm faucet works (balance > 0).
5. Locate current official example repos in the `gluwa` GitHub org (search "usc" and "attestcoin"); pin commit hashes you fork from (attribution + originality clarity).
6. Update this guide + `CLAUDE.md` + `.env.example` with verified values. Anything still ⚠️ after Day 1 gets a Discord question.

---

## 8. Testing, deployment & security

**Tests (Foundry/Hardhat):** ScoreLib math (fuzz the caps/floors) · segment decoding from fixture-encoded `ResultSegment[]` · hook validation matrix (wrong chainKey / wrong contract / wrong event sig / replay → all revert) · tier transitions incl. Platinum's `late == 0` rule · pool terms per tier, reentrancy, pause. A mocked prover is fine **in unit tests only** — the demo path uses the real precompile, always.

**Deploy runbook:** deploy order LoanBook (Sepolia) → tUSD, CreditTierSBT, CreditRegistry(prover, loanbook, chainKey), LendingPool(registry, tUSD) (CC3) → wire roles (registry↔SBT, pool funding) → verify all on both explorers → write `/deployments.json` → smoke-test e2e script → tag `v0.1-testnet`.

**Security checklist (also a deck slide — judges love this):** replay protection (`isQueryUsed`) ✅ · source authentication (chainKey + contract address + event topic) ✅ · in-contract success validation (precompile limitation handled) ✅ · SBT non-transferability enforced ✅ · reentrancy guards + CEI ✅ · pausable ✅ · test-only keys, secrets never committed ✅ · forked example code attributed ✅.

---

## 9. Demo video — shot-by-shot (≤ 3:30, judges decide in the first 30s)

- **0:00–0:20 — Cold open, no logo, no intro.** Split screen: LEFT `repay()` confirms on Sepolia Etherscan; RIGHT ~15s later CreditRegistry event on CC3 Blockscout + tier badge flips Silver→Gold in the UI. Caption: *"A foreign transaction, cryptographically verified and acted on, in one Creditcoin block. No oracle. No bridge."*
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

| Form field | Asset |
|---|---|
| Project name / sector | CrossCredit · DeFi |
| Description + **Attestcoin Integration Summary** | 150–250 words each; integration summary = §3.2/§5.3 condensed with contract addresses |
| GitHub URL (README required) | Public repo, README with quickstart, diagram, addresses, demo GIF |
| Deck/whitepaper PDF URL | §10 exported, hosted (GitHub raw / Drive public) |
| Demo video URL | §9 on YouTube (unlisted OK) |
| Testnet deployment | All addresses linked to both explorers in README + form |
| Team info | Name, email, country, bio, role; Telegram/X/LinkedIn recommended (CEIP will look) |

Also required by rules: original work in-window (clean Aug-13+ history, forks attributed), no third-party IP infringement, truthful info.

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

- Hackathon: `dorahacks.io/hackathon/buidlctc-2026-fall` (via your DoraHacks dashboard) · AMA: `luma.com/buidlctc-fall26-ama`
- Docs: `docs.creditcoin.org/attestcoin-protocol` · `docs.creditcoin.org/creditcoin-usc` (+ `/usc-chains-environments`, `/guided-tutorials`, `/dapp-builder-infrastructure/usc-sdk`)
- RPC: `https://rpc.cc3-testnet.creditcoin.network` (chainId 102031) · Discord: `discord.gg/Gu43zTfmtc` · Help: `team@creditcoin.org`
- GitHub: `github.com/gluwa` (search usc / attestcoin / bridge-examples) · Community Claude Code skill: `github.com/phamdat721101/creditcoin-dapp-skills`
- Companion docs in this folder: `CLAUDE_CODE_MASTER_PROMPT.md` (paste into Claude Code / save as CLAUDE.md) · `Winning_Strategy_BUIDL_CTC_2026_Fall.md` (research)

**Now open Claude Code and paste the master prompt. First milestone: Gate G0 — a verified proof round-trip — within 48 hours.**
