---
workflow: product-launch-video
mode: autonomous
message: "Your real Ethereum credit history can be proven on another chain, and priced as a loan"
audience: "Hackathon judges, protocol-literate, scoring depth of Attestcoin utilisation"
aspect: 1920x1080
length: 137s
fps: 30
---

# CrossCredit — storyboard

Eight beats, 137 seconds, one continuous ground. The film never cuts to a different world: it is one
dark bench surface throughout, and scenes arrive on it. That restraint is the point — the product is
about evidence, and evidence does not need a transition wipe.

**Motion budget.** One signature (the strike, beat 01), one recurring device (the score ladder
stepping on the read, beat 06), and one comparison that arrives in two halves (850, then 1,300, beat 07). Everything else
is a masked line rising, at 0.08s stagger on `expo.out`. If a movement is not carrying meaning it is
not in the film.

**Type.** Instrument Serif for the three sentences that matter, Inter Tight for captions, IBM Plex
Mono for every number, hash and address. Numbers are always mono — on this project mono means "this
is a real value read from a chain."

| # | In | Dur | Beat | On screen | Motion |
|---|---|---|---|---|---|
| 01 | 0:00 | 9.8s | Cold open | `0x76f30e3f…5b1A` alone. The punch descends and strikes; `800` and PLATINUM resolve. | **The strike**, rebuilt natively in CSS 3D. Address fades in, punch falls, impact, mark holds. |
| 02 | 0:09.8 | 16.2s | The problem | Five Aave repayments as five marks on an Ethereum rail; hard cut to a second chain where the same address is blank. | Marks arrive in sequence; the blank chain arrives with nothing and holds a beat too long. |
| 03 | 0:26.0 | 18.9s | The easy version that fails | `openLoan(1 wei) → repay(1 wei)` ×6 typing out; score climbing to Platinum; then the admission. | Terminal type-on, score climbs, everything drains except one line. |
| 04 | 0:44.9 | 13.2s | Who was the lender? | The question full-bleed in serif, held in silence. Then chainKey 3 resolving. | Line reveal, long hold, then the chain identity snaps in. |
| 05 | 0:58.1 | 24.8s | How it verifies | The two proofs, then the five checks arriving one line at a time. | Five checks stagger in on the read — the densest beat, deliberately unhurried. |
| 06 | 1:22.8 | 21.4s | The live demo | Batch tx hash and gas; then the score ladder 0→800 stepping with the numbers spoken. | Ladder steps once per spoken number; the final step lands on `800` and sits. |
| 07 | 1:44 | 13s | The payoff | `collateralRequired` for two borrowers: **850** against **1,300**. Then the closing line alone. | 850 lands at 105.1s, 1,300 at 112.3s. **The plan had them arriving together; the take separates them by seven seconds, so they arrive apart.** The read wins — and it is better, because you sit with 850 before the comparison lands. |
| 08 | 1:57.3 | 19.7s | Honesty and sign-off | The twelve disclosures scrolling past; the mark; the URL. | Slow continuous scroll, then everything clears to the mark. |

## Frames

Built monolithic in `index.html` — eight clips on track 1 over a persistent ground on track 0, with
burned-in captions on track 2. Eight scenes does not justify the host-id risk of sub-compositions,
and one file keeps the whole 137s timeline legible in one place.

## The film is cut to the take

The voiceover is recorded and locked. **Every cue is positioned on a real timestamp** pulled from
`assets/transcript.json` (`npx hyperframes transcribe`), collected in the `T` map at the top of the
script in `index.html`. Nothing in the timing is an estimate.

The take runs 2:15 against the script's 2:50 estimate — read at roughly 190 wpm rather than 150 —
so re-timing meant moving cues onto words, not compressing the old spacing. Two consequences worth
recording:

- **The strike now falls through the entire cold open**, landing on "what happens next" at 8.51s.
  It reads better than the shorter fall it replaced: the punch is in the air for the whole opening
  claim.
- **The 850/1,300 comparison is sequential, not simultaneous.** See beat 07.

Captions are generated from the transcript rather than the script, so they carry what was actually
said. Whisper's mishearings of the domain terms are corrected in the generator — "credit coin" →
"Creditcoin", "six-way" → "six wei", and "who is the lender" → "who **was** the lender", which
otherwise contradicted the type on screen.

To re-cut against a new take: re-run `transcribe`, update `T`, regenerate the caption array.
