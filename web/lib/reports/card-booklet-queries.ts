import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyCollection, getSetLogoUrls } from "@/lib/colecoes/colecoes-queries";
import {
  BOOKLET_MAX_PAGES,
  BOOKLET_PAGE_SIZE,
  type BookletCatalogPage,
  type BookletCatalogRead,
  type BookletReport,
  buildCardBooklet,
  mergeCatalogPages,
  parseCatalogPage,
} from "./card-booklet";
import { getChecklist } from "./checklist-queries";
import { type ChecklistKind, checklistKindOf, issuedAtLabel } from "./collection-checklist";
import { readRarityCatalog } from "./distribution-queries";
import { SEARCH_CARDS_RPC } from "./rarity-distribution-queries";

export type CardBookletCollection = {
  id: string;
  name: string;
  cardSetCode: string | null;
  cardSetName: string | null;
};

export type CardBookletData = {
  collection: CardBookletCollection;
  kind: ChecklistKind;
  report: BookletReport;
  logoUrl: string | null;
  /** Data de emissão (dd/mm/aaaa) — capa e encerramento. */
  issuedOn: string;
  issuedAt: string;
};

export type CardBookletPrepared =
  | { status: "not_found" }
  | { status: "error" }
  | { status: "unavailable"; name: string }
  | { status: "ready"; data: CardBookletData };

type AnyRpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }> };

/**
 * Cartas ativas do Card Set da coleção AUTORIZADA (código vindo da 5332), pela busca do catálogo
 * (`search_cards`, a mesma leitura da R2-G): 1ª página dá o total; as demais duas a duas. Falha na
 * 1ª = erro; falha depois ou conjunto que não fecha = incompleto (nunca truncado em silêncio).
 */
export async function readSetCatalog(supabase: AnyRpc, setCode: string): Promise<BookletCatalogRead> {
  const read = async (offset: number) => {
    const res = await supabase.rpc(SEARCH_CARDS_RPC, {
      p_query: null,
      p_card_id: null,
      p_card_set_code: setCode,
      p_category_code: null,
      p_rarity_code: null,
      p_limit: BOOKLET_PAGE_SIZE,
      p_offset: offset,
    });
    return res.error ? null : parseCatalogPage(res.data);
  };
  const first = await read(0);
  if (!first) return { status: "error" };
  const pagesNeeded = Math.max(1, Math.ceil(first.total / BOOKLET_PAGE_SIZE));
  if (pagesNeeded > BOOKLET_MAX_PAGES) return { status: "incomplete", cards: [], reason: "too_large" };
  const pages: Array<BookletCatalogPage | null> = [first];
  const offsets = Array.from({ length: pagesNeeded - 1 }, (_, i) => (i + 1) * BOOKLET_PAGE_SIZE);
  for (let i = 0; i < offsets.length; i += 2) pages.push(...(await Promise.all(offsets.slice(i, i + 2).map((offset) => read(offset)))));
  return mergeCatalogPages(setCode, pages, pagesNeeded);
}

/**
 * Caderno de Cartas da Coleção (D7 §4p), sem SQL nova:
 *  1. 5332 `get_my_collection` — titularidade (alheia/compartilhada/inexistente → `not_found`, sem
 *     distinguir), objetivo (Set padrão/Master Set; senão `unavailable`) e totais canônicos;
 *  2. em paralelo: cartas do Set (`search_cards`), posições inteiras do Checklist (5169 ou 5189/5198),
 *     catálogo de raridades (5355) e logo do Set.
 * Somente leitura. Tempos no log do servidor, sem dados do titular.
 */
export async function prepareCardBooklet(supabase: SupabaseClient, collectionId: string, now: Date = new Date()): Promise<CardBookletPrepared> {
  const startedAt = Date.now();
  const collection = await getMyCollection(supabase, collectionId);
  if (collection === undefined) return { status: "not_found" };
  if (collection === null) return { status: "error" };
  const kind = checklistKindOf(collection.completionPolicy);
  if (kind === null || !collection.cardSetCode) return { status: "unavailable", name: collection.name };
  const authorizedId = collection.id.toLowerCase();
  const rpc = supabase as unknown as AnyRpc;
  const logoPath = collection.cardSetLogoPath;

  const [catalog, positions, rarityCatalog, logoUrl] = await Promise.all([
    readSetCatalog(rpc, collection.cardSetCode),
    getChecklist(supabase, authorizedId, kind, "todas"),
    readRarityCatalog(rpc),
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null).catch(() => null) : Promise.resolve(null),
  ]);
  if (catalog.status === "error" || positions.status === "error") {
    console.error("[reports] caderno de cartas falhou", { stage: catalog.status === "error" ? "catalog" : "positions", ms: Date.now() - startedAt });
    return { status: "error" };
  }
  const report = buildCardBooklet({
    kind,
    catalog,
    positions: positions.rows,
    positionsComplete: positions.complete,
    rarityCatalog,
    canonical: { total: collection.totalPositions, satisfied: collection.satisfiedPositions },
  });
  console.info("[reports] caderno de cartas", { ms: Date.now() - startedAt, cards: report.cards.length, pages: report.totalPages, complete: report.complete });
  if (!report.complete) console.warn("[reports] caderno de cartas incompleto", { reason: report.incompleteReason });
  return {
    status: "ready",
    data: {
      collection: { id: collection.id, name: collection.name, cardSetCode: collection.cardSetCode, cardSetName: collection.cardSetName },
      kind,
      report,
      logoUrl,
      issuedOn: now.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" }),
      issuedAt: issuedAtLabel(now),
    },
  };
}
