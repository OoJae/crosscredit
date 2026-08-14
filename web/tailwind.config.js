/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // ─── Tier palette ────────────────────────────────────────────────────────────────
        // Locked to `_tierColour` in CreditTierSBT.sol. The badge is deployed and immutable, so
        // the brand yields to the contract rather than the other way round. These are DATA
        // colours: they appear on tier objects only, never on chrome or decoration.
        bronze: '#cd7f32',
        silver: '#c0c0c0',
        gold: '#d4af37',
        platinum: '#e5e4e2',

        // ─── Surfaces ────────────────────────────────────────────────────────────────────
        // `ink` is the existing app scale, untouched. `950` is new: the marketing ground, one
        // shade below the app so a full-bleed page reads as bench metal rather than as a panel.
        ink: {950: '#0A0B0D', 900: '#0f1115', 800: '#151922', 700: '#1c2029', 600: '#2a2f3a'},

        // ─── Ink and accent ──────────────────────────────────────────────────────────────
        // vellum: the assay certificate. 17:1 on ink-950.
        // ash:    secondary text. 4.9:1 on ink-950 — the floor for body copy.
        // assay:  the one accent. Vermilion, from sealing wax and punch-mark ink. It replaces
        //         Tailwind's default sky-500, which is what every crypto dashboard reaches for.
        //         Used at display size or as a mark; never as body text, where it fails contrast.
        vellum: '#EDE7DD',
        ash: '#8A8F97',
        assay: '#C8482A',
      },
      fontFamily: {
        // Display is used oversized and sparingly — it is the one voice in the type system.
        display: ['"Instrument Serif"', 'ui-serif', 'Georgia', 'serif'],
        sans: ['"Inter Tight"', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        // Mono carries every number, because every number on this site is real on-chain data —
        // and because the on-chain badge is set entirely in mono, so artifact and identity agree.
        mono: ['"IBM Plex Mono"', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      fontSize: {
        // Fluid scale. Line-height tightens as size grows; tracking goes negative on display and
        // open on labels, which is how engraved legends are actually spaced.
        hero: ['clamp(3rem, 11vw, 12rem)', {lineHeight: '0.88', letterSpacing: '-0.03em'}],
        section: ['clamp(2rem, 4.5vw, 4.5rem)', {lineHeight: '1', letterSpacing: '-0.02em'}],
        lede: ['clamp(1.125rem, 1.6vw, 1.5rem)', {lineHeight: '1.5'}],
        body: ['clamp(1rem, 1.05vw, 1.15rem)', {lineHeight: '1.6'}],
        label: ['0.72rem', {lineHeight: '1', letterSpacing: '0.14em'}],
      },
      transitionTimingFunction: {
        // The expressive out-curve everything reveals on, and the symmetric one for state toggles.
        strike: 'cubic-bezier(0.16, 1, 0.3, 1)',
        toggle: 'cubic-bezier(0.65, 0, 0.35, 1)',
      },
      maxWidth: {measure: '62ch'},
    },
  },
  plugins: [],
};
