import type { SupabaseClient } from "@supabase/supabase-js";
import { type BinderFinish, resolveFinish } from "./binder-finish.ts";
import { LIBRARY_PAGE_SIZE, POSITIONS_PAGE_SIZE, type PositionFilter, type StorageOption, toPositionsRpcFilter } from "./colecoes.ts";

/**
 * Leituras de Minhas coleções (MY-COLLECTIONS-FRONTEND-01) — contratos LIVE
 * 5168 (R1), 5169 (R2) e 5170 (R3), mais os locais do próprio Inventory pela
 * RLS de `storage_container` (select-own). Todas exigem sessão; a fronteira
 * de autorização é o banco.
 *
 * Mesmo padrão de `acervo-queries.ts`: falha de leitura devolve `null` (a
 * página mostra o estado de erro, nunca uma lista vazia enganosa) e a causa
 * vai para o log do servidor, sem dados do usuário.
 */

export type CollectionSummary = {
  id: string;
  name: string;
  completionPolicy: string;
  lifecycleStatus: string;
  cardSetCode: string | null;
  cardSetName: string | null;
  /** Logo do Set (bucket privado `card-set-logo`); só vira imagem se a sessão puder assiná-la. */
  cardSetLogoPath: string | null;
  /** Acabamento do fichário: gravado (quando a proposta estiver no LIVE) ou padrão estável. */
  finish: BinderFinish;
  /** `true` só quando R1 já devolve `cover_finish` — habilita o seletor de cor. */
  finishEditable: boolean;
  totalPositions: number;
  satisfiedPositions: number;
  isComplete: boolean;
  copiesCount: number;
  coverImagePath: string | null;
  createdAt: string;
};

export type CollectionsPage = { items: CollectionSummary[]; total: number };

type CollectionRow = {
  collection_id: string;
  name: string;
  mode: string;
  completion_policy: string;
  lifecycle_status: string;
  card_set_id: string | null;
  card_set_code: string | null;
  card_set_name: string | null;
  card_set_logo_path: string | null;
  /** Ausente até a proposta 2026-10-17-collection-cover-finish ir para o LIVE. */
  cover_finish?: string | null;
  total_positions: number | string | null;
  satisfied_positions: number | string | null;
  is_complete: boolean | null;
  copies_count: number | string;
  cover_image_path: string | null;
  created_at: string;
  total_count: number | string;
};

function toSummary(row: CollectionRow): CollectionSummary {
  return {
    id: row.collection_id,
    name: row.name,
    completionPolicy: row.completion_policy,
    lifecycleStatus: row.lifecycle_status,
    cardSetCode: row.card_set_code,
    cardSetName: row.card_set_name,
    cardSetLogoPath: row.card_set_logo_path,
    finish: resolveFinish(row.collection_id, row.cover_finish),
    finishEditable: Object.prototype.hasOwnProperty.call(row, "cover_finish"),
    totalPositions: Number(row.total_positions ?? 0),
    satisfiedPositions: Number(row.satisfied_positions ?? 0),
    isComplete: row.is_complete === true,
    copiesCount: Number(row.copies_count ?? 0),
    coverImagePath: row.cover_image_path,
    createdAt: row.created_at,
  };
}

export async function getMyCollections(supabase: SupabaseClient, page: number): Promise<CollectionsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collections", {
    p_include_archived: false,
    p_limit: LIBRARY_PAGE_SIZE,
    p_offset: (page - 1) * LIBRARY_PAGE_SIZE,
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_collections", startedAt, error);
    return null;
  }
  const rows = data as CollectionRow[];
  return { items: rows.map(toSummary), total: rows[0] ? Number(rows[0].total_count) : 0 };
}

/**
 * Uma coleção pelo id, com o mesmo resumo da Biblioteca. R1 não filtra por id:
 * percorre as páginas (100 por chamada) até achar — para a escala atual é uma
 * chamada só. `undefined` = não existe ou é de outra pessoa (o banco não
 * distingue); `null` = falha de leitura. Ressalva registrada: com milhares de
 * coleções, o custo cresce linearmente — um R1 por id resolve quando for o caso.
 */
export async function getMyCollection(supabase: SupabaseClient, id: string): Promise<CollectionSummary | null | undefined> {
  const startedAt = Date.now();
  const pageSize = 100;
  for (let offset = 0; offset < 10_000; offset += pageSize) {
    const { data, error } = await supabase.rpc("get_my_collections", {
      p_include_archived: true,
      p_limit: pageSize,
      p_offset: offset,
    });
    if (error || !Array.isArray(data)) {
      logReadFailure("get_my_collections", startedAt, error);
      return null;
    }
    const rows = data as CollectionRow[];
    const found = rows.find((row) => row.collection_id === id);
    if (found) return toSummary(found);
    if (rows.length < pageSize) return undefined;
  }
  return undefined;
}

export type CollectionPosition = {
  cardId: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardName: string;
  imagePath: string | null;
  isSatisfied: boolean;
  copiesInCollection: number;
  copiesAvailable: number;
};

export type PositionsPage = { items: CollectionPosition[]; total: number };

type PositionRow = {
  card_id: string;
  collector_number: string;
  collector_total: number | null;
  card_name: string;
  image_path: string | null;
  is_satisfied: boolean;
  copies_in_collection: number;
  copies_available: number;
  total_count: number | string;
};

export async function getMyCollectionPositions(
  supabase: SupabaseClient,
  id: string,
  filter: PositionFilter,
): Promise<PositionsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_positions", {
    p_collection_id: id,
    p_filter: toPositionsRpcFilter(filter),
    p_limit: POSITIONS_PAGE_SIZE,
    p_offset: 0,
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_collection_positions", startedAt, error);
    return null;
  }
  const rows = data as PositionRow[];
  return {
    items: rows.map((row) => ({
      cardId: row.card_id,
      collectorNumber: row.collector_number,
      collectorTotal: row.collector_total,
      cardName: row.card_name,
      imagePath: row.image_path,
      isSatisfied: row.is_satisfied,
      copiesInCollection: Number(row.copies_in_collection ?? 0),
      copiesAvailable: Number(row.copies_available ?? 0),
    })),
    total: rows[0] ? Number(rows[0].total_count) : 0,
  };
}

/**
 * Quantas cartas do acervo podem entrar agora ("1 de cada", R3). Uma linha
 * basta — `total_count` vem antes do limite. `null` = falha (o botão some).
 */
export async function getLinkableCount(supabase: SupabaseClient, id: string): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_link_candidates", { p_collection_id: id, p_limit: 1 });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_collection_link_candidates", startedAt, error);
    return null;
  }
  const first = (data as { total_count: number | string }[])[0];
  return first ? Number(first.total_count) : 0;
}

/** Locais do próprio Inventory (RLS select-own), do mais antigo ao mais novo. */
export async function getMyStorageLocations(supabase: SupabaseClient): Promise<StorageOption[] | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase
    .from("storage_container")
    .select("id, name")
    .order("created_at", { ascending: true })
    .limit(200);
  if (error || !Array.isArray(data)) {
    logReadFailure("storage_container", startedAt, error);
    return null;
  }
  return (data as { id: string; name: string }[]).map((row) => ({ id: row.id, name: row.name }));
}

export function logReadFailure(fn: string, startedAt: number, error: { code?: string; message?: string } | null) {
  console.error(
    JSON.stringify({
      scope: "colecoes.read",
      fn,
      ms: Date.now() - startedAt,
      code: error?.code ?? "NO_DATA",
      message: error?.message ?? null,
    }),
  );
}

/**
 * URLs assinadas (1 h) dos logos de Set de uma página, numa chamada só.
 * O bucket `card-set-logo` hoje só é legível por administradores: para os
 * demais, o Storage recusa cada item e o mapa volta vazio — a capa usa a
 * identidade tipográfica do Set. Proposta de leitura para autenticados em
 * `database/proposals/2026-10-17-collection-cover-finish/` (não executada).
 */
export async function getSetLogoUrls(supabase: SupabaseClient, paths: (string | null)[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  const unique = [...new Set(paths.filter((path): path is string => typeof path === "string" && path !== "" && !path.includes("..")))];
  if (unique.length === 0) return map;
  const { data, error } = await supabase.storage.from("card-set-logo").createSignedUrls(unique, 60 * 60);
  if (error || !data) return map;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}
