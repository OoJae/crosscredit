# The CrossCredit scoring model

Implementation: [`contracts/src/creditcoin/ScoreLib.sol`](../contracts/src/creditcoin/ScoreLib.sol) ·
Tests: [`contracts/test/ScoreLib.t.sol`](../contracts/test/ScoreLib.t.sol)

A credit score is only as trustworthy as the data underneath it. CrossCredit's differentiator is
that **every input has been cryptographically verified** — each number below traces back to a
Sepolia transaction that Creditcoin's block-prover precompile confirmed for itself. So the model
on top can afford to be simple, transparent and fully on-chain rather than a black box.

Three properties are deliberate:

- **Deterministic.** No oracle, no off-chain model, no owner-tunable weights. Identical history
  always produces an identical score, and anyone can recompute it from public data.
- **Auditable in under a minute.** Five constants, one subtraction, one floor.
- **Predictable for the borrower.** You can work out in advance what repaying on time will do to
  your terms — the opposite of an opaque bureau score.

## The model

Range **0–1000**.

| Component | Points | Cap | Why |
|---|---|---|---|
| On-time repayment | **+100** each | 600 | The dominant signal. Repaying on time, repeatedly, *is* creditworthiness |
| Loan fully repaid | **+40** each | 120 | Rewards finishing, not just servicing — a borrower who closes loans is a better risk than one who pays indefinitely |
| Volume repaid | **+1** per 0.0001 ETH | 200 | Size matters, but capped so a single large repayment cannot buy a tier that conduct should earn |
| Collateral posted | **+1** per 0.0001 ETH | 80 | Skin in the game — but it is capital, not behaviour, so it is weighted well below repayment history |
| **Late repayment** | **−150** each | — | Deliberately larger than the on-time reward |

Positive components are capped individually, summed, then penalties are subtracted with a
**saturating floor at zero** (never underflows, never wraps).

### Why one default costs more than one success earns

If a late repayment cost the same as an on-time one gained, a borrower could farm a high score by
borrowing recklessly and repaying often — volume would drown out reliability. At −150 against
+100, a single default wipes out the credit earned by the repayment that caused it *and* some of
the record before it. This is exactly what Borrower B's real profile shows below.

## Tiers

| Tier | Requires | Collateral | APR |
|---|---|---|---|
| Bronze | < 250 | 150% | 14% |
| Silver | ≥ 250 | 130% | 11% |
| Gold | ≥ 500 | 110% | 8% |
| **Platinum** | ≥ 700 **and `late == 0`** | **85% — undercollateralized** | 6% |

Platinum carries an extra rule because it is the one tier that lends more than the borrower posts.
A borrower can accumulate enough points to clear 700 despite a historical default; that earns
Gold, not uncollateralized credit. *(Collateral ratios and rates are enforced by `LendingPool` in
Phase 3; the tiers themselves are live now.)*

## Calibration against real history

The original spec scored volume per 0.01 ETH. Against the 0.001–0.002 ETH loans a faucet-funded
testnet demo can afford, that rounds to **zero** — the volume term would have been decorative.
Rescaling to per-0.0001 ETH keeps the component meaningful at demo scale while preserving its
shape.

Constants were then calibrated against the **actual seeded history** on Sepolia
([`evidence/seeded-history.json`](evidence/seeded-history.json)), not against hypotheticals:

### Borrower A — `0x8ce707…89c6`, a clean record

3 loans opened and closed · 5 on-time repayments · 0 late · 0.006 ETH repaid · 0.003 ETH collateral

```
on-time     min(5 × 100, 600) = 500
closed      min(3 ×  40, 120) = 120
volume      min(0.006e18 / 1e14, 200) =  60
collateral  min(0.003e18 / 1e14,  80) =  30
penalty     0 × 150            =   0
                                 ─────
                                   710   →  Platinum (≥700, late == 0)
```

### Borrower B — `0x04163f…A0B6`, one default

1 loan opened and closed · 0 on-time · **1 late** · 0.002 ETH repaid · no collateral

```
closed 40 + volume 20 = 60
penalty                 150
                        ────
                     −90 → floors at 0   →  Bronze
```

**Both figures are asserted on-chain and in the test suite.** `test_calibration_borrowerAReachesPlatinum`
requires exactly 710; the live CC3 registry returns exactly 710. Retuning any constant fails that
test, so the demo narrative cannot silently drift out from under the model.

## Deliberately not scored (yet)

- **Longevity.** The profile records `firstSeen`, and mature credit systems reward account age —
  but a history seeded inside a hackathon window cannot demonstrate it honestly, so it contributes
  nothing rather than contributing a rigged constant.
- **Utilisation, delinquency depth, recency weighting.** Real underwriting weights a default from
  last month differently from one three years ago. That belongs in a system with real history
  behind it; claiming it here would be theatre.

The interesting claim CrossCredit makes is not that this model is sophisticated. It is that the
**inputs are trustless** — and a simple model over verified data is far more defensible than a
sophisticated one over data you were asked to take on faith.
