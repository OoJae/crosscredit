/**
 * The hallmark system, inline.
 *
 * The same geometry ships as static files in `public/brand/` for favicons, OG images and README
 * use. These are the inline versions, and they exist because an SVG loaded through an `<img>` tag
 * has no parent to inherit from — `currentColor` resolves to black and the mark vanishes. Inline,
 * every mark takes its colour from whatever it sits on.
 */
import type {CSSProperties} from 'react';

/** Maker's mark: two counter-facing arcs in a cut-corner cartouche. */
export function Mark({size = 28, className = ''}: {size?: number; className?: string}) {
  return (
    <svg
      viewBox="0 0 64 64"
      width={size}
      height={size}
      fill="none"
      role="img"
      aria-label="CrossCredit"
      className={className}
    >
      <path
        d="M32 3 61 32 32 61 3 32Z"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinejoin="round"
        opacity="0.4"
      />
      {/* The right arc is an exact mirror of the left — hand-drawing both let them drift closed. */}
      <path id="cc-arc" d="M29.1 20.4A12 12 0 1 0 29.1 43.6" stroke="currentColor" strokeWidth="4.4" strokeLinecap="round" />
      <use href="#cc-arc" transform="translate(64 0) scale(-1 1)" />
    </svg>
  );
}

export const TIER_HALLMARKS = [
  {name: 'Bronze', floor: '000', colour: '#cd7f32', d: 'M4 4h40v40l-6 8H10l-6-8Z', y: 32},
  {name: 'Silver', floor: '250', colour: '#c0c0c0', d: null, y: 34},
  {name: 'Gold', floor: '500', colour: '#d4af37', d: 'M24 3 44 9v22c0 11-9 18-20 22C13 49 4 42 4 31V9Z', y: 31},
  {name: 'Platinum', floor: '700', colour: '#e5e4e2', d: 'M24 3 44 17v22L24 53 4 39V17Z', y: 33},
] as const;

/**
 * A fineness mark. The cartouche shape denotes the tier and the number is its score floor — which
 * is how real hallmarking works, and means the set survives greyscale, a 20px row and
 * colour-blindness without leaning on the metal colour to do the identifying.
 */
export function Hallmark({
  tier,
  size = 48,
  muted = false,
  className = '',
  style,
}: {
  tier: 0 | 1 | 2 | 3;
  size?: number;
  muted?: boolean;
  className?: string;
  style?: CSSProperties;
}) {
  const mark = TIER_HALLMARKS[tier];
  const stroke = muted ? 'currentColor' : mark.colour;

  return (
    <svg
      viewBox="0 0 48 56"
      width={size}
      height={(size * 56) / 48}
      fill="none"
      role="img"
      aria-label={`${mark.name} tier, from ${Number(mark.floor)} points`}
      className={className}
      style={style}
    >
      {mark.d === null ? (
        <ellipse cx="24" cy="28" rx="20" ry="24" stroke={stroke} strokeWidth="2.5" />
      ) : (
        <path d={mark.d} stroke={stroke} strokeWidth="2.5" strokeLinejoin="round" />
      )}
      <text
        x="24"
        y={mark.y}
        fontFamily="'IBM Plex Mono', ui-monospace, monospace"
        fontSize="15"
        fontWeight="600"
        letterSpacing="0.5"
        fill={stroke}
        textAnchor="middle"
      >
        {mark.floor}
      </text>
    </svg>
  );
}

/**
 * The assay office mark — which chain tested the metal. A Merkle path of two halving steps meeting
 * the anvil line of the attested block they resolve against.
 */
export function AssayMark({size = 48, className = ''}: {size?: number; className?: string}) {
  return (
    <svg
      viewBox="0 0 48 56"
      width={size}
      height={(size * 56) / 48}
      fill="none"
      role="img"
      aria-label="Assayed on Creditcoin"
      className={className}
    >
      <path d="M4 12 12 4h24l8 8v40H4Z" stroke="currentColor" strokeWidth="2.5" strokeLinejoin="round" opacity="0.5" />
      <path d="M15 18h18M20 28h8" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" />
      <path d="M12 40h24" stroke="currentColor" strokeWidth="4.5" strokeLinecap="round" />
    </svg>
  );
}

/** Mark plus legend, at cap height — the lockup a silversmith punches: mark first, then the name. */
export function Wordmark({size = 26, className = ''}: {size?: number; className?: string}) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <Mark size={size} />
      <span className="font-mono font-semibold tracking-[0.18em]" style={{fontSize: size * 0.62}}>
        CROSSCREDIT
      </span>
    </span>
  );
}
