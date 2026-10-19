import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { cache } from "react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesDetailView } from "@/components/pokedex/detail/species-detail-view";
import { Alert } from "@/components/ui/alert";
import {
  getPokedexSpeciesDetail,
  getPokedexSpeciesHeroArtwork,
  getPokedexSpeciesOriginalText,
  type SpeciesDetailResult,
} from "@/lib/pokedex/detail";
import { needsOriginalText } from "@/lib/pokedex/description-presentation";
import {
  nationalPokedexHref,
  parseGenerationParam,
  parseNationalNumberParam,
  parseOriginParam,
  parseQueryParam,
  speciesDetailHref,
} from "@/lib/pokedex/format";
import { type NavigationSpecies, isGenerationContextMismatch, resolveSpeciesNavigation } from "@/lib/pokedex/navigation";
import { POKEDEX_QUERY_MAX_LENGTH, getMyPokedexFavorites, getPokedexGenerations } from "@/lib/pokedex/queries";
import { parseTypeParam } from "@/lib/pokedex/type-filter";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

/**
 * Página de detalhes da espécie — /pokedex/[numero] (Pokédex P3b, 2026-10-12).
 *
 * Acesso: qualquer usuário autenticado (mesma guarda da Pokédex Nacional); a
 * autorização real está no banco — as funções exigem auth.uid() e não existem
 * para anon. Nenhuma chamada à PokéAPI: tudo vem das Queries 6131/6133 (e 6134,
 * opcional, para o PNG original do palco).
 *
 * Contexto da galeria (`?q=`, `?geracao=`) é validado com os mesmos parsers da
 * Pokédex Nacional e repassado ao "voltar" e aos vizinhos — navegar entre
 * espécies não perde a pesquisa de origem.
 *
 * Pokédex P4a (2026-10-13): com `?geracao=`, anterior/próximo ficam dentro da
 * geração e a fronteira vira uma transição explícita para a próxima geração
 * (lib/pokedex/navigation.ts). Uma `?geracao=` que não corresponde à espécie
 * (link antigo, editado à mão ou busca rápida para outra geração) redireciona
 * para o contexto nacional, mantendo a pesquisa — o "voltar" nunca procura uma
 * espécie fora da geração filtrada. Nenhuma leitura nova: os vizinhos ±1 já
 * eram lidos e trazem a geração.
 *
 * Pokédex P5a (2026-10-14): `?tipo=` também é contexto — normalizado com o mesmo
 * parser da galeria e repassado ao "voltar", aos vizinhos e à busca rápida, para que
 * o filtro sobreviva à ida e volta. Anterior/próximo não são restringidos por tipo
 * (seguem a regra nacional/de geração); se a espécie aberta não tem os tipos do
 * filtro, o "voltar" volta à galeria filtrada sem âncora (a espécie não está lá).
 *
 * Pokédex P6 (2026-10-15): `?origem=favoritos` é contexto — a ficha aberta a partir da
 * página Pokémon Favoritos volta para ela (com pesquisa, geração e tipos), e os vizinhos
 * e a busca rápida mantêm a origem. Anterior/próximo NÃO são restringidos a favoritos:
 * seguem a regra nacional/de geração da P4a, como já acontece com o filtro por tipo. O
 * coração da ficha usa a mesma leitura agregada da galeria (`get_my_pokedex_favorites`,
 * em paralelo com as demais) — nenhuma consulta por espécie nova.
 */

type Params = Promise<{ numero: string }>;
type SearchParams = Promise<Record<string, string | string[] | undefined>>;

/** Mesma leitura usada pelo título e pela página — uma chamada por requisição. */
const loadSpeciesDetail = cache(async (nationalDexNumber: number): Promise<SpeciesDetailResult> => {
  const supabase = await createClient();
  return getPokedexSpeciesDetail(supabase, nationalDexNumber);
});

export async function generateMetadata({ params }: { params: Params }): Promise<Metadata> {
  const { numero } = await params;
  const nationalDexNumber = parseNationalNumberParam(numero);
  if (nationalDexNumber === null) return { title: "Pokédex" };
  const result = await loadSpeciesDetail(nationalDexNumber);
  return { title: result.status === "ok" ? `${result.species.species_name} · Pokédex` : "Pokédex" };
}

export default async function PokedexSpeciesPage({ params, searchParams }: { params: Params; searchParams: SearchParams }) {
  const [{ numero }, query] = await Promise.all([params, searchParams]);
  const nationalDexNumber = parseNationalNumberParam(numero);
  if (nationalDexNumber === null) notFound();

  const context = {
    query: parseQueryParam(query.q, POKEDEX_QUERY_MAX_LENGTH),
    generation: parseGenerationParam(query.geracao),
    types: parseTypeParam(query.tipo).types,
    origin: parseOriginParam(query.origem),
  };

  // URL canônica: /pokedex/0025 -> /pokedex/25 (mesmo contexto).
  if (numero !== String(nationalDexNumber)) {
    redirect(speciesDetailHref(nationalDexNumber, context));
  }

  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");
  void getCachedUserProfile().catch(() => {});

  const supabase = await createClient();
  // Texto oficial em inglês só quando a ficha veio com descrição editorial pt-BR
  // (P3d): a leitura `en` começa assim que a ficha chega, em paralelo com as
  // demais — sem custo para espécies sem conteúdo editorial.
  const detailPromise = loadSpeciesDetail(nationalDexNumber);
  const originalPromise = detailPromise.then((detail) =>
    detail.status === "ok" && needsOriginalText(detail.species)
      ? getPokedexSpeciesOriginalText(supabase, nationalDexNumber)
      : null,
  );
  const [result, original, hero, previous, next, generations, favorites] = await Promise.all([
    detailPromise,
    originalPromise,
    getPokedexSpeciesHeroArtwork(supabase, nationalDexNumber),
    nationalDexNumber > 1 ? getPokedexSpeciesDetail(supabase, nationalDexNumber - 1) : Promise.resolve(null),
    getPokedexSpeciesDetail(supabase, nationalDexNumber + 1),
    getPokedexGenerations(supabase),
    getMyPokedexFavorites(supabase),
  ]);

  if (result.status === "not_found") notFound();

  if (result.status === "ok" && isGenerationContextMismatch(context, result.species.generation_ordinal)) {
    redirect(speciesDetailHref(nationalDexNumber, { ...context, generation: null }));
  }

  if (result.status === "error") {
    return (
      <AppShell title="Pokédex" icon={Pokeball}>
        <div className="mx-auto max-w-xl space-y-4 pt-6">
          <Alert variant="destructive">
            <p className="font-medium">Não foi possível carregar esta espécie agora.</p>
            <p className="mt-1 text-sm opacity-90">
              Isso costuma ser passageiro.{" "}
              <Link href={speciesDetailHref(nationalDexNumber, context)} className="font-medium underline underline-offset-2">
                Tentar novamente
              </Link>
            </p>
          </Alert>
          <Link href={nationalPokedexHref(context)} className="inline-block text-sm font-medium text-primary-ink underline-offset-2 hover:underline">
            {context.origin === "favoritos" ? "Voltar para Pokémon Favoritos" : "Voltar para a Pokédex Nacional"}
          </Link>
        </div>
      </AppShell>
    );
  }

  const total = generations?.reduce((sum, item) => sum + item.species_count, 0) ?? null;
  const navigation = resolveSpeciesNavigation({
    current: result.species,
    previous: toNavigationSpecies(previous),
    next: toNavigationSpecies(next),
    context,
  });

  return (
    <AppShell title="Pokédex" icon={Pokeball}>
      <SpeciesDetailView
        species={result.species}
        original={original}
        hero={hero}
        previous={navigation.previous}
        next={navigation.next}
        nextGeneration={navigation.nextGeneration}
        total={total}
        context={context}
        isFavorite={favorites?.has(nationalDexNumber) ?? false}
        favoritesAvailable={favorites !== null}
      />
    </AppShell>
  );
}

function toNavigationSpecies(result: SpeciesDetailResult | null): NavigationSpecies | null {
  if (!result || result.status !== "ok") return null;
  const { national_dex_number, species_name, artwork_path, generation_ordinal, generation_code, region_name } = result.species;
  return { national_dex_number, species_name, artwork_path, generation_ordinal, generation_code, region_name };
}
