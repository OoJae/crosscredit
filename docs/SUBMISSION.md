# DoraHacks submission — field-by-field

Paste-ready copy for the BUIDL CTC 2026 Fall form. Every figure here is traceable to a file in
this repo or to a live contract; nothing is rounded up for effect.

The form has five steps: **Profile · Details · Team · Contact · Submission**.

---

## Step 1 — Profile

### Logo

`docs/evidence/submission/crosscredit-avatar-480.png` — 480×480, 5.6 KB, PNG.

Raw URL, if an upload is refused:
`https://raw.githubusercontent.com/OoJae/crosscredit/main/docs/evidence/submission/crosscredit-avatar-480.png`

> The slot is square and the wordmark was being centre-cropped in it, which is why the tile read
> "SCR". This is the maker's mark instead, optically resized for a listing: arc radius 12 → 9 so
> the counters stay open rather than closing into a blob, and the cartouche at full opacity on a
> 1.6 stroke so the frame survives below 64px. Checked at 200 / 96 / 48 / 32px.

### Vision — *"Describe the problem which this project solves"*

**Hard cap: 256 characters** — measured on the live form, which rejects anything longer.

**Vision (236 characters):**

> A wallet with years of Aave repayments on Ethereum posts $1,500 to borrow $1,000 on every other
> chain. Not because the lender doubts that history — because it cannot read that chain.
> CrossCredit makes the lending chain verify it itself.

### Key innovation domains (optional)

DeFi · Lending · Cross-chain / Interoperability · Identity & Reputation

### Infrastructures — Layer-1s (optional)

Creditcoin · Ethereum

### Category

**Crypto / Web3**

### Links

- GitHub — `https://github.com/OoJae/crosscredit`
- Project website — `https://crosscredit.vercel.app`

---

## Step 2 — Details

### Project description (250 words)

> CrossCredit rebuilds a borrower's credit profile on Creditcoin CC3 from Ethereum transactions
> never signed on Creditcoin. CreditRegistry calls the Attestcoin Protocol's BlockProver
> precompile (0x…0FD2) on every ingest path: verifyAndEmit for a single proof; the batch overload
> sharing one continuity proof across up to ten source transactions, unexercised in Gluwa's
> examples, 134,167 gas per event against 532,140 singly; read-only verify as a free pre-flight in
> previewIngest; and calculateTxIndex to derive the replay id. The precompile proves inclusion and
> continuity, not transaction success, so the registry decodes the payload itself with
> EvmV1Decoder.decodeReceiptFields and enforces receiptStatus == 1. It authenticates the
> (chainKey, emitter) pair against its own allowlist and dispatches every recognised log on the
> log's own topic0, never on the caller's declared action. CC3 attests Ethereum mainnet as
> chainKey 3 — we found that in neither the docs nor the official examples — so the evidence is
> third-party Aave V3 history. Proven repayments update a CreditProfile, ScoreLib scores it inside
> the EVM that verified the evidence, a soulbound ERC-5192 badge syncs, and LendingPool prices the
> loan: tier sets the rate, demonstratedCapacityWei caps borrowing above collateral posted. No
> oracle we run, though Creditcoin's attestor set is in the trust path. This is minutes, not
> seconds: Gate G0 measured 9 min 39 s end to end, ~8.5 min of it attestation, one CC3 block of it
> verification. Five proven Aave repayments took 0x76f30e…5b1A from 0 to 800, Platinum:
> collateralRequired(that wallet, 1000e18) returns 850e18; the same free view call on a self-dealt
> wallet returns 1300e18.

### Attestcoin Protocol Integration Summary

**534 words** — over the 300–500 I aimed for, kept deliberately: DoraHacks states no limit on this field, and the labelled blocks let a skimming judge take the first paragraph and stop.

**This is the field the #1 criterion is scored from.** The hackathon's only published scoring
statement is *"Depth of Attestcoin Protocol utilization will be evaluated as one of the core
scoring criteria."*

> CrossCredit's registry verifies Ethereum transactions for itself, inside the Creditcoin EVM,
> then decides what to believe about them: a valid proof of the wrong thing is worthless. Nine
> Sepolia proofs verified in one CC3 transaction (0xffad0a92…, 1,207,503 gas — 134,167 per event
> vs 532,140 singly). Five real Aave V3 mainnet repayments proven and scored, 0 → 800. Five
> attacks rejected on the live chain — three by the precompile itself, two by the registry's own
> guards — reproducible with no wallet and no funds: `npm run negative-paths`.
>
> **PRIMITIVES — every overload BlockProver (0x…0FD2) exposes.** `verifyAndEmit` single: main
> ingest, via vendored USCBase (pinned gluwa/usc-testnet-bridge-examples@4ff9a3bf).
> `verifyAndEmit` BATCH (CreditRegistry.sol:382), with no precedent in Gluwa's examples: ten
> proofs against one shared continuity proof. We confirmed the documented ceiling of ten against
> the live precompile — an eleventh reverts with `heights: Value is too large for length`. Both
> read-only `verify` views as free pre-flight: `previewIngest` names the guard that would reject a
> proof before a signature is requested; `dryRunBatch` staticCalls a whole batch, so a doomed one
> costs nothing. `calculateTxIndex` inside `_computeQueryId`, re-exposed as `queryIdFor`.
> `TransactionVerified` as an on-chain audit trail. ChainInfo (0x…0fd3) for `getSupportedChains`
> and attested heights. `EvmV1Decoder` (@gluwa/usc-contracts@0.1.2) — external, delegatecall'd
> into our storage context, so we deploy our own build rather than link a stranger's.
> @gluwa/usc-sdk@0.18.0: `ProofBuilder.getProof`/`getBatchProof`, `waitUntilHeightAttested`.
> ("Attestcoin Protocol" is prose branding; every import is `usc-*`.)
>
> **DEPLOYED.** CreditRegistry `0x4C4381dB68a1cAAE46a2E6CFc2f667ad22Dddf81` · EvmV1Decoder
> `0x2b887101B0E7710BDBC252c4c4a6aEb45052EDfa` · CreditTierSBT
> `0x326F8806cBd5ABF413889BfAc0A6622a0AEddD18` · LendingPool
> `0xf27877faC13244a4ad959E83cD9E5a15d919029C` (CC3) · LoanBook
> `0x07AdA5C60dFbe5C3A7dC48081B0fa70E14c6d41D` (Sepolia).
>
> **FIVE CHECKS on every proven payload,** each with a negative test. (1) Replay:
> `queryId = keccak(chainKey, blockHeight, txIndex)`, rejected at the vendored USCBase guard.
> (2) Source authentication on the (chainKey, emitter) PAIR — which required modifying vendored
> USCBase to pass chainKey into the business hook at all, as upstream does not. (3)
> `receiptStatus == 1`, decoded by the registry itself: the precompile does not validate
> transaction success, and a reverted repayment is still "included". (4) Dispatch on the log's OWN
> emitter, never the caller's `action` byte, which arrives outside the proof. (5) topic0 must
> match that source's signatures.
>
> **NOT IN THE DOCS OR EXAMPLES.** CC3 attests Ethereum MAINNET as chainKey 3 beside Sepolia's 1 —
> found in neither, and it became the project: unaffiliated Aave V3 history verifies on CC3.
> `verify()` reverts; it never returns false, so `require(verify(...))` is an unreachable,
> untested branch. Continuity proofs EXPIRE, anchored to attestation state at generation — a
> negative-path script failed its own baseline on a proof captured hours earlier.
> `getBatchProof` returns a nested Map ordered by height, not input order; zip it against your
> inputs and you silently credit the wrong borrower. queryId identifies a TRANSACTION, not an
> event: examples take only the first matching log, so a second credit event is lost forever
> behind the replay guard. We ingest every recognised log, skipping anonymous zero-topic ones that
> a naive `topics[0]` read would revert on — log index 4 of our headline mainnet proof is one.
>
> **TIMING, honestly.** ~15s is verification inside one Creditcoin block, and only after the
> source block is attested. Sepolia lag is 8–10 minutes; Gate G0 end to end was 9 min 39 s at
> 393,638 gas. No oracle we run — but Creditcoin's attestor set is in the trust path.

---

## Step 5 — Submission

| Field | Status |
|---|---|
| GitHub repository URL | `https://github.com/OoJae/crosscredit` — public, README current |
| Technical documentation | `docs/ATTESTCOIN_INTEGRATION.md` — **mandatory**, not optional polish |
| Prototype demo video URL | ⛔ **film is rendered, not uploaded** — 137s, 1920×1080, h264+AAC, `videos/crosscredit-demo/renders/` |
| Project deck / whitepaper PDF | ⛔ **not built** — `BUILD_GUIDE.md` §10 outlines 10 slides |

---

## Steps 3 & 4 — Team and Contact

These need your personal details and I have not guessed at any of them.

Per member: First & Last Name · Email · Telegram · X/Twitter · LinkedIn · Résumé PDF URL · Short
Bio · Role · Country of Residence · Country of Citizenship. Solo is explicitly allowed
(*"Minimum team size: 1 member"*).

**Fill the optional social fields.** Top three advance directly to CEIP due diligence, and due
diligence will look.

---

## Accuracy constraints these were written under

Repeating a retracted claim in front of protocol-literate judges costs more than the claim buys.

- Verification is synchronous within one Creditcoin block; the source block must be attested
  first, and Sepolia attestation lag is ~8–10 minutes. Never imply the end-to-end journey is
  instant.
- "No oracle **we** run", never a bare "no oracle" or "trustless" — Creditcoin's attestor set is
  in the trust path.
- Mainnet chainKey 3 is **our** finding, in the sense that we found it in neither the docs nor the
  official examples. Not a claim about what exists.
- The precompile does not validate transaction success. We check `receiptStatus == 1` ourselves.
- Multi-block wash lending is **not** solved and is disclosed. Nothing here claims sybil-proof.
