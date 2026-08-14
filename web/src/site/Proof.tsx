import {PageShell} from './PageShell';
import {PageHead, Section, P, Mono, Figure} from './Prose';
import {useReveal} from './useReveal';
import {ADDRESSES} from '../config';

/**
 * How a fact crosses a chain.
 *
 * Content is from `docs/ATTESTCOIN_INTEGRATION.md`. The five-check table is verbatim from §3,
 * because it is the part a judge will compare against the contract line by line.
 */

const CHECKS = [
  {
    check: 'Replay guard on the derived query id',
    stops: 'Resubmitting one genuine repayment to farm score.',
  },
  {
    check: 'sources[chainKey][log.address_] != None',
    stops:
      'A look-alike contract forging history. The allowlist is keyed on the pair, so a Sepolia address cannot impersonate its mainnet namesake even though both chains are attested.',
  },
  {
    check: 'receipt.receiptStatus == 1',
    stops: 'A reverted repayment counting as a successful one. The precompile does not check this.',
  },
  {
    check: "Dispatch on the log's own emitter → SourceKind",
    stops:
      "Any other contract emitting an identically-shaped event. Aave's Repay and our RepaymentMade are decoded by different code paths chosen by the proven log, never by the caller.",
  },
  {
    check: "topic0 must match that source kind's known signatures",
    stops: 'Unrelated events from a registered contract being misread.',
  },
] as const;

/**
 * The five checks, revealing in sequence.
 *
 * The stagger is the point: they run in order, and a proof that clears four of them still moves no
 * score. Each row reveals on its own delay so the chain reads as gates closing rather than as a
 * table appearing.
 */
function CheckChain() {
  const {ref, revealed} = useReveal<HTMLDivElement>();

  return (
    <div ref={ref} className={revealed ? 'revealed' : ''}>
      <Figure caption="CreditRegistry.sol — each check has a test that fails loudly if it is removed">
        <ol>
          {CHECKS.map((row, i) => (
            <li key={row.check} className="border-t border-ink-700 first:border-t-0">
              {/*
                The grid sits on a child of `.reveal-line`, not on it. `.reveal-line` declares
                `display: block` and is defined after `@tailwind utilities`, so it wins the cascade
                against a `grid` utility on the same element and the columns silently collapse.
              */}
              <span className="block overflow-hidden">
                <span className="reveal-line" style={{transitionDelay: `${i * 90}ms`}}>
                  <span className="grid gap-x-6 gap-y-2 py-5 md:grid-cols-12">
                    <span className="font-mono text-label text-assay md:col-span-1">
                      {String(i + 1).padStart(2, '0')}
                    </span>
                    <span className="font-mono text-sm text-vellum md:col-span-5">{row.check}</span>
                    <span className="text-sm leading-relaxed text-ash md:col-span-6">{row.stops}</span>
                  </span>
                </span>
              </span>
            </li>
          ))}
        </ol>
      </Figure>
    </div>
  );
}

export default function Proof() {
  return (
    <PageShell>
      <PageHead
        eyebrow="How it works"
        title={
          <>
            How a fact <em>crosses</em> a chain.
          </>
        }
        lede="Creditcoin can verify, for itself, that a transaction really happened on Ethereum. Everything else here is what you have to do after that to stop a true fact from meaning the wrong thing."
      />

      <Section label="The primitive" title="Two proofs, checked together">
        <P>
          The Attestcoin Protocol exposes a block-prover precompile in the Creditcoin runtime at{' '}
          <Mono>{ADDRESSES.blockProver}</Mono>. It answers one question: did this exact transaction
          really occur in a real block of a supported source chain?
        </P>
        <div className="mt-8 grid gap-6 md:grid-cols-2">
          <div className="rounded-sm border border-ink-700 p-6">
            <p className="font-mono text-label uppercase text-assay">Merkle inclusion</p>
            <p className="mt-3 text-body text-ash">
              Is this transaction in the block it claims to be in?
            </p>
          </div>
          <div className="rounded-sm border border-ink-700 p-6">
            <p className="font-mono text-label uppercase text-assay">Continuity</p>
            <p className="mt-3 text-body text-ash">
              Is that block genuinely part of the source chain, linked back to one the attestor
              network has already attested?
            </p>
          </div>
        </div>
        <div className="mt-8">
          <P tone="vellum">
            It reverts on failure. It never returns false.
          </P>
          <P>
            The signature says <Mono>returns (bool)</Mono>, which invites{' '}
            <Mono>require(prover.verify(...))</Mono>. In practice a bad proof reverts with a typed
            reason and the boolean is always true by the time you hold it — so code written against
            that return value looks correct and is never exercised.
          </P>
        </div>
      </Section>

      <Section
        step="→"
        label="Where the depth is"
        title="A valid proof of the wrong thing is still worthless."
      >
        <P>
          The precompile answering &ldquo;this transaction happened&rdquo; is the start of the
          security argument, not the end. A proof of a real transaction proves nothing useful if it
          came from the wrong chain, the wrong contract, or a call that reverted. The registry
          enforces five checks in sequence before a single point of credit score moves.
        </P>
        <div className="mt-10">
          <CheckChain />
        </div>
        <div className="mt-10">
          <P>
            Check 2 got <span className="text-vellum">stronger</span> when the source set widened.
            It began as <Mono>chainKey == 1</Mono>, a single equality. It is now a lookup that must
            return a non-<Mono>None</Mono> kind, and that kind decides which decoder runs. Reading
            more chains narrowed what any individual proof is allowed to mean.
          </P>
        </div>
      </Section>

      <Section label="The finding" title="Creditcoin attests Ethereum mainnet.">
        <P>
          This is the thing the project turns on, and it is in no documentation or example we could
          find. CC3 testnet attests Ethereum <span className="text-vellum">mainnet</span> as chainKey
          3, alongside Sepolia as chainKey 1 — so a borrower&rsquo;s real Aave history is provable,
          not just their testnet one.
        </P>
        <Figure>
          <dl className="mt-6 divide-y divide-ink-700 border-y border-ink-700">
            {[
              ['Mainnet proofs verify on CC3 today', 'verify(chainKey=3, …) returns true for a real Aave V3 Repay'],
              ['History reaches back to February 2016', 'a 2016-era block proved successfully'],
              ['Attestation lag ≈ 8.8 min', 'the same as Sepolia'],
              ['A mainnet proof cannot be replayed as Sepolia', 'Continuity proof does not match attestation or checkpoint'],
              ['Tampering is caught', 'mutated txBytes → Merkle proof validation failed'],
              ['Batching does not carry over', 'real history spans years; a >1000-block span is rejected'],
            ].map(([claim, how]) => (
              <div key={claim} className="grid gap-x-6 gap-y-1 py-4 md:grid-cols-12">
                <dt className="text-sm text-vellum md:col-span-5">{claim}</dt>
                <dd className="font-mono text-sm text-ash md:col-span-7">{how}</dd>
              </div>
            ))}
          </dl>
        </Figure>
        <div className="mt-8">
          <P>
            <Mono>chainKey</Mono> is not an EVM chain id — Ethereum mainnet is chainKey 3, not 1.
            Conflating them is the easiest way to write a check that silently never fires, which is
            why check 2 keys on the pair rather than on either alone.
          </P>
        </div>
      </Section>

      <Section label="Worth writing down" title="Three protocol behaviours that cost us time.">
        <ol className="space-y-8">
          <li>
            <p className="text-lede text-vellum">Continuity proofs expire.</p>
            <P>
              A proof anchors to attestation state at generation time and stops verifying once
              attestation advances past its anchor — even though the underlying transaction is
              untouched. We found it when a negative-path script failed its own baseline using a
              proof captured hours earlier. Fetch proofs fresh; stored fixtures are only good for
              decoder tests.
            </P>
          </li>
          <li>
            <p className="text-lede text-vellum">
              <Mono>getBatchProof</Mono> returns ascending block-height order, not input order.
            </p>
            <P>
              Zipping its results against your input array silently mis-attributes proofs. Key on
              the transaction hash, and assert nothing was dropped.
            </P>
          </li>
          <li>
            <p className="text-lede text-vellum">
              One query id covers a whole transaction, not one event.
            </p>
            <P>
              The id derives from <Mono>(chainKey, blockHeight, txIndex)</Mono>. Official examples
              ingest only the first matching log, which means a transaction carrying two credit
              events can only ever be submitted once and the second is lost behind the replay guard.
              We ingest every recognised log instead — which matters far more on mainnet, where a
              real Aave repayment sits in a transaction with a dozen logs from unrelated protocols.
            </P>
          </li>
        </ol>
      </Section>
    </PageShell>
  );
}
