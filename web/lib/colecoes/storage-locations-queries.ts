import type { SupabaseClient } from "@supabase/supabase-js";
import { ACERVO_PAGE_SIZE, ACERVO_QUERY_MAX_LENGTH, type AcervoItemKey, type AcervoState, parseAcervoState } from "./acervo.ts";
import { type AcervoItem, type AcervoItemDetail, getAcervoItemDetail, getAcervoItems } from "./acervo-queries.ts";
import {
  type StorageKind,
  type StorageLocation,
  type StorageSummary,
  toStorageKind,
  toStorageLocation,
  toStorageSummary,
} from "./storage-locations.ts";
import { readRarityCatalog } from "../reports/distribution-queries.ts";

/**
 * Leituras de "Meus locais" (WHERE-02) — só com a sessão do usuário, nunca
 * `service_role`. Três leituras em paralelo, uma de cada:
 *
 * - `get_my_storage_locations()` (5219): locais do próprio acervo com as
 *   contagens já calculadas no banco (exemplares e coleções que usam o local
 *   como padrão) e `can_delete` — a tela nunca percorre o acervo para contar;
 * - `get_my_storage_summary()` (5219): total, localizados, "Sem localização
 *   definida" e número de locais;
 * - `storage_container_kind` (5212, RLS: só tipos ativos para authenticated):
 *   o vocabulário de tipos vem do banco — nenhuma lista fixa no frontend.
 *
 * Locais ou resumo indisponíveis → `null` (a página mostra o erro de leitura).
 * Tipos indisponíveis não bloqueiam: o local pode ser criado sem tipo.
 */
export type StorageOverview = {
  locations: StorageLocation[];
  summary: StorageSummary;
  kinds: StorageKind[];
  /**
   * Fichários digitais guardados em cada local (Conceito B): id do local →
   * nomes das coleções donas do fichário (`collection_layout.storage_container_id`,
   * RLS select-own). Falha → `{}` (as linhas só deixam de mostrar o vínculo).
   */
  binders: Record<string, string[]>;
};

export async function getStorageOverview(supabase: SupabaseClient): Promise<StorageOverview | null> {
  const startedAt = Date.now();
  const [locations, summary, kinds, binders] = await Promise.all([
    supabase.rpc("get_my_storage_locations"),
    supabase.rpc("get_my_storage_summary"),
    supabase.from("storage_container_kind").select("code, label").eq("is_active", true).order("sort_order", { ascending: true }),
    readBinderLinks(supabase),
  ]);

  if (locations.error || !Array.isArray(locations.data)) {
    logRead("get_my_storage_locations", startedAt, locations.error);
    return null;
  }
  const summaryRow = Array.isArray(summary.data) ? (summary.data[0] as Record<string, unknown> | undefined) : undefined;
  const parsedSummary = summary.error ? null : toStorageSummary(summaryRow);
  if (!parsedSummary) {
    logRead("get_my_storage_summary", startedAt, summary.error ?? { code: "BAD_SHAPE" });
    return null;
  }

  const parsedLocations = (locations.data as Record<string, unknown>[])
    .map(toStorageLocation)
    .filter((location): location is StorageLocation => location !== null);
  if (parsedLocations.length !== locations.data.length) {
    logRead("get_my_storage_locations", startedAt, { code: "BAD_SHAPE" });
  }

  let parsedKinds: StorageKind[] = [];
  if (kinds.error || !Array.isArray(kinds.data)) {
    logRead("storage_container_kind", startedAt, kinds.error ?? { code: "NO_DATA" });
  } else {
    parsedKinds = (kinds.data as Record<string, unknown>[]).map(toStorageKind).filter((kind): kind is StorageKind => kind !== null);
  }

  console.info(
    JSON.stringify({ scope: "colecoes.locais_read", ms: Date.now() - startedAt, locations: parsedLocations.length, kinds: parsedKinds.length }),
  );
  return { locations: parsedLocations, summary: parsedSummary, kinds: parsedKinds, binders };
}

/** Fichários digitais por local (duas leituras pequenas com RLS; nenhuma SQL nova). Falha → `{}`. */
async function readBinderLinks(supabase: SupabaseClient): Promise<Record<string, string[]>> {
  const startedAt = Date.now();
  const layouts = await supabase.from("collection_layout").select("collection_id, storage_container_id").not("storage_container_id", "is", null).limit(2000);
  if (layouts.error || !Array.isArray(layouts.data)) {
    logRead("collection_layout.storage", startedAt, layouts.error ?? { code: "NO_DATA" });
    return {};
  }
  const rows = (layouts.data as Record<string, unknown>[]).filter(
    (r): r is { collection_id: string; storage_container_id: string } => typeof r.collection_id === "string" && typeof r.storage_container_id === "string",
  );
  if (rows.length === 0) return {};
  const names = await supabase.from("collection").select("id, name").in("id", [...new Set(rows.map((r) => r.collection_id))]);
  if (names.error || !Array.isArray(names.data)) {
    logRead("collection.binder_names", startedAt, names.error ?? { code: "NO_DATA" });
    return {};
  }
  const byId = new Map((names.data as Record<string, unknown>[]).filter((r) => typeof r.id === "string" && typeof r.name === "string").map((r) => [r.id as string, r.name as string]));
  const out: Record<string, string[]> = {};
  for (const r of rows) {
    const name = byId.get(r.collection_id);
    if (!name) continue;
    (out[r.storage_container_id] ??= []).push(name);
  }
  return out;
}

function logRead(fn: string, startedAt: number, error: { code?: string; message?: string } | null) {
  // Sem dados do usuário: só função, duração e código.
  console.error(JSON.stringify({ scope: "colecoes.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA" }));
}

/**
 * WHERE-04 — locais do usuário para o filtro "Localização física" do Meu
 * acervo (5219, mesmos nomes e contagens de "Meus locais"; nada duplicado no
 * frontend). Falha → `null`: o filtro continua com "Todos os locais" e
 * "Sem localização definida", e a página explica que a lista não carregou.
 * Uma única chamada por renderização: o detalhe (WHERE-03) reaproveita esta
 * mesma leitura em vez de repetir a 5219.
 */
export async function getMyStorageLocations(supabase: SupabaseClient): Promise<StorageLocation[] | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_storage_locations");
  if (error || !Array.isArray(data)) {
    logRead("get_my_storage_locations", startedAt, error ?? { code: "NO_DATA" });
    return null;
  }
  return (data as Record<string, unknown>[]).map(toStorageLocation).filter((l): l is StorageLocation => l !== null);
}

/**
 * WHERE-03 — contexto de localização do detalhe de uma carta no Meu acervo.
 *
 * - local corrente de cada exemplar desta variante (`physical_card`, RLS
 *   select-own — só o próprio acervo; o filtro por variante mantém a leitura
 *   pequena). A 5162 devolve o NOME do local; aqui vem o id, para comparar
 *   e pré-marcar sem nunca usar o nome como identidade;
 * - os locais do usuário com contagens (5219);
 * - o local padrão de cada coleção do usuário (`collection`, RLS select-own),
 *   exibido só como referência ("Local padrão da coleção") — nunca aplicado.
 *
 * Qualquer falha → `null`: o detalhe continua funcionando, só sem a
 * alteração de local (a interface explica).
 */
export type CopyStorageContext = {
  storageByCopy: Record<string, string | null>;
  locations: StorageLocation[];
  collectionDefaults: Record<string, string>;
};

export async function getCopyStorageContext(
  supabase: SupabaseClient,
  cardVariantId: string,
  /** Leitura da 5219 já em andamento na página (WHERE-04) — evita repetir a chamada. */
  locationsRead: Promise<StorageLocation[] | null> = getMyStorageLocations(supabase),
): Promise<CopyStorageContext | null> {
  const startedAt = Date.now();
  const [copies, locations, collections] = await Promise.all([
    supabase.from("physical_card").select("id, storage_container_id").eq("card_variant_id", cardVariantId).limit(5000),
    locationsRead,
    supabase.from("collection").select("id, default_storage_container_id").limit(1000),
  ]);
  if (copies.error || !Array.isArray(copies.data)) {
    logRead("physical_card.storage", startedAt, copies.error ?? { code: "NO_DATA" });
    return null;
  }
  // Falha da 5219 já registrada em getMyStorageLocations.
  if (locations === null) return null;
  const storageByCopy: Record<string, string | null> = {};
  for (const row of copies.data as { id: string; storage_container_id: string | null }[]) {
    storageByCopy[row.id] = typeof row.storage_container_id === "string" ? row.storage_container_id : null;
  }
  const collectionDefaults: Record<string, string> = {};
  if (!collections.error && Array.isArray(collections.data)) {
    for (const row of collections.data as { id: string; default_storage_container_id: string | null }[]) {
      if (typeof row.default_storage_container_id === "string") collectionDefaults[row.id] = row.default_storage_container_id;
    }
  } else {
    // Sem o local padrão das coleções a tela só deixa de mostrar a referência.
    logRead("collection.default_storage", startedAt, collections.error ?? { code: "NO_DATA" });
  }
  return {
    storageByCopy,
    locations,
    collectionDefaults,
  };
}

/**
 * Consulta contextual de um local (STORAGE LOCATIONS UX REDESIGN-01) — somente
 * leitura, só com a sessão do usuário. Reaproveita a leitura do Meu acervo:
 *
 * - `get_my_inventory_items` (5159/5220) com o filtro de local no banco
 *   (`?local=<id>` do Meu acervo, `getAcervoItems`): mesmos itens (variante +
 *   idioma), mesmos contadores (`copies_count` = exemplares DESTE local,
 *   `total_copies` em todas as páginas), 1ª página em ordem de Set e número;
 *   local de outra conta → vazio (a 5220 não distingue, de propósito);
 * - coleções que usam o local como padrão (`collection`, RLS select-own) —
 *   preferência, nunca localização (NS-15);
 * - fichários digitais guardados neste local (`collection_layout`, RLS
 *   select-own; `storage_container_id`, 5247) — só o atalho para a tela
 *   existente do fichário; capacidade e ocupação ficam para o relatório.
 *
 * Itens indisponíveis → `null` (o painel mostra o erro com nova tentativa);
 * coleções/fichários indisponíveis só somem do painel.
 */
export type LocationCollectionRef = { id: string; name: string };

/** Teto da leitura completa de um local (itens = variante + idioma). Acima: incompleto, nunca truncado em silêncio. */
export const LOCATION_ITEMS_MAX = 5000;

export type LocationItemsRead = { items: AcervoItem[]; totalGroups: number; totalCopies: number; complete: boolean };

/**
 * TODO o conteúdo de um local (L2-01): a mesma leitura do Meu acervo filtrado
 * pelo local (5159/5220 com `p_storage_container_id`, ordem de Set e número),
 * todas as páginas — 1ª página dá `total_count`/`total_copies`, as demais em
 * lotes de 4. `copies_count` de cada item = exemplares DESTE local. Completa =
 * itens lidos = total e Σ exemplares = `total_copies`. Falha → `null`.
 */
export async function readAllLocationItems(supabase: SupabaseClient, storageId: string): Promise<LocationItemsRead | null> {
  const base: AcervoState = { ...parseAcervoState({}), storage: { kind: "location", id: storageId }, sort: "set" };
  const first = await getAcervoItems(supabase, base);
  if (!first) return null;
  const pages = Math.min(Math.ceil(first.totalGroups / ACERVO_PAGE_SIZE), Math.ceil(LOCATION_ITEMS_MAX / ACERVO_PAGE_SIZE));
  const items = [...first.items];
  for (let page = 2; page <= pages; page += 4) {
    const batch = await Promise.all(
      Array.from({ length: Math.min(4, pages - page + 1) }, (_, k) => getAcervoItems(supabase, { ...base, page: page + k })),
    );
    for (const result of batch) {
      if (!result) return null;
      items.push(...result.items);
    }
  }
  const seen = new Set<string>();
  const unique = items.filter((item) => {
    const key = `${item.cardVariantId}|${item.languageCode}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  const copies = unique.reduce((n, item) => n + item.copiesCount, 0);
  return {
    items: unique,
    totalGroups: first.totalGroups,
    totalCopies: first.totalCopies,
    complete: unique.length === first.totalGroups && copies === first.totalCopies && unique.length === items.length,
  };
}

export type LocationContents = LocationItemsRead & {
  defaultCollections: LocationCollectionRef[];
  binders: LocationCollectionRef[];
  /**
   * Nome canônico de cada raridade (`rarity.code` → `rarity.name`, 5355
   * `get_rarity_catalog`, a mesma fonte dos relatórios) para a prévia da carta.
   * `null` = catálogo indisponível agora (a prévia diz isso; nada é inferido).
   */
  rarityNames: Record<string, string> | null;
};

export async function getLocationContents(supabase: SupabaseClient, storageId: string): Promise<LocationContents | null> {
  const startedAt = Date.now();
  const [read, defaults, layouts, rarities] = await Promise.all([
    readAllLocationItems(supabase, storageId),
    supabase.from("collection").select("id, name").eq("default_storage_container_id", storageId).order("name").limit(200),
    supabase.from("collection_layout").select("collection_id").eq("storage_container_id", storageId).limit(200),
    readRarityCatalog(supabase as unknown as Parameters<typeof readRarityCatalog>[0]),
  ]);
  if (!read) return null;
  const rarityNames = rarities.status === "ok" ? Object.fromEntries(rarities.entries.map((e) => [e.code, e.name])) : null;

  const refs = (rows: unknown): LocationCollectionRef[] =>
    Array.isArray(rows)
      ? (rows as Record<string, unknown>[])
          .filter((r) => typeof r.id === "string" && typeof r.name === "string")
          .map((r) => ({ id: r.id as string, name: r.name as string }))
      : [];
  const defaultCollections = defaults.error ? [] : refs(defaults.data);
  if (defaults.error) logRead("collection.default_storage", startedAt, defaults.error);

  let binders: LocationCollectionRef[] = [];
  if (layouts.error || !Array.isArray(layouts.data)) {
    logRead("collection_layout.storage", startedAt, layouts.error ?? { code: "NO_DATA" });
  } else {
    const ids = [...new Set((layouts.data as Record<string, unknown>[]).map((r) => r.collection_id).filter((v): v is string => typeof v === "string"))];
    if (ids.length > 0) {
      const named = await supabase.from("collection").select("id, name").in("id", ids).order("name");
      if (named.error) logRead("collection.binder_names", startedAt, named.error);
      else binders = refs(named.data);
    }
  }

  console.info(JSON.stringify({ scope: "colecoes.locais_content", ms: Date.now() - startedAt, groups: read.totalGroups, complete: read.complete, binders: binders.length }));
  return { ...read, defaultCollections, binders, rarityNames };
}

/**
 * Encontrar carta (L2-01) — candidatas no acervo do próprio usuário: a busca do
 * Meu acervo (5159/5220 `p_search`: nome da carta ou número, "25" / "25/88"),
 * sem filtro de local, ordem de Set e número, 1ª página. Cada resultado é uma
 * identidade física do acervo (variante + idioma) — nunca agrupada por nome.
 */
export async function searchAcervoCards(supabase: SupabaseClient, query: string): Promise<{ items: AcervoItem[]; totalGroups: number } | null> {
  const q = query.trim().slice(0, ACERVO_QUERY_MAX_LENGTH);
  if (q.length < 2) return { items: [], totalGroups: 0 };
  const page = await getAcervoItems(supabase, { ...parseAcervoState({}), query: q, sort: "set" });
  return page ? { items: page.items, totalGroups: page.totalGroups } : null;
}

/**
 * Onde estão os exemplares de UMA identidade (variante + idioma): os exemplares
 * da 5162 (`get_my_inventory_item_copies`, só do titular) e o local corrente de
 * cada um (`physical_card.storage_container_id`, RLS select-own, pelos ids da
 * própria 5162). Localização física apenas — alocação em coleção não conta.
 * `undefined` = identidade inexistente/alheia; `null` = falha.
 */
export type CardLocations = {
  item: AcervoItemDetail["item"];
  total: number;
  /** id do local → exemplares; `none` = sem localização. */
  byStorage: Record<string, number>;
  unlocated: number;
};

export async function locateCardCopies(supabase: SupabaseClient, key: AcervoItemKey): Promise<CardLocations | null | undefined> {
  const startedAt = Date.now();
  const detail = await getAcervoItemDetail(supabase, key);
  if (detail === undefined) return undefined;
  if (detail === null) return null;
  const ids = detail.copies.map((c) => c.physicalCardId);
  const storage = new Map<string, string | null>();
  for (let i = 0; i < ids.length; i += 200) {
    const chunk = ids.slice(i, i + 200);
    const res = await supabase.from("physical_card").select("id, storage_container_id").in("id", chunk);
    if (res.error || !Array.isArray(res.data)) {
      logRead("physical_card.storage", startedAt, res.error ?? { code: "NO_DATA" });
      return null;
    }
    for (const row of res.data as { id: string; storage_container_id: string | null }[]) storage.set(row.id, row.storage_container_id ?? null);
  }
  if (storage.size !== ids.length) {
    logRead("physical_card.storage", startedAt, { code: "MISMATCH" });
    return null;
  }
  const byStorage: Record<string, number> = {};
  let unlocated = 0;
  for (const id of ids) {
    const where = storage.get(id) ?? null;
    if (where === null) unlocated += 1;
    else byStorage[where] = (byStorage[where] ?? 0) + 1;
  }
  return { item: detail.item, total: ids.length, byStorage, unlocated };
}

/**
 * Inventário do Local (relatório L2-01, D7): o local pela 5219 (titularidade —
 * id alheio/inexistente → `not_found`) e TODO o seu conteúdo
 * (`readAllLocationItems`). Somente leitura.
 */
export type LocationInventory = { location: StorageLocation; read: LocationItemsRead };

export async function getLocationInventory(
  supabase: SupabaseClient,
  storageId: string,
): Promise<{ status: "ready"; data: LocationInventory } | { status: "not_found" } | { status: "error" }> {
  const locations = await getMyStorageLocations(supabase);
  if (!locations) return { status: "error" };
  const location = locations.find((l) => l.id.toLowerCase() === storageId.toLowerCase());
  if (!location) return { status: "not_found" };
  if (location.cardCount === 0) return { status: "ready", data: { location, read: { items: [], totalGroups: 0, totalCopies: 0, complete: true } } };
  const read = await readAllLocationItems(supabase, location.id);
  if (!read) return { status: "error" };
  return { status: "ready", data: { location, read } };
}
