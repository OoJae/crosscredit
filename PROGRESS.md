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
| Aug 13 | ⏳ pending operator | 0 | wallet created |

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

**Next**
- Finish Track A: toolchain + CI, `check-chains.ts` evidence, vendor USCBase, push to GitHub.
- Gate G0 the moment the wallet is funded.
- Then Phase 1: `LoanBook.sol` TDD (needs no testnet — safe to start while faucets pend).

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
