import { NextResponse } from "next/server";
import { getPokedexNationalSpecies } from "@/lib/pokedex/queries";
import type { SpeciesIndexEntry } from "@/lib/pokedex/species-search";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * Índice compacto da Pokédex Nacional para a busca rápida da ficha
 * (/pokedex/[numero], Pokédex P3b, 2026-10-12).
 *
 * - Nenhuma função SQL nova: reutiliza `get_pokedex_national_species` (Query
 *   6131/6132) pelo mesmo leitor paginado da galeria, com o client da sessão
 *   (cookies) — nunca `service_role`. A função recusa chamada sem `auth.uid()`;
 *   a verificação abaixo só evita a ida ao banco e devolve 401 limpo.
 * - Sem parâmetros de entrada: nada do cliente chega à consulta.
 * - Corpo mínimo: [número, nome, caminho do WebP 320 | null] — os mesmos dados
 *   que a galeria já entrega a qualquer usuário autenticado; nenhum UUID.
 * - Carregado pelo navegador só quando o usuário demonstra intenção de buscar
 *   (passar o mouse, focar ou abrir), nunca no carregamento da ficha.
 * - Cache privado no navegador (por usuário, nunca em CDN compartilhada).
 */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401, headers: { "Cache-Control": "no-store" } });
  }

  const species = await getPokedexNationalSpecies(supabase, { query: null, generation: null });
  if (!species) {
    return NextResponse.json({ error: "unavailable" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }

  const index: SpeciesIndexEntry[] = species.map((row) => [row.national_dex_number, row.species_name, row.artwork_path ?? null]);

  return NextResponse.json(
    { species: index },
    { headers: { "Cache-Control": "private, max-age=900, stale-while-revalidate=3600" } },
  );
}
