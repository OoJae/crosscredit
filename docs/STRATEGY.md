# Winning Strategy — BUIDL CTC 2026 Fall ("BUIDL For The Real World")

## TL;DR
- **Build one champion project: "CrossCredit" — a trustless, cross-chain, undercollateralized lending protocol that verifies a borrower's repayment/collateral history on Ethereum (Sepolia) using the Attestcoin Protocol's native verifier precompile, converts it into an on-chain credit score / soulbound reputation tier on Creditcoin, and unlocks better loan terms accordingly.** It maps to the DeFi *and* RWA tracks, sits exactly on Creditcoin's founding mission (on-chain credit for the underbanked), and uses Attestcoin as its irreplaceable core — not a bolt-on.
- **The single most important technical constraint that should shape every idea: on the current testnet, the Attestcoin Protocol is effectively READ/VERIFY-ONLY, and Ethereum Sepolia (chainKey 1, chainId 11155111) is the only source chain you can rely on being live.** Design a demo that proves an event on Sepolia and triggers Creditcoin-side business logic in one ~15-second block — do not promise native "write to any chain" outbound messaging you cannot demo.
- **Win condition = depth of Attestcoin integration (an explicit core scoring criterion) × a flawless 3-minute demo video × a credible "this is a fundable startup" narrative for the CEIP fast-track.** A solo builder with Claude Code can realistically ship this in 23 days by starting from Gluwa's official bridge examples and the `@gluwa/usc-sdk`, and by reusing the loan-repayment-verification pattern Creditcoin itself already documents.

---

## Key Findings

**1. What the Attestcoin Protocol actually is (and what it is not).** Attestcoin Protocol is the rebrand of Universal Smart Contracts (USC). Per the Creditcoin docs, it is "a general-purpose cross-chain execution layer built into Creditcoin's runtime" that lets **Attestcoin Smart Contracts (ASC)** "natively read, verify, and act on data from any supported chain, without trusting a bridge or oracle operator." Trust is distributed across a decentralized network of independent **attestors**; **provers** supply Merkle + continuity proofs; a **native precompile at address `0x0FD2`** verifies them. The canonical developer-facing function is `verify(chainKey, blockHeight, encodedTx, merkleProof, continuityProof) → bool`.

**2. It is inbound/read-oriented today.** My verification pass confirmed the precompile is a boolean *verifier* of inbound proofs: it "validates two proofs: a Merkle proof for transaction inclusion in a block, and a continuity proof linking that block to an on-chain attestation." Critically, the docs state: *"The native verifier precompile does not validate if a transaction was successful or not. It only validates if a transaction is included in a block and that block is really a part of the confirmed source chain."* So **your ASC must itself check success/decode the event data**. "Writing to" another chain in practice means *your own off-chain Oracle Worker submits a transaction to a source-chain contract you deployed* — an app-layer pattern you build, not a single native outbound-messaging call. The hackathon copy adds "and messaging," but on testnet that still resolves to attested-inbound-data + Creditcoin-side execution. **Plan your demo around inbound verification; treat outbound messaging as roadmap.**

**3. Speed & batching are the "wow" primitives.** Verification "completes in one block (~15 seconds)… synchronously… same transaction," with **batch query verification supporting up to 10 queries that share a continuity proof.** In USC v2 this replaced the old STARK flow (previously 6–20 minutes; Cairo/STARK complexity; multi-step async) with "<15 sec… Standard Solidity/Rust… Single function call." This is your headline demo moment: *"a foreign transaction validated, decoded, and used in dApp execution within a single Creditcoin block."*

**4. Supported source chains are narrow right now.** The SDK's `getSupportedChains()` documented output shows exactly one confirmed entry: `{ chainKey: 1, chainId: 11155111, chainName: 'Ethereum Sepolia', chainEncoding: 1 }` — used on both "USC Testnet2 and CC3 Testnet." BNB/BSC appears only as a *schema example* (`bsc-testnet`) in the `gluwa/creditcoin-usc-networks` README and in marketing/Wormhole-token contexts; Bitcoin, Polygon, and Solana are described as roadmap ("Phase 2… other L1 blockchains, such as Bitcoin and Ethereum"). **Actionable:** before committing to a multi-chain narrative, call `getSupportedChains()` against `https://rpc.cc3-testnet.creditcoin.network` on Day 1. If only Sepolia is live, design a *deep* single-source-chain integration (many event types) rather than a shallow multi-chain one — depth is what's scored.

**5. Concrete developer surface you'll actually use.**
- **Networks:** Creditcoin CC3 Testnet — RPC `https://rpc.cc3-testnet.creditcoin.network` (EVM chainId **102031**; native/Substrate side chainId 102030), Blockscout explorer, tCTC gas from the Discord faucet. Older USC v2 testnet RPC `https://rpc.usc-testnet.creditcoin.network` was deprecated in favor of CC3 — **build on CC3**.
- **SDK:** `@gluwa/usc-sdk` (TypeScript/JS, requires `ethers` v6). Key classes: `PrecompileChainInfoProvider` (query supported chains/attestation state), `PrecompileBlockProver` (submit proofs to the on-chain verifier), `ProverAPIProofGenerator` (fetch pre-computed proofs from the hosted prover API — "recommended starting point"), and `waitUntilHeightAttested` (polls, default 15s, until the source block is attested).
- **Contract pattern:** Split into (a) a **Core USC/ASC contract** — `_processOracleResults(proverContractAddr, queryId)`, `isQueryUsed`/`_markQueryUsed` (replay protection), and the `_onQueryValidated(...)` hook — and (b) a **Business-Logic contract** that inherits it and implements the hook. Cross-chain data arrives as an array of ABI-encoded `ResultSegment`s (`bytes32` you decode to `address`/`uint256`/`bool`). Import `@gluwa/creditcoin-public-prover` (`Types.sol`, `Prover.sol`). `MintableUSCBridge` is a ready extension for token movement. An **off-chain worker** listens for completed oracle queries and calls `processOracleResults`, so the end user signs only one transaction.
- **Starter repos to fork:** `gluwa/usc-testnet-bridge-examples` and `gluwa/ccnext-testnet-bridge-examples` (three tutorials: **Hello Bridge** → **Custom Contracts Bridging** → **Bridge Off-chain Worker**). The blog documents two reference dApps: a Sepolia↔Creditcoin **trustless bridge** and a **credit-verification dApp** (repay on Sepolia → prove → mint a credit NFT on Creditcoin). **Your champion project is a natural, more ambitious extension of the second one — a huge de-risking factor for a solo build.**
- **AI assist:** A community "Creditcoin dApp Skill" for Claude Code exists (`github.com/phamdat721101/creditcoin-dapp-skills`) that preloads Solidity/ethers/USC patterns, RPC endpoints, and chain IDs. Install it Day 1 — it demonstrably generates the exact `recordRepayment(queryId, proverContract)` / `_processOracleResults` patterns you need. (Treat generated code as a draft; audit it — it's community-made, not official.)

**6. What judges and investors want.** Judging explicitly weights **depth of Attestcoin utilization** as a core criterion, plus a full deliverable set (working integration code, technical docs of setup/usage, GitHub + README, deck/whitepaper PDF, prototype demo video, testnet deployment, original work). The **top 3 teams fast-track into CEIP** — a **$10M program managed by Credit Labs**, tickets **$25K–$250K** (equity/token), with engineering/product advisory and VC-network access. Credit Labs (CIO Sung Choi) explicitly prioritizes projects that **"enhance decentralized credit and payment solutions," "improve financial inclusion," and "leverage Creditcoin's infrastructure for real-world applications."** Creditcoin's identity is real-world credit in emerging markets: Aella disbursed **100B Naira to 2M+ Nigerians**, and the network has recorded **millions of real-world loans ($100M+ by 2025)**. **Translation: a cross-chain *credit/RWA* project is the highest-EV bet — it maximizes both the "depth of Attestcoin" score and CEIP investment fit, because credit reputation is the exact use case Creditcoin invented Attestcoin for.**

**7. Competitive landscape.** Prior BUIDL CTC seasons drew ~76 BUIDLs / ~189 hackers with a strong "real-world/purpose-driven" framing. Expect DeFi to be **oversaturated** with generic lending/DEX clones and RWA to be crowded with shallow "tokenize X" demos where Attestcoin is a bolt-on. **Gaming, DePIN, and AI tracks are underserved and easier to stand out in — but they are harder to integrate Attestcoin *deeply* and less aligned with CEIP's credit thesis.** The winning wedge for a solo builder is therefore **not a new track — it's out-executing the crowded credit/DeFi field on Attestcoin depth + polish + narrative**, since that's where the judges' rubric and the investors' checkbook both point.

---

## Details — Five project ideas (each with Attestcoin as the core)

### Idea 1 — **CrossCredit** (DeFi + RWA) ★ CHAMPION
**Concept.** An undercollateralized/variable-collateral lending market on Creditcoin where a borrower's *creditworthiness is imported trustlessly from other chains*. A user repays loans / provides liquidity / manages collateral on Ethereum (Sepolia); CrossCredit uses the Attestcoin precompile to verify those transactions and computes an on-chain credit score, minting a **soulbound "Credit Tier" NFT** that governs their collateral ratio and interest rate on Creditcoin.
**Deep Attestcoin use.** Multiple *distinct* attested event types → the ASC's `_onQueryValidated` hook decodes `ResultSegment`s into (borrower, event-type, amount, on-time flag) and updates a `CreditProfile`. Uses **batch verification (≤10 queries, shared continuity proof)** to ingest a full repayment history in one transaction — a genuinely differentiated use of a documented feature.
**Why judges score it high.** It *is* Creditcoin's thesis; Attestcoin is load-bearing (remove it and the product collapses); it directly extends the team's own reference dApp, so it's polished and credible.
**CEIP appeal.** Highest — "portable cross-chain credit reputation" is a fundable category and exactly Credit Labs' stated priority.
**Solo-feasibility (23 days).** High — forks the documented loan-verification pattern.
**Risks.** Credit scoring can look "toy" — mitigate with a clean tiering rule and a live end-to-end demo, not just math.

### Idea 2 — **ProofYield** (DeFi)
**Concept.** A yield vault on Creditcoin that adjusts strategy/allocations based on *cryptographically verified* DeFi positions/rates read from a source chain, instead of a centralized price/rate oracle.
**Deep Attestcoin use.** ASC verifies balance/position/rate-bearing transactions from Sepolia and rebalances; the pitch is "trustless oracle-free yield."
**Judges/CEIP.** Strong "no centralized oracle" narrative; medium CEIP fit (less credit-specific).
**Feasibility.** Medium — DeFi accounting is fiddly solo.
**Risks.** Crowded DeFi track; reading "rates" from a testnet source chain can feel contrived without a real venue to read from.

### Idea 3 — **AttestInvoice** (RWA)
**Concept.** Invoice-financing / RWA receivables platform: a supplier's payment/settlement event on another chain is verified by Attestcoin to release financing or mark a tokenized invoice as paid on Creditcoin.
**Deep Attestcoin use.** Settlement-event verification drives lifecycle state of a tokenized RWA; ties off-chain value to on-chain transparency (the RWA track's exact wording).
**Judges/CEIP.** Very strong real-world/RWA + credit fit.
**Feasibility.** Medium-high.
**Risks.** RWA track likely crowded; needs a crisp "who pays whom" story to avoid looking generic.

### Idea 4 — **SensorSettle** (DePIN)
**Concept.** DePIN coordination layer where hardware/sensor operators log attestable proofs-of-work/uptime on a source chain; Attestcoin verifies them on Creditcoin to release token rewards and settle payments.
**Deep Attestcoin use.** "Cross-chain data driving incentives/settlement" verbatim; verify device-event transactions → pay operators.
**Judges/CEIP.** Underserved track = easier to stand out; medium CEIP fit.
**Feasibility.** Medium — must simulate a device/data source convincingly.
**Risks.** Hard to make tangible in a video without real hardware; simulate with a scripted "device" contract on Sepolia.

### Idea 5 — **VerdictAI** (AI)
**Concept.** An AI underwriting/decision agent on Creditcoin that consumes *only cryptographically verified* cross-chain data (via Attestcoin) to autonomously approve/size loans and trigger on-chain transactions — "no centralized oracle feeding the model."
**Deep Attestcoin use.** The AI's inputs are attested facts (verified repayments/positions); its outputs are on-chain calls guarded by `isQueryUsed` replay protection.
**Judges/CEIP.** AI track is fresh and buzzy; strong "verified data → autonomous action" story; good CEIP fit if framed as credit underwriting.
**Feasibility.** Medium — risk of the AI being "a prompt wrapper." Keep the ML minimal and make the *verified-data pipeline* the star.
**Risks.** Judges may discount thin AI; the Attestcoin plumbing must clearly do the heavy lifting.

**Ranking for a solo builder chasing Grand Prize + CEIP:** **1 (CrossCredit) > 3 (AttestInvoice) > 5 (VerdictAI) > 2 (ProofYield) > 4 (SensorSettle).**

---

## The Champion: CrossCredit — full justification

- **Depth of Attestcoin (the core criterion):** Attestcoin is the product's spine — multiple distinct attested event types, batch verification, decoded `ResultSegment`s driving state, replay protection via `isQueryUsed`. It cannot be removed without deleting the product. That is the definition of "meaningful integration."
- **Wow-factor / demo-ability:** One clean 15-second on-camera moment — repay on Sepolia → one signature → Credit Tier upgrades on Creditcoin, live, same block. Batch-verifying a whole history in one tx is a visual "aha."
- **Real-world relevance:** It is *the* Creditcoin mission — portable, trustless credit reputation for the underbanked, extended cross-chain. Aligns perfectly with "BUIDL for the Real World."
- **Originality vs. the field:** Most DeFi/RWA entries will bolt Attestcoin onto a generic clone. CrossCredit inverts that — the cross-chain attestation *is* the moat, and "portable reputation" is more original than another lending pool.
- **CEIP/venture appeal:** Matches Credit Labs' stated funding priorities word-for-word (decentralized credit, financial inclusion, Creditcoin infra for real-world use). Clear path from hackathon MVP → fundable protocol.
- **Solo scope in 23 days:** De-risked by forking Gluwa's credit-verification reference dApp + `@gluwa/usc-sdk` + the Claude Code skill.

---

## Execution roadmap

**Suggested architecture.**
1. **Source-chain (Sepolia) contract** — `LoanBook.sol`: emits rich events on repay/collateral/liquidity actions (indexed borrower, amount, timestamp, on-time flag). Reuse example ERC-20/loan contracts to save time.
2. **Off-chain Oracle Worker** (TypeScript, `@gluwa/usc-sdk`): watches Sepolia events → `waitUntilHeightAttested` → `ProverAPIProofGenerator` fetches proof → submits to your ASC via `PrecompileBlockProver`. Handles retries/dedup so the user signs once.
3. **Creditcoin ASC (CC3 Testnet):** `CrossCreditCore` (inherits the USC core: `_processOracleResults`, `_onQueryValidated`, replay guards) + `CrossCreditLogic` (implements the hook: decode `ResultSegment`s, update `CreditProfile`, recompute score, mint/upgrade **soulbound Credit Tier** ERC-721/5192). A `LendingPool` reads the tier to set collateral ratio + rate. Verify success in-contract (precompile won't).
4. **Frontend** (Next.js + wagmi/ethers v6): wallet connect (add CC3 network), "prove my Sepolia history" button, live score/tier, and a lending UI showing improved terms.

**Week-by-week (23 days, Aug 13 → Sep 6).**
- **Days 1–3 (Setup & de-risk):** Register on DoraHacks; join Discord, get tCTC + Sepolia ETH; add CC3 (chainId 102031). Install the Claude Code Creditcoin skill. **Run Tutorial 1 (Hello Bridge) end-to-end and confirm `getSupportedChains()` output** — lock your source-chain assumption. Deliverable: a verified proof round-trip on your machine.
- **Days 4–8 (Core integration):** Complete Tutorials 2–3; adapt them into `CrossCreditCore`/`CrossCreditLogic`; decode `ResultSegment`s for one event type; deploy to CC3; prove one Sepolia repayment → score update on-chain. **This is the make-or-break milestone — hit it by Day 8.**
- **Days 9–13 (Depth):** Add 2–3 event types + **batch verification (≤10)** to ingest a history in one tx; implement soulbound Credit Tiers; wire tiers into `LendingPool` terms; off-chain worker for one-signature UX.
- **Days 14–18 (Frontend + polish):** Build the demo UI; seed a compelling Sepolia history; handle edge cases; write NatSpec + README as you go.
- **Days 19–21 (Deliverables):** Record the demo video (see tips); write the deck/whitepaper PDF; finalize technical docs of Attestcoin setup/usage; clean the repo.
- **Days 22–23 (Submit early):** Submit on DoraHacks with buffer for the ET deadline; verify every link (repo, video, live testnet contracts on Blockscout) works from an incognito window.

**Submission checklist (mapped to requirements).**
- ☑ Working Attestcoin integration code → `CrossCreditCore` calling `verify`/`_processOracleResults`, plus the SDK worker.
- ☑ Technical documentation of setup & usage → `/docs/ATTESTCOIN.md`: chainKeys used, proof flow, contract addresses, how to run the worker.
- ☑ GitHub repo + README → quickstart, architecture diagram, deployed addresses, demo GIF.
- ☑ Deck/whitepaper PDF → problem (fragmented credit), solution, Attestcoin depth, market (emerging-market credit), roadmap, ask.
- ☑ Prototype demo video → ≤3–4 min, see tips.
- ☑ Testnet deployment → all contracts on CC3 Testnet + Sepolia, linked on Blockscout.
- ☑ Original work created during the hackathon → keep clean commit history from Aug 13; disclose forked examples honestly.

**Tips to maximize judge impact.**
1. **Lead the video with the 15-second proof moment**, not a slide intro. Show the Sepolia tx hash, then the same-block Creditcoin state change, on screen.
2. **Say the core-criterion words back to the judges:** narrate "no centralized oracle, no bridge — the precompile at `0x0FD2` verifies a Merkle + continuity proof in one block," and show batch verification.
3. **Make it obviously fundable:** one slide on emerging-market credit + Aella-scale numbers to frame CrossCredit as the cross-chain generalization of Creditcoin's proven business.
4. **Verify success in-contract** and show a rejected/invalid-proof path — demonstrating you understood the precompile's stated limitation earns credibility.
5. **Engage Discord mentoring** during the build; visibility with the team helps at judging and at CEIP due diligence.
6. **Ship a live testnet link judges can click and use themselves** — a working, clickable demo beats a video every time.

---

## Recommendations (staged, with decision thresholds)
1. **Day 1 gate — confirm the source-chain reality.** Call `getSupportedChains()` on CC3. *If only Sepolia is live* → commit to CrossCredit's *deep single-source, multi-event* design. *If BSC/Polygon are also live* → add a second source chain as a "portable across chains" flourish (do this only after the Sepolia path fully works).
2. **Day 8 gate — end-to-end proof or pivot scope.** If one Sepolia event isn't verifying into a Creditcoin state change by Day 8, **cut features, not the core**: drop the AI/extra chains, keep the single trustless credit-verification loop — that alone satisfies "meaningful Attestcoin integration" and is demo-worthy.
3. **Day 14 gate — depth check.** You should have ≥2 attested event types + batch verification working; if not, prioritize batch verification (it's a documented, differentiating feature judges recognize) over UI polish.
4. **Always favor a working live demo over feature count.** The rubric rewards depth + a functioning prototype; a narrow, flawless, deeply-integrated CrossCredit beats a broad, half-working multi-track app.
5. **Submit 24h early.** The deadline is 23:59 ET Sep 6; treat Sep 5 as your real deadline.

---

## Caveats
- **Rebrand/version flux (verify on Day 1).** "USC → Attestcoin Protocol" is recent and docs URLs moved from `/usc/*` and `/creditcoin-usc` to `/attestcoin-protocol/*`; some old pages 404 or are marked "outdated." The technical facts here (precompile `0x0FD2`, `verify(...)→bool`, `_processOracleResults`, `ResultSegment`, `@gluwa/usc-sdk`, ≤10 batch, ~15s) come from Creditcoin's own docs/blog but reflect USC v2 / CC3 naming — reconfirm exact contract package names and RPCs against the live `/attestcoin-protocol` docs before coding.
- **Supported chains are conservative by design here.** Only **Ethereum Sepolia (chainKey 1)** is confirmed live in docs. BSC is a schema *example* only; Bitcoin/Polygon/Solana are roadmap. Do **not** build a demo that depends on an unverified source chain. Authoritative check: `getSupportedChains()` on `https://rpc.cc3-testnet.creditcoin.network` and the raw `networks.json` in `gluwa/creditcoin-usc-networks`.
- **Read vs. write.** The protocol is inbound-verification-oriented on testnet; "write to any chain"/"messaging" is achieved via your own off-chain worker + source-chain contract, and broader outbound messaging appears to be positioning/roadmap. **The precompile does not check transaction success — your contract must.** Don't over-promise outbound messaging in the pitch.
- **The Claude Code "Creditcoin dApp Skill" is community-built** (`phamdat721101`), not official Creditcoin tooling. Use it to accelerate, but audit all generated Solidity.
- **"Live on Mainnet" signal.** Creditcoin's homepage timeline states cross-chain reads went live on *mainnet* in '26. The hackathon requires **testnet** deployment (CC3), so build/deploy on testnet regardless; mainnet status is a bullish narrative point, not a build target.
- **Past-winner specifics unverified.** I could not retrieve a published list of prior BUIDL CTC winning projects with names/scores; patterns above are inferred from the hackathon's framing, general Web3-hackathon judging norms, and CEIP's stated priorities. Treat competitive-saturation claims as informed judgment, not confirmed data.
