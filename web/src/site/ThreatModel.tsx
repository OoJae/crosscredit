import {PageShell} from './PageShell';
import {PageHead, Section, P, Mono, NumberedItem} from './Prose';

/**
 * The disclosure page — `docs/THREAT_MODEL.md` in full.
 *
 * Deliberately the quietest page on the site: no display type below the masthead, no reveal
 * choreography beyond the shared one, no accent except the numbers. A page admitting a leaked key
 * and a retracted citation should not look pleased with itself, and the content is the effect.
 *
 * All twelve items, in order. An accordion here would hide items 6–12 behind a click and quietly
 * undo the only reason the page exists.
 */

export default function ThreatModel() {
  return (
    <PageShell>
      <PageHead
        eyebrow="Disclosure"
        title={
          <>
            What this <em>does not</em> solve.
          </>
        }
        lede="Undercollateralized lending is a category with a graveyard. Maple lost $36M and has publicly abandoned unsecured lending. Goldfinch wrote off ~$18M and shut its credit platform. TrueFi's operator filed Chapter 11. Every one of those was a disclosure failure, not a modelling failure — so here is ours, before anyone else has to write it."
      />

      <Section label="The flaw that shaped the design" title="Six wei reached the top tier.">
        <P>
          An earlier version read one source: our own loan contract on Sepolia. It is permissionless,
          escrows nothing, and takes a self-declared principal. There is no lender.
        </P>
        <pre className="mt-8 overflow-x-auto rounded-sm border border-ink-700 bg-ink-900/60 p-5 font-mono text-sm text-ash">
          <code>openLoan(principal = 1 wei) → repay&#123;value: 1 wei&#125;(loanId)     × 6</code>
        </pre>
        <div className="mt-8">
          <P>
            Six wei. Twelve transactions. One wallet. That reached Platinum and unlocked 85% LTV —
            and every event was cryptographically true. The Merkle proof was valid, the continuity
            proof was valid, the precompile verified correctly.
          </P>
          <P tone="vellum">
            We had built a rigorous pipeline for the high-integrity delivery of worthless data.
          </P>
          <P>
            Sybil resistance was never the real issue. A thousand wallets is the expensive version of
            an attack that already worked with one. What fixed it was reading Aave on Ethereum
            mainnet, where the counterparty is real — the verification path never changed, only the
            evidence did.
          </P>
        </div>
      </Section>

      <Section label="Why not proof of personhood" title="5 of 5 proved. 0 of 5 still valid.">
        <P>
          The obvious alternative is to demand a human credential. We implemented it — the registry
          ingests Proof of Humanity events from mainnet — and then measured whether it means
          anything. Five real 2021 registrations, each proved to Creditcoin, then mainnet asked
          whether those people are registered today.
        </P>
        <P>
          Every proof succeeded. Every registration has lapsed. That is not a bug; it is the
          precompile working exactly as documented: <span className="text-vellum">it proves that an
          event occurred, not that a state holds.</span> For a repayment those coincide — a repayment
          that happened stays happened. For an identity they do not, and no proof of the original
          registration can tell you whether it has since expired, been revoked or been transferred.
        </P>
        <P>
          The population problem is worse than the semantics problem. PoH v2 on mainnet holds 55
          humanities; the real population lives on Gnosis, which Creditcoin does not attest. So
          personhood is implemented and honest about being decorative. Economics does the work.
        </P>
      </Section>

      <Section label="Still unsolved" title="Twelve things, in order.">
        <ol className="mt-4">
          <NumberedItem n={1} title="There is no enforcement layer">
            <P>
              If a borrower takes an undercollateralized loan and walks away, their score drops. That
              is all. Every serious protocol in this category answers this with off-chain legal
              recourse — 3Jane auctions defaulted debt to licensed collection agencies; Maple and
              Clearpool sign agreements with named legal entities; Goldfinch holds a first-loss
              tranche. &ldquo;Your score goes down&rdquo; is nobody&rsquo;s enforcement mechanism. It
              is everybody&rsquo;s pricing mechanism. We have the pricing layer and no enforcement
              layer.
            </P>
          </NumberedItem>

          <NumberedItem n={2} title="Proofs are monotone-positive">
            <P>
              Users prove facts about themselves and nobody is obliged to prove the unflattering
              ones. A borrower imports their repayments and declines to import their liquidation.
              Partially mitigated because anyone can import anyone&rsquo;s history — the borrower is
              read from an indexed topic, not <Mono>msg.sender</Mono> — so a lender or a bot can
              submit what was omitted. That makes omission contestable rather than impossible.
            </P>
          </NumberedItem>

          <NumberedItem n={3} title="A soulbound token is bound to an address, and addresses are for sale">
            <P>
              Transfers revert, approvals revert, there is no burn. But the address holding it can be
              sold with its private key. This is the exact criticism levelled at Spectral&rsquo;s
              non-fungible credit in 2021 and ERC-5192 does not answer it. The capacity cap limits
              the payoff — buying a Platinum wallet buys a rate, not an unbounded credit line — but
              it does not prevent the sale.
            </P>
          </NumberedItem>

          <NumberedItem n={4} title="Capital-rich sybils">
            <P>
              Capacity is proportional to capital demonstrably repaid, not to headcount. Someone with
              $10M can build ten addresses each with $1M of genuine history and get capacity for
              each. That is the intended behaviour, but it means this is one-dollar-one-vote, not
              one-person-one-vote — a sybil <span className="text-vellum">cost</span> mechanism, not a
              sybil <span className="text-vellum">proof</span> mechanism.
            </P>
          </NumberedItem>

          <NumberedItem n={5} title="Wash lending, and the flash loan that broke our first answer">
            <P>
              Our original mitigation was wrong, and an audit proved it. We argued that capacity being
              the largest single repayment bounded this. That bound only exists if loan size is
              bounded by the attacker&rsquo;s own capital — and a flash loan removes exactly that
              bound, while largest-single is precisely what a flash loan maximises.
            </P>
            <P>
              One transaction: flash-loan 8,000,000 USDC at zero fee, supply, borrow, repay
              immediately, withdraw, return the loan. Aave V3 imposes no same-block restriction. Every
              log genuine, every proof valid, and with no per-transaction cap five{' '}
              <Mono>Repay</Mono> logs scored five repayments — <span className="text-vellum">one
              proof reached Platinum.</span>
            </P>
            <P>
              Now closed by pairing each repayment against a borrow of the same reserve, for the same
              account, from the same pool, in the same transaction; a flash loan cannot span blocks.
              What it does <span className="text-vellum">not</span> close is a multi-block wash loan,
              where the attacker genuinely holds the debt and pays real interest. Bounding that needs
              capacity weighted by the integral of debt over time, which we have not built.
            </P>
          </NumberedItem>

          <NumberedItem n={6} title="Units are normalised; value is not">
            <P>
              Reserve decimals are registered so a 6-decimal USDC repayment and an 18-decimal WETH one
              are comparable — a real bug caught on the first live run, where a genuine 789 USDT
              repayment was rounding to zero capacity. But no price conversion happens: one USDC and
              one WETH count alike. A price feed for a foreign chain&rsquo;s assets is precisely the
              oracle dependency this project exists to avoid.
            </P>
          </NumberedItem>

          <NumberedItem n={7} title="The source allowlist is a trust decision">
            <P>
              The proofs are trustless. Which contracts count as credit sources is curated by the
              registry owner, and registering a malicious contract would let it mint credit history.
              This is deliberate and, we think, irreducible — something has to decide that
              Aave&rsquo;s <Mono>Repay</Mono> means creditworthiness and a random contract&rsquo;s
              identically-shaped event does not. A production deployment should move it behind a
              timelock. Today it is an owner key.
            </P>
          </NumberedItem>

          <NumberedItem n={8} title="Attestor trust — and a correction to our own earlier copy">
            <P>
              Earlier versions of this project said &ldquo;no oracle operator.&rdquo; That was an
              overclaim. The protocol has a decentralized attestor network reaching consensus on
              source-chain histories, and the precompile verifies against their attestations. The
              accurate claim is narrower and still strong:{' '}
              <span className="text-vellum">no additional trust beyond the chain you are already
              settling on.</span>
            </P>
          </NumberedItem>

          <NumberedItem n={9} title="Continuity proofs expire">
            <P>
              A proof anchors to attestation state at generation time and stops verifying once
              attestation advances past its anchor, even though the underlying transaction is
              untouched. Fetch proofs fresh and submit promptly; stored fixtures are for decoder
              tests only. Documented nowhere we could find.
            </P>
          </NumberedItem>

          <NumberedItem n={10} title="A key of ours reached a public repository">
            <P>
              A seeding script wrote a demo borrower&rsquo;s private key into a committed evidence
              file, and it was pushed publicly and sat there for about 26 hours. It controlled a
              testnet-only wallet holding 0.02 Sepolia ETH. The deployer key was never committed.
            </P>
            <P>
              The interesting part is not the funds, which were worthless. Anyone holding that key
              could have opened and repaid loans <span className="text-vellum">as that borrower</span>{' '}
              — and because ingestion is permissionless, proven the result. A single late repayment
              would have permanently altered the profile the demo is built on. The script no longer
              records a key at all, the borrower was rotated, and CI now fails on any committed field
              named like a secret.
            </P>
          </NumberedItem>

          <NumberedItem n={11} title="Third parties could brand you late, and could brand you at all">
            <P>
              Repayment is permissionless — a friend settling your debt should build your reputation —
              but the event omitted <Mono>msg.sender</Mono>. So a stranger could settle{' '}
              <span className="text-vellum">1 wei</span> on your past-due loan and stamp an indelible
              late on your profile: −150 points and Platinum barred forever, for the price of gas. The
              event now carries an indexed payer and the penalty applies only when the borrower paid
              for themselves.
            </P>
            <P>
              Separately, the badge would mint for any address. It is permanent, non-transferable and
              unburnable, so anyone could brand any wallet Bronze forever. The initial mint now
              requires either the borrower or a genuine verified history.
            </P>
          </NumberedItem>

          <NumberedItem n={12} title="The age term rests on an owner-supplied anchor">
            <P>
              Source-chain time is not provable. The only temporal fact covered by a proof is the
              block height, which is converted to time against an owner-registered anchor. That is a
              trusted input and an approximation — measured drift is 3.8 days over 1.8 years, well
              inside the granularity the term scores in, but a dishonest anchor could inflate
              everyone&rsquo;s age. It is bounded at 120 points, and it replaced something strictly
              worse: before it, the term measured time since <span className="text-vellum">import</span>.
            </P>
          </NumberedItem>
        </ol>
      </Section>

      <Section label="Next" title="What we would build next, in order.">
        <ol className="max-w-measure list-inside list-decimal space-y-3 text-body text-ash marker:font-mono marker:text-assay">
          <li>Duration-weighted capacity — score the integral of debt held over time. Closes wash lending properly.</li>
          <li>Continuous indexing of all registered sources, so liquidations arrive whether or not the borrower wants them.</li>
          <li>A first-loss tranche. The only mechanism in this category that has ever survived a default is somebody&rsquo;s junior capital absorbing it.</li>
          <li>Governance on the source allowlist — timelock, then a council.</li>
          <li>Price normalisation, once there is a trust-minimised way to get foreign asset prices.</li>
        </ol>
        <div className="mt-12">
          <P>
            Sybil resistance here is <span className="text-vellum">priced, not prevented</span> —
            which is what the whole field actually does, whether or not it says so.
          </P>
        </div>
      </Section>
    </PageShell>
  );
}
