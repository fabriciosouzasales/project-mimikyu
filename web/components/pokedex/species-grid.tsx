import Link from "next/link";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { PRIORITY_ARTWORK_COUNT, speciesArtworkUrl } from "@/lib/pokedex/artwork";
import type { PokedexGeneration, PokedexSpecies } from "@/lib/pokedex/queries";
import { type PokedexContext, formatCount, formatDexNumber, generationLabel, speciesAnchorId, speciesDetailHref } from "@/lib/pokedex/format";

/**
 * Grade da Pokédex Nacional (Pokédex P1), agrupada por geração.
 *
 * Arte (P2 Lote C): quando a função devolve `artwork_path`, a moldura mostra o
 * WebP da espécie (bucket próprio, D1); sem arte ou se a imagem falhar, a
 * moldura neutra com a Pokébola — mesma proporção nos dois casos (sem CLS) e
 * nunca imagem de carta TCG como substituto.
 *
 * Performance: renderizada inteira no servidor (sem JavaScript por item);
 * cada geração usa `content-visibility: auto`, então o navegador só faz
 * layout/paint das gerações que entram na tela — as 1.025 espécies custam o
 * HTML, não o trabalho de renderização.
 */
export function SpeciesGrid({
  species,
  generations,
  context,
}: {
  species: PokedexSpecies[];
  generations: PokedexGeneration[];
  /** Pesquisa/geração atuais — levadas à ficha da espécie e de volta (Pokédex P3b). */
  context: PokedexContext;
}) {
  const regionByCode = new Map(generations.map((generation) => [generation.generation_code, generation]));
  // Posição de cada espécie na grade renderizada — só o topo visível carrega
  // com prioridade; o resto é lazy (e fica fora do paint por content-visibility).
  const positionByNumber = new Map(species.map((item, index) => [item.national_dex_number, index]));
  const groups: { code: string; items: PokedexSpecies[] }[] = [];
  for (const item of species) {
    const current = groups[groups.length - 1];
    if (current && current.code === item.generation_code) current.items.push(item);
    else groups.push({ code: item.generation_code, items: [item] });
  }

  return (
    <div className="space-y-10">
      {groups.map((group) => {
        const generation = regionByCode.get(group.code);
        const headingId = `geracao-${group.code.toLowerCase()}`;
        return (
          <section
            key={group.code}
            aria-labelledby={headingId}
            className="[contain-intrinsic-size:auto_1200px] [content-visibility:auto]"
          >
            <header className="mb-4 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-border/70 pb-3">
              <h3 id={headingId} className="font-heading text-lg font-semibold tracking-tight text-foreground">
                {generationLabel(group.code)}
                {generation?.region_name ? (
                  <span className="font-normal text-muted-foreground"> · {generation.region_name}</span>
                ) : null}
              </h3>
              <p className="text-xs tabular-nums text-muted-foreground">
                {formatCount(group.items.length)} {group.items.length === 1 ? "espécie" : "espécies"}
                {generation?.first_number && generation.last_number ? (
                  <span className="hidden sm:inline">
                    {" "}
                    · Nº {formatDexNumber(generation.first_number)}–{formatDexNumber(generation.last_number)}
                  </span>
                ) : null}
              </p>
            </header>

            <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
              {group.items.map((item) => (
                <SpeciesTile
                  key={item.national_dex_number}
                  species={item}
                  context={context}
                  priority={(positionByNumber.get(item.national_dex_number) ?? Infinity) < PRIORITY_ARTWORK_COUNT}
                />
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

/**
 * Card da espécie — desde a P3b é um link para a ficha (/pokedex/[numero]),
 * levando o contexto da galeria. O `id` do item é a âncora para a qual o
 * "voltar" da ficha rola de volta.
 */
function SpeciesTile({ species, priority, context }: { species: PokedexSpecies; priority: boolean; context: PokedexContext }) {
  const number = formatDexNumber(species.national_dex_number);
  const artworkUrl = speciesArtworkUrl(species.artwork_path);
  return (
    <li id={speciesAnchorId(species.national_dex_number)} className="scroll-mt-6">
      <Link
        href={speciesDetailHref(species.national_dex_number, context)}
        aria-label={`Nº ${number}, ${species.species_name}`}
        className="group flex h-full flex-col overflow-hidden rounded-xl border border-border/80 bg-surface shadow-subtle transition-[transform,border-color,box-shadow] duration-200 ease-out hover:-translate-y-0.5 hover:border-border hover:shadow-panel focus-visible:-translate-y-0.5 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
      >
        <div
          className="relative flex aspect-square items-center justify-center overflow-hidden bg-gradient-to-b from-surface-muted/90 to-surface-muted/30 dark:from-surface-muted/50 dark:to-transparent"
          aria-hidden="true"
        >
          {artworkUrl ? (
            // Arte da espécie (WebP do bucket próprio) — volta à Pokébola se falhar.
            <SpeciesArtwork src={artworkUrl} priority={priority} />
          ) : (
            <>
              <Pokeball className="h-1/3 w-1/3 text-foreground/[0.07] dark:text-foreground/[0.09]" strokeWidth={1.25} />
              <span className="absolute bottom-2 right-3 font-heading text-[28px] font-semibold leading-none tracking-tight tabular-nums text-foreground/[0.06] dark:text-foreground/[0.08]">
                {species.national_dex_number}
              </span>
            </>
          )}
        </div>
        <div className="flex flex-1 flex-col gap-0.5 px-3 pb-3 pt-2.5" aria-hidden="true">
          <span className="text-[11px] font-medium tabular-nums tracking-wide text-muted-foreground">Nº {number}</span>
          <span className="truncate text-sm font-semibold text-foreground" title={species.species_name}>
            {species.species_name}
          </span>
        </div>
      </Link>
    </li>
  );
}
