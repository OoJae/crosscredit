import {useState} from 'react';
import type {Address} from 'viem';
import {formatEther, parseEther} from 'viem';
import {usePublicClient, useWriteContract} from 'wagmi';
import {ADDRESSES, TIER_NAMES, TIER_STYLES, creditcoinCC3} from '../config';
import {poolAbi, erc20Abi} from '../abis';
import {
  useTier,
  useAllTerms,
  useActiveLoan,
  useTotalOwed,
  useCollateralRequired,
  useUndercollateralizedPortion,
  useDemonstratedCapacity,
} from '../hooks';
import {Card, Button, Banner, Spinner, TierPill, ExplorerLink, readableError} from '../components/ui';

export default function Borrow({address, canWrite}: {address: Address; canWrite: boolean}) {
  const client = usePublicClient({chainId: creditcoinCC3.id});
  const {data: tier} = useTier(address);
  const {data: terms} = useAllTerms();
  const {data: loan, refetch: refetchLoan} = useActiveLoan(address);
  const {data: owed, refetch: refetchOwed} = useTotalOwed(address);
  const {writeContractAsync} = useWriteContract();

  const [amount, setAmount] = useState('100');
  const [status, setStatus] = useState<{kind: 'idle' | 'busy' | 'error' | 'done'; message?: string; hash?: string}>({
    kind: 'idle',
  });

  const tierIndex = Number(tier ?? 0);
  const myTerms = terms?.find((t) => t.tier === tierIndex);
  // Index 5, not 4: `aprBps` was inserted before `active` when the loan started carrying the rate
  // it was written at. Positional tuple reads like this are exactly why the ABI-parity check
  // cannot save us here — `loans(address)` has the same selector whatever it returns.
  const hasLoan = loan !== undefined && loan[5];

  const parsedAmount = (() => {
    try {
      return parseEther(amount || '0');
    } catch {
      return 0n;
    }
  })();
  // Asked of the pool, never recomputed from the tier ratio — the ratio is capped by demonstrated
  // capacity, so the naive formula both misquotes and produces a reverting transaction.
  const {data: quotedCollateral} = useCollateralRequired(address, parsedAmount);
  const {data: underPortion} = useUndercollateralizedPortion(address, parsedAmount);
  const {data: capacity} = useDemonstratedCapacity(address);
  const requiredCollateral = quotedCollateral ?? 0n;

  const bronzeTerms = terms?.find((t) => t.tier === 0);
  const bronzeCollateral =
    bronzeTerms === undefined ? 0n : (parsedAmount * BigInt(bronzeTerms.collateralRatioBps)) / 10_000n;
  const saving = bronzeCollateral > requiredCollateral ? bronzeCollateral - requiredCollateral : 0n;

  // A tier earns a rate; only real repaid third-party capital earns a credit line. When those
  // disagree, the UI has to say so rather than advertise a discount the pool will not honour.
  const tierImpliesDiscount = myTerms !== undefined && myTerms.collateralRatioBps < 10_000;
  const cappedByCapacity = tierImpliesDiscount && (underPortion ?? 0n) < parsedAmount;

  async function doBorrow() {
    if (client === undefined) return;
    try {
      setStatus({kind: 'busy', message: 'Confirm the borrow in your wallet…'});
      const hash = await writeContractAsync({
        address: ADDRESSES.pool,
        abi: poolAbi,
        functionName: 'borrow',
        args: [parsedAmount],
        value: requiredCollateral,
      });
      setStatus({kind: 'busy', message: 'Waiting for Creditcoin…', hash});
      await client.waitForTransactionReceipt({hash});
      setStatus({kind: 'done', message: 'Borrowed.', hash});
      void refetchLoan();
      void refetchOwed();
    } catch (error) {
      setStatus({kind: 'error', message: readableError(error)});
    }
  }

  async function doRepay() {
    if (client === undefined || owed === undefined) return;
    try {
      // Interest accrues every second, so approving exactly `totalOwed` would leave the allowance
      // a few wei short by the time repay() executes a block later. Approve a small buffer.
      const withBuffer = (owed * 1005n) / 1000n;

      setStatus({kind: 'busy', message: 'Approving tUSD…'});
      const approveHash = await writeContractAsync({
        address: ADDRESSES.tusd,
        abi: erc20Abi,
        functionName: 'approve',
        args: [ADDRESSES.pool, withBuffer],
      });
      await client.waitForTransactionReceipt({hash: approveHash});

      setStatus({kind: 'busy', message: 'Repaying…'});
      const hash = await writeContractAsync({
        address: ADDRESSES.pool,
        abi: poolAbi,
        functionName: 'repay',
      });
      await client.waitForTransactionReceipt({hash});
      setStatus({kind: 'done', message: 'Repaid — collateral returned.', hash});
      void refetchLoan();
      void refetchOwed();
    } catch (error) {
      setStatus({kind: 'error', message: readableError(error)});
    }
  }

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <Card
        className="lg:col-span-2"
        title="Terms by tier"
        subtitle="Priced from verified cross-chain history — not from a credit bureau, and not self-reported."
      >
        {terms === undefined ? (
          <Spinner label="Reading pool terms…" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-[11px] uppercase tracking-wider text-slate-500">
                <tr className="border-b border-ink-600">
                  <th className="pb-2 pr-4 font-medium">Tier</th>
                  <th className="pb-2 pr-4 font-medium">Collateral</th>
                  <th className="pb-2 pr-4 font-medium">APR</th>
                  <th className="pb-2 font-medium">Max loan</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-700/60">
                {terms.map((t) => {
                  const mine = t.tier === tierIndex;
                  const style = TIER_STYLES[t.tier]!;
                  const under = t.collateralRatioBps < 10_000;
                  return (
                    <tr
                      key={t.tier}
                      className={mine ? `${style.bg} font-semibold text-slate-100` : 'text-slate-400'}
                    >
                      <td className="py-2.5 pr-4">
                        <span className={style.text}>{TIER_NAMES[t.tier]}</span>
                        {mine && <span className="ml-2 text-[10px] uppercase text-slate-400">you</span>}
                      </td>
                      <td className="py-2.5 pr-4 font-mono tabular-nums">
                        {(t.collateralRatioBps / 100).toFixed(0)}%
                        {under && (
                          <span className="ml-2 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-emerald-300">
                            undercollateralized
                          </span>
                        )}
                      </td>
                      <td className="py-2.5 pr-4 font-mono tabular-nums">{(t.aprBps / 100).toFixed(0)}%</td>
                      <td className="py-2.5 font-mono tabular-nums">
                        {Number(formatEther(t.maxBorrow)).toLocaleString()} tUSD
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            <p className="mt-4 text-xs leading-relaxed text-slate-500">
              Platinum requires a score of 700 <em>and</em> zero late repayments. It is the only
              tier that lends more than the borrower posts, so a spotless record — not just a high
              score — is the condition.
            </p>
          </div>
        )}
      </Card>

      <Card title={hasLoan ? 'Your loan' : 'Borrow'} subtitle={hasLoan ? undefined : 'Collateral is native tCTC.'}>
        {hasLoan ? (
          <div className="space-y-4">
            <div className="space-y-1.5 text-sm">
              <Row label="Principal" value={`${formatEther(loan[0])} tUSD`} />
              <Row label="Collateral locked" value={`${formatEther(loan[1])} tCTC`} />
              <Row label="Owed now" value={`${Number(formatEther(owed ?? 0n)).toFixed(6)} tUSD`} />
              <Row label="Rate fixed at" value={TIER_NAMES[Number(loan[3])] ?? '—'} />
            </div>
            <p className="text-xs text-slate-500">
              Terms were fixed when the loan opened, so a later tier downgrade cannot retroactively
              margin-call it.
            </p>
            <Button disabled={!canWrite || status.kind === 'busy'} onClick={() => void doRepay()}>
              {canWrite ? 'Repay in full' : 'Connect a wallet to repay'}
            </Button>
          </div>
        ) : (
          <div className="space-y-4">
            <label className="block">
              <span className="text-[11px] uppercase tracking-wider text-slate-500">Borrow (tUSD)</span>
              <input
                type="number"
                min="0"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="mt-1 w-full rounded-lg border border-ink-600 bg-ink-900 px-3 py-2 font-mono text-lg text-slate-100 outline-none focus:border-sky-500"
              />
            </label>

            <div className="space-y-1.5 text-sm">
              <Row label="Your tier" value={<TierPill tier={tierIndex} />} />
              <Row
                label="Collateral needed"
                value={`${Number(formatEther(requiredCollateral)).toLocaleString()} tCTC`}
                emphasis
              />
              {saving > 0n && (
                <Row
                  label="Saved vs Bronze"
                  value={`${Number(formatEther(saving)).toLocaleString()} tCTC`}
                  tone="good"
                />
              )}
            </div>

            {requiredCollateral < parsedAmount && parsedAmount > 0n && (
              <Banner tone="success">
                You are borrowing more than you post — {formatEther(requiredCollateral)} tCTC for{' '}
                {formatEther(parsedAmount)} tUSD. That is only possible because you repaid{' '}
                {Number(formatEther(capacity ?? 0n)).toLocaleString()} of a real third party&rsquo;s
                capital on Ethereum, and that repayment was proven here rather than claimed.
              </Banner>
            )}

            {cappedByCapacity && parsedAmount > 0n && (
              <Banner tone="info">
                Your {TIER_NAMES[tierIndex]} tier prices this loan, but it does not size it. Only{' '}
                {Number(formatEther(underPortion ?? 0n)).toLocaleString()} tUSD of it can be
                undercollateralized, because that is all the third-party capital this address has
                provably repaid. The remainder is fully collateralized whatever the tier says.
              </Banner>
            )}

            <Button disabled={!canWrite || status.kind === 'busy' || parsedAmount === 0n} onClick={() => void doBorrow()}>
              {canWrite ? 'Borrow' : 'Connect a wallet to borrow'}
            </Button>
          </div>
        )}

        {status.kind === 'busy' && <div className="mt-3"><Spinner label={status.message ?? 'Working…'} /></div>}
        {status.kind === 'error' && <div className="mt-3"><Banner tone="error">{status.message}</Banner></div>}
        {status.kind === 'done' && (
          <div className="mt-3">
            <Banner tone="success">
              {status.message}{' '}
              {status.hash !== undefined && <ExplorerLink chain="cc3" type="tx" hash={status.hash} />}
            </Banner>
          </div>
        )}

        <p className="mt-4 border-t border-ink-600 pt-3 text-[11px] text-slate-500">
          Pool:{' '}
          <ExplorerLink chain="cc3" type="address" hash={ADDRESSES.pool}>
            {ADDRESSES.pool.slice(0, 10)}…
          </ExplorerLink>
        </p>
      </Card>
    </div>
  );
}

function Row({
  label,
  value,
  emphasis,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  emphasis?: boolean;
  tone?: 'good';
}) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <span className="text-slate-500">{label}</span>
      <span
        className={`font-mono tabular-nums ${
          tone === 'good' ? 'text-emerald-300' : emphasis ? 'text-lg text-slate-100' : 'text-slate-200'
        }`}
      >
        {value}
      </span>
    </div>
  );
}
