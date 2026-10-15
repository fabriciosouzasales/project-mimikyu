import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { PokedexNationalView } from "@/components/pokedex/pokedex-national-view";
import { parseGenerationParam, parseQueryParam, pokedexHref } from "@/lib/pokedex/format";
import {
  POKEDEX_QUERY_MAX_LENGTH,
  getPokedexGenerations,
  getPokedexNationalSpecies,
  getPokedexSpeciesTypeIndex,
} from "@/lib/pokedex/queries";
import { parseTypeParam } from "@/lib/pokedex/type-filter";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

/**
 * Pokédex Nacional — entrada do módulo Pokédex (Pokédex P1, 2026-10-12).
 *
 * Acesso (D2): qualquer usuário autenticado; sem acesso anônimo. Mesma
 * guarda simples de `/pesquisa` (sessão obrigatória, redireciona para
 * /login). A autorização real está no banco: as funções da Query 6131
 * recusam chamada sem `auth.uid()` e não existem para `anon`.
 *
 * Estado (pesquisa, geração e tipos) vive na URL — `?q=`, `?geracao=` e
 * `?tipo=` (P5a) —, então a página é compartilhável, funciona com
 * voltar/avançar do navegador e é renderizada inteira no servidor.
 *
 * Pokédex P5a (2026-10-14): `?tipo=` é normalizado (códigos válidos, sem repetição,
 * ordem oficial, no máximo dois); qualquer outra forma redireciona para a canônica
 * antes de qualquer leitura. O filtro é aplicado sobre as leituras que a página já
 * faz (6131 + índice de tipos 6135) — nenhuma consulta nova.
 */
export default async function PokedexPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const query = parseQueryParam(params.q, POKEDEX_QUERY_MAX_LENGTH);
  const generation = parseGenerationParam(params.geracao);
  const typeParam = parseTypeParam(params.tipo);
  const types = typeParam.types;

  // Link editado à mão (`?tipo=fire`, `?tipo=FLYING,FIRE`, código desconhecido, mais de
  // dois): uma URL canônica por resultado, sem custo de leitura.
  if (params.tipo !== undefined && !typeParam.isCanonical) {
    redirect(pokedexHref({ query, generation, types }));
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

  // Tipos (Query 6135) em paralelo, numa leitura em lote; opcionais — sem eles os
  // cards ficam no tom neutro (Pokédex P3c).
  const [generations, species, speciesTypes] = await Promise.all([
    getPokedexGenerations(supabase),
    getPokedexNationalSpecies(supabase, { query, generation }),
    getPokedexSpeciesTypeIndex(supabase),
  ]);

  // Geração inexistente num link editado à mão: volta para "todas" em vez de
  // mostrar uma lista vazia sem explicação.
  if (generation !== null && generations && !generations.some((item) => item.generation_ordinal === generation)) {
    redirect(pokedexHref({ query, generation: null, types }));
  }

  return (
    <AppShell title="Pokédex Nacional" icon={Pokeball}>
      <PokedexNationalView
        generations={generations}
        species={species}
        speciesTypes={speciesTypes}
        query={query}
        generation={generation}
        types={types}
      />
    </AppShell>
  );
}
