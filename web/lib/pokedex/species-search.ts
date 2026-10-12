/**
 * Busca rápida da página de detalhes (Pokédex P3b, 2026-10-12).
 *
 * Lógica pura, sem React e sem rede: recebe o índice compacto da Pokédex
 * Nacional (número, nome, caminho da arte) e devolve as sugestões ordenadas.
 * O índice inteiro tem ~1.025 entradas — filtrar no cliente custa menos que
 * uma ida ao servidor por tecla e responde no mesmo quadro.
 *
 * Regras:
 * - Número: "25", "#25", "nº 25", "n 25" → espécie 25 primeiro, depois as que
 *   começam com os mesmos dígitos (250–259...). Com zeros à esquerda ("0025",
 *   "#0006") a intenção é o número exato: só ele volta.
 * - Nome: sem acentos, maiúsculas, espaços ou pontuação ("mr mime" acha
 *   "Mr. Mime", "flabebe" acha "Flabébé"). Ordem: nome exato, começo do nome,
 *   começo de uma palavra, trecho no meio; empate pelo número nacional.
 */

/** Entrada do índice: [número nacional, nome oficial, caminho do WebP 320 ou null]. */
export type SpeciesIndexEntry = readonly [number, string, string | null];

export type SpeciesSuggestion = {
  nationalDexNumber: number;
  name: string;
  artworkPath: string | null;
};

export const QUICK_SEARCH_MAX_RESULTS = 8;
export const QUICK_SEARCH_MAX_QUERY = 40;

const NUMBER_QUERY = /^(?:#|n\s*[º°o.]?\s*)?(\d{1,4})$/i;

/** "Nº 25" / "#0025" / "25" → 25; qualquer outra coisa → null. Zero não é número nacional. */
export function parseNumberQuery(raw: string): number | null {
  const match = NUMBER_QUERY.exec(raw.trim());
  if (!match) return null;
  const value = Number(match[1]);
  return value >= 1 ? value : null;
}

/** Número digitado com zero à esquerda ("0025") = número exato, sem sugestões por prefixo. */
function isExactNumberQuery(raw: string): boolean {
  const match = NUMBER_QUERY.exec(raw.trim());
  const digits = match?.[1] ?? "";
  return digits.length > 1 && digits.startsWith("0");
}

/** Forma comparável de um nome: minúsculas, sem acentos, só letras e dígitos. */
export function normalizeSpeciesName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

/** Palavras do nome, já normalizadas ("Mr. Mime" → ["mr", "mime"]). */
function nameWords(value: string): string[] {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function toSuggestion(entry: SpeciesIndexEntry): SpeciesSuggestion {
  return { nationalDexNumber: entry[0], name: entry[1], artworkPath: entry[2] };
}

export function searchSpecies(
  index: readonly SpeciesIndexEntry[],
  rawQuery: string,
  limit: number = QUICK_SEARCH_MAX_RESULTS,
): SpeciesSuggestion[] {
  const query = rawQuery.trim().slice(0, QUICK_SEARCH_MAX_QUERY);
  if (!query) return [];

  const number = parseNumberQuery(query);
  if (number !== null) {
    const digits = String(number);
    const exactOnly = isExactNumberQuery(query);
    const ranked: Array<{ entry: SpeciesIndexEntry; rank: number }> = [];
    for (const entry of index) {
      if (entry[0] === number) ranked.push({ entry, rank: 0 });
      else if (!exactOnly && String(entry[0]).startsWith(digits)) ranked.push({ entry, rank: 1 });
    }
    ranked.sort((a, b) => a.rank - b.rank || a.entry[0] - b.entry[0]);
    return ranked.slice(0, limit).map((item) => toSuggestion(item.entry));
  }

  const needle = normalizeSpeciesName(query);
  if (!needle) return [];

  const ranked: Array<{ entry: SpeciesIndexEntry; rank: number }> = [];
  for (const entry of index) {
    const name = normalizeSpeciesName(entry[1]);
    let rank = -1;
    if (name === needle) rank = 0;
    else if (name.startsWith(needle)) rank = 1;
    else if (nameWords(entry[1]).some((word) => word.startsWith(needle))) rank = 2;
    else if (name.includes(needle)) rank = 3;
    if (rank >= 0) ranked.push({ entry, rank });
  }
  ranked.sort((a, b) => a.rank - b.rank || a.entry[0] - b.entry[0]);
  return ranked.slice(0, limit).map((item) => toSuggestion(item.entry));
}

/**
 * Valida o corpo devolvido pela rota do índice. Qualquer linha fora do
 * contrato é descartada em vez de quebrar a busca; um corpo inteiro inválido
 * vira `null` (a busca cai no modo "só número").
 */
export function parseSpeciesIndex(body: unknown): SpeciesIndexEntry[] | null {
  if (!body || typeof body !== "object") return null;
  const rows = (body as { species?: unknown }).species;
  if (!Array.isArray(rows)) return null;
  const entries: SpeciesIndexEntry[] = [];
  for (const row of rows) {
    if (!Array.isArray(row) || row.length !== 3) continue;
    const [n, name, path] = row as unknown[];
    if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > 9999) continue;
    if (typeof name !== "string" || name.length === 0 || name.length > 64) continue;
    if (path !== null && typeof path !== "string") continue;
    entries.push([n, name, path as string | null]);
  }
  return entries;
}
