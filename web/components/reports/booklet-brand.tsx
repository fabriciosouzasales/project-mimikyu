/**
 * Linguagem de fundo do Caderno de Cartas — a marca MMKYU DECOMPOSTA (D7 §4p): os três gestos do
 * símbolo, redesenhados em vetor e usados como textura, nunca como logotipo inteiro:
 *   - o rabisco circular (os "olhos") — massas translúcidas, ampliadas e cortadas pela borda;
 *   - o zigue-zague (a "boca") — grande traço que atravessa a página, ou fio de divisão;
 *   - a hachura dourada (as "bochechas") — pequenos acentos de cor.
 * Caminhos gerados de forma DETERMINÍSTICA (semente fixa): idênticos no servidor, no cliente e na
 * impressão. Sem imagem raster; cor por `currentColor`/variáveis do caderno (tema claro, escuro e
 * papel). Decorativo: `aria-hidden`.
 */

function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const f = (n: number) => Math.round(n * 100) / 100;

/** Rabisco circular em torno de (0,0), raio ~1: várias voltas com deriva e tremor, como traço de caneta. */
function scribblePath(seed: number, turns = 7): string {
  const r = rng(seed);
  const steps = turns * 28;
  let d = "";
  let cx = 0;
  let cy = 0;
  for (let i = 0; i <= steps; i += 1) {
    const t = (i / 28) * Math.PI * 2;
    cx += (r() - 0.5) * 0.02;
    cy += (r() - 0.5) * 0.02;
    const radius = 0.62 + 0.3 * Math.sin(t * 0.21 + seed) + (r() - 0.5) * 0.07;
    const x = cx + Math.cos(t) * radius * 0.92;
    const y = cy + Math.sin(t) * radius;
    d += `${i === 0 ? "M" : "L"}${f(x)} ${f(y)}`;
  }
  return d;
}

/** Hachura: traços curtos inclinados, empilhados, em mancha — de (0,0) a ~(1,1). */
function hatchPath(seed: number, strokes = 9): string {
  const r = rng(seed);
  let d = "";
  for (let i = 0; i < strokes; i += 1) {
    const y = i / (strokes - 1);
    const width = 0.55 + Math.sin((i / (strokes - 1)) * Math.PI) * 0.45;
    const x0 = 0.5 - width / 2 + (r() - 0.5) * 0.08;
    const x1 = 0.5 + width / 2 + (r() - 0.5) * 0.08;
    d += `M${f(x0)} ${f(y + 0.05)}L${f(x1)} ${f(y - 0.05 + (r() - 0.5) * 0.04)}`;
  }
  return d;
}

/** Zigue-zague da "boca": 4 dentes, de (0,0) a (1, ~0.35). */
const ZIGZAG = "M0 0.04L0.1 0.3L0.27 0.12L0.43 0.33L0.6 0.14L0.77 0.35L0.92 0.17L1 0.27";

const SCRIBBLE_A = scribblePath(11);
const SCRIBBLE_B = scribblePath(29, 6);
const HATCH_A = hatchPath(7);
const HATCH_B = hatchPath(19, 8);

type Mark = { x: number; y: number; size: number; rotate?: number };

function Scribble({ x, y, size, rotate = 0, path = SCRIBBLE_A, width = 0.035 }: Mark & { path?: string; width?: number }) {
  return (
    <path
      d={path}
      transform={`translate(${x} ${y}) rotate(${rotate}) scale(${size})`}
      fill="none"
      stroke="currentColor"
      strokeWidth={width}
      strokeLinecap="round"
      strokeLinejoin="round"
      vectorEffect="none"
    />
  );
}

function Hatch({ x, y, size, rotate = -18, path = HATCH_A, width = 0.09 }: Mark & { path?: string; width?: number }) {
  return (
    <path
      d={path}
      transform={`translate(${x} ${y}) rotate(${rotate}) scale(${size})`}
      fill="none"
      stroke="var(--bk-gold)"
      strokeWidth={width}
      strokeLinecap="round"
    />
  );
}

function Zigzag({ x, y, size, rotate = 0, width = 0.035 }: Mark & { width?: number }) {
  return (
    <path
      d={ZIGZAG}
      transform={`translate(${x} ${y}) rotate(${rotate}) scale(${size})`}
      fill="none"
      stroke="currentColor"
      strokeWidth={width}
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  );
}

/** Campo da capa: massas amplas cortadas pela borda + acentos dourados. Coordenadas em mm (A4). */
export function CoverField({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 210 297" preserveAspectRatio="xMinYMin slice" aria-hidden="true" focusable="false">
      <g style={{ color: "var(--bk-ink)" }}>
        <g opacity="0.075">
          <Scribble x={168} y={62} size={78} rotate={-12} width={0.03} />
        </g>
        <g opacity="0.05">
          <Scribble x={30} y={250} size={46} rotate={24} path={SCRIBBLE_B} width={0.04} />
        </g>
        <g opacity="0.06">
          <Zigzag x={-18} y={206} size={250} rotate={-9} width={0.02} />
        </g>
      </g>
      <g opacity="0.8">
        <Hatch x={176} y={128} size={12} rotate={-24} />
      </g>
      <g opacity="0.55">
        <Hatch x={170} y={250} size={24} rotate={-30} path={HATCH_B} />
      </g>
    </svg>
  );
}

/** Campo das páginas de cartas: só uma marca d'água muito leve atrás da grade. */
export function PageField({ className, variant }: { className?: string; variant: number }) {
  const left = variant % 2 === 0;
  return (
    <svg className={className} viewBox="0 0 210 297" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
      <g style={{ color: "var(--bk-ink)" }} opacity="0.035">
        <Scribble x={left ? 18 : 192} y={left ? 270 : 34} size={58} rotate={left ? 30 : -20} path={left ? SCRIBBLE_B : SCRIBBLE_A} width={0.035} />
      </g>
    </svg>
  );
}

/** Pequeno acento dourado (hachura) para cabeçalhos corridos e selos. */
export function HatchMark({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="-2 -2 24 24" aria-hidden="true" focusable="false">
      <Hatch x={0} y={1} size={20} rotate={-18} width={0.11} />
    </svg>
  );
}

/** Fio em zigue-zague (divisor editorial). */
export function ZigzagRule({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="-2 -2 104 40" preserveAspectRatio="none" aria-hidden="true" focusable="false">
      <g style={{ color: "currentColor" }}>
        <Zigzag x={0} y={0} size={100} width={0.03} />
      </g>
    </svg>
  );
}

/** Campo do encerramento: espelho discreto da capa. */
export function ClosingField({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 210 297" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
      <g style={{ color: "var(--bk-ink)" }}>
        <g opacity="0.06">
          <Scribble x={44} y={226} size={74} rotate={18} path={SCRIBBLE_B} width={0.03} />
        </g>
        <g opacity="0.05">
          <Zigzag x={70} y={70} size={170} rotate={8} width={0.025} />
        </g>
      </g>
      <g opacity="0.7">
        <Hatch x={176} y={210} size={16} rotate={-26} />
      </g>
    </svg>
  );
}
