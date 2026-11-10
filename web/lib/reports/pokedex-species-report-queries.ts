import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getPokedexGenerationOptions } from "../colecoes/colecoes-queries.ts";
import { parsePokedexPositions } from "../colecoes/pokedex.ts";
import { issuedAtLabel } from "./collection-checklist.ts";
import {
  POKEDEX_REPORT_MAX,
  POKEDEX_REPORT_PAGE,
  type PokedexSpeciesRead,
  type PokedexSpeciesReport,
  buildPokedexSpeciesReport,
  mergePokedexPages,
} from "./pokedex-species-report.ts";

export type PokedexSpeciesReportData = {
  collection: { id: string; name: string };
  report: PokedexSpeciesReport;
  issuedAt: string;
};

export type PokedexSpeciesPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: PokedexSpeciesReportData };

type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }> };

/** A leitura da grade da página (5204), aqui para todas as espécies do objetivo, sem filtro de geração. */
export const POKEDEX_POSITIONS_RPC = "get_my_pokedex_positions";

/**
 * Lê o objetivo INTEIRO da coleção autorizada pela 5204 (`ALL`, sem geração — a própria função limita às
 * gerações selecionadas), 500 por página: 1ª página dá o total; as demais em sequência (no máximo 2 para
 * a Nacional). Falha na 1ª = erro; falha depois ou conjunto que não fecha = incompleto.
 */
export async function readPokedexSpecies(supabase: AnyRpc, collectionId: string): Promise<PokedexSpeciesRead> {
  const read = async (offset: number) => {
    const res = await supabase.rpc(POKEDEX_POSITIONS_RPC, {
      p_collection_id: collectionId,
      p_filter: "ALL",
      p_generation_code: null,
      p_limit: POKEDEX_REPORT_PAGE,
      p_offset: offset,
    });
    return res.error || !Array.isArray(res.data) ? null : parsePokedexPositions(res.data);
  };
  const first = await read(0);
  if (!first) return { status: "error" };
  if (first.total > POKEDEX_REPORT_MAX) return { status: "incomplete", positions: first.items, total: first.total, reason: "too_large" };
  const expected = Math.max(1, Math.ceil(first.total / POKEDEX_REPORT_PAGE));
  const pages: Array<ReturnType<typeof parsePokedexPositions> | null> = [first];
  for (let page = 1; page < expected; page += 1) pages.push(await read(page * POKEDEX_REPORT_PAGE));
  return mergePokedexPages(pages, expected);
}

/**
 * F2-2 (D7 §4q) — preparação do Checklist da Pokédex e das Espécies faltantes (a mesma leitura serve
 * aos dois): 5332 primeiro (titularidade — alheia/compartilhada/inexistente → `not_found`, sem
 * distinguir —, modalidade Pokédex — senão `unavailable` — e totais canônicos); depois, em paralelo,
 * 5201 (nomes e seleção das gerações) e 5204 inteira. Somente leitura; sem SQL nova.
 */
export async function preparePokedexSpeciesReport(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<PokedexSpeciesPrepared> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  if (collection.completionPolicy !== "REFERENCE_POSITION") return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();

  const [generations, read] = await Promise.all([
    getPokedexGenerationOptions(supabase, authorizedId),
    readPokedexSpecies(supabase as unknown as AnyRpc, authorizedId),
  ]);
  if (generations === null || read.status === "error") {
    console.error("[reports] pokédex falhou", { stage: generations === null ? "generations" : "positions", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const report = buildPokedexSpeciesReport({
    read,
    generations,
    canonical: { total: collection.totalPositions, satisfied: collection.satisfiedPositions },
  });
  console.info("[reports] pokédex", { ms: Date.now() - startedAt, species: report.total, generations: report.generations.length, complete: report.complete });
  if (!report.complete) console.warn("[reports] pokédex incompleta", { reason: report.incompleteReason });
  return {
    status: "ready",
    data: { collection: { id: collection.id, name: collection.name }, report, issuedAt: issuedAtLabel(now) },
  };
}
