import {useEffect, useRef, useState} from 'react';

/** True once the user has asked for less motion. Read once — it is not a thing that toggles often. */
export const prefersReducedMotion = (): boolean =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/**
 * Adds `revealed` to an element the first time it enters the viewport, and then stops watching.
 *
 * Fires once, at 85% down the viewport — a reveal that re-runs every time you scroll past turns a
 * page into a slot machine, and one that fires at the very bottom edge is finished before it is
 * looked at.
 */
export function useReveal<T extends HTMLElement = HTMLDivElement>() {
  const ref = useRef<T>(null);
  const [revealed, setRevealed] = useState(prefersReducedMotion());

  useEffect(() => {
    const node = ref.current;
    if (node === null || revealed) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setRevealed(true);
            observer.disconnect();
          }
        }
      },
      {rootMargin: '0px 0px -15% 0px'},
    );

    observer.observe(node);
    return () => {
      observer.disconnect();
    };
  }, [revealed]);

  return {ref, revealed};
}

/**
 * Scroll progress through an element, 0 → 1, measured against the viewport.
 *
 * Reads on `requestAnimationFrame` rather than in the scroll handler itself: `getBoundingClientRect`
 * in a scroll listener forces layout on every event and is the classic way to lose 60fps on exactly
 * the kind of scene this drives.
 */
export function useScrollProgress<T extends HTMLElement = HTMLDivElement>() {
  const ref = useRef<T>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    if (prefersReducedMotion()) {
      setProgress(1);
      return;
    }

    let frame = 0;
    let running = true;

    const tick = () => {
      if (!running) return;
      const node = ref.current;
      if (node !== null) {
        const rect = node.getBoundingClientRect();
        const total = rect.height - window.innerHeight;
        const next = total <= 0 ? 0 : Math.min(1, Math.max(0, -rect.top / total));
        setProgress((current) => (Math.abs(current - next) > 0.002 ? next : current));
      }
      frame = requestAnimationFrame(tick);
    };

    frame = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(frame);
    };
  }, []);

  return {ref, progress};
}
