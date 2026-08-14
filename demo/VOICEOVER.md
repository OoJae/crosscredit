# CrossCredit — voiceover script

**Recorded: 2:15.** Under the 3:30 cap in `BUILD_GUIDE.md` §9. 16:9, 1080p, captions burned in.

> **This take is locked and the film is cut to it.** The read came in at ~190 wpm rather than the
> 150 this script estimated, so the delivered film is 2:17, not the 2:50 planned below. Every cue in
> the composition is positioned on a real timestamp from `videos/crosscredit-demo/assets/transcript.json`.
> If you re-record, re-run `npx hyperframes transcribe` and update the `T` map in `index.html` —
> nothing else needs touching.

**How to record this.** Read at roughly 150 words per minute — unhurried, low, closer to a
documentary narrator than a product ad. The silences are written in and they are load-bearing:
they are where the on-screen numbers land. Do not fill them.

**After you generate the audio in Clipchamp**, send me the file and the timings. I only need the
in-point of each numbered beat below; I will re-time the composition to your read rather than ask
you to fit mine.

---

## 01 — Cold open · 0:00–0:18

> This wallet has never sent a transaction to Creditcoin.
>
> *(beat)*
>
> It has never heard of us. It did not sign up, did not opt in, and could not have stopped what
> happens next.

**On screen:** the address `0x76f30e3f…5b1A` alone on black, mono, small. Then the hallmark strikes
and the score resolves to 800. No logo yet. No music yet.

---

## 02 — The problem · 0:18–0:40

> Everything a lender needs to know about it already exists — on Ethereum. Five loans from Aave,
> every one repaid.
>
> But credit history does not travel. So on every other chain, this borrower is a stranger, and a
> stranger posts a hundred and fifty percent collateral.

**On screen:** the five Aave repayments as five marks on Ethereum, then a hard cut to a second chain
where the same address is blank.

---

## 03 — The one question · 0:40–1:02

> There is an easy version of this that does not work.
>
> Our first build read repayments from our own contract. It had no lender. So six wei, twelve
> transactions and one wallet reached the top tier — and every proof was cryptographically valid.
>
> *(beat)*
>
> We had built a rigorous pipeline for the high-integrity delivery of worthless data.

**On screen:** `openLoan(1 wei) → repay(1 wei) × 6` typing out, the score climbing to Platinum, then
the whole frame going quiet as the last line lands.

---

## 04 — What fixed it · 1:02–1:22

> The question that exposes it is one sentence. Who was the lender?
>
> You cannot fake an Aave loan. So we read the chain where the lenders are. Creditcoin attests
> Ethereum mainnet — undocumented, and the thing this project turns on.

**On screen:** "Who was the lender?" full-bleed in the serif, held. Then chainKey 3 resolving.

---

## 05 — How it verifies · 1:22–1:50

> A Merkle inclusion proof says the transaction is in the block. A continuity proof says the block
> is really on Ethereum. Creditcoin's own precompile checks both, inside one block, in the contract.
>
> No oracle we run. No multisig we control. No bridge holding funds.
>
> Then five more checks run before a single point of score moves — because a valid proof of the
> wrong thing is still worthless.

**On screen:** the two proofs; then the five checks arriving in sequence, one line each.

---

## 06 — The live demo · 1:50–2:14

> Nine Sepolia transactions, verified in a single Creditcoin transaction, for a hundred and
> thirty-four thousand gas each.
>
> Five real Aave repayments, proven one at a time. Zero. Three-twenty. Four-forty. Five-sixty. Six-eighty.
> Eight hundred.
>
> Platinum, assembled entirely from transactions made somewhere else.

**On screen:** the batch tx hash, then the score ladder stepping up with the read.

---

## 07 — The payoff · 2:14–2:34

> Which buys this. Eight hundred and fifty of collateral, to borrow a thousand.
>
> And the same call, for a wallet whose history it dealt to itself, returns thirteen hundred.
>
> *(beat)*
>
> Their proofs are just as valid. Their evidence is not.

**On screen:** the two `collateralRequired` reads side by side — 850 against 1,300 — from the live
pool. The last line alone on black.

---

## 08 — Honesty · 2:34–2:50

> An audit found that a flash loan could buy that capacity for the price of gas. It is closed, it is
> tested, and it is written down — along with eleven other things we have not solved.
>
> Every number you just saw is live on testnet, from real mainnet history.
>
> CrossCredit. Proof, punched into metal.

**On screen:** the threat-model index scrolling past — all twelve, unhurried — then the mark, the
URL, and out.

---

## Word count and pacing

| Beat | Words | Seconds @150wpm | Notes |
|---|---|---|---|
| 01 | 38 | 15 + 3 beat | the cold open earns the pause |
| 02 | 53 | 21 | |
| 03 | 62 | 25 + 2 beat | |
| 04 | 44 | 18 | |
| 05 | 68 | 27 | densest beat; do not rush the five checks |
| 06 | 55 | 22 | read the ladder as numbers, evenly |
| 07 | 47 | 19 + 2 beat | |
| 08 | 56 | 22 | |
| | **423 words** | **≈ 2:49** | |

## Two notes on accuracy

The film says "verified inside one Creditcoin block", which is true of the verification itself.
It does **not** claim the whole journey is instant — Sepolia attestation runs about eight to ten
minutes ahead of it. If you ad-lib, keep that distinction; it is the one an informed judge checks.

"Undocumented" for mainnet chainKey 3 is our finding, in the sense that we found it in neither the
docs nor the examples. Phrase it as ours, not as a claim about what exists.
