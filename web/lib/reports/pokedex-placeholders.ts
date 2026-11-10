/**
 * Placeholders da Pokédex — núcleo PURO do kit de fichário (D7 §4q). Sem banco, sem rede.
 *
 * Base = a MESMA leitura do Checklist e das Espécies faltantes (F2-2): 5332 → 5201 + 5204 inteira, já
 * restrita às gerações do objetivo da coleção (`buildPokedexSpeciesReport`). Nenhum filtro próprio:
 * Kanto = 151, Johto = 100, Kanto + Johto = 251, Nacional = 1.025.
 *
 * Unidade = ESPÉCIE (um placeholder por espécie). Ordem = número nacional, contínua entre gerações —
 * a mesma ordem do Fichário digital da Pokédex. Folhas de 3 × 3 = 9 placeholders de 63 × 88 mm (o
 * tamanho da carta): a folha N corresponde à página N de um fichário de 9 bolsos.
 */
import { generationNumeral } from "../colecoes/pokedex.ts";
import type { PokedexPosition } from "../colecoes/pokedex.ts";
import type { PokedexSpeciesReport } from "./pokedex-species-report.ts";

export const POKEDEX_PLACEHOLDERS_TITLE = "Placeholders da Pokédex";
/** Tamanho da carta (mm) — o placeholder ocupa o bolso como uma carta. */
export const PLACEHOLDER_MM = { width: 63, height: 88 } as const;
export const PLACEHOLDER_COLUMNS = 3;
export const PLACEHOLDER_ROWS = 3;
export const PLACEHOLDERS_PER_SHEET = PLACEHOLDER_COLUMNS * PLACEHOLDER_ROWS;
/** Folha A4 (mm) e a grade centralizada nela. */
export const SHEET_MM = { width: 210, height: 297 } as const;
export const GRID_MM = {
  left: (SHEET_MM.width - PLACEHOLDER_COLUMNS * PLACEHOLDER_MM.width) / 2,
  top: (SHEET_MM.height - PLACEHOLDER_ROWS * PLACEHOLDER_MM.height) / 2,
  width: PLACEHOLDER_COLUMNS * PLACEHOLDER_MM.width,
  height: PLACEHOLDER_ROWS * PLACEHOLDER_MM.height,
} as const;

export type Placeholder = {
  positionId: string;
  number: number;
  name: string;
  generationCode: string;
  /** "I", "II"… (secundário no placeholder). */
  generation: string;
  artworkPath: string | null;
};

export type PlaceholderSheet = {
  /** 1, 2, 3… = página do fichário de 9 bolsos. */
  index: number;
  first: number;
  last: number;
  items: Placeholder[];
};

export type PlaceholderKit = {
  sheets: PlaceholderSheet[];
  species: number;
  /** "Geração I · Kanto", "Gerações I e II", "Gerações I a IX". */
  scope: string;
  /** Gerações do objetivo, em ordem (código, numeral, região). */
  generations: { code: string; numeral: string; region: string | null; species: number }[];
};

function toPlaceholder(p: PokedexPosition): Placeholder {
  return {
    positionId: p.positionId,
    number: p.number,
    name: p.speciesName,
    generationCode: p.generationCode,
    generation: generationNumeral(p.generationCode),
    artworkPath: p.artworkPath,
  };
}

/** Rótulo do objetivo a partir das gerações do próprio relatório (já em ordem). */
export function placeholderScopeText(generations: readonly { code: string; ordinal: number; region: string | null }[]): string {
  if (generations.length === 0) return "Nenhuma geração";
  const numerals = generations.map((g) => generationNumeral(g.code));
  if (generations.length === 1) {
    const g = generations[0]!;
    return g.region ? `Geração ${numerals[0]} · ${g.region}` : `Geração ${numerals[0]}`;
  }
  const ordinals = generations.map((g) => g.ordinal);
  const contiguous = ordinals.every((o, i) => i === 0 || o === ordinals[i - 1]! + 1);
  if (contiguous && generations.length > 2) return `Gerações ${numerals[0]} a ${numerals[numerals.length - 1]}`;
  return `Gerações ${numerals.slice(0, -1).join(", ")} e ${numerals[numerals.length - 1]}`;
}

/** Espécies do objetivo (uma vez cada) em ordem nacional, em folhas de 9. */
export function buildPlaceholderKit(report: Pick<PokedexSpeciesReport, "generations">): PlaceholderKit {
  const seen = new Set<string>();
  const all: Placeholder[] = [];
  for (const g of report.generations) {
    for (const p of g.species) {
      if (seen.has(p.positionId)) continue;
      seen.add(p.positionId);
      all.push(toPlaceholder(p));
    }
  }
  all.sort((a, b) => a.number - b.number || (a.positionId < b.positionId ? -1 : 1));
  const sheets: PlaceholderSheet[] = [];
  for (let i = 0; i < all.length; i += PLACEHOLDERS_PER_SHEET) {
    const items = all.slice(i, i + PLACEHOLDERS_PER_SHEET);
    sheets.push({ index: sheets.length + 1, first: items[0]!.number, last: items[items.length - 1]!.number, items });
  }
  return {
    sheets,
    species: all.length,
    scope: placeholderScopeText(report.generations),
    generations: report.generations.map((g) => ({ code: g.code, numeral: generationNumeral(g.code), region: g.region, species: g.species.length })),
  };
}

/** "#0025". */
export function placeholderNumber(n: number): string {
  return `#${String(n).padStart(4, "0")}`;
}

/** Faixa de nomes: longos ganham corpo menor para caber numa linha do placeholder. */
export function placeholderNameSize(name: string): "regular" | "long" | "xlong" {
  const n = [...name].length;
  return n > 13 ? "xlong" : n > 10 ? "long" : "regular";
}

const N = new Intl.NumberFormat("pt-BR");

export function sheetCountText(n: number): string {
  return n === 1 ? "1 folha" : `${N.format(n)} folhas`;
}

export function speciesCountLabel(n: number): string {
  return n === 1 ? "1 espécie" : `${N.format(n)} espécies`;
}

/** "Folha 3 de 17 · #0019–#0027". */
export function sheetHeaderText(sheet: PlaceholderSheet, total: number): string {
  const range = sheet.first === sheet.last ? placeholderNumber(sheet.first) : `${placeholderNumber(sheet.first)}–${placeholderNumber(sheet.last)}`;
  return `Folha ${N.format(sheet.index)} de ${N.format(total)} · ${range}`;
}

/**
 * Endereço PÚBLICO do MMKYU Collector na página de orientações (texto + QR Code, `qr-code.ts`).
 * PROVISÓRIO, aprovado pelo proprietário em 2026-11-09 (`PUBLIC URL & QR ACTIVATION-01`, D7 §4q) —
 * não é o domínio definitivo. Exatamente este valor vai no QR (sem parâmetros). `null` = a página
 * mostra só a marca, sem URL nem QR.
 */
export const MMKYU_PUBLIC_URL: string | null = "https://mmkyu.vercel.app/";

/** Espécies do leque da capa: os iniciais de Kanto (#0001, #0004, #0007), decisão do proprietário. */
export const COVER_FAN_NUMBERS: readonly number[] = [1, 4, 7];

/**
 * Leque da capa: as espécies de `COVER_FAN_NUMBERS` presentes no kit, na ordem; objetivo sem elas
 * (ex.: só Johto) → completa com as primeiras espécies do próprio kit. No máximo três.
 */
export function coverFanItems(kit: Pick<PlaceholderKit, "sheets">): Placeholder[] {
  const all = kit.sheets.flatMap((s) => s.items);
  const byNumber = new Map(all.map((p) => [p.number, p]));
  const picked = COVER_FAN_NUMBERS.map((n) => byNumber.get(n)).filter((p): p is Placeholder => p !== undefined);
  for (const p of all) {
    if (picked.length >= COVER_FAN_NUMBERS.length) break;
    if (!picked.includes(p)) picked.push(p);
  }
  return picked.slice(0, COVER_FAN_NUMBERS.length);
}

/** Capa + orientações antes da Folha 1. */
export const OPENING_PAGES = 2;

/** Página do PDF em que está a folha N (a Folha 1 é a página 3). */
export function pdfPageOfSheet(sheet: number): number {
  return sheet + OPENING_PAGES;
}

/** Total de páginas do PDF: capa + orientações + folhas (Nacional: 2 + 114 = 116). */
export function kitPageCount(kit: Pick<PlaceholderKit, "sheets">): number {
  return OPENING_PAGES + kit.sheets.length;
}

/** Exemplo de intervalo para imprimir só as primeiras folhas ("3–5" = Folhas 1 a 3). */
export function printRangeExample(kit: Pick<PlaceholderKit, "sheets">): { pages: string; sheets: string } | null {
  const n = Math.min(3, kit.sheets.length);
  if (n === 0) return null;
  if (n === 1) return { pages: String(pdfPageOfSheet(1)), sheets: "a Folha 1" };
  return { pages: `${pdfPageOfSheet(1)}–${pdfPageOfSheet(n)}`, sheets: n === 2 ? "as Folhas 1 e 2" : `as Folhas 1 a ${n}` };
}

/** Texto curto do endereço ("mmkyu.app/colecoes"), sem protocolo nem barra final. */
export function displayUrl(url: string): string {
  return url.replace(/^https?:\/\//, "").replace(/^www\./, "").replace(/\/$/, "");
}

/** Host público do produto para a assinatura (nunca localhost). */
export function brandHost(siteUrl: string | undefined | null): string | null {
  if (!siteUrl) return null;
  try {
    const host = new URL(siteUrl).host.replace(/^www\./, "");
    return /^(localhost|127\.|\[::1\])/.test(host) ? null : host;
  } catch {
    return null;
  }
}
