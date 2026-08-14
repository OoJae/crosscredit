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
   capacity rather than multiplying it, because capacity is the largest single repayment rather
   than a sum. `test_capacityCap_isInvariantUnderIdentitySplitting` asserts exactly this.

   **A correction to our own earlier citation.** Previous versions cited
   [arXiv:2605.03307](https://arxiv.org/pdf/2605.03307) as "the conservation theorem" behind this
   property, in three places. The paper is real and the intuition is related, but it formalises
   **sponsor-delegated** capacity, where conservation follows from sponsors bearing loss recourse
   along the delegation path. CrossCredit has no sponsors and no recourse, so it does not inherit
   the theorem — our invariance is a direct consequence of using a maximum instead of a sum, which
   is a much smaller claim and one we can actually prove. We cite the paper now as related work,
   not as authority. A judge who reads it would have caught this, and should have.

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

### 5. Wash lending, and the flash loan that broke our first answer

Borrowing from Aave and repaying immediately produces a genuine `Repay` event at the cost of gas
plus a few seconds of interest.

**Our original mitigation was wrong, and an audit proved it.** We argued that capacity being the
*largest single* repayment bounded this, because repeating a small loan demonstrates only the small
loan. That bound exists only if loan size is bounded by the attacker's own capital — and a flash
loan removes exactly that bound. Worse, largest-single is precisely the metric a flash loan
maximises.

The attack, in one transaction, with **zero capital at risk for any length of time**: flash-loan
8,000,000 USDC at 0% fee, supply it, borrow against it, repay immediately, withdraw, return the
flash loan. Aave V3 imposes no same-block borrow/repay restriction. Every log is genuine, every
proof verifies. And because `_ingestTransaction` had no per-transaction cap, five `Repay` logs in
that one transaction scored five repayments — 600 points — so **one proof reached Platinum**.

Two fixes, both live:

1. **Same-transaction detection.** A pre-scan pairs each `Repay` against any `Borrow` of the same
   reserve, for the same account, from the same registered pool in the same transaction. When they
   match, the repayment still counts but grants **no capacity**. A flash loan cannot span blocks,
   so this kills the zero-capital variant specifically while leaving a borrower who genuinely
   repays one debt and opens another untouched. Five tests pin both directions.
2. **One repayment credit per proven transaction**, however many `Repay` logs it carries.

**What this still does not close.** A *multi-block* wash loan — genuinely borrowing, holding the
debt across blocks, paying real interest, then repaying — is bounded only by the interest paid,
which is small for a short hold. Closing it properly needs capacity weighted by the **integral of
debt held over time**, which we have not built. Until then, capacity means "this address has
repaid this much at least momentarily", not "this address can carry this much".

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

### 10. A key of ours reached a public repository

`scripts/seed-borrower-c.ts` wrote the demo borrower's private key into
`docs/evidence/borrower-c-history.json` — a **committed** artifact — and it was pushed publicly on
Aug 13 2026 and sat there for about 26 hours. It controlled a testnet-only wallet holding 0.02
Sepolia ETH and 15 tCTC. The deployer key was never committed.

The interesting part is not the funds, which were worthless. It is that anyone holding that key
could have opened and repaid loans *as that borrower* on Sepolia — and because ingestion is
permissionless, proven the result. A single late repayment would have permanently altered the
profile the demo is built on.

Three changes: the script no longer records a key at all (the wallet is generated per run and its
key discarded, never printed, never written); the borrower was rotated by re-seeding; and CI now
fails on any committed field named like a secret, or on `.env` becoming tracked. The gate was
replayed against the original leaked blob and catches it.

Git history was **not** rewritten. The key is a throwaway, already rotated, and a force-push during
judging risks breaking links a reviewer has already opened. Disclosure plus rotation is the better
trade; pretending it never happened is not one of the options.

### 11. Third parties could brand you late, and could brand you at all

Two related holes, both now closed, both worth stating because they are the kind that survive in
production systems for years.

`LoanBook.repay` is permissionless — a friend settling your debt should build *your* reputation —
but the event omitted `msg.sender`. So a stranger could settle **1 wei** on your past-due loan and
stamp an indelible `late` on your profile: −150 points and Platinum barred for ever, for the price
of gas. The event now carries an indexed `payer`, and the penalty applies only when the borrower
paid for themselves. Credit for the repayment still accrues to the borrower whoever pays.

Separately, `CreditTierSBT.sync` would mint for any address. The badge is permanent,
non-transferable and unburnable by construction, so anyone could brand any wallet Bronze for ever.
The initial mint now requires either the borrower themselves or a genuine verified history.

### 12. The age term rests on an owner-supplied anchor

Source-chain time is not provable. Aave, ENS and Proof of Humanity emit no timestamp, and the
precompile proves transactions rather than block headers, so the only temporal fact covered by a
proof is the **block height**. `registerChainAnchor` converts height to time against an
owner-registered `(height, timestamp, secondsPerBlock)` reference.

That is a trusted input and an approximation. Measured against our own headline transaction it
drifts 3.8 days over 1.8 years (0.55%), well inside the 30-day granularity the term scores in — but
a dishonest anchor could inflate everyone's age term, and a chain that changed its block time would
skew it. It is bounded (120 points) and it replaced something strictly worse: before it, the term
measured time since *import*, which rewarded importing early and idling.

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
npm run check:abi         # the frontend ABI matches the compiled contracts
forge test                # 214 tests, including the flash-loan guard, the capacity high-water
                          # rule, the age axis, and the self-dealt ceiling
```
