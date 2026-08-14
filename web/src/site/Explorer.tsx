import {useState} from 'react';
import {Link, useSearchParams} from 'react-router-dom';
import {isAddress, formatEther, type Address} from 'viem';
import {PageShell} from './PageShell';
import {Eyebrow, Mono} from './Prose';
import {Hallmark} from './Mark';
import {
  useProfile,
  useTier,
  useDemonstratedCapacity,
  useIngestedEvents,
  useScoreHistory,
} from '../hooks';
import {DEMO_BORROWERS, TIER_NAMES, EXPLORERS} from '../config';

/**
 * The read-only lens. One address in; hallmark, score, capacity and proven events out.
 *
 * Deliberately CC3-only. `useSourceHistory` would also work here, but it fans out a growing number
 * of parallel `eth_getLogs` calls to a public Sepolia endpoint — fine behind the app's own front
 * door, not on a shareable page that anyone can link to.
 *
 * The address lives in `?a=` so a profile can be sent to someone. That is the whole point of
 * splitting this out of the dashboard: a hallmark is worth sharing, and a tab inside a dapp is not.
 */

const DEFAULT_ADDRESS = DEMO_BORROWERS[0].address;

function Figure({label, value, tone}: {label: string; value: string; tone?: 'good' | 'plain'}) {
  return (
    <div className="border-t border-ink-700 py-4">
      <dt className="font-mono text-label uppercase text-ash">{label}</dt>
      <dd
        className={`mt-2 font-mono text-2xl tabular-nums ${
          tone === 'good' ? 'text-emerald-300' : 'text-vellum'
        }`}
      >
        {value}
      </dd>
    </div>
  );
}

export default function Explorer() {
  const [params, setParams] = useSearchParams();
  const queried = params.get('a');
  const address = queried !== null && isAddress(queried) ? (queried as Address) : DEFAULT_ADDRESS;
  const malformed = queried !== null && !isAddress(queried);

  const [draft, setDraft] = useState('');

  const profile = useProfile(address);
  const {data: tier} = useTier(address);
  const {data: capacity} = useDemonstratedCapacity(address);
  const {data: events} = useIngestedEvents(address);
  const {data: history} = useScoreHistory(address);

  const tierIndex = Number(tier ?? 0);
  const score = Number(profile.data?.score ?? 0);
  const known = DEMO_BORROWERS.find((b) => b.address.toLowerCase() === address.toLowerCase());

  /*
    Three states that are genuinely different and used to render identically. An unreachable RPC
    produced a confident profile of zeroes, which is a lie told in the product's own voice — the
    one failure mode a page about verified data cannot have.
  */
  const unreachable = profile.isError;
  const empty = !unreachable && !profile.isLoading && profile.data?.firstSeen === 0n;

  return (
    <PageShell>
      <div className="mx-auto max-w-6xl px-5 pb-16 pt-32 md:pt-40">
        <Eyebrow>Explorer</Eyebrow>
        <h1 className="mt-7 max-w-[20ch] font-display text-section">
          Any address. <em>Whatever it proved.</em>
        </h1>

        <form
          className="mt-10 flex flex-wrap gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            const next = draft.trim();
            if (next !== '') setParams({a: next});
          }}
        >
          <label className="sr-only" htmlFor="addr">
            Ethereum address
          </label>
          <input
            id="addr"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="0x…"
            spellCheck={false}
            className="w-full max-w-sm rounded-sm border border-ink-600 bg-ink-900 px-4 py-3 font-mono text-sm text-vellum outline-none transition-colors duration-200 placeholder:text-ash/60 focus:border-assay"
          />
          <button
            type="submit"
            className="rounded-sm bg-assay px-5 py-3 font-mono text-sm font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
          >
            Look up
          </button>
        </form>

        {malformed && (
          <p className="mt-4 font-mono text-sm text-rose-300">
            That is not a valid Ethereum address — showing {DEFAULT_ADDRESS.slice(0, 10)}… instead.
          </p>
        )}

        <div className="mt-6 flex flex-wrap gap-2">
          {DEMO_BORROWERS.map((b) => (
            <button
              key={b.address}
              onClick={() => setParams({a: b.address})}
              className={`rounded-sm px-3 py-2 text-left font-mono text-label uppercase ring-1 transition-colors duration-200 ${
                b.address.toLowerCase() === address.toLowerCase()
                  ? 'text-assay ring-assay/50'
                  : 'text-ash ring-ink-600 hover:text-vellum'
              }`}
            >
              {b.label.split('—')[0]?.trim()}
              {/* `real` was declared in config and never read. It is the one distinction worth surfacing. */}
              {b.real && <span className="ml-2 text-emerald-300/80">live mainnet</span>}
            </button>
          ))}
        </div>
      </div>

      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-12">
        <p className="font-mono text-sm text-ash">
          <span className="text-vellum">{address}</span>
          {known !== undefined && <span className="ml-3 text-ash">{known.note}</span>}
        </p>

        {unreachable ? (
          <div className="mt-10 rounded-sm border border-rose-500/30 bg-rose-500/5 p-6">
            <p className="text-lede text-rose-200">Creditcoin CC3 is not answering.</p>
            <p className="mt-3 max-w-measure text-body text-ash">
              This is a network failure, not a verdict on the address. Showing a profile of zeroes
              here would be indistinguishable from a real borrower with no history, so nothing is
              shown at all.
            </p>
          </div>
        ) : empty ? (
          <div className="mt-10 rounded-sm border border-ink-700 p-6">
            <p className="text-lede text-vellum">Nothing has been proven for this address.</p>
            <p className="mt-3 max-w-measure text-body text-ash">
              That is not the same as having no credit history — it means no one has yet proven any
              of it to Creditcoin. Ingestion is permissionless, so anyone can.
            </p>
            <Link
              to="/app"
              className="mt-6 inline-flex rounded-sm bg-assay px-5 py-3 font-mono text-sm font-semibold text-ink-950 transition-transform duration-200 ease-toggle active:translate-y-[var(--strike-depth)]"
            >
              Prove some history →
            </Link>
          </div>
        ) : (
          <>
            <div className="mt-12 grid gap-12 md:grid-cols-12">
              <div className="md:col-span-4">
                <Hallmark tier={tierIndex as 0 | 1 | 2 | 3} size={104} />
                <p className="mt-6 font-display text-5xl leading-none text-vellum">{score}</p>
                <p className="mt-2 font-mono text-label uppercase text-ash">
                  {TIER_NAMES[tierIndex]} · out of 1000
                </p>
              </div>

              <dl className="md:col-span-8">
                <Figure
                  label="Demonstrated capacity"
                  value={
                    capacity === undefined || capacity === 0n
                      ? '$0'
                      : `$${Number(formatEther(capacity)).toLocaleString('en-US', {maximumFractionDigits: 0})}`
                  }
                  tone={capacity !== undefined && capacity > 0n ? 'good' : 'plain'}
                />
                <Figure label="Mainnet repayments" value={String(profile.data?.mainnetRepayments ?? 0)} />
                <Figure
                  label="Late / liquidations"
                  value={`${profile.data?.late ?? 0} / ${profile.data?.liquidations ?? 0}`}
                />
                <Figure label="Events proven" value={String(events?.length ?? 0)} />
              </dl>
            </div>

            {history !== undefined && history.length > 1 && (
              <div className="mt-16">
                <p className="font-mono text-label uppercase text-ash">
                  How the score was earned — one proof at a time
                </p>
                <ol className="mt-5 flex flex-wrap items-center gap-x-3 gap-y-3">
                  {history.map((point, i) => (
                    <li key={`${point.txHash}-${i}`} className="flex items-center gap-3">
                      <a
                        href={`${EXPLORERS.cc3}/tx/${point.txHash}`}
                        className="rounded-sm px-3 py-2 font-mono text-sm tabular-nums text-ash ring-1 ring-ink-600 transition-colors duration-200 hover:text-vellum hover:ring-assay"
                      >
                        {point.score}
                      </a>
                      {i < history.length - 1 && (
                        <span aria-hidden="true" className="text-ink-600">
                          →
                        </span>
                      )}
                    </li>
                  ))}
                </ol>
              </div>
            )}

            {events !== undefined && events.length > 0 && (
              <div className="mt-16">
                <p className="font-mono text-label uppercase text-ash">Proven events</p>
                <div className="-mx-5 mt-5 overflow-x-auto px-5 md:mx-0 md:px-0">
                  <table className="w-full min-w-[32rem] text-left">
                    <thead>
                      <tr className="border-b border-ink-700">
                        {['Event', 'Query id', 'Verified on Creditcoin'].map((h) => (
                          <th key={h} className="pb-3 pr-4 font-mono text-label font-normal uppercase text-ash">
                            {h}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-ink-700/70">
                      {events.map((event) => (
                        <tr key={event.queryId}>
                          <td className="py-3.5 pr-4 text-sm text-vellum">{event.kind}</td>
                          <td className="py-3.5 pr-4 font-mono text-sm text-ash">
                            {event.queryId.slice(0, 10)}…
                          </td>
                          <td className="py-3.5">
                            <a
                              href={`${EXPLORERS.cc3}/tx/${event.cc3TxHash}`}
                              className="font-mono text-sm text-vellum underline decoration-assay/40 underline-offset-2 hover:decoration-assay"
                            >
                              {event.cc3TxHash.slice(0, 10)}…{event.cc3TxHash.slice(-6)}
                            </a>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {new Set(events.map((e) => e.cc3TxHash)).size === 1 && events.length > 1 && (
                  <p className="mt-5 max-w-measure text-sm text-emerald-300/90">
                    All {events.length} events were verified in a single Creditcoin transaction — one
                    shared continuity proof instead of {events.length} separate ones.
                  </p>
                )}
              </div>
            )}

            <p className="mt-16 max-w-measure text-body text-ash">
              Every row above is an Ethereum transaction that Creditcoin verified for itself.{' '}
              <Mono>{address.slice(0, 10)}…</Mono> did not have to consent to any of it, and could
              not have faked any of it.
            </p>
          </>
        )}
      </div>
    </PageShell>
  );
}
