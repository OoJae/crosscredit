import type {ReactNode} from 'react';
import {useReveal} from './useReveal';

/**
 * Long-form primitives. The content pages are mostly reading, so the job here is measure, rhythm
 * and one consistent reveal — not decoration.
 */

/** A masked line that rises into place once. The site's only reveal mechanism. */
export function Line({children, delay = 0}: {children: ReactNode; delay?: number}) {
  return (
    <span className="block overflow-hidden">
      <span className="reveal-line" style={{transitionDelay: `${delay}ms`}}>
        {children}
      </span>
    </span>
  );
}

/**
 * Section label. The step number is only ever passed where the content is a genuine sequence —
 * the five checks run in order, the twelve disclosures are numbered in the doc. Numbering a set
 * that has no order is decoration wearing structure's clothes.
 */
export function Eyebrow({step, children}: {step?: string; children: ReactNode}) {
  return (
    <p className="flex items-center gap-3 font-mono text-label uppercase text-ash">
      {step !== undefined && <span className="text-assay">{step}</span>}
      <span aria-hidden="true" className="h-px w-8 bg-ink-600" />
      {children}
    </p>
  );
}

/** A page's opening plate: eyebrow, display heading, and a lede at reading measure. */
export function PageHead({
  eyebrow,
  title,
  lede,
}: {
  eyebrow: string;
  title: ReactNode;
  lede?: ReactNode;
}) {
  const {ref, revealed} = useReveal<HTMLDivElement>();

  return (
    <div ref={ref} className={`mx-auto max-w-6xl px-5 pb-16 pt-32 md:pb-20 md:pt-40 ${revealed ? 'revealed' : ''}`}>
      <Eyebrow>{eyebrow}</Eyebrow>
      <h1 className="mt-7 max-w-[18ch] font-display text-section">{title}</h1>
      {lede !== undefined && <p className="mt-8 max-w-measure text-lede text-ash">{lede}</p>}
    </div>
  );
}

/** A block within a page. Reveals once as a unit. */
export function Section({
  step,
  label,
  title,
  children,
}: {
  step?: string;
  label: string;
  title?: ReactNode;
  children: ReactNode;
}) {
  const {ref, revealed} = useReveal<HTMLElement>();

  return (
    <section ref={ref} className={revealed ? 'revealed' : ''}>
      <div className="mx-auto max-w-6xl border-t border-ink-700 px-5 py-16 md:py-24">
        <Eyebrow step={step}>{label}</Eyebrow>
        {title !== undefined && <h2 className="mt-7 max-w-[22ch] font-display text-section">{title}</h2>}
        <div className="mt-10">{children}</div>
      </div>
    </section>
  );
}

/** Body copy, held to a real measure. */
export function P({children, tone = 'ash'}: {children: ReactNode; tone?: 'ash' | 'vellum'}) {
  return (
    <p className={`max-w-measure text-body ${tone === 'ash' ? 'text-ash' : 'text-vellum'} [&+&]:mt-5`}>
      {children}
    </p>
  );
}

/** Inline code and on-chain values. Everything numeric on this site is mono. */
export function Mono({children}: {children: ReactNode}) {
  return <span className="font-mono text-[0.92em] text-vellum">{children}</span>;
}

/**
 * A table that scrolls inside itself rather than pushing the page sideways.
 *
 * The five-check chain has a long third column, and on a 375px screen an unwrapped table is the
 * single most common way a content page ends up with a horizontally scrolling body.
 */
export function Figure({caption, children}: {caption?: string; children: ReactNode}) {
  return (
    <figure className="my-2">
      <div className="-mx-5 overflow-x-auto px-5 md:mx-0 md:px-0">
        <div className="min-w-[34rem]">{children}</div>
      </div>
      {caption !== undefined && (
        <figcaption className="mt-4 font-mono text-label uppercase text-ash">{caption}</figcaption>
      )}
    </figure>
  );
}

/** A numbered item in a genuine sequence — the five checks, the twelve disclosures. */
export function NumberedItem({
  n,
  title,
  children,
}: {
  n: number;
  title: string;
  children: ReactNode;
}) {
  const {ref, revealed} = useReveal<HTMLLIElement>();

  return (
    <li ref={ref} className={`border-t border-ink-700 py-8 ${revealed ? 'revealed' : ''}`}>
      <div className="grid gap-4 md:grid-cols-12 md:gap-8">
        <p className="font-mono text-label text-assay md:col-span-1">
          {String(n).padStart(2, '0')}
        </p>
        <div className="md:col-span-11">
          <h3 className="text-lede text-vellum">{title}</h3>
          <div className="mt-4">{children}</div>
        </div>
      </div>
    </li>
  );
}
