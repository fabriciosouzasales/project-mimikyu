/**
 * Coleção "Completar a Pokédex" — regras puras de apresentação, URL, leitura
 * dos contratos e tradução de erros (POKEDEX-PKX-02-FRONTEND-IMPLEMENTATION-01).
 *
 * Sem React, sem Supabase, sem rede: testável com
 * `node --experimental-strip-types --test lib/colecoes/pokedex.test.ts`.
 *
 * Contratos (LIVE e canônicos, PKX-01):
 * - 5201 `get_my_pokedex_generation_options(p_collection_id)` — gerações catalogadas;
 * - 5202 `create_my_pokedex_collection(...)` — criação idempotente, escopo explícito;
 * - 5203 `set_my_pokedex_generations(...)` — Ajustes, devolve o progresso do banco;
 * - 5204 `get_my_pokedex_positions(...)` — grade paginada com estado no acervo.
 *
 * Nenhuma completude é calculada aqui: o progresso vem de
 * `collection_completion_summary` (R1/5203) e das contagens por geração da 5201.
 * A única soma local é a PRÉVIA de Ajustes, rotulada como prévia — o valor
 * gravado é sempre o que a 5203 devolve.
 */

// ---------------------------------------------------------------------------
// Liberação
// ---------------------------------------------------------------------------

/**
 * Publicado (autorização do proprietário, 2026-10-19): criação, Ajustes de
 * gerações, vínculo de cartas (PKX-03) e capa/código do fichário ligados em
 * produção. Contratos 5201–5211 e 5206/5207 no LIVE e homologados.
 */
export const POKEDEX_COLLECTION_RELEASED: boolean = true;

/**
 * Homologação local (mesmo padrão do Master Set): só com `next dev`
 * (NODE_ENV = development) E `NEXT_PUBLIC_POKEDEX_LOCAL_HOMOLOGATION=1` no
 * `.env.local`. Qualquer build de produção ignora a variável.
 */
export const POKEDEX_LOCAL_HOMOLOGATION: boolean =
  process.env.NODE_ENV === "development" && process.env.NEXT_PUBLIC_POKEDEX_LOCAL_HOMOLOGATION === "1";

export const POKEDEX_COLLECTION_ENABLED: boolean = POKEDEX_COLLECTION_RELEASED || POKEDEX_LOCAL_HOMOLOGATION;

/** Identidade física da coleção Pokédex (Fatia B): nunca exibida ao usuário. */
export const POKEDEX_POLICY = "REFERENCE_POSITION";

export function isPokedexCollection(summary: { completionPolicy: string | null }): boolean {
  return summary.completionPolicy === POKEDEX_POLICY;
}

/** Posições por leitura da grade (5204 aceita 1..500). */
export const POKEDEX_PAGE_SIZE = 120;

/**
 * Busca/salto (UX-04): com uma geração escolhida a grade vem inteira numa
 * página (a maior geração tem 156 Pokémon) — o salto para um número cai sempre
 * numa posição já carregada, sem "Mostrar mais". Dentro do teto da 5204 (500).
 */
export const POKEDEX_GENERATION_PAGE_SIZE = 200;

export function pokedexPageSize(generation: string | null): number {
  return generation ? POKEDEX_GENERATION_PAGE_SIZE : POKEDEX_PAGE_SIZE;
}
/** Teto do contrato para a lista de gerações (5202/5203). */
export const MAX_GENERATIONS = 64;
/** Nome sugerido na criação — editável, nunca identidade. */
export const SUGGESTED_POKEDEX_NAME = "Minha Pokédex";

// ---------------------------------------------------------------------------
// 5201 — gerações
// ---------------------------------------------------------------------------

export type GenerationOption = {
  code: string;
  ordinal: number;
  name: string;
  region: string | null;
  speciesCount: number;
  firstNumber: number;
  lastNumber: number;
  /** `null` sem coleção (criação). */
  selected: boolean | null;
  /** Conquistadas nesta geração (só com coleção). */
  satisfied: number | null;
};

function toNumber(value: unknown): number {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) ? n : 0;
}

/** Linhas da 5201 → opções, na ordem das gerações. Linhas sem código são descartadas. */
export function parseGenerationOptions(rows: unknown): GenerationOption[] {
  if (!Array.isArray(rows)) return [];
  const out: GenerationOption[] = [];
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    if (!row || typeof row.generation_code !== "string" || row.generation_code === "") continue;
    out.push({
      code: row.generation_code,
      ordinal: toNumber(row.generation_ordinal),
      name: typeof row.generation_name === "string" ? row.generation_name : row.generation_code,
      region: typeof row.region_name === "string" && row.region_name !== "" ? row.region_name : null,
      speciesCount: toNumber(row.species_count),
      firstNumber: toNumber(row.first_number),
      lastNumber: toNumber(row.last_number),
      selected: typeof row.is_selected === "boolean" ? row.is_selected : null,
      satisfied: row.satisfied_count === null || row.satisfied_count === undefined ? null : toNumber(row.satisfied_count),
    });
  }
  return out.sort((a, b) => a.ordinal - b.ordinal || a.code.localeCompare(b.code));
}

/** "I", "II"… a partir do código (`GENERATION_IV` → "IV"); outro formato fica como veio. */
export function generationNumeral(code: string): string {
  return code.startsWith("GENERATION_") ? code.slice("GENERATION_".length) : code;
}

/** "Geração I". */
export function generationTitle(code: string): string {
  return `Geração ${generationNumeral(code)}`;
}

/** Uma linha por geração: "Geração I - Kanto: 151 Pokémon" (sem região: "Geração I: 151 Pokémon"). "Pokémon" é invariável. */
export function generationLine(option: Pick<GenerationOption, "code" | "region" | "speciesCount">): string {
  const count = new Intl.NumberFormat("pt-BR").format(option.speciesCount);
  const region = option.region ? ` - ${option.region}` : "";
  return `${generationTitle(option.code)}${region}: ${count} Pokémon`;
}

/** "#0001 - #0151". */
export function generationRange(option: Pick<GenerationOption, "firstNumber" | "lastNumber">): string {
  return `#${formatDex(option.firstNumber)} - #${formatDex(option.lastNumber)}`;
}

export function formatDex(value: number): string {
  return String(Math.max(0, Math.trunc(value))).padStart(4, "0");
}

/** Códigos marcados por padrão na criação: todas as gerações catalogadas (decisão do proprietário). */
export function defaultSelection(options: readonly GenerationOption[]): string[] {
  return options.map((option) => option.code);
}

/** Seleção atual de uma coleção (5201 com coleção). */
export function currentSelection(options: readonly GenerationOption[]): string[] {
  return options.filter((option) => option.selected === true).map((option) => option.code);
}

/** Liga/desliga uma geração, mantendo a ordem das opções e ignorando códigos desconhecidos. */
export function toggleGeneration(selection: readonly string[], code: string, options: readonly GenerationOption[]): string[] {
  const set = new Set(selection);
  if (set.has(code)) set.delete(code);
  else set.add(code);
  return options.filter((option) => set.has(option.code)).map((option) => option.code);
}

/** Espécies contempladas pelas gerações escolhidas (catálogo da 5201). */
export function speciesInSelection(selection: readonly string[], options: readonly GenerationOption[]): number {
  const set = new Set(selection);
  return options.reduce((sum, option) => (set.has(option.code) ? sum + option.speciesCount : sum), 0);
}

/** Lista pronta para envio: só códigos conhecidos, sem repetição, na ordem; `null` se vazia ou acima do teto. */
export function normalizeSelection(selection: readonly string[], options: readonly GenerationOption[]): string[] | null {
  const set = new Set(selection);
  const codes = options.filter((option) => set.has(option.code)).map((option) => option.code);
  if (codes.length === 0 || codes.length > MAX_GENERATIONS) return null;
  return codes;
}

/** Mesma lista (ordem não importa). */
export function sameSelection(a: readonly string[], b: readonly string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a);
  return b.every((code) => set.has(code));
}

/** "Todas as gerações (I–IX)", "Gerações I, III e V", "Geração I". */
export function selectionLabel(selection: readonly string[], options: readonly GenerationOption[]): string {
  const set = new Set(selection);
  const chosen = options.filter((option) => set.has(option.code));
  if (chosen.length === 0) return "Nenhuma geração";
  const numerals = chosen.map((option) => generationNumeral(option.code));
  if (chosen.length === options.length && options.length > 1) {
    return `Todas as gerações (${numerals[0]}–${numerals[numerals.length - 1]})`;
  }
  if (numerals.length === 1) return `Geração ${numerals[0]}`;
  return `Gerações ${numerals.slice(0, -1).join(", ")} e ${numerals[numerals.length - 1]}`;
}

// ---------------------------------------------------------------------------
// Ajustes — plano e prévia da mudança de gerações (5203)
// ---------------------------------------------------------------------------

export type GenerationPlan =
  | { kind: "none" }
  | { kind: "invalid" }
  | {
      kind: "change";
      codes: string[];
      added: GenerationOption[];
      removed: GenerationOption[];
      /** Prévia a partir da 5201: o valor gravado é o que a 5203 devolver. */
      preview: { currentTotal: number; currentSatisfied: number; nextTotal: number; nextSatisfied: number };
    };

export function planGenerationChange(options: readonly GenerationOption[], target: readonly string[]): GenerationPlan {
  const codes = normalizeSelection(target, options);
  if (codes === null) return { kind: "invalid" };
  const current = currentSelection(options);
  if (sameSelection(current, codes)) return { kind: "none" };
  const now = new Set(current);
  const next = new Set(codes);
  const sum = (set: Set<string>, pick: (option: GenerationOption) => number) =>
    options.reduce((total, option) => (set.has(option.code) ? total + pick(option) : total), 0);
  return {
    kind: "change",
    codes,
    added: options.filter((option) => next.has(option.code) && !now.has(option.code)),
    removed: options.filter((option) => now.has(option.code) && !next.has(option.code)),
    preview: {
      currentTotal: sum(now, (option) => option.speciesCount),
      currentSatisfied: sum(now, (option) => option.satisfied ?? 0),
      nextTotal: sum(next, (option) => option.speciesCount),
      nextSatisfied: sum(next, (option) => option.satisfied ?? 0),
    },
  };
}

// ---------------------------------------------------------------------------
// URL da página da coleção
// ---------------------------------------------------------------------------

export const GENERATION_PARAM = "geracao";

type Params = Record<string, string | string[] | undefined>;

/** `?geracao=GENERATION_IV`; qualquer outro formato vira "todas". */
export function parseGenerationFilter(params: Params): string | null {
  const raw = Array.isArray(params[GENERATION_PARAM]) ? params[GENERATION_PARAM][0] : params[GENERATION_PARAM];
  return typeof raw === "string" && /^[A-Z0-9_]{1,40}$/.test(raw) ? raw : null;
}

export type PokedexFilter = "todas" | "tenho" | "faltam";

/** Número nacional em destaque na grade depois de uma busca (UX-04). */
export const JUMP_PARAM = "n";

export function parseJumpNumber(params: Params): number | null {
  const raw = Array.isArray(params[JUMP_PARAM]) ? params[JUMP_PARAM][0] : params[JUMP_PARAM];
  if (typeof raw !== "string" || !/^\d{1,4}$/.test(raw)) return null;
  const value = Number(raw);
  return value >= 1 && value <= 9999 ? value : null;
}

/**
 * Para onde a busca leva um número nacional: a geração (escolhida nesta
 * Pokédex) que o contém, sempre em "Todas" — o Pokémon aparece, conquistado ou
 * não. Fora das gerações escolhidas → "outside" (a interface explica, não navega).
 */
export type PokedexJumpPlan = { kind: "go"; generation: string } | { kind: "outside" };

export function planPokedexJump(
  options: readonly Pick<GenerationOption, "code" | "firstNumber" | "lastNumber" | "selected">[],
  number: number,
): PokedexJumpPlan {
  const hit = options.find((option) => option.selected === true && number >= option.firstNumber && number <= option.lastNumber);
  return hit ? { kind: "go", generation: hit.code } : { kind: "outside" };
}

export function pokedexHref(
  collectionId: string,
  filter: PokedexFilter,
  generation: string | null,
  focusNumber: number | null = null,
): string {
  const params = new URLSearchParams();
  if (filter !== "todas") params.set("ver", filter);
  if (generation) params.set(GENERATION_PARAM, generation);
  if (focusNumber !== null && Number.isInteger(focusNumber) && focusNumber > 0) params.set(JUMP_PARAM, String(focusNumber));
  const query = params.toString();
  return `/colecoes/colecoes/${collectionId}${query ? `?${query}` : ""}`;
}

export function toPokedexRpcFilter(filter: PokedexFilter): "ALL" | "OWNED" | "MISSING" {
  if (filter === "tenho") return "OWNED";
  if (filter === "faltam") return "MISSING";
  return "ALL";
}

// ---------------------------------------------------------------------------
// 5204 — posições
// ---------------------------------------------------------------------------

export type AcervoState = "OWNED" | "AVAILABLE" | "ELSEWHERE" | "NOT_FOUND";

export type PokedexPosition = {
  positionId: string;
  number: number;
  speciesId: string;
  speciesName: string;
  generationCode: string;
  artworkPath: string | null;
  isSatisfied: boolean;
  copiesInCollection: number;
  copiesAvailable: number;
  copiesElsewhere: number;
  state: AcervoState;
  representative: { cardName: string; collectorNumber: string | null; setCode: string | null; imagePath: string | null } | null;
};

export type PokedexPositionsPage = { items: PokedexPosition[]; total: number };

const STATES: readonly AcervoState[] = ["OWNED", "AVAILABLE", "ELSEWHERE", "NOT_FOUND"];

function text(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

/** Linhas da 5204 → página. Linha sem id ou com estado desconhecido é descartada (nunca inventa estado). */
export function parsePokedexPositions(rows: unknown): PokedexPositionsPage {
  if (!Array.isArray(rows)) return { items: [], total: 0 };
  const items: PokedexPosition[] = [];
  let total = 0;
  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    if (!row) continue;
    total = Math.max(total, toNumber(row.total_count));
    const id = text(row.pokedex_position_id);
    const state = row.acervo_state as AcervoState;
    if (!id || !STATES.includes(state)) continue;
    const cardName = text(row.representative_card_name);
    items.push({
      positionId: id,
      number: toNumber(row.position_number),
      speciesId: text(row.species_id) ?? id,
      speciesName: text(row.species_name) ?? "",
      generationCode: text(row.generation_code) ?? "",
      artworkPath: text(row.species_artwork_path),
      isSatisfied: row.is_satisfied === true,
      copiesInCollection: toNumber(row.copies_in_collection),
      copiesAvailable: toNumber(row.copies_available),
      copiesElsewhere: toNumber(row.copies_elsewhere),
      state,
      representative: cardName
        ? {
            cardName,
            collectorNumber: text(row.representative_collector_number),
            setCode: text(row.representative_set_code),
            imagePath: text(row.representative_image_path),
          }
        : null,
    });
  }
  return { items, total };
}

/** Texto curto da etiqueta, em linguagem de colecionador. */
export function stateTag(state: AcervoState): string {
  switch (state) {
    case "OWNED":
      return "Conquistado";
    case "AVAILABLE":
      return "No seu acervo";
    case "ELSEWHERE":
      return "Em outra coleção";
    default:
      return "Falta";
  }
}

/** Frase completa para leitor de tela e dica. */
export function stateDescription(position: Pick<PokedexPosition, "state" | "copiesAvailable" | "copiesElsewhere" | "copiesInCollection">): string {
  switch (position.state) {
    case "OWNED":
      return position.copiesInCollection > 1
        ? `conquistado, ${position.copiesInCollection} cartas deste Pokémon na coleção`
        : "conquistado";
    case "AVAILABLE":
      return position.copiesAvailable === 1
        ? "falta na coleção, mas você tem 1 carta deste Pokémon livre no acervo"
        : `falta na coleção, mas você tem ${position.copiesAvailable} cartas deste Pokémon livres no acervo`;
    case "ELSEWHERE":
      return position.copiesElsewhere === 1
        ? "falta na coleção; você tem 1 carta deste Pokémon em outra coleção"
        : `falta na coleção; você tem ${position.copiesElsewhere} cartas deste Pokémon em outras coleções`;
    default:
      return "falta — nenhuma carta deste Pokémon no acervo";
  }
}

/** Próximo deslocamento para "Mostrar mais", ou `null` quando acabou. */
export function nextOffset(loaded: number, total: number): number | null {
  return loaded < total ? loaded : null;
}

/** Junta páginas sem repetir posição (uma releitura concorrente nunca duplica um card). */
export function appendPositions(current: readonly PokedexPosition[], more: readonly PokedexPosition[]): PokedexPosition[] {
  const seen = new Set(current.map((item) => item.positionId));
  return [...current, ...more.filter((item) => !seen.has(item.positionId))];
}

// ---------------------------------------------------------------------------
// Erros (5201–5204)
// ---------------------------------------------------------------------------

export type PokedexFailure =
  | "not_authenticated"
  | "generation_unavailable"
  | "pokedex_unavailable"
  | "storage_required"
  | "storage_invalid"
  | "conflict"
  | "not_found"
  | "archived"
  | "invalid"
  | "disabled"
  | "unavailable";

/** Pelo SQLSTATE e pela mensagem estável dos contratos — o texto cru nunca chega ao usuário. */
export function classifyPokedexFailure(code: string | null | undefined, message: string | null | undefined): PokedexFailure {
  const textValue = message ?? "";
  if (code === "28000" || code === "42501" || textValue === "not_authenticated") return "not_authenticated";
  if (textValue === "GENERATION_NOT_AVAILABLE") return "generation_unavailable";
  if (textValue === "POKEDEX_NOT_AVAILABLE") return "pokedex_unavailable";
  if (textValue === "STORAGE_CONTAINER_REQUIRED") return "storage_required";
  if (textValue === "STORAGE_CONTAINER_INVALID") return "storage_invalid";
  if (textValue === "IDEMPOTENCY_KEY_REUSED") return "conflict";
  if (textValue === "COLLECTION_NOT_FOUND" || code === "P0002") return "not_found";
  if (textValue === "COLLECTION_ARCHIVED") return "archived";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unavailable";
}

export function pokedexFailureMessage(reason: PokedexFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "generation_unavailable":
      return "Uma das gerações escolhidas não está mais disponível. A lista foi atualizada — revise e tente de novo.";
    case "pokedex_unavailable":
      return "A Pokédex Nacional está indisponível no momento. Nada foi alterado — tente mais tarde.";
    case "storage_required":
      return "Escolha onde esta coleção fica guardada para continuar.";
    case "storage_invalid":
      return "Esse local não está mais disponível. Escolha outro.";
    case "conflict":
      return "Este envio já foi usado para outro pedido. Revise e tente de novo.";
    case "not_found":
      return "Esta coleção não está disponível.";
    case "archived":
      return "Esta coleção está arquivada e não aceita mudanças. Nada foi alterado.";
    case "invalid":
      return "Algo no pedido não está certo. Revise e tente de novo.";
    case "disabled":
      return "Este recurso ainda não está disponível.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente em instantes.";
  }
}
