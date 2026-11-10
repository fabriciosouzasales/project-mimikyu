import type { CSSProperties } from "react";
import styles from "./capture-burst.module.css";

/**
 * Momento de captura da Pokédex. Objeto PRÓPRIO do MMKYU — a "Esfera MMKYU": esfera grafite
 * envernizada, com um anel orbital dourado inclinado (como um planeta) e o rabisco circular da marca
 * acendendo no centro. Não reproduz a Pokébola (design registrado da franquia: sem divisão em duas
 * cores, faixa equatorial ou botão central); o que vem das referências é só a linguagem de luz da
 * captura — tensão, clarão, raios, ondas e estrelas.
 *
 * Sequência (~3,2 s, só `transform`/`opacity`):
 *  1. queda com quique (0–0,4 s) e um brilho que cresce a cada um dos três balanços (0,45–1,6 s);
 *  2. TRAVA (1,65 s): clarão branco-dourado sobre a carta, coroa de raios girando, duas ondas de luz,
 *     estrelas de quatro pontas e faíscas em todas as direções; o emblema acende;
 *  3. "Capturado!" entra com um reflexo passando (1,9 s) e tudo se dissolve no fim.
 * `prefers-reduced-motion`: esfera acesa e o selo, sem movimento nem clarão.
 * Decorativo (`aria-hidden`): o anúncio acessível continua no `aria-live` da grade.
 */

/** Estrelas: deslocamento a partir da esfera (rem), tamanho (rem), atraso (s) e giro — fixos, sem aleatoriedade. */
const STARS: ReadonlyArray<{ x: number; y: number; s: number; d: number; r: number }> = [
  { x: -2.6, y: -2.2, s: 1.15, d: 0, r: 0 },
  { x: 2.5, y: -2.4, s: 0.95, d: 0.05, r: 20 },
  { x: -3, y: 0.7, s: 0.8, d: 0.1, r: -15 },
  { x: 2.9, y: 1, s: 1.2, d: 0.02, r: 10 },
  { x: -0.6, y: -3.3, s: 0.75, d: 0.14, r: 30 },
  { x: 1, y: 3.1, s: 0.85, d: 0.08, r: -25 },
  { x: -1.9, y: 2.7, s: 0.65, d: 0.18, r: 5 },
  { x: 1.6, y: -1.1, s: 0.6, d: 0.22, r: 40 },
  { x: -1.5, y: -0.8, s: 0.55, d: 0.26, r: -40 },
  { x: 3.4, y: -0.4, s: 0.7, d: 0.16, r: 15 },
];

const SPARKS = 14;

function Star() {
  return (
    <svg viewBox="-10 -10 20 20" focusable="false">
      <path d="M0 -10 C1.2 -2.2 2.2 -1.2 10 0 C2.2 1.2 1.2 2.2 0 10 C-1.2 2.2 -2.2 1.2 -10 0 C-2.2 -1.2 -1.2 -2.2 0 -10 Z" fill="url(#mmkyu-capture-star)" />
    </svg>
  );
}

export function CaptureBurst() {
  return (
    <span className={styles.root} aria-hidden="true">
      {/* Definições compartilhadas (gradientes); ids estáveis, iguais em todas as instâncias. */}
      <svg className={styles.defs} focusable="false">
        <defs>
          <radialGradient id="mmkyu-capture-star">
            <stop offset="0%" stopColor="#ffffff" />
            <stop offset="45%" stopColor="#fff6dc" />
            <stop offset="100%" stopColor="#f1c25f" />
          </radialGradient>
          <radialGradient id="mmkyu-capture-body" cx="36%" cy="30%" r="78%">
            <stop offset="0%" stopColor="#6b6157" />
            <stop offset="38%" stopColor="#2b2620" />
            <stop offset="100%" stopColor="#0b0907" />
          </radialGradient>
          <radialGradient id="mmkyu-capture-core" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#fff3cf" stopOpacity="0.95" />
            <stop offset="45%" stopColor="#f0b84f" stopOpacity="0.55" />
            <stop offset="100%" stopColor="#f0b84f" stopOpacity="0" />
          </radialGradient>
          {/* Metade inferior (frente) do anel orbital, no mesmo ângulo da elipse. */}
          <clipPath id="mmkyu-capture-front">
            <rect x="-20" y="33" width="104" height="40" transform="rotate(-18 32 33)" />
          </clipPath>
          <linearGradient id="mmkyu-capture-ring" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#8c5d1d" />
            <stop offset="35%" stopColor="#f6d27f" />
            <stop offset="60%" stopColor="#dca54b" />
            <stop offset="100%" stopColor="#8c5d1d" />
          </linearGradient>
        </defs>
      </svg>

      {/* Luz da trava recortada pela carta (clarão, raios e ondas não invadem as vizinhas). */}
      <span className={styles.glow}>
        <span className={styles.flash} />
        <span className={styles.rays} />
        <span className={styles.wave} />
        <span className={`${styles.wave} ${styles.waveLate}`} />
      </span>

      <span className={styles.stage}>
        <span className={styles.aura} />

        <span className={styles.sparks}>
          {Array.from({ length: SPARKS }, (_, i) => (
            <span key={i} className={styles.spark} style={{ "--a": `${(360 / SPARKS) * i + 9}deg`, "--d": `${(i % 3) * 0.05}s` } as CSSProperties} />
          ))}
        </span>

        <span className={styles.drop}>
          <span className={styles.wobble}>
            <span className={styles.lock}>
              <svg className={styles.orb} viewBox="0 0 64 64" focusable="false">
                {/* Metade de trás do anel orbital (passa atrás da esfera). */}
                <ellipse cx="32" cy="33" rx="30" ry="9" transform="rotate(-18 32 33)" fill="none" stroke="url(#mmkyu-capture-ring)" strokeWidth="2.6" strokeOpacity="0.55" />
                <circle cx="32" cy="32" r="21" fill="url(#mmkyu-capture-body)" />
                <circle cx="32" cy="32" r="21" fill="none" stroke="#f0c46e" strokeOpacity="0.45" strokeWidth="1" />
                {/* Núcleo de luz e emblema: rabisco circular da marca MMKYU. */}
                <circle className={styles.core} cx="32" cy="32" r="13" fill="url(#mmkyu-capture-core)" />
                <path
                  className={styles.emblem}
                  d="M32 23.5c5.4-.3 9 3.7 8.5 8.4-.5 4.9-5 8-9.6 7.3-4.4-.7-7.1-4.7-6.3-8.7.8-4.1 4.9-6.3 8.5-5.5 3.7.9 5.7 4.5 4.9 7.9-.9 3.3-4.4 4.9-7.4 3.7-2.8-1-3.8-4.2-2.6-6.6 1.1-2.3 4-3.1 5.9-1.9 1.8 1.1 2.1 3.6.8 4.9"
                  fill="none"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
                {/* Verniz: reflexo grande suave + ponto de luz. */}
                <ellipse cx="24" cy="21" rx="9" ry="5" fill="#ffffff" fillOpacity="0.18" transform="rotate(-32 24 21)" />
                <circle cx="21.5" cy="19" r="1.8" fill="#ffffff" fillOpacity="0.7" />
                {/* Metade da frente do anel orbital (cobre a esfera). */}
                <ellipse cx="32" cy="33" rx="30" ry="9" transform="rotate(-18 32 33)" fill="none" stroke="url(#mmkyu-capture-ring)" strokeWidth="2.8" clipPath="url(#mmkyu-capture-front)" />
              </svg>
            </span>
          </span>
        </span>

        {STARS.map((star, i) => (
          <span
            key={i}
            className={styles.star}
            style={{ "--x": `${star.x}rem`, "--y": `${star.y}rem`, "--s": `${star.s}rem`, "--d": `${star.d}s`, "--r": `${star.r}deg` } as CSSProperties}
          >
            <Star />
          </span>
        ))}
      </span>

      <span className={styles.label}>
        <span className={styles.labelText}>Capturado!</span>
      </span>
    </span>
  );
}
