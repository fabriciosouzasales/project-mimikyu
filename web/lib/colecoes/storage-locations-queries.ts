import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type StorageKind,
  type StorageLocation,
  type StorageSummary,
  toStorageKind,
  toStorageLocation,
  toStorageSummary,
} from "./storage-locations.ts";

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
};

export async function getStorageOverview(supabase: SupabaseClient): Promise<StorageOverview | null> {
  const startedAt = Date.now();
  const [locations, summary, kinds] = await Promise.all([
    supabase.rpc("get_my_storage_locations"),
    supabase.rpc("get_my_storage_summary"),
    supabase.from("storage_container_kind").select("code, label").eq("is_active", true).order("sort_order", { ascending: true }),
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
  return { locations: parsedLocations, summary: parsedSummary, kinds: parsedKinds };
}

function logRead(fn: string, startedAt: number, error: { code?: string; message?: string } | null) {
  // Sem dados do usuário: só função, duração e código.
  console.error(JSON.stringify({ scope: "colecoes.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA" }));
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
): Promise<CopyStorageContext | null> {
  const startedAt = Date.now();
  const [copies, locations, collections] = await Promise.all([
    supabase.from("physical_card").select("id, storage_container_id").eq("card_variant_id", cardVariantId).limit(5000),
    supabase.rpc("get_my_storage_locations"),
    supabase.from("collection").select("id, default_storage_container_id").limit(1000),
  ]);
  if (copies.error || !Array.isArray(copies.data)) {
    logRead("physical_card.storage", startedAt, copies.error ?? { code: "NO_DATA" });
    return null;
  }
  if (locations.error || !Array.isArray(locations.data)) {
    logRead("get_my_storage_locations", startedAt, locations.error ?? { code: "NO_DATA" });
    return null;
  }
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
    locations: (locations.data as Record<string, unknown>[]).map(toStorageLocation).filter((l): l is StorageLocation => l !== null),
    collectionDefaults,
  };
}
