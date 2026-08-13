# Gate G0 — verified proof round-trip on live CC3 testnet ✅

**Aug 13, 2026.** A transaction on Ethereum Sepolia was proven to Creditcoin through the
Attestcoin Protocol's block-prover precompile and acted upon in a Creditcoin smart contract —
with no oracle operator, no bridge multisig and no trusted relayer in the trust path.

This is Tutorial 1 (`hello-bridge`) from
[`gluwa/usc-testnet-bridge-examples@4ff9a3bf`](https://github.com/gluwa/usc-testnet-bridge-examples/tree/4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b),
run against the live testnet with our own wallet and their pre-deployed contracts. It exists to
prove the pipeline works end to end before CrossCredit's own contracts depend on it.

## What happened

| | |
|---|---|
| Wallet | `0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6` (test-only) |
| Source chain | Ethereum Sepolia (Attestcoin chainKey **1**) |
| **1. Mint** 50 TEST | [`0x4280867f…83b4c1`](https://sepolia.etherscan.io/tx/0x4280867f357178bffd421323d5f2e0dea41d0ba6903250a6a0df7e069883b4c1) · block 11482811 |
| **2. Burn** 50 TEST | [`0xad717c5c…0ca28d`](https://sepolia.etherscan.io/tx/0xad717c5c85279de036a321b63ccdb109a6c447e79f47261e52f969bdd20ca28d) · block **11482813** · 21:28:36 UTC |
| **3. Proof** | Fetched from `https://prover.cc3-testnet.creditcoin.network` once block 11482813 was attested |
| **4. Verify + mint on CC3** | [`0x7ae82162…50f872`](https://creditcoin-testnet.blockscout.com/tx/0x7ae82162d5f8ec24471637d1e545452d24adf3aa0066b42b874890fbf550f872) · block **5304687** · 21:38:15 UTC |
| QueryId | `0x2bf5346d29ad6628550c1eedca98d2c378b5fd2b20c4cce5363687e6e4750987` |
| Result | **50.0 BTKT** minted on Creditcoin (balance was 0 before) |

Success marker in [`submit-query.log`](./submit-query.log):

```
Block 11482813 attested! Generating proof...
Proof generation successful!
   Estimated gas: 419719, Gas limit with buffer: 566620
Proof submitted:  0x7ae82162d5f8ec24471637d1e545452d24adf3aa0066b42b874890fbf550f872
Tokens minted! Contract: 0x914Cf9…134E, To: 0x8ce707…89c6,
               Amount: 50000000000000000000, QueryId: 0x2bf5346d…750987
```

## Measured numbers (these replace the estimates in our docs)

| Metric | Measured | Note |
|---|---|---|
| **End-to-end latency** | **9 min 39 s** (579 s) | Sepolia burn 21:28:36 → CC3 mint 21:38:15 |
| Attestation wait | ~8.5 min, 30 polls at 15 s | Dominates the total. This is the honest demo constraint |
| On-chain verification | 1 CC3 block (~15 s) | The "~15 second" figure applies *only* to this step |
| **Gas on CC3** | **393,638** at 0.5 gwei | ≈ **0.000197 CTC** per verified query |
| Gas estimate accuracy | 419,719 estimated vs 393,638 used | Estimation worked; the examples' low fallback was never hit |

### The query-budget constraint we had been designing around does not exist

Gluwa's tutorial README states *"the faucet yields 100 test CTC every 24 hours. This balance is
sufficient to submit 9 oracle queries, since testnet oracle fees are artificially high."* At a
measured **0.000197 CTC** per query, 100 CTC is worth roughly **half a million** queries. That
line is stale, and we had been letting it shape decisions. Corrected across `CLAUDE.md`,
`docs/BUILD_GUIDE.md` and `docs/HUMAN_ACTIONS.md`.

## Two failure modes worth recording

**Attempt 1 died on the SDK's 10-second HTTP timeout.** `ProofBuilder`'s default `timeout` applies
to the attested-height poll as well as proof fetches, and it expired while attestation was still
in progress:

```
Error: Failed to fetch attested height: AxiosError: timeout of 10000ms exceeded
```

Re-running cost nothing — attestation continues independently of our polling, and the prover
caches. **Our own worker sets a 60 s timeout** (`scripts/capture-proof.ts`) rather than inheriting
the default.

**The script exits 0 even when it fails.** `submit_query.ts` ends with `main().catch(console.error)`,
so a failed run is indistinguishable from a successful one by exit code. Attempt 1 "succeeded"
according to `$?` while having produced nothing. Success must be gated on the literal string
`Tokens minted!` — which is exactly what Gluwa's own CI greps for. Anything we build on top of
this SDK needs to check outcomes, not exit codes.

## Golden proof fixture

The proof for the burn transaction was re-fetched and saved to
[`contracts/test/fixtures/g0-proof.json`](../../../contracts/test/fixtures/g0-proof.json):

```
headerNumber   11482813
txBytes        3842 chars (~1.9 KB encoded transaction + receipt)
merkleProof    7 siblings
continuityProof 8 roots
```

Capturing it was free: the block was already attested so the prover served from cache, and no
transaction was sent. It gives us a **real** encoded transaction to unit-test `CreditRegistry`'s
decode-and-validate chain against, plus a proof replayable against the live precompile's `verify`
**view** in a fork test. Proofs are the one input we cannot invent — a hand-written `bytes` blob
would prove nothing about whether our decoding is correct.

## Reproducing

```bash
cd vendor/usc-testnet-bridge-examples          # pinned at 4ff9a3bf
yarn install
# set CREDITCOIN_WALLET_PRIVATE_KEY and SOURCE_CHAIN_RPC_URL in its .env
cast send --rpc-url $SOURCE_CHAIN_RPC_URL $SOURCE_CHAIN_CONTRACT_ADDRESS \
  "mint(uint256)" 50000000000000000000 --private-key $CREDITCOIN_WALLET_PRIVATE_KEY
cast send --rpc-url $SOURCE_CHAIN_RPC_URL $SOURCE_CHAIN_CONTRACT_ADDRESS \
  "burn(uint256)" 50000000000000000000 --private-key $CREDITCOIN_WALLET_PRIVATE_KEY
yarn hello_bridge:submit_query <BURN_TX_HASH>   # ~9 min
```

Private keys are redacted from the committed log; it contains no secrets.
