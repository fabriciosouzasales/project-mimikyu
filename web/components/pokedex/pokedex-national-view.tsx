import Link from "next/link";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Alert } from "@/components/ui/alert";
import { GenerationFilter } from "@/components/pokedex/generation-filter";
import { PokedexSearch } from "@/components/pokedex/pokedex-search";
import { SpeciesGrid } from "@/components/pokedex/species-grid";
import { formatCount, generationLabel } from "@/lib/pokedex/format";
import { POKEDEX_QUERY_MAX_LENGTH, type PokedexGeneration, type PokedexSpecies } from "@/lib/pokedex/queries";

/**
 * Pokédex Nacional (Pokédex P1, 2026-10-12) — composição da página:
 * cabeçalho do módulo com a pesquisa, filtro por geração, linha de
 * resultado e a grade. Server Component; a única ilha cliente é a pesquisa.
 */
export function PokedexNationalView({
  generations,
  species,
  query,
  generation,
}: {
  generations: PokedexGeneration[] | null;
  species: PokedexSpecies[] | null;
  query: string | null;
  generation: number | null;
}) {
  const totalSpecies = generations?.reduce((sum, item) => sum + item.species_count, 0) ?? 0;
  const firstRegion = generations?.[0]?.region_name;
  const lastRegion = generations?.[generations.length - 1]?.region_name;
  const activeGeneration = generations?.find((item) => item.generation_ordinal === generation) ?? null;
  const isFiltered = query !== null || activeGeneration !== null;

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <section className="relative overflow-hidden rounded-xl border border-border bg-surface p-5 shadow-subtle sm:p-6">
        <Pokeball
          className="pointer-events-none absolute -right-10 -top-12 h-56 w-56 text-primary/[0.08]"
          strokeWidth={1}
          aria-hidden="true"
        />
        <div className="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
          <div className="space-y-1.5">
            <p className="text-[11px] font-medium uppercase tracking-[0.08em] text-primary-ink">Explorar</p>
            <h2 className="font-heading text-2xl font-semibold tracking-tight text-foreground sm:text-[28px]">
              Pokédex Nacional
            </h2>
            {generations ? (
              <p className="max-w-xl text-sm text-muted-foreground">
                {formatCount(totalSpecies)} espécies em {generations.length} gerações
                {firstRegion && lastRegion ? `, de ${firstRegion} a ${lastRegion}` : ""}.
              </p>
            ) : null}
          </div>
          <div className="w-full lg:max-w-sm">
            <PokedexSearch initialQuery={query} generation={activeGeneration ? generation : null} maxLength={POKEDEX_QUERY_MAX_LENGTH} />
          </div>
        </div>
      </section>

      {generations ? (
        <GenerationFilter
          generations={generations}
          activeGeneration={activeGeneration ? generation : null}
          query={query}
          totalSpecies={totalSpecies}
        />
      ) : null}

      {species === null || generations === null ? (
        <Alert variant="destructive">
          <p className="font-medium">Não foi possível carregar a Pokédex agora.</p>
          <p className="mt-1 text-sm opacity-90">
            Isso costuma ser passageiro.{" "}
            <Link href={currentHref(query, generation)} className="font-medium underline underline-offset-2">
              Tentar novamente
            </Link>
          </p>
        </Alert>
      ) : species.length === 0 ? (
        <EmptyResult query={query} activeGeneration={activeGeneration} />
      ) : (
        <>
          <p className="text-sm text-muted-foreground" aria-live="polite">
            {isFiltered ? (
              <>
                <span className="font-medium tabular-nums text-foreground">{formatCount(species.length)}</span>{" "}
                {species.length === 1 ? "espécie encontrada" : "espécies encontradas"}
                {query ? <> para “{query}”</> : null}
                {activeGeneration ? <> em {generationLabel(activeGeneration.generation_code)}</> : null}
              </>
            ) : (
              <>
                Todas as <span className="font-medium tabular-nums text-foreground">{formatCount(species.length)}</span> espécies, em
                ordem de número nacional.
              </>
            )}
          </p>
          <SpeciesGrid species={species} generations={generations} context={{ query, generation: activeGeneration ? generation : null }} />
        </>
      )}
    </div>
  );
}

function EmptyResult({ query, activeGeneration }: { query: string | null; activeGeneration: PokedexGeneration | null }) {
  return (
    <div
      className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border px-6 py-14 text-center"
      aria-live="polite"
    >
      <Pokeball className="h-10 w-10 text-muted-foreground/50" strokeWidth={1.5} aria-hidden="true" />
      <div className="space-y-1">
        <p className="text-base font-medium text-foreground">Nenhum Pokémon encontrado</p>
        <p className="max-w-md text-sm text-muted-foreground">
          {query ? <>Nada corresponde a “{query}”{activeGeneration ? ` em ${generationLabel(activeGeneration.generation_code)}` : ""}. </> : null}
          Confira a grafia ou pesquise pelo número nacional, como 25 ou #0025.
        </p>
      </div>
      <div className="flex flex-wrap justify-center gap-x-4 gap-y-1 text-sm">
        <Link href={currentHref(null, activeGeneration?.generation_ordinal ?? null)} className="font-medium text-primary-ink underline-offset-2 hover:underline">
          Limpar pesquisa
        </Link>
        {activeGeneration ? (
          <Link href={currentHref(query, null)} className="font-medium text-primary-ink underline-offset-2 hover:underline">
            Pesquisar em todas as gerações
          </Link>
        ) : null}
      </div>
    </div>
  );
}

function currentHref(query: string | null, generation: number | null): string {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  if (generation) params.set("geracao", String(generation));
  const search = params.toString();
  return search ? `/pokedex?${search}` : "/pokedex";
}
