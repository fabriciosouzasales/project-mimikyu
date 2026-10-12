import { Pokeball } from "@/components/icons/pokeball-icon";
import type { PokedexGeneration, PokedexSpecies } from "@/lib/pokedex/queries";
import { formatCount, formatDexNumber, generationLabel } from "@/lib/pokedex/format";

/**
 * Grade da Pokédex Nacional (Pokédex P1), agrupada por geração.
 *
 * Arte: as imagens oficiais das espécies entram no incremento de importação
 * (D1 — PokéAPI, armazenadas na infraestrutura do MMKYU). Até lá cada
 * espécie ocupa uma moldura de arte neutra, com a mesma proporção que a
 * imagem terá — a troca futura não altera layout (sem CLS) e não usa cartas
 * TCG como substituto (decisão D1).
 *
 * Performance: renderizada inteira no servidor (sem JavaScript por item);
 * cada geração usa `content-visibility: auto`, então o navegador só faz
 * layout/paint das gerações que entram na tela — as 1.025 espécies custam o
 * HTML, não o trabalho de renderização.
 */
export function SpeciesGrid({
  species,
  generations,
}: {
  species: PokedexSpecies[];
  generations: PokedexGeneration[];
}) {
  const regionByCode = new Map(generations.map((generation) => [generation.generation_code, generation]));
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
                <SpeciesTile key={item.national_dex_number} species={item} />
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

function SpeciesTile({ species }: { species: PokedexSpecies }) {
  const number = formatDexNumber(species.national_dex_number);
  return (
    <li>
      <article
        aria-label={`Nº ${number}, ${species.species_name}`}
        className="flex h-full flex-col overflow-hidden rounded-xl border border-border/80 bg-surface shadow-subtle"
      >
        <div
          className="relative flex aspect-square items-center justify-center overflow-hidden bg-gradient-to-b from-surface-muted/90 to-surface-muted/30 dark:from-surface-muted/50 dark:to-transparent"
          aria-hidden="true"
        >
          <Pokeball className="h-1/3 w-1/3 text-foreground/[0.07] dark:text-foreground/[0.09]" strokeWidth={1.25} />
          <span className="absolute bottom-2 right-3 font-heading text-[28px] font-semibold leading-none tracking-tight tabular-nums text-foreground/[0.06] dark:text-foreground/[0.08]">
            {species.national_dex_number}
          </span>
        </div>
        <div className="flex flex-1 flex-col gap-0.5 px-3 pb-3 pt-2.5">
          <span className="text-[11px] font-medium tabular-nums tracking-wide text-muted-foreground">Nº {number}</span>
          <h4 className="truncate text-sm font-semibold text-foreground" title={species.species_name}>
            {species.species_name}
          </h4>
        </div>
      </article>
    </li>
  );
}
