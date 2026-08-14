# The CrossCredit scoring model

Implementation: [`contracts/src/creditcoin/ScoreLib.sol`](../contracts/src/creditcoin/ScoreLib.sol) ·
Tests: [`contracts/test/ScoreLib.t.sol`](../contracts/test/ScoreLib.t.sol) ·
Limits: [`THREAT_MODEL.md`](THREAT_MODEL.md)

A credit score is only as trustworthy as the data underneath it. Every input below traces back to
an Ethereum transaction that Creditcoin's block-prover precompile verified for itself, so the model
on top can afford to be simple, transparent and fully on-chain rather than a black box.

Three properties are deliberate:

- **Deterministic.** No oracle, no off-chain model, no owner-tunable weights. Identical history
  always produces an identical score, and anyone can recompute it from public data. Every
  comparable system — Spectral, Cred, Nomis, RociFi — computes off-chain and delivers a number by
  API. This one computes inside the EVM of the chain that verified the evidence.
- **Auditable in under a minute.** Eight constants, one subtraction, one floor.
- **Predictable for the borrower.** You can work out in advance what repaying will do to your terms.

## The one distinction the model is built around

**Who was the lender?**

CrossCredit reads two kinds of source and refuses to treat them as equivalent evidence:

| | Our `LoanBook` (Sepolia) | Aave V3 / Sparklend (Ethereum mainnet) |
|---|---|---|
| Counterparty | **None.** Permissionless, escrows nothing, self-declared `uint256` principal | A real pool with real capital at risk |
| Cost to fabricate a perfect record | Gas | The loan |
| Has due dates | Yes → `onTime` / `late` | No — Aave has no due dates |
| Real negative signal | `late` | `LiquidationCall` |
| Can raise borrowing capacity | **No** | **Yes** |

An earlier version of this project read only the first column. `openLoan(1 wei) → repay(1 wei)`
six times reached Platinum and unlocked 85% LTV, for six wei, from one wallet — with every proof
cryptographically valid. The model below exists to make that impossible.

## The model

Range **0–1000**.

### Self-reported signals — capped below the top on purpose

| Component | Points | Cap |
|---|---|---|
| On-time repayment (`LoanBook`) | **+60** each | 360 |
| Loan fully repaid | **+30** each | 90 |
| **Late repayment** | **−150** each | — |

### Mainnet signals — where the weight sits

| Component | Points | Cap |
|---|---|---|
| Repayment to a real third-party protocol | **+120** each | 600 |
| Demonstrated capacity | **+1** per 0.01 ETH-equivalent repaid | 200 |
| **Liquidation** | **−250** each | — |

### Time and identity

| Component | Points | Cap |
|---|---|---|
| Age of proven history | **+10** per 30 days | 120 |
| Live ENS name or PoH humanity | **+60** | 60 |

Positive components are capped individually, summed, then penalties are subtracted with a
**saturating floor at zero** (never underflows, never wraps).

## Three load-bearing properties

**1. A perfect self-dealt record cannot reach Platinum.** Ceiling for a `LoanBook`-only borrower:
360 + 90 + 120 (a decade of age) + 60 (ENS) = **630**, against a Platinum threshold of 700. Our
own seeded Borrower A dropped from 710/Platinum to **390/Silver** when this landed, and that drop
is the fix, not a regression. `test_selfDealtHistoryCannotReachPlatinum` fails if any cap is
loosened enough to undo it.

**2. Time cannot be compressed.** Six repayments in six blocks and six over six months scored
identically before the age term existed. Wall-clock age is the single input a scripted attacker
cannot fabricate.

**3. A liquidation costs more than a late payment.** −250 against −150: being liquidated means a
third party lost patience and seized collateral, which is materially worse than paying our toy
contract late.

## Tiers

| Tier | Requires | Collateral | APR |
|---|---|---|---|
| Bronze | < 250 | 150% | 14% |
| Silver | ≥ 250 | 130% | 11% |
| Gold | ≥ 500 | 110% | 8% |
| **Platinum** | ≥ 700 **and `late == 0` and `liquidations == 0`** | **85%** | 6% |

Platinum carries the extra rule because it is the one tier that lends more than the borrower posts.
A borrower can clear 700 points despite a historical default; that earns Gold.

## The tier is not the credit line

This is the part that matters most, and it lives in
[`LendingPool.collateralRequired`](../contracts/src/creditcoin/LendingPool.sol):

> The tier sets your **rate**. `demonstratedCapacityWei` — the largest single amount you have
> provably repaid to a real third-party protocol — sets the **ceiling on how much you may borrow
> above what you post**. Everything beyond it is fully collateralized.

A wallet holding Platinum with zero demonstrated capacity gets the Platinum *rate* on a fully
collateralized loan and **no discount at all**. Live, right now, that is exactly what the three
Sepolia demo borrowers show: Silver tiers, zero capacity, zero undercollateralized portion.

It also gives sybil resistance an arithmetic rather than an identity answer. Capacity is the
*largest single* repayment, not the sum, so splitting a history across a thousand wallets divides
capacity instead of multiplying it — the conservation result formalised in
[arXiv:2605.03307](https://arxiv.org/pdf/2605.03307), asserted by
`test_capacityCap_isInvariantUnderIdentitySplitting`. We tried the identity route first and
measured it failing; see [`THREAT_MODEL.md`](THREAT_MODEL.md#why-not-proof-of-personhood).

## Calibration against real history

Constants are calibrated against **live on-chain profiles**, not hypotheticals.

### A real Ethereum wallet — `0x76f30e…5b1A`

This address has never interacted with Creditcoin. Its entire profile was built by proving five of
its genuine Aave V3 repayments from Ethereum mainnet, one `execute` each:

```
score  0 → 320 → 440 → 560 → 680 → 800     tier Bronze → Silver → Gold → Platinum

mainnet repayments  min(5 × 120, 600) = 600
capacity            min(960145e18 / 1e16, 200) = 200
                                        ─────
                                          800   →  Platinum, and a real credit line
```

Its quote from the live pool: **850 collateral to borrow 1000**, with the full 1000 counted as
undercollateralized because capacity (~$960k) far exceeds it.

### Borrower A — `0x8ce707…89c6`, self-dealt but spotless

3 loans closed · 5 on-time · 0 late · imported by 11 separate proofs

```
on-time     min(5 × 60, 360) = 300
closed      min(3 × 30,  90) =  90
capacity                        0     ← no third party was ever involved
                              ─────
                                390   →  Silver, and zero undercollateralized credit
```

### Borrower B — `0x04163f…A0B6`, one default

```
closed 30 − penalty 150 = −120 → floors at 0   →  Bronze
```

### A calibration error this caught

The mainnet repayment cap was originally 480. With the capacity cap at 200 that puts a
mainnet-only borrower's ceiling at **680** — permanently twenty points short of Platinum, making
the top tier unreachable by exactly the evidence it is supposed to require. Found by watching a
real borrower stall at 680/Gold on the live registry, not in a test. The cap is now 600 and
`test_mainnet_platinumReachableWithoutAgeOrIdentity` pins it.

## Deliberately not scored

- **Price.** Aave denominates repayments in each reserve's own units. `registerReserve` records
  decimals so USDC (6dp) and WETH (18dp) are comparable — a real bug caught on the first live run,
  where a genuine 789 USDT repayment was rounding to zero capacity. But no *price* conversion
  happens: one USDC and one WETH count alike. A price feed for a foreign chain's assets is
  precisely the oracle dependency this project exists to avoid.
- **Duration of exposure.** Capacity should scale with the integral of debt held over time, which
  would close wash lending (borrow and instantly repay) properly. Capping on the largest single
  repayment blunts it; it does not close it. This is the first thing we would build next.
- **Recency decay.** Belongs in a system with years of history, not a hackathon window.
