/**
 * V1-14 F2-2 (D7 §4q) — "Checklist da Pokédex" e "Espécies faltantes". Núcleo PURO sobre a leitura
 * canônica da grade da Pokédex (5204 `get_my_pokedex_positions`, a mesma da página), lida inteira:
 *
 *  - Universo = o objetivo da própria coleção: a 5204 só devolve espécies das gerações selecionadas
 *    (`collection_pokedex_scope_generation`); nada é filtrado aqui além do que ela devolve. Kanto = 151,
 *    Johto = 100, Kanto + Johto = 251, Nacional = 1.025.
 *  - Unidade = espécie (posição da Pokédex). Atendida = `is_satisfied` do banco; várias cópias contam
 *    uma vez. Espécie ≠ carta ≠ exemplar.
 *  - Faltantes = não atendidas, em três grupos pelo estado do acervo devolvido pela 5204:
 *    `AVAILABLE` (disponível para vincular), `ELSEWHERE` (só em outras coleções), `NOT_FOUND` (sem
 *    exemplar no acervo — NUNCA "não existe carta").
 *  - Conferência: lido = `total_count`, sem repetição, cada espécie numa geração do objetivo, estado
 *    coerente com `is_satisfied`, totais = resumo canônico (5332). Divergência → incompleto com motivo
 *    (impressão bloqueada); nada é estimado.
 */
import { progressPercentText } from "../colecoes/colecoes.ts";
import { type AcervoState, type GenerationOption, type PokedexPosition, generationTitle } from "../colecoes/pokedex.ts";

export const POKEDEX_CHECKLIST_TITLE = "Checklist da Pokédex";
export const POKEDEX_MISSING_TITLE = "Espécies faltantes";
/** Página da 5204 (o teto da função). */
export const POKEDEX_REPORT_PAGE = 500;
/** Teto de leitura: a Pokédex Nacional inteira cabe com folga. */
export const POKEDEX_REPORT_MAX = 2000;

const N = new Intl.NumberFormat("pt-BR");

export type PokedexSpeciesRead =
  | { status: "ok"; positions: PokedexPosition[]; total: number }
  | { status: "incomplete"; positions: PokedexPosition[]; total: number; reason: "pages" | "too_large" }
  | { status: "error" };

export type SpeciesGeneration = {
  code: string;
  ordinal: number;
  name: string;
  region: string | null;
  species: PokedexPosition[];
  satisfied: number;
};

export type MissingGroupKey = "AVAILABLE" | "ELSEWHERE" | "NOT_FOUND";

export type MissingGroup = { key: MissingGroupKey; title: string; hint: string; species: PokedexPosition[] };

export type PokedexReportIncomplete = "read" | "duplicate" | "out_of_scope" | "state_mismatch" | "total_mismatch";

export type PokedexSpeciesReport = {
  /** Totais canônicos (5332) — os indicadores. */
  total: number;
  satisfied: number;
  missing: number;
  percentText: string;
  /** Gerações do objetivo, em ordem, cada uma com as espécies em ordem nacional. */
  generations: SpeciesGeneration[];
  missingGroups: MissingGroup[];
  /** Espécies com mais de uma cópia vinculada (contam uma vez). */
  multiCopySpecies: number;
  complete: boolean;
  incompleteReason: PokedexReportIncomplete | null;
};

export const MISSING_GROUPS: ReadonlyArray<{ key: MissingGroupKey; title: string; hint: string }> = [
  {
    key: "AVAILABLE",
    title: "Disponíveis para vincular",
    hint: "Você tem exemplar livre no acervo — dá para atender sem obter nada novo.",
  },
  {
    key: "ELSEWHERE",
    title: "Em outras coleções",
    hint: "Seus exemplares desta espécie estão alocados a outras coleções — depende de reorganizar o acervo.",
  },
  {
    key: "NOT_FOUND",
    title: "Sem exemplar no acervo",
    hint: "Ainda não há exemplar desta espécie no seu acervo. Não significa que não exista carta da espécie.",
  },
];

/**
 * Junta as páginas da 5204 (já interpretadas por `parsePokedexPositions`), conferindo total estável,
 * páginas cheias até o fim e o conjunto fechado (lido = total).
 */
export function mergePokedexPages(pages: ReadonlyArray<{ items: PokedexPosition[]; total: number } | null>, expectedPages: number): PokedexSpeciesRead {
  const first = pages[0];
  if (!first) return { status: "error" };
  const positions: PokedexPosition[] = [];
  let consistent = pages.length === expectedPages;
  pages.forEach((page, index) => {
    if (!page || (page.items.length > 0 && page.total !== first.total)) {
      consistent = false;
      return;
    }
    if (index < pages.length - 1 && page.items.length !== POKEDEX_REPORT_PAGE) consistent = false;
    positions.push(...page.items);
  });
  if (positions.length !== first.total) consistent = false;
  return consistent ? { status: "ok", positions, total: first.total } : { status: "incomplete", positions, total: first.total, reason: "pages" };
}

export function buildPokedexSpeciesReport(input: {
  read: PokedexSpeciesRead;
  generations: readonly GenerationOption[];
  canonical: { total: number; satisfied: number };
}): PokedexSpeciesReport {
  const { read, canonical } = input;
  const positions = read.status === "error" ? [] : [...read.positions].sort((a, b) => a.number - b.number);
  const selected = new Map(input.generations.filter((g) => g.selected === true).map((g) => [g.code, g]));

  const seen = new Set<string>();
  let duplicate = false;
  let outOfScope = false;
  let stateMismatch = false;
  const byGeneration = new Map<string, PokedexPosition[]>();
  const unique: PokedexPosition[] = [];
  for (const p of positions) {
    if (seen.has(p.positionId)) {
      duplicate = true;
      continue;
    }
    seen.add(p.positionId);
    unique.push(p);
    if (!selected.has(p.generationCode)) outOfScope = true;
    if (p.isSatisfied !== (p.state === "OWNED")) stateMismatch = true;
    const list = byGeneration.get(p.generationCode);
    if (list) list.push(p);
    else byGeneration.set(p.generationCode, [p]);
  }

  const generations: SpeciesGeneration[] = [...byGeneration.entries()]
    .map(([code, species]) => {
      const g = selected.get(code);
      return {
        code,
        ordinal: g?.ordinal ?? Number.MAX_SAFE_INTEGER,
        name: g?.name ?? code,
        region: g?.region ?? null,
        species,
        satisfied: species.filter((s) => s.isSatisfied).length,
      };
    })
    .sort((a, b) => a.ordinal - b.ordinal || (a.species[0]?.number ?? 0) - (b.species[0]?.number ?? 0));

  const missingGroups: MissingGroup[] = MISSING_GROUPS.map((g) => ({
    ...g,
    species: unique.filter((p) => !p.isSatisfied && p.state === g.key),
  }));

  const sumTotal = unique.length;
  const sumSatisfied = unique.filter((p) => p.isSatisfied).length;
  const incompleteReason: PokedexReportIncomplete | null =
    read.status !== "ok"
      ? "read"
      : duplicate
        ? "duplicate"
        : outOfScope
          ? "out_of_scope"
          : stateMismatch
            ? "state_mismatch"
            : sumTotal !== canonical.total || sumSatisfied !== canonical.satisfied
              ? "total_mismatch"
              : null;

  return {
    total: canonical.total,
    satisfied: canonical.satisfied,
    missing: Math.max(0, canonical.total - canonical.satisfied),
    percentText: progressPercentText(canonical.satisfied, canonical.total),
    generations,
    missingGroups,
    multiCopySpecies: unique.filter((p) => p.copiesInCollection > 1).length,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------------------------
// Textos (pt-BR)
// ---------------------------------------------------------------------------------------------

/** "#0025". */
export function nationalNumberText(n: number): string {
  return `#${String(n).padStart(4, "0")}`;
}

export function speciesWord(n: number): string {
  return n === 1 ? "espécie" : "espécies";
}

export function speciesCountText(n: number): string {
  return `${N.format(n)} ${speciesWord(n)}`;
}

/**
 * "Geração I · Kanto" — o mesmo rótulo pt-BR da página Pokédex (`generationTitle`, numeral a partir do
 * código `GENERATION_I`), nunca o nome canônico em inglês do catálogo ("Generation I"); região como vem.
 */
export function generationLabel(g: Pick<SpeciesGeneration, "code" | "region">): string {
  const title = generationTitle(g.code);
  return g.region ? `${title} · ${g.region}` : title;
}

/** Situação curta de uma espécie faltante (a 5204 decide; nunca inferida). */
export function missingStateText(p: Pick<PokedexPosition, "state" | "copiesAvailable" | "copiesElsewhere">): string {
  switch (p.state as AcervoState) {
    case "AVAILABLE":
      return p.copiesAvailable === 1 ? "1 exemplar livre" : `${N.format(p.copiesAvailable)} exemplares livres`;
    case "ELSEWHERE":
      return p.copiesElsewhere === 1 ? "1 exemplar em outra coleção" : `${N.format(p.copiesElsewhere)} exemplares em outras coleções`;
    case "NOT_FOUND":
      return "Sem exemplar no acervo";
    default:
      return "Atendida";
  }
}

export function pokedexReportIncompleteText(reason: PokedexReportIncomplete | null): string | null {
  switch (reason) {
    case null:
      return null;
    case "read":
      return "Relatório incompleto: nem todas as espécies do objetivo puderam ser lidas agora. Tente novamente; nada foi alterado.";
    case "duplicate":
      return "Relatório incompleto: a leitura devolveu uma espécie repetida.";
    case "out_of_scope":
      return "Relatório incompleto: a leitura devolveu espécie fora das gerações do objetivo.";
    case "state_mismatch":
      return "Relatório incompleto: o estado de uma espécie não confere com o atendimento da coleção.";
    case "total_mismatch":
      return "Relatório incompleto: as espécies lidas não conferem com o resumo da coleção.";
  }
}

export const POKEDEX_REPORT_NOTES: readonly string[] = [
  "Objetivo = as gerações escolhidas para esta Pokédex. Mudar as gerações muda este relatório, sem mover nem excluir exemplares.",
  "Espécie atendida = ao menos um exemplar desta coleção vinculado a ela; várias cópias da mesma espécie contam uma vez. Espécies não são cartas nem exemplares físicos.",
  "Percentual arredondado para baixo, como no restante do produto; 100% só com o objetivo completo.",
];
