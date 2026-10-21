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
