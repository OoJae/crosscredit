import {Link} from 'react-router-dom';
import {PageShell} from './PageShell';
import {PageHead, Section, P, Mono, Figure} from './Prose';
import {Hallmark, TIER_HALLMARKS} from './Mark';

/** Content from `docs/SCORING.md`. Every constant here is one `ScoreLib.sol` can be checked against. */

const TERMS = [
  {collateral: '150%', apr: '14%', max: '100'},
  {collateral: '130%', apr: '11%', max: '500'},
  {collateral: '110%', apr: '8%', max: '2,000'},
  {collateral: '85%', apr: '6%', max: '10,000'},
] as const;

const SELF_REPORTED = [
  ['On-time repayment (LoanBook)', '+60 each', '360'],
  ['Loan fully repaid', '+30 each', '90'],
  ['Late repayment', '−150 each', '—'],
] as const;

const MAINNET = [
  ['Repayment to a real third-party protocol', '+120 each', '600'],
  ['Demonstrated capacity', '+1 per 0.01 ETH-equivalent', '200'],
  ['Liquidation', '−250 each', '—'],
] as const;

const TIME = [
  ['Age of proven history', '+10 per 30 days', '120'],
  ['Live ENS name or PoH humanity', '+60', '60'],
] as const;

function ScoreTable({rows, caption}: {rows: readonly (readonly [string, string, string])[]; caption: string}) {
  return (
    <Figure caption={caption}>
      <table className="w-full text-left">
        <thead>
          <tr className="border-b border-ink-700">
            <th className="pb-3 pr-4 font-mono text-label font-normal uppercase text-ash">Component</th>
            <th className="pb-3 pr-4 font-mono text-label font-normal uppercase text-ash">Points</th>
            <th className="pb-3 font-mono text-label font-normal uppercase text-ash">Cap</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-ink-700/70">
          {rows.map(([component, points, cap]) => (
            <tr key={component}>
              <td className="py-3.5 pr-4 text-sm text-vellum">{component}</td>
              <td className="py-3.5 pr-4 font-mono text-sm tabular-nums text-ash">{points}</td>
              <td className="py-3.5 font-mono text-sm tabular-nums text-ash">{cap}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Figure>
  );
}

/**
 * The age axis, shown as two real wallets rather than described.
 *
 * This is the strongest single figure the project has: one proof of old history beats five proofs
 * of new history, on the one axis nobody can script. Both rows are live on the deployed registry.
 */
function AgeAxis() {
  const rows = [
    {
      address: '0xe57D6C…dd00',
      proofs: '1',
      oldest: 'Oct 2024',
      months: '22 months',
      age: '120',
      score: '423',
      emphasis: true,
    },
    {
      address: '0x76f30e…5b1A',
      proofs: '5',
      oldest: 'Aug 2026',
      months: '< 1 month',
      age: '0',
      score: '800',
      emphasis: false,
    },
  ];

  return (
    <Figure caption="Both live on the deployed registry, scored by the same contract on the same day">
      <table className="w-full text-left">
        <thead>
          <tr className="border-b border-ink-700">
            {['Borrower', 'Proofs', 'Oldest proven', 'Spans', 'Age points', 'Score'].map((h) => (
              <th key={h} className="pb-3 pr-4 font-mono text-label font-normal uppercase text-ash">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-ink-700/70">
          {rows.map((r) => (
            <tr key={r.address}>
              <td className="py-4 pr-4 font-mono text-sm text-vellum">{r.address}</td>
              <td className="py-4 pr-4 font-mono text-sm tabular-nums text-ash">{r.proofs}</td>
              <td className="py-4 pr-4 font-mono text-sm text-ash">{r.oldest}</td>
              <td className="py-4 pr-4 font-mono text-sm text-ash">{r.months}</td>
              <td
                className={`py-4 pr-4 font-mono text-sm tabular-nums ${
                  r.emphasis ? 'text-assay' : 'text-ash'
                }`}
              >
                {r.age}
              </td>
              <td className="py-4 font-mono text-sm tabular-nums text-vellum">{r.score}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Figure>
  );
}

export default function Tiers() {
  return (
    <PageShell>
      <PageHead
        eyebrow="Scoring"
        title={
          <>
            The tier is not the <em>credit line.</em>
          </>
        }
        lede="Eight constants, one subtraction, one floor — computed inside the EVM of the chain that verified the evidence, so anyone can recompute it from public data and nobody, including us, can quietly retune it."
      />

      <Section label="The marks">
        <ul className="grid gap-x-8 gap-y-12 sm:grid-cols-2 lg:grid-cols-4">
          {TIER_HALLMARKS.map((mark, i) => {
            const terms = TERMS[i]!;
            return (
              <li key={mark.name}>
                <Hallmark tier={i as 0 | 1 | 2 | 3} size={72} />
                <p className="mt-5 font-display text-3xl" style={{color: mark.colour}}>
                  {mark.name}
                </p>
                <dl className="mt-4 space-y-1.5 font-mono text-sm">
                  <div className="flex justify-between gap-4">
                    <dt className="text-ash">from</dt>
                    <dd className="tabular-nums text-vellum">{Number(mark.floor)}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-ash">collateral</dt>
                    <dd className="tabular-nums text-vellum">{terms.collateral}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-ash">apr</dt>
                    <dd className="tabular-nums text-vellum">{terms.apr}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-ash">max</dt>
                    <dd className="tabular-nums text-vellum">{terms.max}</dd>
                  </div>
                </dl>
              </li>
            );
          })}
        </ul>
        <div className="mt-14">
          <P>
            The cartouche shape denotes the tier and the number inside is its score floor, which is
            how hallmarking has always worked — so the set stays legible in greyscale, at 20px, and
            to anyone who cannot separate bronze from gold by colour.
          </P>
          <P>
            Platinum carries one extra rule: <Mono>late == 0</Mono> and{' '}
            <Mono>liquidations == 0</Mono>. It is the only tier that lends more than the borrower
            posts, so a single default anywhere in the proven history bars it.
          </P>
        </div>
      </Section>

      <Section label="The model" title="Who was the lender?">
        <P>
          Two kinds of source, and the model refuses to treat them as equivalent evidence. Our own
          loan contract has no lender — it is permissionless and escrows nothing, so a perfect record
          on it costs gas. Aave had a real counterparty whose capital was genuinely at risk.
        </P>
        <div className="mt-10 space-y-12">
          <ScoreTable rows={SELF_REPORTED} caption="Self-reported — capped below the top tier on purpose" />
          <ScoreTable rows={MAINNET} caption="Mainnet — where the weight sits" />
          <ScoreTable rows={TIME} caption="Time and identity" />
        </div>
        <div className="mt-10">
          <P>
            A perfect, decade-long, ENS-backed record on our own contract tops out at{' '}
            <span className="text-vellum">630</span> against a Platinum threshold of 700. That
            ceiling is asserted by a test that fails if any cap is loosened enough to undo it.
          </P>
          <P>
            Positive components are capped individually, summed, clamped to 1,000, and{' '}
            <span className="text-vellum">then</span> penalties are subtracted. The order matters:
            with every cap maxed the positive terms sum to 1,430, so clamping the net let the first
            430 points of default vanish — two liquidations and a late payment could leave a score
            untouched.
          </P>
        </div>
      </Section>

      <Section label="The time axis" title="Time cannot be compressed.">
        <P>
          Aave, ENS and Proof of Humanity emit no timestamp, and the precompile proves transactions
          rather than block headers. The one temporal fact covered by a proof is the source block
          height, so height is converted to time against a registered per-chain anchor. Measured
          against our own marquee transaction that estimate drifts 3.8 days over 1.8 years — 0.55%,
          well inside the 30-day granularity the term scores in.
        </P>
        <div className="mt-10">
          <AgeAxis />
        </div>
        <div className="mt-8">
          <P tone="vellum">
            One proof of old history beats five proofs of new history.
          </P>
          <P>
            The second wallet has five times the proofs and earns nothing from age, because
            everything it proved happened last week. No amount of scripting converts one into the
            other — which is the entire reason the term exists.
          </P>
        </div>
      </Section>

      <Section label="The limit" title="A tier sets your rate. It does not set your ceiling.">
        <P>
          The largest single amount you have provably repaid to a real third-party protocol is what
          caps how much you may borrow <span className="text-vellum">above what you post</span>.
          Everything beyond it is fully collateralized. A wallet holding Platinum with no real
          history gets the Platinum rate and no discount at all.
        </P>
        <P>
          Capacity is the largest single repayment, never the sum — so splitting a history across a
          thousand wallets divides it rather than multiplying it. And a repayment funded by a borrow
          in the same transaction is a flash loan wearing a repayment&rsquo;s clothes: real event,
          valid proof, zero exposure. It counts as a repayment and proves no capacity.
        </P>
        <div className="mt-10 flex flex-wrap gap-x-8 gap-y-4">
          <Link
            to="/explorer"
            className="inline-flex items-center gap-2 rounded-sm bg-assay px-5 py-3 font-mono text-sm font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
          >
            See a live profile →
          </Link>
          <Link
            to="/threat-model"
            className="font-mono text-sm text-ash underline-offset-4 hover:text-vellum hover:underline"
          >
            What this still does not solve
          </Link>
        </div>
      </Section>
    </PageShell>
  );
}
