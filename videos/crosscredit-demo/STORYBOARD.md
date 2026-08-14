---
workflow: product-launch-video
mode: autonomous
message: "Your real Ethereum credit history can be proven on another chain, and priced as a loan"
audience: "Hackathon judges, protocol-literate, scoring depth of Attestcoin utilisation"
aspect: 1920x1080
length: 170s
fps: 30
---

# CrossCredit — storyboard

Eight beats, 170 seconds, one continuous ground. The film never cuts to a different world: it is one
dark bench surface throughout, and scenes arrive on it. That restraint is the point — the product is
about evidence, and evidence does not need a transition wipe.

**Motion budget.** One signature (the strike, beat 01), one recurring device (the score ladder
stepping on the read, beat 06), and one hard cut (the 850/1300 comparison, beat 07). Everything else
is a masked line rising, at 0.08s stagger on `expo.out`. If a movement is not carrying meaning it is
not in the film.

**Type.** Instrument Serif for the three sentences that matter, Inter Tight for captions, IBM Plex
Mono for every number, hash and address. Numbers are always mono — on this project mono means "this
is a real value read from a chain."

| # | In | Dur | Beat | On screen | Motion |
|---|---|---|---|---|---|
| 01 | 0:00 | 18s | Cold open | `0x76f30e3f…5b1A` alone. The punch descends and strikes; `800` and PLATINUM resolve. | **The strike**, rebuilt natively in CSS 3D. Address fades in, punch falls, impact, mark holds. |
| 02 | 0:18 | 22s | The problem | Five Aave repayments as five marks on an Ethereum rail; hard cut to a second chain where the same address is blank. | Marks arrive in sequence; the blank chain arrives with nothing and holds a beat too long. |
| 03 | 0:40 | 22s | The easy version that fails | `openLoan(1 wei) → repay(1 wei)` ×6 typing out; score climbing to Platinum; then the admission. | Terminal type-on, score climbs, everything drains except one line. |
| 04 | 1:02 | 20s | Who was the lender? | The question full-bleed in serif, held in silence. Then chainKey 3 resolving. | Line reveal, long hold, then the chain identity snaps in. |
| 05 | 1:22 | 28s | How it verifies | The two proofs, then the five checks arriving one line at a time. | Five checks stagger in on the read — the densest beat, deliberately unhurried. |
| 06 | 1:50 | 24s | The live demo | Batch tx hash and gas; then the score ladder 0→800 stepping with the numbers spoken. | Ladder steps once per spoken number; the final step lands on `800` and sits. |
| 07 | 2:14 | 20s | The payoff | `collateralRequired` for two borrowers: **850** against **1,300**. Then the closing line alone. | Both figures land on one hard cut, together. No sequence — the comparison IS the moment. |
| 08 | 2:34 | 16s | Honesty and sign-off | The twelve disclosures scrolling past; the mark; the URL. | Slow continuous scroll, then everything clears to the mark. |

## Frames

Built monolithic in `index.html` — eight clips on track 1 over a persistent ground on track 0, with
burned-in captions on track 2. Eight scenes does not justify the host-id risk of sub-compositions,
and one file keeps the whole 170s timeline legible in one place.

## Re-timing when the real audio lands

Every beat's in-point and duration is declared once in the `BEATS` array at the top of the script in
`index.html`. Changing those numbers re-times the entire film — clip windows, tween positions and
caption windows are all derived from it. Nothing else needs editing.
