import {Link} from 'react-router-dom';
import {Hallmark, AssayMark, TIER_HALLMARKS} from './Mark';
import {PageShell} from './PageShell';
import {Line, Eyebrow} from './Prose';
import {Punch} from './Punch';
import {useReveal, useScrollProgress} from './useReveal';
import {ADDRESSES} from '../config';

/**
 * The landing page.
 *
 * Almost every line of copy here is lifted verbatim from README.md, docs/SCORING.md and
 * docs/THREAT_MODEL.md. That is deliberate: the project already writes about itself better than a
 * marketing pass would, and every claim on this page is one the repository can be held to.
 */

function Hero() {
  const {ref, progress} = useScrollProgress<HTMLDivElement>();

  return (
    // Tall on purpose: the scene needs scroll distance to strike into.
    <div ref={ref} className="relative h-[220vh]">
      <div className="sticky top-0 flex h-screen flex-col overflow-hidden">
        <div className="mx-auto grid w-full max-w-6xl flex-1 grid-cols-1 gap-8 px-5 pt-24 md:grid-cols-12 md:pt-28">
          <div className="md:col-span-7">
            <Eyebrow step="01">Proof</Eyebrow>

            <h1 className="revealed mt-7 font-display text-hero">
              <Line>Repaid on</Line>
              <Line delay={80}>Ethereum.</Line>
              <Line delay={160}>
                <em className="text-assay not-italic">Proven</em> here.
              </Line>
            </h1>

            <p className="mt-8 max-w-measure text-body text-ash">
              Nothing is self-reported and no oracle delivers a number. The score is computed inside
              the EVM of the chain that verified the evidence, from events that chain checked for
              itself.
            </p>

            <div className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-3">
              <Link
                to="/app"
                className="group inline-flex items-center gap-2 rounded-sm bg-assay px-5 py-3 font-mono text-sm font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
              >
                Prove my history
                <span aria-hidden="true" className="transition-transform duration-200 group-hover:translate-x-1">
                  →
                </span>
              </Link>
              <a
                href="https://github.com/OoJae/crosscredit/blob/main/docs/THREAT_MODEL.md"
                className="font-mono text-sm text-ash underline-offset-4 hover:text-vellum hover:underline"
              >
                What this does not solve
              </a>
            </div>
          </div>

          {/*
            `overflow-hidden` is load-bearing, not tidiness. The punch begins its descent 210px
            above its resting position, and in the single-column phone layout that put a steel
            prism straight through the middle of the paragraph. Clipping gives the strike its own
            frame to happen inside.
          */}
          <div className="relative h-[32vh] min-h-[220px] origin-bottom scale-[0.78] overflow-hidden md:col-span-5 md:h-auto md:min-h-[300px] md:scale-100">
            <Punch progress={progress} />
          </div>
        </div>

        <p className="mx-auto w-full max-w-6xl px-5 pb-8 font-mono text-label uppercase text-ash/70">
          Scroll to strike
        </p>
      </div>
    </div>
  );
}

/** The idea the whole product turns on, and the one a judge tests first. */
function Lender() {
  const {ref, revealed} = useReveal<HTMLElement>();

  return (
    <section ref={ref} className={revealed ? 'revealed' : ''}>
      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-24 md:py-32">
        <Eyebrow step="02">Evidence</Eyebrow>

        <h2 className="mt-7 max-w-[16ch] font-display text-section">
          <Line>Who was the</Line>
          <Line delay={80}>
            <em>lender?</em>
          </Line>
        </h2>

        <div className="mt-12 grid gap-10 md:grid-cols-2 md:gap-16">
          <p className="max-w-measure text-body text-ash">
            An earlier version of this read one source: our own loan contract, which is
            permissionless and escrows nothing. Six wei and twelve transactions reached the top
            tier — and every proof was cryptographically valid. We had built a rigorous pipeline for
            the high-integrity delivery of worthless data.
          </p>
          <p className="max-w-measure text-body text-ash">
            So it now reads Aave on Ethereum mainnet, where the counterparty is real and the capital
            genuinely was at risk. The verification path never changed. Only the evidence did.{' '}
            <strong className="font-normal text-vellum">
              Their proofs are just as valid; their evidence is not.
            </strong>
          </p>
        </div>
      </div>
    </section>
  );
}

/** The ladder is already a graphic device in the README. It stays one. */
function Ladder() {
  const {ref, revealed} = useReveal<HTMLElement>();
  const steps = [0, 320, 440, 560, 680, 800];

  return (
    <section ref={ref} className={revealed ? 'revealed' : ''}>
      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-24 md:py-32">
        <Eyebrow step="03">Score</Eyebrow>

        <h2 className="mt-7 max-w-[20ch] font-display text-section">
          <Line>One wallet. Five real</Line>
          <Line delay={80}>Aave repayments.</Line>
        </h2>

        <ol className="mt-12 flex flex-wrap items-center gap-x-3 gap-y-4 font-mono">
          {steps.map((step, i) => (
            <li key={step} className="flex items-center gap-3">
              <span
                className={`rounded-sm px-3 py-2 text-lg tabular-nums ring-1 transition-colors duration-500 ${
                  i === steps.length - 1 ? 'text-platinum ring-platinum/40' : 'text-ash ring-ink-600'
                }`}
              >
                {step}
              </span>
              {i < steps.length - 1 && (
                <span aria-hidden="true" className="text-ink-600">
                  →
                </span>
              )}
            </li>
          ))}
        </ol>

        <p className="mt-8 max-w-measure text-body text-ash">
          <span className="font-mono text-vellum">0x76f30e…5b1A</span> had never sent a transaction
          to Creditcoin. Its entire credit profile was assembled from transactions it made somewhere
          else, proven here one at a time.
        </p>
      </div>
    </section>
  );
}

/** The tier hallmarks, and the rule that stops a tier from being a credit line. */
function Tiers() {
  const {ref, revealed} = useReveal<HTMLElement>();

  return (
    <section ref={ref} className={revealed ? 'revealed' : ''}>
      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-24 md:py-32">
        <Eyebrow step="04">Credit</Eyebrow>

        <h2 className="mt-7 max-w-[18ch] font-display text-section">
          <Line>The tier is not</Line>
          <Line delay={80}>the credit line.</Line>
        </h2>

        <ul className="mt-14 flex flex-wrap gap-x-12 gap-y-10">
          {TIER_HALLMARKS.map((mark, i) => (
            <li key={mark.name} className="flex flex-col items-start gap-3">
              <Hallmark tier={i as 0 | 1 | 2 | 3} size={56} />
              <div>
                <p className="font-mono text-sm" style={{color: mark.colour}}>
                  {mark.name}
                </p>
                <p className="mt-0.5 font-mono text-label uppercase text-ash">from {Number(mark.floor)}</p>
              </div>
            </li>
          ))}
        </ul>

        <p className="mt-14 max-w-measure text-body text-ash">
          A tier sets your <span className="text-vellum">rate</span>. The largest single amount you
          have provably repaid to a real third-party protocol sets the{' '}
          <span className="text-vellum">ceiling</span> on how much you may borrow above what you
          post. A wallet holding the top tier with no real history gets the rate and no discount at
          all.
        </p>
        <p className="mt-5 max-w-measure text-body text-vellum">
          Self-reported history sets a rate; only real history sets a limit.
        </p>
      </div>
    </section>
  );
}

/** Closing plate. The disclosure page is the link we most want followed. */
function Colophon() {
  const {ref, revealed} = useReveal<HTMLElement>();

  return (
    <section ref={ref} className={revealed ? 'revealed' : ''}>
      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-24 md:py-32">
        <div className="flex flex-col gap-12 md:flex-row md:items-end md:justify-between">
          <div>
            <Eyebrow step="05">Assay</Eyebrow>
            <h2 className="mt-7 max-w-[17ch] font-display text-section">
              <Line>Reputation that</Line>
              <Line delay={80}>can be bought</Line>
              <Line delay={160}>
                <em>is not</em> reputation.
              </Line>
            </h2>
          </div>
          <AssayMark size={72} className="text-assay" />
        </div>

        <div className="mt-16 flex flex-wrap items-center gap-x-8 gap-y-4">
          <Link
            to="/app"
            className="inline-flex items-center gap-2 rounded-sm bg-assay px-5 py-3 font-mono text-sm font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
          >
            Open the app →
          </Link>
          <a
            href={`https://creditcoin-testnet.blockscout.com/address/${ADDRESSES.registry}`}
            className="font-mono text-sm text-ash underline-offset-4 hover:text-vellum hover:underline"
          >
            Registry on Blockscout
          </a>
          <a
            href="https://github.com/OoJae/crosscredit"
            className="font-mono text-sm text-ash underline-offset-4 hover:text-vellum hover:underline"
          >
            Source
          </a>
        </div>
      </div>
    </section>
  );
}

export default function Landing() {
  return (
    <PageShell>
      <Hero />
      <Lender />
      <Ladder />
      <Tiers />
      <Colophon />
    </PageShell>
  );
}
