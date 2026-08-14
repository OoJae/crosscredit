import type {ReactNode} from 'react';
import {Link, NavLink} from 'react-router-dom';
import {Mark} from './Mark';

/**
 * The frame every page on the site shares: ground, skip link, header, footer.
 *
 * Extracted from `Landing.tsx`, which held all of it privately. Four more pages meant either
 * copying a header four times or lifting it once, and a header that drifts between routes is the
 * fastest way to make five pages feel like five sites.
 */

const NAV = [
  {to: '/proof', label: 'Proof'},
  {to: '/tiers', label: 'Tiers'},
  {to: '/explorer', label: 'Explorer'},
  {to: '/threat-model', label: 'Threat model'},
] as const;

export function PageShell({children, footnote}: {children: ReactNode; footnote?: ReactNode}) {
  return (
    <div className="grain min-h-screen bg-ink-950 text-vellum">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:left-5 focus:top-5 focus:z-50 focus:rounded-sm focus:bg-assay focus:px-4 focus:py-2 focus:font-mono focus:text-sm focus:text-ink-950"
      >
        Skip to content
      </a>

      <header className="fixed inset-x-0 top-0 z-40 border-b border-ink-700/60 bg-ink-950/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-5 py-4">
          <Link to="/" className="flex shrink-0 items-center gap-2.5" aria-label="CrossCredit home">
            <Mark size={26} />
            <span className="font-mono text-sm font-semibold tracking-[0.18em]">CROSSCREDIT</span>
          </Link>

          {/*
            Scrolls horizontally rather than collapsing to a hamburger. Four short labels fit on a
            375px screen with room to spare, and a menu that has to be opened to be read is worse
            than one you can simply nudge.
          */}
          <nav
            aria-label="Sections"
            className="-mx-2 flex flex-1 items-center gap-1 overflow-x-auto px-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:justify-end md:gap-2"
          >
            {NAV.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({isActive}) =>
                  `shrink-0 rounded-sm px-2.5 py-2 font-mono text-label uppercase transition-colors duration-200 ${
                    isActive ? 'text-assay' : 'text-ash hover:text-vellum'
                  }`
                }
              >
                {item.label}
              </NavLink>
            ))}
            <Link
              to="/app"
              className="ml-1 shrink-0 rounded-sm px-3 py-2 font-mono text-label uppercase text-vellum ring-1 ring-ink-600 transition-colors duration-200 hover:ring-assay"
            >
              Open app
            </Link>
          </nav>
        </div>
      </header>

      <main id="main">{children}</main>

      <footer className="border-t border-ink-700">
        <div className="mx-auto max-w-6xl px-5 py-10">
          {footnote ?? <DefaultFootnote />}
        </div>
      </footer>
    </div>
  );
}

function DefaultFootnote() {
  return (
    <p className="max-w-3xl text-sm leading-relaxed text-ash">
      Testnet deployment, real mainnet data. History is proven from Ethereum to Creditcoin by the
      Attestcoin Protocol&rsquo;s native block-prover precompile — a Merkle inclusion proof plus a
      chain-continuity proof, verified inside a single Creditcoin block. There is no oracle we run,
      no multisig we control and no bridge holding funds; Creditcoin&rsquo;s attestor set is in the
      trust path, which is to say this needs no trust beyond the chain you are already settling on.
    </p>
  );
}
