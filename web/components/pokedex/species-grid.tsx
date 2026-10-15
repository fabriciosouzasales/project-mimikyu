import Link from "next/link";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { PokemonTypeSprite, PokemonTypeStyles, pokemonTypeSymbolId } from "@/components/pokedex/pokemon-type-assets";
import { RecentSpeciesMarker } from "@/components/pokedex/recent-species-marker";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { PRIORITY_ARTWORK_COUNT, speciesArtworkUrl } from "@/lib/pokedex/artwork";
import type { PokedexGeneration, PokedexSpecies, PokedexSpeciesTypes } from "@/lib/pokedex/queries";
import {
  type PokedexContext,
  formatCount,
  formatDexNumber,
  generationRoman,
  speciesAnchorId,
  speciesDetailHref,
} from "@/lib/pokedex/format";
import styles from "./species-grid.module.css";

/**
 * Grade da Pokédex Nacional (Pokédex P1; visual premium P3c, 2026-10-12), agrupada
 * por geração na ordem nacional.
 *
 * Cada card é uma pequena "prancha" da espécie: herda da ficha só a luz do tipo
 * primário, o número nacional em contorno e o chão sob a arte — sem lente, callouts
 * ou animação de entrada (o palco cinematográfico continua exclusivo da ficha).
 *
 * Performance (1.025 cards):
 * - renderizada inteira no servidor; o card não tem JavaScript próprio além da arte
 *   (fade-in/fallback, já existente);
 * - cores de tipo por `data-t1`/`data-t2` + 36 regras únicas (PokemonTypeStyles) e
 *   ícones por `<use>` de um sprite único — nada de estilo inline ou SVG por chip;
 * - luz do card = gradientes estáticos; hover só com transform/opacity;
 * - WebP 320 com prioridade só nas primeiras imagens, o resto lazy;
 * - proporção fixa da área da arte (sem layout shift) e `content-visibility` por
 *   geração (o navegador só faz layout/paint das gerações visíveis).
 */
export function SpeciesGrid({
  species,
  generations,
  speciesTypes,
  context,
}: {
  species: PokedexSpecies[];
  generations: PokedexGeneration[];
  /** Tipos por número nacional (Query 6135). `null` = indisponível: cards no tom neutro. */
  speciesTypes: Map<number, PokedexSpeciesTypes> | null;
  /** Pesquisa/geração atuais — levadas à ficha da espécie e de volta (Pokédex P3b). */
  context: PokedexContext;
}) {
  const generationByCode = new Map(generations.map((generation) => [generation.generation_code, generation]));
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
    <div className={styles.root} data-pk-types="">
      <PokemonTypeStyles />
      <PokemonTypeSprite />
      <RecentSpeciesMarker />
      {groups.map((group) => {
        const generation = generationByCode.get(group.code);
        const headingId = `geracao-${group.code.toLowerCase()}`;
        const roman = generationRoman(group.code);
        return (
          <section key={group.code} aria-labelledby={headingId} className={styles.section} data-generation={group.code}>
            <header className={styles.sectionHeader}>
              <span className={styles.roman} aria-hidden="true">
                {roman}
              </span>
              <div className={styles.sectionTitle}>
                <h3 id={headingId}>
                  <span className="sr-only">Geração {roman}, </span>
                  {generation?.region_name ?? `Geração ${roman}`}
                </h3>
                <p>
                  Geração {roman}
                  {generation?.first_number && generation.last_number ? (
                    <>
                      , Nº {formatDexNumber(generation.first_number)} a {formatDexNumber(generation.last_number)}
                    </>
                  ) : null}
                  , {formatCount(group.items.length)} {group.items.length === 1 ? "espécie" : "espécies"}
                </p>
              </div>
            </header>

            <ul className={styles.grid}>
              {group.items.map((item) => (
                <SpeciesTile
                  key={item.national_dex_number}
                  species={item}
                  types={speciesTypes?.get(item.national_dex_number) ?? null}
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
 * Card da espécie — link para a ficha (/pokedex/[numero]) levando o contexto da
 * galeria. O `id` do item é a âncora para a qual o "voltar" da ficha rola de volta;
 * o RecentSpeciesMarker marca esse card como "Última ficha" só quando a âncora
 * existe na URL.
 */
function SpeciesTile({
  species,
  types,
  priority,
  context,
}: {
  species: PokedexSpecies;
  types: PokedexSpeciesTypes | null;
  priority: boolean;
  context: PokedexContext;
}) {
  const number = formatDexNumber(species.national_dex_number);
  const artworkUrl = speciesArtworkUrl(species.artwork_path);
  const typeText = types ? (types.secondaryLabel ? `${types.primaryLabel} e ${types.secondaryLabel}` : types.primaryLabel) : null;

  return (
    <li id={speciesAnchorId(species.national_dex_number)} className={styles.item}>
      <Link
        href={speciesDetailHref(species.national_dex_number, context)}
        aria-label={`Nº ${number}, ${species.species_name}${typeText ? `, ${typeText}` : ""}`}
        className={styles.card}
        data-t1={types?.primaryCode}
        data-t2={types?.secondaryCode ?? undefined}
      >
        <span className={styles.plate} aria-hidden="true">
          <span className={styles.number}>{number}</span>
          <span className={styles.floor} />
          <span className={styles.art}>
            {artworkUrl ? (
              // Arte da espécie (WebP 320 do bucket próprio) — volta à Pokébola se falhar.
              <SpeciesArtwork
                src={artworkUrl}
                priority={priority}
                className={styles.artImage}
                fallbackClassName={styles.fallback}
              />
            ) : (
              <Pokeball className={styles.fallback} strokeWidth={1.25} />
            )}
          </span>
        </span>
        <span className={styles.meta} aria-hidden="true">
          <span className={styles.name} title={species.species_name}>
            {species.species_name}
          </span>
          {types ? (
            <span className={styles.types}>
              <TypeChip code={types.primaryCode} label={types.primaryLabel} />
              {types.secondaryCode && types.secondaryLabel ? (
                <TypeChip code={types.secondaryCode} label={types.secondaryLabel} secondary />
              ) : null}
            </span>
          ) : null}
        </span>
      </Link>
    </li>
  );
}

function TypeChip({ code, label, secondary = false }: { code: string; label: string; secondary?: boolean }) {
  return (
    <span className={secondary ? `${styles.chip} ${styles.chipSecondary}` : styles.chip}>
      <svg className={styles.chipIcon} aria-hidden="true" focusable="false">
        <use href={`#${pokemonTypeSymbolId(code)}`} />
      </svg>
      {label}
    </span>
  );
}
