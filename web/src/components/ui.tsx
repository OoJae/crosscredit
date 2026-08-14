import type {ReactNode} from 'react';
import {EXPLORERS, TIER_NAMES, TIER_STYLES} from '../config';
import {Hallmark} from '../site/Mark';

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
          <h2 className="text-sm font-semibold uppercase tracking-widest text-ash">{title}</h2>
          {subtitle !== undefined && <p className="mt-1 text-sm text-ash">{subtitle}</p>}
        </header>
      )}
      {children}
    </section>
  );
}

/**
 * The tier, as its hallmark.
 *
 * Was a rounded pill. The cartouche carries the same information plus the score floor, and it is
 * the mark the badge, the marketing pages and the favicon all use — a pill here would have been
 * the one place the identity did not reach.
 */
export function TierPill({tier}: {tier: number}) {
  const index = (tier >= 0 && tier <= 3 ? tier : 0) as 0 | 1 | 2 | 3;
  const style = TIER_STYLES[index]!;
  return (
    <span className="inline-flex items-center gap-2">
      <Hallmark tier={index} size={22} />
      <span className={`font-mono text-xs font-semibold uppercase tracking-wider ${style.text}`}>
        {TIER_NAMES[index]}
      </span>
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
        <span className="font-mono text-4xl font-bold text-vellum tabular-nums">{score}</span>
        <span className="font-mono text-[11px] text-ash">/ 1000</span>
      </div>
    </div>
  );
}

export function Stat({label, value, hint}: {label: string; value: ReactNode; hint?: string}) {
  return (
    <div className="rounded-lg border border-ink-600 bg-ink-900/60 px-4 py-3">
      <div className="text-[11px] uppercase tracking-wider text-ash">{label}</div>
      <div className="mt-1 font-mono text-lg text-vellum tabular-nums">{value}</div>
      {hint !== undefined && <div className="mt-0.5 text-[11px] text-ash">{hint}</div>}
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
      className="font-mono text-xs text-vellum underline decoration-assay/40 underline-offset-2 transition-colors duration-200 hover:decoration-assay"
    >
      {children ?? `${hash.slice(0, 10)}…${hash.slice(-6)}`}
    </a>
  );
}

export function Spinner({label}: {label: string}) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-ash">
      <span className="h-3 w-3 animate-spin rounded-full border-2 border-ink-600 border-t-assay" />
      {label}
    </span>
  );
}

export function Banner({tone, children}: {tone: 'info' | 'error' | 'success'; children: ReactNode}) {
  const tones = {
    info: 'border-ink-600 bg-ink-900/60 text-vellum',
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
      ? 'bg-assay text-ink-950 hover:bg-assay/90 disabled:bg-ink-600 disabled:text-ash'
      : 'border border-ink-600 text-vellum hover:border-ash/40 disabled:text-ash/50';
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
