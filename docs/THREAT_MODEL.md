# Threat model, and what CrossCredit has not solved

Undercollateralized lending is a category with a graveyard. Maple lost $36M to a borrower who
misrepresented its FTX exposure and has since [publicly abandoned unsecured
lending](https://www.dlnews.com/articles/defi/crypto-lender-maple-ditches-under-collateralised-lending/)
("no one's profitable"). Goldfinch wrote off ~$18M across three defaults and shut its credit
platform. TrueFi's operator filed Chapter 11. Spectral, the best-funded on-chain credit score, is
now an AI-agent company.

Every one of those failures was a **disclosure** failure, not a modelling failure. So this document
states what CrossCredit does not solve, before anyone else has to.

---

## The flaw that shaped the design

An earlier version of this project read one source: our own `LoanBook` on Ethereum Sepolia. That
contract is permissionless, escrows nothing, and takes a **self-declared** `uint256` principal.
There is no lender.

```
openLoan(principal = 1 wei) → repay{value: 1 wei}(loanId)     × 6
```

Six wei. Twelve transactions. One wallet. Under the old scoring model that reached **Platinum and
unlocked 85% LTV** — and every event was cryptographically true. The Merkle inclusion proof was
valid, the continuity proof was valid, the precompile verified correctly. We had built a rigorous
pipeline for the high-integrity delivery of worthless data.

The question that exposes it is one sentence: **who was the lender?**

Sybil resistance was never the real issue. A thousand wallets is the *expensive* version of an
attack that already worked with one.

### What fixed it

Reading **Aave V3 on Ethereum mainnet**, which Creditcoin attests as chainKey 3. You cannot fake an
Aave loan: Aave's pool is a real counterparty whose capital was genuinely at risk. The verification
path is unchanged — only the evidence is real.

Three things enforce it:

1. **Self-reported signals are capped below the top tier.** A *perfect, decade-long, ENS-backed*
   `LoanBook` record tops out at **Gold**. `ScoreLib.t.sol` fails if anyone loosens a cap enough to
   undo that. Our own seeded Borrower A dropped from 710/Platinum to 390/Silver, and that drop is
   the fix.
2. **Undercollateralized credit is capped by demonstrated capacity** — the largest single repayment
   proven against a real third-party protocol. A wallet with a Platinum tier but no real history
   gets **no discount at all**.
3. **Capacity is conserved across identities.** Splitting a history over a thousand wallets divides
   capacity rather than multiplying it. This is the conservation result formalised in
   [arXiv:2605.03307](https://arxiv.org/pdf/2605.03307): extra pseudonyms cannot create extra
   capacity. `test_capacityCap_isInvariantUnderIdentitySplitting` asserts exactly this.

Sybil resistance here is **priced, not prevented** — which is what the whole field actually does,
whether or not it says so.

---

## Why not proof of personhood

The obvious alternative is to demand a human credential. We implemented it — the registry can
ingest Proof of Humanity events from mainnet — and then measured whether it means anything.

`npm run poh:negative` takes five real 2021 PoH registrations, proves each to Creditcoin, and asks
mainnet whether those people are registered today:

```
5/5 registrations proved to Creditcoin successfully.
0/5 of those humans are still registered today.
```

That is not a bug. It is the precompile working exactly as documented: **it proves that an event
occurred, not that a state holds.** For a repayment those coincide — a repayment that happened
stays happened. For an identity they do not, and no proof of the original event can tell you
whether the registration has since expired, been revoked, or been transferred.

The population problem is worse than the semantics problem. PoH v1 has accepted no registrations in
roughly two years and its two-year expiry means the whole cohort has lapsed. PoH v2 on mainnet holds
**55 humanities** — the real population lives on Gnosis, which Creditcoin does not attest. Mainnet
EAS has 14,398 attestations ever and no personhood schema with real usage. Worldcoin's mainnet
contract emits batched Merkle roots with no per-human address.

So personhood is implemented and honest about being decorative. Economics does the work.

---

## What is still unsolved

### 1. There is no enforcement layer

If a borrower takes an undercollateralized loan and walks away, their score drops. That is all.

Every serious protocol in this category answers this with **off-chain legal recourse**: 3Jane
auctions defaulted debt to licensed US collection agencies and skip-traces with TLOxp; Maple,
TrueFi and Clearpool sign loan agreements with named legal entities; Goldfinch and 3Jane hold
first-loss junior tranches that eat the default. "Your score goes down" is nobody's enforcement
mechanism — it is everybody's *pricing* mechanism.

CrossCredit has the pricing layer and no enforcement layer. The capacity cap bounds the damage —
you cannot borrow undercollateralized beyond what you have demonstrably repaid — but it does not
make anyone whole.

### 2. Proofs are monotone-positive

Users prove facts about themselves, and nobody is obliged to prove the unflattering ones. A borrower
imports their Aave repayments and simply declines to import their liquidation.

Partially mitigated by the fact that **anyone can import anyone's history** — ingestion is
permissionless, and the borrower is read from an indexed topic rather than `msg.sender`, so a
lender, a competitor, or a bot can submit the liquidation the borrower omitted. That makes omission
contestable rather than impossible, which is weaker than a complete view.

A real deployment would index all registered sources continuously rather than waiting to be asked.

### 3. A soulbound token is bound to an address, and addresses are for sale

`CreditTierSBT` is ERC-5192: transfers revert, approvals revert, there is no burn. But the *address*
that holds it can be sold with its private key. This is the exact criticism levelled at Spectral's
non-fungible credit in 2021, and ERC-5192 does not answer it.

The capacity cap limits the payoff — buying a Platinum wallet buys a rate, not an unbounded credit
line — but it does not prevent the sale.

### 4. Capital-rich sybils

Capacity is proportional to capital demonstrably repaid, not to headcount. Someone with $10M can
build ten addresses each with $1M of genuine Aave history and get capacity for each.

The conservation theorem handles this *correctly* — they receive capacity proportional to capital
risked, which is the intended behaviour — but it means this is **one-dollar-one-vote, not
one-person-one-vote**. It is a sybil *cost* mechanism, not a sybil *proof* mechanism.

### 5. Wash lending

Borrowing from Aave and repaying immediately produces a genuine `Repay` event at the cost of gas
plus a few seconds of interest.

Partly mitigated: capacity is the **largest single repayment**, not the sum, so repeating a small
loan a thousand times demonstrates the ability to handle the small loan only. Scaling capacity by
*duration* of debt held — the integral of exposure over time — would close it properly and is the
obvious next iteration.

### 6. Units are normalised; value is not

Aave denominates repayments in each reserve's own units. `registerReserve` records decimals so USDC
(6dp) and WETH (18dp) are comparable — a real bug caught by the first live run, where a genuine
789 USDT repayment was rounding to zero capacity.

But **no price conversion happens**: one USDC and one DAI are treated alike, and so is one WETH.
A price feed for a foreign chain's assets is precisely the oracle dependency this project exists to
avoid. Stablecoins dominate Aave borrowing so face value is a fair approximation for most activity,
but a WBTC-denominated history would be understated and this should be stated in any pitch.

### 7. The source allowlist is a trust decision

The *proofs* are trustless. Which contracts count as credit sources is curated by the registry
owner. Registering a malicious contract as `AaveV3` would let it mint credit history.

This is deliberate and, we think, irreducible: something has to decide that Aave's `Repay` means
creditworthiness and a random contract's identically-shaped event does not. A production deployment
should move it behind governance or a timelock. Today it is an owner key.

### 8. Attestor trust — and a correction to our own earlier copy

Earlier versions of this README said "no oracle operator." That was an overclaim. The Attestcoin
Protocol has a **decentralized attestor network** reaching consensus on source-chain histories; the
precompile verifies proofs against their attestations.

The accurate claim is narrower and still strong: **no additional trust beyond the chain you are
already settling on.** There is no oracle *we* run, no multisig *we* control, and no bridge holding
funds — but Creditcoin's attestor set is in the trust path, and pretending otherwise would be the
first thing a knowledgeable judge caught.

### 9. Continuity proofs expire

A proof anchors to the attestation state at generation time and stops verifying once attestation
advances past its anchor — even though the underlying transaction is untouched. We found this when
the negative-path script failed its own baseline using a proof captured hours earlier.

Operationally: fetch proofs fresh and submit promptly. Stored fixtures are for decoder tests only.
Not documented anywhere we could find.

---

## What we would build next, in order

1. **Duration-weighted capacity** — score the integral of debt held over time, not repayment count.
   Closes wash lending properly.
2. **Continuous indexing of all registered sources**, so a borrower's liquidations arrive whether or
   not they want them. Blunts the monotone-positive problem.
3. **A first-loss tranche.** The only mechanism in this category that has ever survived a default is
   somebody's junior capital absorbing it.
4. **Governance on the source allowlist** — timelock, then a council.
5. **Price normalisation**, once there is a trust-minimised way to get foreign asset prices that
   does not reintroduce an oracle.

---

## Reproducing the claims here

```bash
npm run poh:negative      # 5/5 identities proved, 0/5 still valid
npm run negative-paths    # 5 attacks rejected by the live precompile
forge test                # 163 tests, including the self-dealt and capacity-invariance properties
```
