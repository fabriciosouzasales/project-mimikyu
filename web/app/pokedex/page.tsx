import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { PokedexNationalView } from "@/components/pokedex/pokedex-national-view";
import { parseGenerationParam, parseQueryParam } from "@/lib/pokedex/format";
import { POKEDEX_QUERY_MAX_LENGTH, getPokedexGenerations, getPokedexNationalSpecies } from "@/lib/pokedex/queries";
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
 * Estado (pesquisa e geração) vive na URL — `?q=` e `?geracao=` —, então a
 * página é compartilhável, funciona com voltar/avançar do navegador e é
 * renderizada inteira no servidor.
 */
export default async function PokedexPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const query = parseQueryParam(params.q, POKEDEX_QUERY_MAX_LENGTH);
  const generation = parseGenerationParam(params.geracao);

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

  const [generations, species] = await Promise.all([
    getPokedexGenerations(supabase),
    getPokedexNationalSpecies(supabase, { query, generation }),
  ]);

  // Geração inexistente num link editado à mão: volta para "todas" em vez de
  // mostrar uma lista vazia sem explicação.
  if (generation !== null && generations && !generations.some((item) => item.generation_ordinal === generation)) {
    redirect(query ? `/pokedex?q=${encodeURIComponent(query)}` : "/pokedex");
  }

  return (
    <AppShell title="Pokédex Nacional" icon={Pokeball}>
      <PokedexNationalView generations={generations} species={species} query={query} generation={generation} />
    </AppShell>
  );
}
