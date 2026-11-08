import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "@/lib/colecoes/colecoes-queries";
import { getChecklist } from "./checklist-queries";
import { type ChecklistKind, checklistKindOf, issuedAtLabel } from "./collection-checklist";
import { readRarityCatalog } from "./distribution-queries";
import {
  type CardRarityRead,
  RARITY_MAX_PAGES,
  RARITY_PAGE_SIZE,
  type RarityDistributionReport,
  type RarityPage,
  buildRarityDistribution,
  mergeRarityPages,
  parseRarityPage,
} from "./rarity-distribution";

export type RarityDistributionCollection = { id: string; name: string; cardSetCode: string | null; cardSetName: string | null };

export type RarityDistributionReportData = {
  collection: RarityDistributionCollection;
  kind: ChecklistKind;
  report: RarityDistributionReport;
  logoUrl: string | null;
  issuedAt: string;
};

export type RarityDistributionPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: RarityDistributionReportData };

type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }> };

/** Busca do catálogo (leitura existente, `authenticated`): cartas ativas do Set, 60 por página, ordem total por `collector_order`. */
export const SEARCH_CARDS_RPC = "search_cards";

const pageParams = (setCode: string, offset: number) => ({
  p_query: null,
  p_card_id: null,
  p_card_set_code: setCode,
  p_category_code: null,
  p_rarity_code: null,
  p_limit: RARITY_PAGE_SIZE,
  p_offset: offset,
});

/**
 * Raridade por carta do Card Set da coleção AUTORIZADA (código vindo da 5332, nunca do navegador):
 * 1ª página dá o total; as demais em paralelo, duas por vez. Falha na 1ª = erro; falha depois ou
 * conjunto que não fecha = incompleto (nunca truncado em silêncio).
 */
export async function readCardRarities(supabase: AnyRpc, setCode: string): Promise<CardRarityRead> {
  const read = async (offset: number) => {
    const res = await supabase.rpc(SEARCH_CARDS_RPC, pageParams(setCode, offset));
    return res.error ? null : parseRarityPage(res.data);
  };
  const first = await read(0);
  if (!first) return { status: "error" };
  const pagesNeeded = Math.max(1, Math.ceil(first.total / RARITY_PAGE_SIZE));
  if (pagesNeeded > RARITY_MAX_PAGES) return { status: "incomplete", rarities: new Map(), total: first.total, reason: "too_large" };
  const pages: Array<RarityPage | null> = [first];
  const offsets = Array.from({ length: pagesNeeded - 1 }, (_, i) => (i + 1) * RARITY_PAGE_SIZE);
  for (let i = 0; i < offsets.length; i += 2) {
    const batch = await Promise.all(offsets.slice(i, i + 2).map((offset) => read(offset)));
    pages.push(...batch);
  }
  return mergeRarityPages(setCode, pages, pagesNeeded);
}

/**
 * V1-14 R2-G — preparação de "Distribuição por raridade" (D7 §4o), sem SQL nova:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão/Master Set; senão `unavailable`) e totais canônicos;
 *  2. em paralelo: posições INTEIRAS pela leitura do Checklist (5169 ou 5189/5198), raridade por
 *     carta do Set da coleção (`search_cards`), catálogo de raridades (5355) e logo do Set.
 * Conferência e agrupamento em `buildRarityDistribution`. Somente leitura. Tempos no log do servidor.
 */
export async function prepareRarityDistributionReport(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<RarityDistributionPrepared> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  if (kind === null) return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();
  const rpc = supabase as unknown as AnyRpc;
  const setCode = collection.cardSetCode;
  const logoPath = collection.cardSetLogoPath;

  const timed = <T>(promise: Promise<T>) => {
    const t0 = Date.now();
    return promise.then((value) => ({ value, ms: Date.now() - t0 }));
  };
  const [positions, rarities, catalog, logoUrl] = await Promise.all([
    timed(getChecklist(supabase, authorizedId, kind, "todas")),
    timed(setCode ? readCardRarities(rpc, setCode) : Promise.resolve<CardRarityRead>({ status: "error" })),
    readRarityCatalog(rpc),
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null).catch(() => null) : Promise.resolve(null),
  ]);
  if (positions.value.status === "error") {
    console.error("[reports] distribuição por raridade falhou", { stage: "positions", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  if (rarities.value.status === "error") {
    console.error("[reports] distribuição por raridade falhou", { stage: "rarities", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const load = positions.value;
  const report = buildRarityDistribution({
    kind,
    positions: load.rows,
    positionsComplete: load.complete,
    rarities: rarities.value,
    catalog,
    canonical: { total: collection.totalPositions, satisfied: collection.satisfiedPositions },
  });
  console.info("[reports] distribuição por raridade", {
    ms: Date.now() - startedAt,
    positionsMs: positions.ms,
    raritiesMs: rarities.ms,
    positions: load.rows.length,
    cards: rarities.value.total,
    rarities: report.rarityCount,
    complete: report.complete,
  });
  if (!report.complete) console.warn("[reports] distribuição por raridade incompleta", { reason: report.incompleteReason });
  return {
    status: "ready",
    data: {
      collection: { id: collection.id, name: collection.name, cardSetCode: collection.cardSetCode, cardSetName: collection.cardSetName },
      kind,
      report,
      logoUrl,
      issuedAt: issuedAtLabel(now),
    },
  };
}
