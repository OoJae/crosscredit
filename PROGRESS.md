# PROGRESS

Session log. Updated at the end of every session: done / next / blockers / addresses / open questions.

---

## Status

| | |
|---|---|
| **Phase** | 0 — Verify reality |
| **Day** | 1 of 23 (Aug 13, 2026) |
| **Current gate** | **G0** — real proof round-trip on CC3 testnet (hello-bridge) |
| **G0 status** | ⏳ blocked on wallet funding (faucets — see `docs/HUMAN_ACTIONS.md`) |
| **Repo** | <https://github.com/OoJae/crosscredit> (public, CI green) |
| **Internal submit target** | **Sep 4, 2026** (deadline disputed — see Open questions) |

## Addresses

| What | Chain | Address |
|---|---|---|
| Demo/deployer wallet (test-only) | both | `0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6` |
| LoanBook | Sepolia | _not deployed (P1)_ |
| CreditRegistry | CC3 | _not deployed (P2)_ |
| CreditTierSBT | CC3 | _not deployed (P3)_ |
| LendingPool | CC3 | _not deployed (P3)_ |
| TUSD | CC3 | _not deployed (P3)_ |

Protocol-side (not ours, verified live Aug 13):

| What | Address / URL |
|---|---|
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000fd3` |
| EvmV1Decoder (deployed, debug aid) | `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` |
| CC3 RPC | `https://rpc.cc3-testnet.creditcoin.network` (chainId 102031) |
| CC3 explorer | `https://creditcoin-testnet.blockscout.com` |
| Proof builder API | `https://prover.cc3-testnet.creditcoin.network` |

## tCTC budget ledger

An oracle query costs ~11 tCTC; the faucet gives ~100 tCTC/24h → **~9 queries/day**. Track it.

| Date | Faucet claimed | Spent | Note |
|---|---|---|---|
| Aug 13 | ⏳ pending operator | 0 | wallet created; nothing spent yet (G0 not run) |

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
7. **Faucet economics are a real constraint**: ~100 tCTC/day ≈ 9 oracle queries.
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
