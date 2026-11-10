/**
 * Gerador de QR Code (ISO/IEC 18004) puro, sem dependência — usado pela página de orientações dos
 * Placeholders da Pokédex. Escopo deliberadamente pequeno: modo byte (UTF-8), correção de erro M
 * (≈ 15%, boa para papel impresso em casa), versões 1–10 (até 213 bytes — sobra para um endereço),
 * máscara escolhida pela penalidade da norma. Saída = matriz de módulos (`true` = escuro), sem a zona
 * de silêncio; quem desenha acrescenta 4 módulos claros em volta.
 *
 * Estrutura conforme a norma e a implementação de referência de Project Nayuki (domínio público de
 * fato do algoritmo): padrões de função → códigos com Reed-Solomon em GF(256) (0x11D) entrelaçados →
 * posicionamento em zigue-zague → máscara → informação de formato (BCH 0x537 ⊕ 0x5412) e de versão
 * (BCH 0x1F25, v ≥ 7). Conferido por leitura real (decodificador do OpenCV) nos testes do kit.
 */

type Block = { count: number; data: number };
/** Correção M: códigos de correção por bloco e grupos de blocos (dados por bloco), versões 1–10. */
const VERSIONS: ReadonlyArray<{ ec: number; blocks: Block[]; align: number[] }> = [
  { ec: 10, blocks: [{ count: 1, data: 16 }], align: [] },
  { ec: 16, blocks: [{ count: 1, data: 28 }], align: [6, 18] },
  { ec: 26, blocks: [{ count: 1, data: 44 }], align: [6, 22] },
  { ec: 18, blocks: [{ count: 2, data: 32 }], align: [6, 26] },
  { ec: 24, blocks: [{ count: 2, data: 43 }], align: [6, 30] },
  { ec: 16, blocks: [{ count: 4, data: 27 }], align: [6, 34] },
  { ec: 18, blocks: [{ count: 4, data: 31 }], align: [6, 22, 38] },
  { ec: 22, blocks: [{ count: 2, data: 38 }, { count: 2, data: 39 }], align: [6, 24, 42] },
  { ec: 22, blocks: [{ count: 3, data: 36 }, { count: 2, data: 37 }], align: [6, 26, 46] },
  { ec: 26, blocks: [{ count: 4, data: 43 }, { count: 1, data: 44 }], align: [6, 28, 50] },
];

const dataCapacity = (v: number) => VERSIONS[v - 1]!.blocks.reduce((s, b) => s + b.count * b.data, 0);

function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i -= 1) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function rsDivisor(degree: number): number[] {
  const result = new Array<number>(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i += 1) {
    for (let j = 0; j < degree; j += 1) {
      result[j] = gfMul(result[j]!, root);
      if (j + 1 < degree) result[j]! ^= result[j + 1]!;
    }
    root = gfMul(root, 0x02);
  }
  return result;
}

function rsRemainder(data: readonly number[], divisor: readonly number[]): number[] {
  const result = new Array<number>(divisor.length).fill(0);
  for (const b of data) {
    const factor = b ^ result.shift()!;
    result.push(0);
    for (let i = 0; i < divisor.length; i += 1) result[i]! ^= gfMul(divisor[i]!, factor);
  }
  return result;
}

/** Bytes de dados (modo, contagem, bytes, terminador, preenchimento) para a versão dada. */
function dataCodewords(bytes: readonly number[], version: number): number[] {
  const bits: number[] = [];
  const push = (value: number, length: number) => {
    for (let i = length - 1; i >= 0; i -= 1) bits.push((value >>> i) & 1);
  };
  push(0b0100, 4);
  push(bytes.length, version < 10 ? 8 : 16);
  for (const b of bytes) push(b, 8);
  const capacityBits = dataCapacity(version) * 8;
  push(0, Math.min(4, capacityBits - bits.length));
  push(0, (8 - (bits.length % 8)) % 8);
  const out: number[] = [];
  for (let i = 0; i < bits.length; i += 8) out.push(bits.slice(i, i + 8).reduce((acc, bit) => (acc << 1) | bit, 0));
  for (let pad = 0xec; out.length < dataCapacity(version); pad ^= 0xec ^ 0x11) out.push(pad);
  return out;
}

/** Divide em blocos, calcula a correção de cada um e entrelaça (dados, depois correção). */
function finalCodewords(data: readonly number[], version: number): number[] {
  const { ec, blocks } = VERSIONS[version - 1]!;
  const divisor = rsDivisor(ec);
  const dataBlocks: number[][] = [];
  const ecBlocks: number[][] = [];
  let k = 0;
  for (const group of blocks) {
    for (let i = 0; i < group.count; i += 1) {
      const chunk = data.slice(k, k + group.data);
      k += group.data;
      dataBlocks.push(chunk);
      ecBlocks.push(rsRemainder(chunk, divisor));
    }
  }
  const out: number[] = [];
  const longest = Math.max(...dataBlocks.map((b) => b.length));
  for (let i = 0; i < longest; i += 1) for (const b of dataBlocks) if (i < b.length) out.push(b[i]!);
  for (let i = 0; i < ec; i += 1) for (const b of ecBlocks) out.push(b[i]!);
  return out;
}

class Matrix {
  readonly size: number;
  readonly dark: boolean[][];
  readonly fn: boolean[][];
  constructor(size: number) {
    this.size = size;
    this.dark = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
    this.fn = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  }
  setFn(x: number, y: number, dark: boolean) {
    this.dark[y]![x] = dark;
    this.fn[y]![x] = true;
  }
}

function drawFunctionPatterns(m: Matrix, version: number) {
  const { size } = m;
  for (let i = 0; i < size; i += 1) {
    m.setFn(6, i, i % 2 === 0);
    m.setFn(i, 6, i % 2 === 0);
  }
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]] as const) {
    for (let dy = -4; dy <= 4; dy += 1) {
      for (let dx = -4; dx <= 4; dx += 1) {
        const x = cx + dx;
        const y = cy + dy;
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        const dist = Math.max(Math.abs(dx), Math.abs(dy));
        m.setFn(x, y, dist !== 2 && dist !== 4);
      }
    }
  }
  const align = VERSIONS[version - 1]!.align;
  const n = align.length;
  for (let i = 0; i < n; i += 1) {
    for (let j = 0; j < n; j += 1) {
      if ((i === 0 && j === 0) || (i === 0 && j === n - 1) || (i === n - 1 && j === 0)) continue;
      for (let dy = -2; dy <= 2; dy += 1) for (let dx = -2; dx <= 2; dx += 1) m.setFn(align[i]! + dx, align[j]! + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
  }
  drawFormat(m, 0);
  if (version >= 7) {
    let rem = version;
    for (let i = 0; i < 12; i += 1) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
    const bits = (version << 12) | rem;
    for (let i = 0; i < 18; i += 1) {
      const bit = ((bits >>> i) & 1) !== 0;
      const a = size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      m.setFn(a, b, bit);
      m.setFn(b, a, bit);
    }
  }
}

/** Formato: correção M (00) + máscara, BCH(15,5) ⊕ 0x5412, nas duas cópias + módulo escuro fixo. */
function drawFormat(m: Matrix, mask: number) {
  const data = (0b00 << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i += 1) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  const bits = ((data << 10) | rem) ^ 0x5412;
  const bit = (i: number) => ((bits >>> i) & 1) !== 0;
  const { size } = m;
  for (let i = 0; i <= 5; i += 1) m.setFn(8, i, bit(i));
  m.setFn(8, 7, bit(6));
  m.setFn(8, 8, bit(7));
  m.setFn(7, 8, bit(8));
  for (let i = 9; i < 15; i += 1) m.setFn(14 - i, 8, bit(i));
  for (let i = 0; i < 8; i += 1) m.setFn(size - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i += 1) m.setFn(8, size - 15 + i, bit(i));
  m.setFn(8, size - 8, true);
}

function drawCodewords(m: Matrix, codewords: readonly number[]) {
  const { size } = m;
  let i = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert += 1) {
      for (let j = 0; j < 2; j += 1) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!m.fn[y]![x] && i < codewords.length * 8) {
          m.dark[y]![x] = ((codewords[i >>> 3]! >>> (7 - (i & 7))) & 1) !== 0;
          i += 1;
        }
      }
    }
  }
}

const MASKS: ReadonlyArray<(x: number, y: number) => boolean> = [
  (x, y) => (x + y) % 2 === 0,
  (_x, y) => y % 2 === 0,
  (x) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

function applyMask(m: Matrix, mask: number) {
  const test = MASKS[mask]!;
  for (let y = 0; y < m.size; y += 1) for (let x = 0; x < m.size; x += 1) if (!m.fn[y]![x] && test(x, y)) m.dark[y]![x] = !m.dark[y]![x];
}

/** Penalidade da norma (N1 sequências, N2 blocos 2×2, N3 padrão de localizador, N4 equilíbrio). */
function penalty(m: Matrix): number {
  const { size, dark } = m;
  let score = 0;
  const lines: boolean[][] = [];
  for (let y = 0; y < size; y += 1) lines.push(dark[y]!);
  for (let x = 0; x < size; x += 1) lines.push(dark.map((row) => row[x]!));
  const finderA = [true, false, true, true, true, false, true, false, false, false, false];
  const finderB = [...finderA].reverse();
  for (const line of lines) {
    let run = 1;
    for (let i = 1; i <= size; i += 1) {
      if (i < size && line[i] === line[i - 1]) run += 1;
      else {
        if (run >= 5) score += 3 + (run - 5);
        run = 1;
      }
    }
    for (let i = 0; i + 11 <= size; i += 1) {
      const slice = line.slice(i, i + 11);
      if (slice.every((v, k) => v === finderA[k]) || slice.every((v, k) => v === finderB[k])) score += 40;
    }
  }
  for (let y = 0; y + 1 < size; y += 1) {
    for (let x = 0; x + 1 < size; x += 1) {
      const c = dark[y]![x];
      if (c === dark[y]![x + 1] && c === dark[y + 1]![x] && c === dark[y + 1]![x + 1]) score += 3;
    }
  }
  const total = size * size;
  const darkCount = dark.reduce((s, row) => s + row.filter(Boolean).length, 0);
  score += Math.floor(Math.abs(darkCount * 20 - total * 10) / total) * 10;
  return score;
}

export type QrMatrix = { size: number; version: number; mask: number; modules: boolean[][] };

/** QR do texto (UTF-8). `null` se não couber nas versões 1–10 (≈ 213 bytes com correção M). */
export function encodeQr(text: string): QrMatrix | null {
  const bytes = [...new TextEncoder().encode(text)];
  let version = 0;
  for (let v = 1; v <= VERSIONS.length; v += 1) {
    const headerBits = 4 + (v < 10 ? 8 : 16);
    if (headerBits + bytes.length * 8 <= dataCapacity(v) * 8) {
      version = v;
      break;
    }
  }
  if (version === 0) return null;
  const codewords = finalCodewords(dataCodewords(bytes, version), version);
  const size = version * 4 + 17;
  let best: { mask: number; modules: boolean[][]; score: number } | null = null;
  for (let mask = 0; mask < 8; mask += 1) {
    const m = new Matrix(size);
    drawFunctionPatterns(m, version);
    drawCodewords(m, codewords);
    applyMask(m, mask);
    drawFormat(m, mask);
    const score = penalty(m);
    if (!best || score < best.score) best = { mask, modules: m.dark.map((row) => [...row]), score };
  }
  return { size, version, mask: best!.mask, modules: best!.modules };
}

/** Caminho SVG (um retângulo por módulo escuro, unidade = módulo), deslocado pela zona de silêncio. */
export function qrSvgPath(qr: QrMatrix, quiet = 4): string {
  let d = "";
  for (let y = 0; y < qr.size; y += 1) {
    for (let x = 0; x < qr.size; x += 1) if (qr.modules[y]![x]) d += `M${x + quiet} ${y + quiet}h1v1h-1z`;
  }
  return d;
}
