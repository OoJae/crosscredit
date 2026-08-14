import type {Address} from 'viem';
import {formatEther} from 'viem';
import {useWriteContract} from 'wagmi';
import {ADDRESSES, TIER_NAMES} from '../config';
import {sbtAbi} from '../abis';
import {
  useProfile,
  useTier,
  useBadgeToken,
  useBadgeMetadata,
  useIngestedEvents,
  useScoreHistory,
  useDemonstratedCapacity,
} from '../hooks';
import {Card, ScoreDial, Stat, TierPill, ExplorerLink, Button, Spinner, Banner, readableError} from '../components/ui';

/** Renders a proven-history span in whole months — the one input an attacker cannot compress. */
function formatSpan(oldestActivity: bigint): string {
  if (oldestActivity === 0n) return '—';
  const months = Math.floor((Date.now() / 1000 - Number(oldestActivity)) / (30 * 86_400));
  if (months < 1) return '< 1 month';
  if (months < 24) return `${months} months`;
  return `${Math.floor(months / 12)} years`;
}

/**
 * Capacity is stored 18-decimal normalised, so `formatEther` gives the face value. Rendered with a
 * dollar sign because Aave borrowing is stablecoin-dominated — an approximation we state plainly
 * in `docs/THREAT_MODEL.md` rather than hide behind a price feed we do not have.
 */
function formatUsd(wei: bigint): string {
  const whole = Number(formatEther(wei));
  return `$${whole.toLocaleString('en-US', {maximumFractionDigits: 0})}`;
}

export default function Dashboard({address, canWrite}: {address: Address; canWrite: boolean}) {
  const {data: profile, isLoading} = useProfile(address);
  const {data: tier} = useTier(address);
  const {data: tokenId, refetch: refetchToken} = useBadgeToken(address);
  const {metadata} = useBadgeMetadata(tokenId);
  const {data: ingested} = useIngestedEvents(address);
  const {data: history} = useScoreHistory(address);
  const {data: capacity} = useDemonstratedCapacity(address);
  const {writeContract, isPending, error} = useWriteContract();

  const score = Number(profile?.score ?? 0);
  const tierIndex = Number(tier ?? 0);
  const hasBadge = tokenId !== undefined && tokenId !== 0n;
  const hasHistory =
    (profile?.loansOpened ?? 0) > 0 ||
    (profile?.onTime ?? 0) > 0 ||
    (profile?.mainnetRepayments ?? 0) > 0;
  const hasCapacity = (capacity ?? 0n) > 0n;

  if (isLoading) return <Card><Spinner label="Reading the registry on Creditcoin…" /></Card>;

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <Card className="lg:col-span-2" title="Verified credit profile" subtitle="Every number below was derived from an Ethereum transaction that Creditcoin verified for itself.">
        <div className="flex flex-wrap items-center gap-8">
          <ScoreDial score={score} tier={tierIndex} />
          <div className="flex-1 space-y-3">
            <div className="flex items-center gap-3">
              <TierPill tier={tierIndex} />
              {(profile?.late ?? 0) > 0 && (
                <span className="text-xs text-rose-300/80">
                  {profile!.late} late repayment{profile!.late === 1 ? '' : 's'} — Platinum requires none
                </span>
              )}
              {(profile?.liquidations ?? 0) > 0 && (
                <span className="text-xs text-rose-300/80">
                  {profile!.liquidations} mainnet liquidation{profile!.liquidations === 1 ? '' : 's'}
                </span>
              )}
            </div>

            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Stat label="Mainnet repayments" value={profile?.mainnetRepayments ?? 0} />
              <Stat label="Liquidations" value={profile?.liquidations ?? 0} />
              <Stat label="On time (Sepolia)" value={`${profile?.onTime ?? 0} / ${(profile?.onTime ?? 0) + (profile?.late ?? 0)}`} />
              <Stat label="Loans closed" value={`${profile?.loansClosed ?? 0} / ${profile?.loansOpened ?? 0}`} />
              <Stat label="History spans" value={formatSpan(profile?.oldestActivity ?? 0n)} />
              <Stat label="Events verified" value={ingested?.length ?? 0} />
            </div>

            {/*
              The number that actually gates undercollateralized credit. Shown next to the tier
              rather than buried, because a Platinum tier with zero capacity gets no discount and
              the UI should not imply otherwise.
            */}
            <div
              className={`rounded-xl px-4 py-3 ring-1 ${
                hasCapacity ? 'bg-emerald-500/5 ring-emerald-500/30' : 'bg-ink-900 ring-ink-600'
              }`}
            >
              <div className="flex items-baseline justify-between gap-3">
                <span className="text-[11px] uppercase tracking-wider text-slate-500">
                  Demonstrated capacity
                </span>
                <span
                  className={`font-mono text-lg ${hasCapacity ? 'text-emerald-300' : 'text-slate-500'}`}
                >
                  {hasCapacity ? formatUsd(capacity!) : '$0'}
                </span>
              </div>
              <p className="mt-1 text-xs leading-relaxed text-slate-500">
                {hasCapacity ? (
                  <>
                    The largest single amount this address has provably repaid to a real
                    third-party protocol on Ethereum mainnet. This — not the tier — is the ceiling
                    on how much it can borrow <em>above</em> what it posts as collateral.
                  </>
                ) : (
                  <>
                    No third-party capital has been repaid by this address, so it earns{' '}
                    <strong className="text-slate-400">no undercollateralized credit</strong>{' '}
                    whatever its tier. Self-reported history sets a rate; only real history sets a
                    limit.
                  </>
                )}
              </p>
            </div>
          </div>
        </div>

        {history !== undefined && history.length > 1 && (
          <div className="mt-6">
            <div className="mb-2 text-[11px] uppercase tracking-wider text-slate-500">
              How the score was earned — one verified proof at a time
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              {history.map((point, i) => (
                <span key={`${point.txHash}-${i}`} className="flex items-center gap-1.5">
                  <a
                    href={`https://creditcoin-testnet.blockscout.com/tx/${point.txHash}`}
                    target="_blank"
                    rel="noreferrer"
                    className="rounded bg-ink-900 px-2 py-1 font-mono text-xs text-slate-300 ring-1 ring-ink-600 hover:ring-sky-500/50"
                    title={`${TIER_NAMES[point.tier]} — view on Blockscout`}
                  >
                    {point.score}
                  </a>
                  {i < history.length - 1 && <span className="text-slate-600">→</span>}
                </span>
              ))}
            </div>
          </div>
        )}
      </Card>

      <Card title="Credit tier badge" subtitle="ERC-721 + ERC-5192. Soulbound, and drawn entirely on-chain.">
        {hasBadge && metadata !== null ? (
          <div className="space-y-3">
            {/* Rendered as an image, never inlined: an <img>-sourced SVG is renderer-sandboxed. */}
            <img
              src={metadata.image}
              alt={metadata.name}
              width={400}
              height={400}
              className="w-full rounded-xl ring-1 ring-ink-600"
            />
            <div className="flex items-center justify-between text-xs text-slate-500">
              <span>Token #{tokenId!.toString()}</span>
              <span className="text-emerald-400/80">🔒 non-transferable</span>
            </div>
            <ExplorerLink chain="cc3" type="address" hash={ADDRESSES.sbt}>
              View collection on Blockscout
            </ExplorerLink>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="flex h-56 items-center justify-center rounded-xl border border-dashed border-ink-600 text-sm text-slate-500">
              {hasHistory ? 'No badge minted yet' : 'No verified history yet'}
            </div>
            {hasHistory && (
              <>
                <p className="text-xs text-slate-500">
                  Minting is permissionless — the badge only reflects what the registry already
                  knows, so anyone can pay the gas to bring it up to date.
                </p>
                <Button
                  disabled={!canWrite || isPending}
                  onClick={() =>
                    writeContract(
                      {address: ADDRESSES.sbt, abi: sbtAbi, functionName: 'sync', args: [address]},
                      {onSuccess: () => void refetchToken()},
                    )
                  }
                >
                  {isPending ? 'Confirm in wallet…' : canWrite ? 'Mint badge' : 'Connect a wallet to mint'}
                </Button>
              </>
            )}
            {error !== null && <Banner tone="error">{readableError(error)}</Banner>}
          </div>
        )}
      </Card>

      <Card className="lg:col-span-3" title="Verified events" subtitle="Each row is an Ethereum transaction proven to Creditcoin by the block-prover precompile.">
        {ingested === undefined || ingested.length === 0 ? (
          <p className="text-sm text-slate-500">
            Nothing verified yet. Head to <span className="text-slate-300">Import history</span> to
            prove this address&rsquo;s record on Sepolia or Ethereum mainnet.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-[11px] uppercase tracking-wider text-slate-500">
                <tr className="border-b border-ink-600">
                  <th className="pb-2 pr-4 font-medium">Event</th>
                  <th className="pb-2 pr-4 font-medium">Loan</th>
                  <th className="pb-2 pr-4 font-medium">Query id</th>
                  <th className="pb-2 font-medium">Verified on Creditcoin</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-700/60">
                {ingested.map((event) => (
                  <tr key={event.queryId} className="text-slate-300">
                    <td className="py-2 pr-4">{event.kind}</td>
                    <td className="py-2 pr-4 font-mono text-xs text-slate-500">
                      {event.loanId === 0n ? '—' : `#${event.loanId.toString()}`}
                    </td>
                    <td className="py-2 pr-4 font-mono text-xs text-slate-500">
                      {event.queryId.slice(0, 10)}…
                    </td>
                    <td className="py-2">
                      <ExplorerLink chain="cc3" type="tx" hash={event.cc3TxHash} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {new Set(ingested.map((e) => e.cc3TxHash)).size === 1 && ingested.length > 1 && (
              <p className="mt-3 text-xs text-emerald-300/80">
                All {ingested.length} events were verified in a single Creditcoin transaction —
                one shared continuity proof instead of {ingested.length} separate ones.
              </p>
            )}
          </div>
        )}
      </Card>
    </div>
  );
}
