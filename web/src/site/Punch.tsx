import type {CSSProperties} from 'react';

/**
 * The punch — a real extruded octagonal prism, built from DOM faces in CSS 3D.
 *
 * @remarks
 * This started as a Three.js scene. It is a lathe of one mesh under one light, which `three` plus
 * `@react-three/fiber` would have charged about 150KB gzipped to draw — in the hero, above the
 * fold, on the critical path of a page whose whole argument is that it loads instantly and holds
 * 60fps. Eight rotated faces and a clip-path cap give genuine perspective and genuine depth
 * ordering for roughly two kilobytes, and the result looks made rather than downloaded.
 *
 * The trade-off is honest: no environment reflections and no real specular. Both are faked with
 * per-face gradients lit from the top left, which is enough for brushed steel and would not be
 * enough for chrome.
 *
 * Everything animates on `transform` and `opacity` only.
 */

const FACES = 8;
const FACE_W = 46;
const FACE_H = 250;
/** Apothem of a regular octagon: half-width ÷ tan(π/8). This is what stops the faces gapping. */
const APOTHEM = FACE_W / 2 / Math.tan(Math.PI / FACES);

/**
 * Steel, lit from the top left: each face is shaded by how far it has turned away from the light.
 *
 * The vertical falloff is deliberately shallow. A steep one looked correct in isolation and read
 * as a black bar on the page, because the faces that survive to the camera are exactly the ones
 * the falloff was darkening most.
 */
function faceShading(index: number): string {
  const angle = (index / FACES) * Math.PI * 2;
  const lit = (Math.cos(angle - Math.PI * 0.25) + 1) / 2;
  const top = Math.round(96 + lit * 132);
  const mid = Math.round(64 + lit * 96);
  const bottom = Math.round(44 + lit * 62);
  return `linear-gradient(178deg,
    rgb(${top},${top + 4},${top + 9}) 0%,
    rgb(${mid},${mid + 3},${mid + 7}) 46%,
    rgb(${bottom},${bottom + 2},${bottom + 5}) 100%)`;
}

export function Punch({progress}: {progress: number}) {
  // The strike lands at 55% — late enough that the descent reads as deliberate, early enough that
  // the mark is legible for the rest of the scroll.
  const impact = 0.55;
  const descent = Math.min(1, progress / impact);
  const after = Math.max(0, (progress - impact) / (1 - impact));

  // Ease the fall in, so it accelerates into the blank rather than gliding.
  const fall = descent * descent;
  // A short recoil, then the punch lifts clear.
  const recoil = after < 0.18 ? Math.sin((after / 0.18) * Math.PI) * 26 : 0;

  const y = -210 + fall * 210 + recoil - after * 130;
  const spin = (1 - descent) * 150 + after * 14;
  const struck = progress >= impact;

  const stage: CSSProperties = {
    perspective: '900px',
    perspectiveOrigin: '50% 35%',
  };

  const prism: CSSProperties = {
    transformStyle: 'preserve-3d',
    transform: `translate3d(0, ${y.toFixed(2)}px, 0) rotateX(-8deg) rotateY(${spin.toFixed(2)}deg)`,
    willChange: 'transform',
  };

  return (
    <div className="relative flex h-full w-full flex-col items-center justify-end" style={stage} aria-hidden="true">
      <div className="relative" style={{width: FACE_W, height: FACE_H, ...prism}}>
        {Array.from({length: FACES}, (_, i) => (
          <div
            key={i}
            className="absolute inset-0"
            style={{
              background: faceShading(i),
              transform: `rotateY(${(i * 360) / FACES}deg) translateZ(${APOTHEM.toFixed(2)}px)`,
              // A hairline edge stops adjacent faces from blending into a smooth cylinder.
              boxShadow: 'inset 1px 0 0 rgba(255,255,255,0.06), inset -1px 0 0 rgba(0,0,0,0.5)',
            }}
          />
        ))}

        {/*
          Cap. Sits at the prism's top edge (local y = 0) and lies flat.

          The order is translate-then-rotate: rotating first swings the element's own axes, so a
          subsequent `translateZ` walks along world -Y and the cap detaches and floats above the
          shaft — which is exactly what the first version did.
        */}
        <div
          className="absolute left-0 top-0"
          style={{
            width: FACE_W,
            height: FACE_W,
            transform: `translateY(${(-FACE_W / 2).toFixed(2)}px) rotateX(90deg)`,
            background: 'linear-gradient(135deg, #d7dbe1 0%, #8a929c 55%, #4d545d 100%)',
            clipPath: 'polygon(30% 0,70% 0,100% 30%,100% 70%,70% 100%,30% 100%,0 70%,0 30%)',
          }}
        />
      </div>

      {/* The blank: the metal being struck. Widens under the punch so the strike has a target. */}
      <div className="relative h-2 w-48 rounded-[1px] bg-gradient-to-b from-ink-600 via-ink-700 to-ink-800" />

      {/*
        The struck mark. It does not fly in — it is either not there or permanently there, which is
        the only honest way to animate something the contract cannot undo.
      */}
      <div
        className="mt-5 flex flex-col items-center transition-opacity duration-300"
        style={{opacity: struck ? 1 : 0}}
      >
        <span
          className="font-mono text-[2.6rem] font-semibold leading-none text-platinum"
          style={{
            transform: struck ? 'scale(1)' : 'scale(0.94)',
            transition: 'transform 0.5s var(--strike-ease)',
            textShadow: '0 1px 0 rgba(0,0,0,0.9), 0 -1px 0 rgba(255,255,255,0.10)',
          }}
        >
          800
        </span>
        <span className="mt-2 font-mono text-label uppercase text-platinum/70">Platinum</span>
      </div>
    </div>
  );
}

/**
 * The still frame. Shown under `prefers-reduced-motion`, where the scene resolves to its end state
 * rather than performing a shortened version of it — a strike that does not strike is worse than
 * a mark that was always there.
 */
export function PunchStill() {
  return <Punch progress={1} />;
}
