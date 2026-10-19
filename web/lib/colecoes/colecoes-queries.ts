import type { SupabaseClient } from "@supabase/supabase-js";
import { type BinderFinish, resolveFinish } from "./binder-finish.ts";
import { COVER_BUCKET, FREE_COVER_CODE_ENABLED, FREE_COVER_UPLOAD_ENABLED, isCoverCode, isCoverPath, isFreeCollection } from "./free-collection.ts";
import { LIBRARY_PAGE_SIZE, POSITIONS_PAGE_SIZE, type PositionFilter, type StorageOption, toPositionsRpcFilter } from "./colecoes.ts";
import { MASTER_SET_PAGE_SIZE, type MasterSetPositionsPage, parseMasterSetPositions } from "./master-set.ts";
import {
  type GenerationOption,
  POKEDEX_PAGE_SIZE,
  isPokedexCollection,
  type PokedexFilter,
  type PokedexPositionsPage,
  parseGenerationOptions,
  parsePokedexPositions,
  toPokedexRpcFilter,
} from "./pokedex.ts";

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
  /** Imagem enviada pelo colecionador para a placa (Coleção livre); `null` sem imagem ou antes de 5177. */
  coverLogoPath: string | null;
  /** Código opcional da Coleção livre (2–6 letras/números); `null` sem código ou antes de 5179. */
  coverCode: string | null;
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
    coverLogoPath: null,
    coverCode: null,
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
 * Grade do Master Set (5189, desempenho da 5198): uma página de posições
 * (carta + acabamento, ou carta secreta genérica) com o filtro da URL. Só a
 * página pedida — nunca o Set inteiro. Coleção alheia ou fora de MASTER_SET →
 * página vazia (o banco não distingue). `null` = falha de leitura.
 */
export async function getMyMasterSetPositions(
  supabase: SupabaseClient,
  id: string,
  filter: PositionFilter,
  page: number,
): Promise<MasterSetPositionsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_master_set_positions", {
    p_collection_id: id,
    p_filter: toPositionsRpcFilter(filter),
    p_limit: MASTER_SET_PAGE_SIZE,
    p_offset: (Math.max(page, 1) - 1) * MASTER_SET_PAGE_SIZE,
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_master_set_positions", startedAt, error);
    return null;
  }
  return parseMasterSetPositions(data);
}

/**
 * Quantos exemplares da coleção estão fora do objetivo (5196). Uma linha
 * basta — `total_count` vem antes do limite. `null` = falha (a seção não
 * aparece, a página não finge que não há nada).
 */
export async function getMasterSetOutOfScopeCount(supabase: SupabaseClient, id: string): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_master_set_out_of_scope_copies", {
    p_collection_id: id,
    p_limit: 1,
    p_offset: 0,
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_master_set_out_of_scope_copies", startedAt, error);
    return null;
  }
  const first = (data as { total_count: number | string }[])[0];
  return first ? Number(first.total_count) : 0;
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

/**
 * Master Set: quantas posições faltantes têm exemplar livre no acervo agora
 * (Query 5200, uma linha basta — `total_count` vem antes do limite). `null` =
 * falha: o botão some.
 */
export async function getMasterSetLinkableCount(supabase: SupabaseClient, id: string): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_master_set_link_candidates", { p_collection_id: id, p_limit: 1 });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_master_set_link_candidates", startedAt, error);
    return null;
  }
  const first = (data as { total_count: number | string }[])[0];
  const total = first ? Number(first.total_count) : 0;
  return Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
}

/**
 * Quantas cartas diferentes do acervo estão fora de qualquer coleção e podem
 * entrar numa Coleção livre agora (5159 com `p_without_collection`). Uma linha
 * basta — `total_count` vem antes do limite. `null` = falha (a interface não
 * promete um número que não conseguiu ler).
 */
export async function getAvailableGroupCount(supabase: SupabaseClient): Promise<number | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_inventory_items", {
    p_search: null,
    p_card_set_code: null,
    p_language_code: null,
    p_collection_id: null,
    p_without_collection: true,
    p_sort: "RECENT",
    p_limit: 1,
    p_offset: 0,
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_inventory_items", startedAt, error);
    return null;
  }
  const first = (data as { total_count: number | string }[])[0];
  return first ? Number(first.total_count) : 0;
}

/**
 * Gerações catalogadas da Pokédex Nacional (5201). Sem coleção: opções da
 * criação. Com coleção: seleção atual e conquistadas por geração (coleção
 * alheia → lista vazia; o banco não distingue). `null` = falha de leitura.
 */
export async function getPokedexGenerationOptions(
  supabase: SupabaseClient,
  collectionId: string | null,
): Promise<GenerationOption[] | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_pokedex_generation_options", { p_collection_id: collectionId });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_pokedex_generation_options", startedAt, error);
    return null;
  }
  return parseGenerationOptions(data);
}

/**
 * Grade da coleção Pokédex (5204): uma página no servidor, na ordem nacional,
 * com o filtro da URL. Coleção alheia → página vazia. `null` = falha.
 */
export async function getMyPokedexPositions(
  supabase: SupabaseClient,
  collectionId: string,
  filter: PokedexFilter,
  generation: string | null,
  offset = 0,
): Promise<PokedexPositionsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_pokedex_positions", {
    p_collection_id: collectionId,
    p_filter: toPokedexRpcFilter(filter),
    p_generation_code: generation,
    p_limit: POKEDEX_PAGE_SIZE,
    p_offset: Math.max(0, Math.trunc(offset)),
  });
  if (error || !Array.isArray(data)) {
    logReadFailure("get_my_pokedex_positions", startedAt, error);
    return null;
  }
  return parsePokedexPositions(data);
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

/**
 * Capa da Coleção livre: lê `cover_logo_path` (5177, imagem enviada) e
 * `cover_code` (5179, código opcional) das coleções livres da lista pela RLS
 * select-own (5030) — uma consulta só, por `id`. Cada coluna só entra com a
 * sua flag (`FREE_COVER_UPLOAD_ENABLED`, `FREE_COVER_CODE_ENABLED`); qualquer
 * falha mantém as coleções sem imagem e sem código — a placa tipográfica
 * continua valendo.
 */
export async function attachCoverLogos<T extends CollectionSummary>(supabase: SupabaseClient, items: T[]): Promise<T[]> {
  const columns = [FREE_COVER_UPLOAD_ENABLED ? "cover_logo_path" : null, FREE_COVER_CODE_ENABLED ? "cover_code" : null].filter(
    (column): column is string => column !== null,
  );
  if (columns.length === 0) return items;
  // Coleção livre e Pokédex têm capa e código próprios (5178/5180, ampliados pela 5206/5207).
  const ids = items.filter((item) => isFreeCollection(item) || isPokedexCollection(item)).map((item) => item.id);
  if (ids.length === 0) return items;
  const startedAt = Date.now();
  const { data, error } = await supabase.from("collection").select(["id", ...columns].join(", ")).in("id", ids);
  if (error || !Array.isArray(data)) {
    logReadFailure(`collection.${columns.join("+")}`, startedAt, error);
    return items;
  }
  const rows = new Map(
    (data as unknown as { id: string; cover_logo_path?: string | null; cover_code?: string | null }[]).map((row) => [row.id, row]),
  );
  return items.map((item) => {
    const row = rows.get(item.id);
    if (!row) return item;
    return {
      ...item,
      coverLogoPath: isCoverPath(row.cover_logo_path) ? row.cover_logo_path : item.coverLogoPath,
      coverCode: isCoverCode(row.cover_code) ? row.cover_code : item.coverCode,
    };
  });
}

/** URLs assinadas (1 h) das capas enviadas — bucket privado, só o dono lê (5176). */
export async function getCoverLogoUrls(supabase: SupabaseClient, paths: (string | null)[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (!FREE_COVER_UPLOAD_ENABLED) return map;
  const unique = [...new Set(paths.filter((path): path is string => isCoverPath(path)))];
  if (unique.length === 0) return map;
  const { data, error } = await supabase.storage.from(COVER_BUCKET).createSignedUrls(unique, 60 * 60);
  if (error || !data) return map;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}
