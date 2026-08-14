---
workflow: product-launch-video
flow: automation
storyboard: yes
message: "Your real Ethereum credit history can be proven on another chain, and priced as a loan"
destination: youtube
aspect: 1920x1080
language: en
length: 170s
angle: proof
---

## Intent

The submission film for CrossCredit at the BUIDL CTC 2026 Fall hackathon (Creditcoin). The audience
is hackathon judges who are protocol-literate, skimming, and scoring one criterion above all others:
depth of Attestcoin Protocol utilisation. `docs/BUILD_GUIDE.md` §9 fixes the format — 3:30 hard cap,
16:9, 1080p, captions burned in, no dead air. The script lands at 2:49 because a tight film reads as
confidence and the guide says judges decide in the first thirty seconds.

Tone is documentary, not advertisement: low, unhurried, closer to a Patagonia field film than a SaaS
promo. The product's own writing is already excellent and unusually confessional — it leads with what
it does *not* solve — so the film borrows that voice rather than inventing a louder one. Restraint is
the brand: one accent colour, one signature motion, silence where the numbers land.

The angle is **proof over promise**. Every number on screen is live on testnet from real Ethereum
mainnet history, and the film's spine is a single true story: a wallet that never heard of Creditcoin
gets a credit line anyway. The strongest beat is an admission — our first build could be gamed for six
wei, and saying so is what makes the rest credible.

## Assets

- demo/captures/*.png — 33 stills at 1080p driven from the live site: the hero strike in four steps,
  every content page, the explorer against three real borrowers, all three app tabs, and mobile.
  These are the featured assets; the film shows the real product, not a mockup of it.
- demo/terminal/negative-paths.txt — five attacks rejected by the live precompile. Verbatim output.
- demo/terminal/capacity-comparison.txt — the same `collateralRequired` call for two borrowers,
  850 against 1,300, read live from the deployed pool. The single best frame in the film.
- demo/terminal/live-loan.txt — a real borrow and repay on the deployed pool, with hashes.
- demo/VOICEOVER.md — the script. The user records it in Clipchamp and returns timed audio.
- web/public/brand/*.svg — the hallmark system: maker's mark, four fineness marks, assay mark.

## Customizations

- **Recreate the hero strike natively rather than compositing the screen capture.** It is CSS 3D in
  the product, so it can be rebuilt at full resolution in the composition and driven off the film's
  own timeline. Screen-recording it and scaling it down would throw away the one motion the brand
  owns.
- Score ladder counts up on the read: 0 → 320 → 440 → 560 → 680 → 800, one step per number spoken.
- The 850-vs-1300 comparison resolves as a single hard cut, both figures landing together.
- Burned-in captions throughout — the guide notes judges skim muted.
- Terminal output is typeset in the film's own mono, never screenshotted. Real text, real hashes.

## Notes

- **Audio arrives later.** The user generates the VO in Clipchamp from `demo/VOICEOVER.md` and will
  return the file with per-beat timings. Build to the script's estimated marks, keep every beat's
  duration in one place, and re-time on delivery rather than rebuilding.
- Not signed in to HeyGen: voice is not needed (user-supplied) and music falls to local MusicGen.
- **Accuracy constraints, non-negotiable.** Verification is synchronous within one Creditcoin block,
  but Sepolia attestation runs ~8–10 minutes ahead of it — never imply the end-to-end journey is
  instant. "No oracle *we* run" rather than "no oracle": Creditcoin's attestor set is in the trust
  path and the project retracted the stronger claim in writing.
- Palette and type come from the shipped product: ink-950 `#0A0B0D`, vellum `#EDE7DD`, ash `#8A8F97`,
  vermilion `#C8482A`, and the tier metals locked to the on-chain badge. Instrument Serif / Inter
  Tight / IBM Plex Mono, self-hosted in `web/public/fonts/`.
- No logo sting at the top. The guide is explicit: cold open, no intro. The mark appears once, at the
  end.
