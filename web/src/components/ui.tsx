import type {ReactNode} from 'react';
import {EXPLORERS, TIER_NAMES, TIER_STYLES} from '../config';

export function Card({title, subtitle, children, className = ''}: {
  title?: string;
  subtitle?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`rounded-xl border border-ink-600 bg-ink-800 p-5 ${className}`}>
      {title !== undefined && (
        <header className="mb-4">
          <h2 className="text-sm font-semibold uppercase tracking-widest text-slate-400">{title}</h2>
          {subtitle !== undefined && <p className="mt-1 text-sm text-slate-500">{subtitle}</p>}
        </header>
      )}
      {children}
    </section>
  );
}

export function TierPill({tier}: {tier: number}) {
  const style = TIER_STYLES[tier] ?? TIER_STYLES[0]!;
  return (
    <span
      className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-bold uppercase tracking-wider ring-1 ${style.text} ${style.ring} ${style.bg}`}
    >
      {TIER_NAMES[tier] ?? 'Bronze'}
    </span>
  );
}

/** A circular score dial. Mirrors the arc geometry of the on-chain SVG badge. */
export function ScoreDial({score, tier}: {score: number; tier: number}) {
  const style = TIER_STYLES[tier] ?? TIER_STYLES[0]!;
  const radius = 68;
  const circumference = 2 * Math.PI * radius;
  const filled = (Math.min(score, 1000) / 1000) * circumference;

  return (
    <div className="relative h-44 w-44">
      <svg viewBox="0 0 160 160" className="h-full w-full -rotate-90">
        <circle cx="80" cy="80" r={radius} fill="none" stroke="#2a2f3a" strokeWidth="11" />
        <circle
          cx="80"
          cy="80"
          r={radius}
          fill="none"
          className={style.text}
          stroke="currentColor"
          strokeWidth="11"
          strokeLinecap="round"
          strokeDasharray={`${filled} ${circumference}`}
          style={{transition: 'stroke-dasharray 900ms cubic-bezier(0.22, 1, 0.36, 1)'}}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="font-mono text-4xl font-bold text-slate-100 tabular-nums">{score}</span>
        <span className="font-mono text-[11px] text-slate-500">/ 1000</span>
      </div>
    </div>
  );
}

export function Stat({label, value, hint}: {label: string; value: ReactNode; hint?: string}) {
  return (
    <div className="rounded-lg border border-ink-600 bg-ink-900/60 px-4 py-3">
      <div className="text-[11px] uppercase tracking-wider text-slate-500">{label}</div>
      <div className="mt-1 font-mono text-lg text-slate-100 tabular-nums">{value}</div>
      {hint !== undefined && <div className="mt-0.5 text-[11px] text-slate-500">{hint}</div>}
    </div>
  );
}

export function ExplorerLink({
  chain,
  type,
  hash,
  children,
}: {
  chain: 'sepolia' | 'cc3';
  type: 'tx' | 'address';
  hash: string;
  children?: ReactNode;
}) {
  return (
    <a
      href={`${EXPLORERS[chain]}/${type}/${hash}`}
      target="_blank"
      rel="noreferrer"
      className="font-mono text-xs text-sky-400 underline decoration-sky-400/30 underline-offset-2 hover:decoration-sky-400"
    >
      {children ?? `${hash.slice(0, 10)}…${hash.slice(-6)}`}
    </a>
  );
}

export function Spinner({label}: {label: string}) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-slate-400">
      <span className="h-3 w-3 animate-spin rounded-full border-2 border-slate-600 border-t-sky-400" />
      {label}
    </span>
  );
}

export function Banner({tone, children}: {tone: 'info' | 'error' | 'success'; children: ReactNode}) {
  const tones = {
    info: 'border-sky-500/30 bg-sky-500/10 text-sky-200',
    error: 'border-rose-500/30 bg-rose-500/10 text-rose-200',
    success: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200',
  } as const;
  return <div className={`rounded-lg border px-4 py-3 text-sm ${tones[tone]}`}>{children}</div>;
}

export function Button({
  onClick,
  disabled,
  variant = 'primary',
  children,
}: {
  onClick?: () => void;
  disabled?: boolean;
  variant?: 'primary' | 'ghost';
  children: ReactNode;
}) {
  const styles =
    variant === 'primary'
      ? 'bg-sky-500 text-ink-900 hover:bg-sky-400 disabled:bg-ink-600 disabled:text-slate-500'
      : 'border border-ink-600 text-slate-300 hover:border-slate-500 disabled:text-slate-600';
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`rounded-lg px-4 py-2 text-sm font-semibold transition disabled:cursor-not-allowed ${styles}`}
    >
      {children}
    </button>
  );
}

/** Trims a viem/ethers error down to the part a human can act on. */
export function readableError(error: unknown): string {
  if (error === null || error === undefined) return 'Unknown error';
  const message = error instanceof Error ? error.message : String(error);

  // viem stacks cause chains many lines deep; the first line carries the useful part, and a
  // decoded custom error name (if any) is the single most informative token in the whole blob.
  const custom = /Error: ([A-Z]\w+)\(/.exec(message);
  if (custom !== null) return custom[1]!;
  const reverted = /reverted with the following reason:\s*\n(.+)/.exec(message);
  if (reverted !== null) return reverted[1]!.trim();
  return message.split('\n')[0]!.slice(0, 200);
}
