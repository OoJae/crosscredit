# PROGRESS

Session log. Updated at the end of every session: done / next / blockers / addresses / open questions.

---

## Status

| | |
|---|---|
| **Phase** | 3 complete → next is **Phase 4 (frontend)** |
| **Day** | 1 of 23 (Aug 13, 2026) |
| **G0** — real proof round-trip | ✅ **PASSED** — [evidence](docs/evidence/g0-hello-bridge/README.md) |
| **G1** — seeded history on a public explorer | ✅ **PASSED** — 11 events, verified source |
| **G2** — make-or-break credit loop | ✅ **PASSED** — score 0 → 710, Bronze → Platinum, live |
| **G3** — batch · SBT · pool · negative paths | ✅ **PASSED** — 9 proofs in ONE tx, 3.4× cheaper |
| **Next gate** | **G4** — 3 UI screens vs live testnet; stranger runs demo from README |
| **Repo** | <https://github.com/OoJae/crosscredit> (public, CI green) |
| **Internal submit target** | **Sep 4, 2026** (deadline disputed — see Open questions) |

## Addresses

| What | Chain | Address |
|---|---|---|
| Demo/deployer wallet (test-only) | both | `0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6` |
| LoanBook | Sepolia | [`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events) ✅ verified (Sourcify) |
| Borrower A (clean, targets Platinum) | Sepolia | `0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6` — 9 on-time events |
| Borrower B (one late repayment) | Sepolia | `0x04163f60FA50519D86AeFB8e450312bAD76CA0B6` — 2 events |
| CreditRegistry (batch) | CC3 | [`0xB5F3B44113A31B07508464de39d7ddd939184B2c`](https://creditcoin-testnet.blockscout.com/address/0xB5F3B44113A31B07508464de39d7ddd939184B2c) ✅ **current** |
| CreditTierSBT | CC3 | [`0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6`](https://creditcoin-testnet.blockscout.com/address/0x96a68DBe0cC9BD13E92B4730eFfE531F63f4B2F6) |
| LendingPool (100k tUSD) | CC3 | [`0xA37a9338b17c20917046E29F23D9d8F796a5FDAb`](https://creditcoin-testnet.blockscout.com/address/0xA37a9338b17c20917046E29F23D9d8F796a5FDAb) |
| TUSD | CC3 | [`0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051`](https://creditcoin-testnet.blockscout.com/address/0x26FEEdECb79A69EdC7d3Bdb8Cf4dD96E17a3B051) |
| Borrower C (batch demo) | Sepolia | `0x8C04C28894BADcE63d1F00f356AbB126983522Cf` — 9 events, Platinum |
| ~~CreditRegistry (Phase 2)~~ | CC3 | ~~`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`~~ superseded (no batch) |
| EvmV1Decoder (ours, linked) | CC3 | [`0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa`](https://creditcoin-testnet.blockscout.com/address/0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa) |
| CreditTierSBT | CC3 | _not deployed (P3)_ |
| LendingPool | CC3 | _not deployed (P3)_ |
| TUSD | CC3 | _not deployed (P3)_ |

Protocol-side (not ours, verified live Aug 13):

| What | Address / URL |
|---|---|
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000fd3` |
| EvmV1Decoder (theirs, 9,598 B — **not** our build, see findings) | `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` |
| CC3 RPC | `https://rpc.cc3-testnet.creditcoin.network` (chainId 102031) |
| CC3 explorer | `https://creditcoin-testnet.blockscout.com` |
| Proof builder API | `https://prover.cc3-testnet.creditcoin.network` |

## Cost reality (measured at G0 — the old budget worry was unfounded)

A verified Attestcoin query costs **393,638 gas at 0.5 gwei ≈ 0.000197 CTC**. Gluwa's README
claims 100 tCTC buys ~9 queries; it buys roughly **half a million**. We hold 10,000 tCTC and
0.21 Sepolia ETH — **iteration is effectively free, stop designing around a query budget.**

---

## Session log

### Session 1 — Aug 13, 2026 (Phase 0, Day 1)

**Done**
- Ran the Phase 0 Verification Protocol against live sources (npm registry, live docs corpus,
  CC3 JSON-RPC probes, DoraHacks page). Findings in "Verified ground truth" below — they
  **materially contradict** the original spec; CLAUDE.md and BUILD_GUIDE rewritten to match.
- Generated test-only wallet, wrote `.env` (gitignored) + `.env.example`.
- Scaffolded monorepo, git init on `main`.

**Verified ground truth (the big corrections)**
1. **The spec's contract architecture is dead.** `@gluwa/creditcoin-public-prover`,
   `Types.sol`/`Prover.sol`, `ResultSegment[]`, `_onQueryValidated`, `_processOracleResults`,
   precompile `0x0Be9` — all belong to the pre-2026 async STARK model that was *removed* when
   USC Testnet 2.0 shipped the native verifier. Current stack is `@gluwa/usc-sdk@0.18.0` +
   `@gluwa/usc-contracts@0.1.2`, with the `USCBase.execute(...)` → `verifyAndEmit` →
   `_processAndEmitEvent(...)` pattern.
2. **"Attestcoin" is prose-only branding.** Zero npm packages and zero GitHub repos carry the
   name; everything still ships as `usc-*`. Docs even say so explicitly. Use "Attestcoin
   Protocol" in the pitch, `usc-*` in every import.
3. **`ProverAPIProofGenerator` does not exist** — the real class is
   `proofProvider.service.ProofBuilder(chainKey, url)`. SDK exports are namespaces, not flat
   classes.
4. **Attestation lag is ~8–10 minutes, not ~15 seconds.** The ~15s figure is CC3 block/verify
   time *after* the source block is attested. The demo script must pre-attest — corrected in
   BUILD_GUIDE §1 and §9.
5. **CC3 testnet has two source chains**, not one: Sepolia (chainKey 1) *and* Ethereum Mainnet
   (chainKey 3). chainKey ≠ chainId. This is why our registry hook must authenticate chainKey.
6. **Batch has a second constraint the spec missed**: ≤10 proofs *and* all within a 1000-block
   `MAX_BATCH_RANGE`. This shapes `seed-history.ts` — the seeded events must land inside one
   1000-block window to fit a single batch.
7. ~~**Faucet economics are a real constraint**: ~100 tCTC/day ≈ 9 oracle queries.~~
   **SUPERSEDED in session 2** — measured at G0: a query costs ~0.000197 CTC, not ~11. The
   constraint never existed; Gluwa's README figure is stale.
8. Toolchain follows the live examples: **Foundry** (solc 0.8.30, evm shanghai), OZ 5.4.0.

**Also done (Track A complete)**
- Toolchain: Foundry (solc 0.8.30, settings mirrored from the pinned examples) + TS strict +
  eslint + GitHub Actions CI. **CI green on first push.**
- `scripts/check-chains.ts` → `docs/evidence/supported-chains.json`, capturing supported chains
  *and* each one's latest attested height (registration ≠ attestors actually running).
- Vendored `USCBase.sol` + `VerifierInterface.sol` with full attribution headers, pinned to
  `4ff9a3bf`. 8 unit tests, all green, exercising the real vendored bytecode via `vm.etch` of a
  mock at the precompile's actual address.
- `docs/ATTESTCOIN_INTEGRATION.md` seeded (this is a **required** submission deliverable).
- Public repo created and pushed: <https://github.com/OoJae/crosscredit>.
- Verified no private key ever entered git history.

**Findings that only surfaced by running the code** (documented in ATTESTCOIN_INTEGRATION.md)
- `INativeQueryVerifier` as published in `@gluwa/usc-contracts@0.1.2` is, by its own NatSpec, a
  **lean copy** with only the single-query view `verify` — no `verifyAndEmit`, no batch, no
  `calculateTxIndex`. Our vendored interface adds them from the SDK's canonical
  `block_prover.json` ABI, which also **confirms the batch `verify` view variant exists**.
- `EvmV1Decoder`'s functions are `public`, not `internal` → it is an **external library needing
  link-time deployment** (13,261 B), not an inlined one. The instance already on CC3 at
  `0x731c34…` is 9,598 B, i.e. a *different build*, so Phase 2 must deploy and link our own.
- ChainInfo returns `chainName` hex-encoded, contradicting the SDK docstring's example.
- `chainInfo.waitUntilHeightAttested` is marked **legacy in its own docstring**; the canonical one
  lives in `proof-provider/service`. The worker must use the latter.
- ethers ships dual CJS/ESM types; under NodeNext our ESM scripts and the CJS SDK resolved two
  incompatible `JsonRpcApiProvider` declarations. Fixed via `moduleResolution: bundler`.

**Next**
- **Gate G0** the moment the wallet is funded (hello-bridge round-trip; runbook in the plan).
  Capture a golden proof fixture at the same time — the block is already attested by then, so
  `getProof` returns instantly and the fixture is free.
- Phase 1: `LoanBook.sol` TDD — **needs no testnet**, so it starts now regardless of faucets.

**Blockers**
- Wallet unfunded on both chains → G0 blocked. Operator checklist: `docs/HUMAN_ACTIONS.md`.
- `SEPOLIA_RPC_URL` not yet set (needs an Alchemy/Infura key from operator).

**Open questions (for `#buidl-ctc-qna` / the Aug 18 AMA)**
1. **Deadline conflict.** DoraHacks page prose says Sep 6, 23:59 ET; the platform countdown is
   configured to Sep 6, 04:59 UTC (= Sep 6, 00:59 ET) — the submit button likely locks ~23h
   before the stated deadline. Eventbrite lists a third time (Sep 6, 16:00 ET). Which governs?
2. **Batch `verify` view variant.** The SDK's `block_prover.json` ABI exposes a batch `verify`
   (view) alongside batch `verifyAndEmit`. Is the view variant live on CC3 testnet?
3. Judging criteria weights are unpublished — only "depth of Attestcoin Protocol utilization
   will be evaluated as one of the core scoring criteria" is stated. Worth asking for the rubric.


### Session 2 — Aug 13, 2026 (Gate G0 + Phase 1)

**G0 PASSED — the whole premise is proven on live testnet.**
Sepolia burn [`0xad717c5c…`](https://sepolia.etherscan.io/tx/0xad717c5c85279de036a321b63ccdb109a6c447e79f47261e52f969bdd20ca28d)
(block 11482813) → verified and acted upon on Creditcoin
[`0x7ae82162…`](https://creditcoin-testnet.blockscout.com/tx/0x7ae82162d5f8ec24471637d1e545452d24adf3aa0066b42b874890fbf550f872)
(block 5304687), QueryId `0x2bf5346d…`, 50 BTKT minted from a zero balance.
**End-to-end 9 min 39 s**; 393,638 gas ≈ 0.000197 CTC.

**G1 PASSED — LoanBook live and seeded.**
[`0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c`](https://sepolia.etherscan.io/address/0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c#events),
source verified on Sourcify (`exact_match`), 23 unit tests green, 11 events seeded across two
borrowers. Borrower A's 9 events span 10 blocks — comfortably inside both batch limits, so
"import my whole history in one transaction" is demonstrably possible.

**Findings that change Phase 2**
1. **Alchemy free tier caps `eth_getLogs` at a 10-block range.** The worker must paginate its
   event scan in 10-block windows (or use another provider). A naive full-range query fails.
2. **The SDK's 10 s HTTP timeout also governs the attested-height poll** and expired
   mid-attestation on our first G0 attempt. Our scripts use 60 s. Retrying is free — attestation
   proceeds independently and the prover caches.
3. **`submit_query.ts` exits 0 even on failure.** Our worker must gate on outcomes, never on
   exit codes. The failed attempt looked successful by `$?`.
4. **`getProof` returns a `{success, data}` envelope**, not the proof — unwrap before use.
5. **ScoreLib needs recalibrating for testnet scale.** BUILD_GUIDE §5.4's "+1 per 0.01 ETH repaid
   (cap 200)" would score ~0 against our 0.001–0.002 ETH seeded amounts. Retune to per-0.0001 ETH
   in Phase 3, before the scoring demo depends on it.

**Next — Phase 2, the make-or-break G2 loop**
- `CreditRegistry.sol`: extend the vendored `USCBase`, override `_processAndEmitEvent`, run the
  five-check validation chain (chainKey → receiptStatus → topic0 → emitter → replay), update
  `CreditProfile`. Deploy to CC3 with a linked `EvmV1Decoder`.
- Oracle worker: watch → `waitUntilHeightAttested` → `ProofBuilder.getProof` → `execute(...)`,
  mapping `headerNumber/txBytes/merkleProof/continuityProof` onto the call as `utils/index.ts` does.
- **G2 = one seeded Sepolia repayment verified on CC3 and visibly changing a score.**

**Blockers**
- None. `ETHERSCAN_API_KEY` is still outstanding but Sourcify verification already covers G1;
  Etherscan is a nice-to-have for judge familiarity.


### Session 3 — Aug 13, 2026 (Phase 2, Gate G2)

**G2 PASSED — the make-or-break loop works end to end on live testnet.**
Ten Sepolia transactions attested, proven and verified on Creditcoin. Borrower A's score climbed
**0 → 110 → 260 → 290 → 450 → 560 → 710**, Bronze → Silver → Gold → **Platinum**. Borrower B's
late repayment floors them at 0/Bronze. ~403,558 gas (~0.0002 CTC) per ingest.
Evidence: `docs/evidence/g2-verified-credit-loop/`.

**Shipped**
- `CreditRegistry.sol` — the ASC. Five-check validation chain, all three event types, loan closure
  *derived* from proven events (LoanBook emits no "closed"), out-of-order proof reconciliation.
- `ScoreLib.sol` — deterministic 0–1000 model, `internal` so it inlines. Calibrated against the
  real seeded profiles; Borrower A scores exactly 710 both in the test and on chain.
- `worker/` — persisted state, 10-block paginated scans, watch + backfill + single-tx modes.
- 72 tests (was 31), including `RealProof.t.sol`, which decodes txBytes captured from the live
  prover — synthetic tests only prove our decoder agrees with our encoder.
- Deployed + linked on CC3; LoanBook now also verified on Etherscan.

**Findings for Phase 3**
1. **`forge script` cannot deploy to CC3** — simulation panics with `prevrandao not set` on the
   Frontier/Substrate EVM. Use `forge create` + `--libraries`, as Gluwa's examples do (now we know
   why they do). Any future deploy script must follow that path.
2. **`EvmV1Decoder` is an external library**, not inlined — all 16 functions are `public`. Deploy
   our own and link; the pre-existing CC3 instance is a different build of unverified provenance,
   and libraries execute in the caller's storage context. **CLAUDE.md corrected.**
3. **Gas estimation needs triage.** A deterministic `Query already processed` revert during
   estimation means "do not broadcast"; the examples' fallback broadcasts anyway and burns gas.
4. Continuity proofs grow with distance from the attestation anchor (40–59 roots observed) —
   worth watching when batching, since a batch shares one continuity proof.

**Next — Phase 3 (G3)**
- **Batch verification (≤10, one shared continuity proof, ≤1000-block range)** — the remaining
  depth item and the riskiest: no official example uses it, so it is being built from the ABI.
  Borrower A's 9 events span 10 blocks, so the whole history fits one batch by construction.
- `CreditTierSBT` (ERC-721 + ERC-5192, on-chain SVG) · `LendingPool` tier-priced terms · `TUSD`.
- ScoreLib recalibration is **done** (per-0.0001 ETH) — no longer outstanding.

**Blockers**
- None.


### Session 4 — Aug 13–14, 2026 (Phase 3, Gate G3)

**G3 PASSED — the depth items are done and demonstrated live.**

- **Batch verification.** 9 Sepolia transactions verified in ONE Creditcoin transaction
  ([`0xc8ca57e3…`](https://creditcoin-testnet.blockscout.com/tx/0xc8ca57e39f8fb840ff4e9de837f1f826b0ff41f30039cb311f6a1fbce325437b),
  block 5305011), 9 `HistoryEventIngested` events, Bronze → Platinum. **126,146 gas per event vs
  ~433,000 single-proof — 3.4× cheaper**, measured like-for-like.
- **CreditTierSBT** — ERC-721 + ERC-5192, on-chain SVG, permissionless `sync`. Badge #1 minted and
  locked for Borrower C.
- **LendingPool + TUSD** — funded with 100k tUSD. Borrower C **borrowed 100 tUSD against 85 tCTC**
  live. B's one late repayment costs 650 tCTC more collateral on an identical loan.
- **5/5 attacks rejected** against the live precompile, all free `eth_call`s.
- 130 tests (was 72), all green.

**Findings**
1. **Continuity proofs expire.** A proof captured hours earlier failed to verify — it anchors to
   the attestation state at generation time. Fetch fresh, submit promptly; stored fixtures are for
   decoder tests only. Undocumented anywhere we could find.
2. **`getBatchProof` returns a nested Map in ascending-height order, not input order.** Keying
   positionally would credit the wrong borrower. We key on each entry's `txHash`.
3. `MAX_BATCH_SIZE = 10` confirmed by probing the live precompile; the SDK has no such constant.
4. `forge script` still cannot deploy to CC3 (`prevrandao`) — `forge create --libraries` throughout.

**Registry redeployed** to `0xB5F3B441…84B2c` to add `executeBatch`; all three borrowers were
re-imported onto it, so single-proof and batch paths are both demonstrable on one contract. The
Phase 2 registry's G2 transactions remain valid historical evidence.

**Next — Phase 4 (G4)**
- Three screens against live testnet: Dashboard (score dial, SBT badge, ingested events),
  Import History (the batch moment), Borrow (tier terms, collateral calculator).
- NatSpec/docs pass; README quickstart a stranger can follow in <10 min.

**Blockers**
- None.
