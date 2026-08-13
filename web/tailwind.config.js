/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Tier palette, matching the on-chain SVG in CreditTierSBT so the badge and the UI agree.
        bronze: '#cd7f32',
        silver: '#c0c0c0',
        gold: '#d4af37',
        platinum: '#e5e4e2',
        ink: {900: '#0f1115', 800: '#151922', 700: '#1c2029', 600: '#2a2f3a'},
      },
      fontFamily: {mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']},
    },
  },
  plugins: [],
};
