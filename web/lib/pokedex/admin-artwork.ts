import type { SupabaseClient } from "@supabase/supabase-js";
import { matchesArtworkQuery, type ArtworkStatus } from "@/lib/pokedex/admin-artwork-format";

/**
 * Leituras da administração de Imagens da Pokédex (Pokédex P2 Lote E).
 *
 * Fonte única: `admin_list_pokemon_species_artwork_status(p_status, p_limit,
 * p_offset)` da Query 6132 — SECURITY DEFINER, exige `is_admin()`, sem
 * leitura direta da tabela. Nenhuma consulta por espécie.
 *
 * - Sem pesquisa: paginação no banco (`limit/offset` + `total_count`).
 * - Com pesquisa: a função não filtra por nome, então a lista do status
 *   escolhido é lida em blocos de 1.000 (2 chamadas para as 1.025 espécies)
 *   e filtrada no servidor; só a página pedida vai para o navegador. O
 *   universo é a Pokédex Nacional (~1.000 linhas leves), não uma tabela de
 *   crescimento aberto.
 */

export const ARTWORK_ADMIN_PAGE_SIZE = 50;
const RPC_MAX_ROWS = 1000;

export type ArtworkAdminRow = {
  national_dex_number: number;
  species_name: string;
  artwork_status: ArtworkStatus;
  attempt_count: number;
  last_attempt_at: string | null;
  last_error_code: string | null;
  last_error_message: string | null;
  source_pokemon_id: string | null;
  original_storage_path: string | null;
  display_storage_path: string | null;
  display_size_bytes: number | null;
  rights_status: string | null;
  imported_at: string | null;
  total_count: number;
};

export type ArtworkCoverage = { imported: number; pending: number; failed: number; total: number };

async function listStatus(
  supabase: SupabaseClient,
  status: ArtworkStatus | null,
  limit: number,
  offset: number,
): Promise<ArtworkAdminRow[] | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("admin_list_pokemon_species_artwork_status", {
    p_status: status,
    p_limit: limit,
    p_offset: offset,
  });
  if (error || !data) {
    console.error(
      `[pokedex-imagens] admin_list_pokemon_species_artwork_status falhou (código ${error?.code ?? "NO_DATA"}, ${
        Date.now() - startedAt
      } ms): ${error?.message ?? "sem dados"}`,
    );
    return null;
  }
  return (data as ArtworkAdminRow[]).map((row) => ({ ...row, total_count: Number(row.total_count) }));
}

/** Resumo de cobertura — 3 chamadas paralelas de 1 linha cada (só o `total_count`). */
export async function getArtworkCoverage(supabase: SupabaseClient): Promise<ArtworkCoverage | null> {
  const results = await Promise.all(
    (["IMPORTED", "PENDING", "FAILED"] as const).map((status) => listStatus(supabase, status, 1, 0)),
  );
  if (results.some((rows) => rows === null)) return null;
  const [imported, pending, failed] = results.map((rows) => rows?.[0]?.total_count ?? 0) as [number, number, number];
  return { imported, pending, failed, total: imported + pending + failed };
}

export async function getArtworkAdminPage(
  supabase: SupabaseClient,
  filters: { status: ArtworkStatus | null; query: string | null; page: number },
): Promise<{ rows: ArtworkAdminRow[]; total: number } | null> {
  const from = filters.page * ARTWORK_ADMIN_PAGE_SIZE;

  if (!filters.query) {
    const rows = await listStatus(supabase, filters.status, ARTWORK_ADMIN_PAGE_SIZE, from);
    if (!rows) return null;
    return { rows, total: rows[0]?.total_count ?? 0 };
  }

  const all: ArtworkAdminRow[] = [];
  for (let offset = 0; ; offset += RPC_MAX_ROWS) {
    const rows = await listStatus(supabase, filters.status, RPC_MAX_ROWS, offset);
    if (!rows) return null;
    all.push(...rows);
    if (rows.length < RPC_MAX_ROWS) break;
  }
  const query = filters.query;
  const matched = all.filter((row) => matchesArtworkQuery(row, query));
  return { rows: matched.slice(from, from + ARTWORK_ADMIN_PAGE_SIZE), total: matched.length };
}

/** Estado atual de UMA espécie, pela mesma função (ordem nacional contígua 1..N, conferida pelo número). */
export async function getArtworkRow(supabase: SupabaseClient, nationalDexNumber: number): Promise<ArtworkAdminRow | null> {
  const rows = await listStatus(supabase, null, 1, nationalDexNumber - 1);
  const row = rows?.[0];
  return row && row.national_dex_number === nationalDexNumber ? row : null;
}
