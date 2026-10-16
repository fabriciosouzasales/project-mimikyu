import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { PokedexNationalView } from "@/components/pokedex/pokedex-national-view";
import { parseGenerationParam, parseQueryParam, pokedexHref } from "@/lib/pokedex/format";
import {
  POKEDEX_QUERY_MAX_LENGTH,
  getMyPokedexFavorites,
  getPokedexGenerations,
  getPokedexNationalSpecies,
  getPokedexSpeciesTypeIndex,
} from "@/lib/pokedex/queries";
import { parseTypeParam } from "@/lib/pokedex/type-filter";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

/**
 * Página da galeria da Pokédex — compartilhada por `/pokedex` (Pokédex Nacional) e
 * `/pokedex/favoritos` (Pokémons Favoritos, P6). Mesma guarda, mesmas leituras, mesma
 * normalização de URL; a única diferença é o modo da view e a rota base dos links.
 *
 * Acesso (D2): qualquer usuário autenticado; sem acesso anônimo (redireciona para
 * /login). A autorização real está no banco: as funções exigem `auth.uid()` e não
 * existem para `anon`.
 *
 * Estado (pesquisa, geração e tipos) vive na URL — `?q=`, `?geracao=` e `?tipo=`
 * (P5a) —, então a página é compartilhável, funciona com voltar/avançar e é renderizada
 * inteira no servidor. `?tipo=` fora da forma canônica redireciona antes de qualquer
 * leitura.
 *
 * Leituras (todas em paralelo, uma de cada por página — nenhuma por card): gerações e
 * espécies (6131), índice de tipos (6135, opcional) e — P6 — os favoritos do usuário
 * (6137, `get_my_pokedex_favorites`). Sem favoritos (falha), a Pokédex Nacional continua
 * funcionando com os corações desabilitados; a página Favoritos mostra o erro específico.
 */
export async function PokedexGalleryPage({
  searchParams,
  mode,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
  mode: "national" | "favorites";
}) {
  const params = await searchParams;
  const origin = mode === "favorites" ? ("favoritos" as const) : null;
  const query = parseQueryParam(params.q, POKEDEX_QUERY_MAX_LENGTH);
  const generation = parseGenerationParam(params.geracao);
  const typeParam = parseTypeParam(params.tipo);
  const types = typeParam.types;

  // Link editado à mão (`?tipo=fire`, `?tipo=FLYING,FIRE`, código desconhecido, mais de
  // dois): uma URL canônica por resultado, sem custo de leitura.
  if (params.tipo !== undefined && !typeParam.isCanonical) {
    redirect(pokedexHref({ query, generation, types, origin }));
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();

  if (!user) {
    redirect("/login");
  }

  // Mesmo padrão dos guards (diagnóstico P0 de performance): a leitura do
  // perfil usada pelo Header já começa em paralelo com as leituras da página.
  void getCachedUserProfile().catch(() => {});

  const [generations, species, speciesTypes, favorites] = await Promise.all([
    getPokedexGenerations(supabase),
    // Favoritos (UX-01): a geração é filtrada em memória na view, para o filtro compacto
    // contar os favoritos de cada geração — mesma leitura da Pokédex Nacional sem filtro.
    getPokedexNationalSpecies(supabase, { query, generation: mode === "favorites" ? null : generation }),
    getPokedexSpeciesTypeIndex(supabase),
    getMyPokedexFavorites(supabase),
  ]);

  // Geração inexistente num link editado à mão: volta para "todas" em vez de
  // mostrar uma lista vazia sem explicação.
  if (generation !== null && generations && !generations.some((item) => item.generation_ordinal === generation)) {
    redirect(pokedexHref({ query, generation: null, types, origin }));
  }

  return (
    <AppShell title={mode === "favorites" ? "Pokémons Favoritos" : "Pokédex Nacional"} icon={Pokeball}>
      <PokedexNationalView
        generations={generations}
        species={species}
        speciesTypes={speciesTypes}
        query={query}
        generation={generation}
        types={types}
        favorites={favorites}
        mode={mode}
      />
    </AppShell>
  );
}
