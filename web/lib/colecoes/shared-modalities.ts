import { type MasterSetPositionsPage, MASTER_SET_PAGE_SIZE, parseMasterSetPositions } from "./master-set.ts";
import { type PokedexPosition, type PokedexPositionsPage, POKEDEX_PAGE_SIZE } from "./pokedex.ts";

/**
 * V1-13 · E3-6 — Master Set (5323) e Pokédex (5324) vistos pelo participante
 * (EDITOR e VIEWER). Regras puras, sem rede.
 *
 * Contratos conferidos nas versões protegidas implantadas:
 *  - 5323 `get_shared_master_set_positions(p_collection_id, p_filter ALL|OWNED|MISSING,
 *    p_limit 1..500, p_offset 0..100000)` → card_id, collector_number,
 *    collector_total, card_name, variant_type_id/code/name, is_secret,
 *    image_path, is_satisfied, copies_in_collection, total_count. SEM
 *    copies_available (acervo do titular nunca lido, C-243).
 *  - 5324 `get_shared_pokedex_positions(p_collection_id, p_filter, p_generation_code,
 *    p_limit 1..500, p_offset)` → pokedex_position_id, position_number,
 *    species_id/name, generation_code/ordinal, species_artwork_path,
 *    is_satisfied, copies_in_collection, representative_card_name /
 *    collector_number / set_code / image_path, total_count. SEM
 *    copies_available, copies_elsewhere e acervo_state; sem id de exemplar.
 *  - Sem acesso, barreira fechada ou modalidade diferente → ZERO linhas, sem
 *    erro. Por isso zero linhas nunca é tratado, sozinho, como coleção vazia.
 *
 * Privacidade da apresentação: a quantidade de exemplares (`copies_in_collection`)
 * não é exibida ao participante nestas grades; nada do acervo do titular existe
 * aqui para ser mostrado.
 */

export type SharedModalityFilter = "todas" | "tenho" | "faltam";

export function sharedModalitySqlFilter(filter: SharedModalityFilter): "ALL" | "OWNED" | "MISSING" {
  return filter === "tenho" ? "OWNED" : filter === "faltam" ? "MISSING" : "ALL";
}

export const SHARED_MASTER_SET_PAGE_SIZE = MASTER_SET_PAGE_SIZE;
export const SHARED_POKEDEX_PAGE_SIZE = POKEDEX_PAGE_SIZE;

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function nonNegInt(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 5323 → página da grade. Formato que não é lista → `null` (falha de
 * leitura). Linhas sem identidade são descartadas pelo parser do titular; o
 * acervo do titular fica zerado de propósito (`copiesAvailable = 0`: a 5323
 * não o devolve e a grade nunca mostra "No seu acervo" ao participante).
 */
export function parseSharedMasterSetPositions(data: unknown): MasterSetPositionsPage | null {
  if (data === null || data === undefined) return { items: [], total: 0 };
  if (!Array.isArray(data)) return null;
  const rows = data.map((r) => {
    const o = obj(r) ?? {};
    // Só os campos do contrato chegam ao parser do titular (nada de copies_available, mesmo que viesse).
    return {
      card_id: o.card_id,
      collector_number: o.collector_number,
      collector_total: o.collector_total,
      card_name: o.card_name,
      variant_type_id: o.variant_type_id,
      variant_type_name: o.variant_type_name,
      is_secret: o.is_secret,
      image_path: o.image_path,
      is_satisfied: o.is_satisfied,
      copies_in_collection: o.copies_in_collection,
      total_count: o.total_count,
    };
  });
  const page = parseMasterSetPositions(rows);
  return { items: page.items.map((p) => ({ ...p, copiesAvailable: 0 })), total: page.total };
}

/**
 * 5324 → página da grade. Estado só da coleção: conquistada (`OWNED`) ou
 * falta (`NOT_FOUND`) — "no seu acervo" e "em outra coleção" não existem
 * para o participante. A representante só aparece em posição conquistada e
 * com nome; sem ela, a arte da espécie (nada é inventado).
 */
export function parseSharedPokedexPositions(data: unknown): PokedexPositionsPage | null {
  if (data === null || data === undefined) return { items: [], total: 0 };
  if (!Array.isArray(data)) return null;
  const items: PokedexPosition[] = [];
  let total = 0;
  for (const raw of data) {
    const r = obj(raw);
    if (!r) continue;
    total = Math.max(total, nonNegInt(r.total_count) ?? 0);
    const id = text(r.pokedex_position_id);
    const number = nonNegInt(r.position_number);
    if (!id || !UUID_RE.test(id) || number === null || number < 1) continue;
    const satisfied = r.is_satisfied === true;
    const repName = satisfied ? text(r.representative_card_name) : null;
    items.push({
      positionId: id.toLowerCase(),
      number,
      speciesId: text(r.species_id) ?? id,
      speciesName: text(r.species_name) ?? "",
      generationCode: text(r.generation_code) ?? "",
      artworkPath: text(r.species_artwork_path),
      isSatisfied: satisfied,
      copiesInCollection: nonNegInt(r.copies_in_collection) ?? 0,
      copiesAvailable: 0,
      copiesElsewhere: 0,
      state: satisfied ? "OWNED" : "NOT_FOUND",
      representative: repName
        ? {
            cardName: repName,
            collectorNumber: text(r.representative_collector_number),
            setCode: text(r.representative_set_code),
            imagePath: text(r.representative_image_path),
          }
        : null,
    });
  }
  return { items, total: Math.max(total, items.length) };
}

/** Rótulo acessível do participante: só o estado na coleção, sem quantidade. */
export function sharedPokedexDescription(position: Pick<PokedexPosition, "isSatisfied">): string {
  return position.isSatisfied ? "capturado" : "falta na coleção";
}

/**
 * Zero linhas: vazio de verdade ou leitura indisponível (barreira, papel,
 * modalidade)? Só o progresso da coleção (5310, já na página) decide, sem
 * consulta nova: se ele diz que deveria haver posições nesta página, a
 * leitura é tratada como INDISPONÍVEL (a página volta à galeria de sempre).
 * Progresso desconhecido → indisponível (nunca afirma vazio sem prova).
 */
export function sharedModalityRead(
  rows: number,
  filter: SharedModalityFilter,
  offset: number,
  progress: { satisfied: number; total: number } | null,
): "ok" | "unavailable" {
  if (rows > 0) return "ok";
  if (!progress || progress.total <= 0) return "unavailable";
  const expected = filter === "tenho" ? progress.satisfied : filter === "faltam" ? Math.max(0, progress.total - progress.satisfied) : progress.total;
  return Math.max(0, expected - offset) > 0 ? "unavailable" : "ok";
}

export function parseSharedModalityFilter(raw: string | string[] | undefined): SharedModalityFilter {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return v === "tenho" || v === "faltam" ? v : "todas";
}

/** Link da grade do participante: `?ver=` e `?pagina=` (só o que não for padrão). */
export function sharedModalityHref(base: string, filter: SharedModalityFilter, page = 1): string {
  const params: string[] = [];
  if (filter !== "todas") params.push(`ver=${filter}`);
  if (page > 1) params.push(`pagina=${page}`);
  return params.length ? `${base}?${params.join("&")}` : base;
}

export function validSharedOffset(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 100_000;
}
