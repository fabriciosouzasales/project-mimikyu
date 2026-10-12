import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { PokemonTypeChip } from "@/components/pokedex/pokemon-type-chip";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { PokedexLens } from "@/components/pokedex/detail/pokedex-lens";
import { SpeciesKeyboardNav } from "@/components/pokedex/detail/species-keyboard-nav";
import { SpeciesQuickSearch } from "@/components/pokedex/detail/species-quick-search";
import { cn } from "@/lib/utils";
import { speciesArtworkUrl, speciesOriginalArtworkUrl } from "@/lib/pokedex/artwork";
import type { PokedexSpeciesDetail, SpeciesHeroArtwork } from "@/lib/pokedex/detail";
import {
  type PokedexContext,
  formatDexNumber,
  formatMeasure,
  languageName,
  nationalPokedexHref,
  sourceVersionLabel,
  speciesDetailHref,
} from "@/lib/pokedex/format";
import { pokemonTypeStyle } from "@/lib/pokedex/type-palette";
import styles from "./species-detail.module.css";

export type SpeciesNeighbor = { national_dex_number: number; species_name: string; artwork_path: string | null };

/** Idioma da página — textos em outro idioma ganham `lang` próprio e a nota de origem. */
const PAGE_LANGUAGE = "pt-BR";
/** Acima disto o nome usa a escala menor (Crabominable, Squawkabilly...). */
const LONG_NAME_LENGTH = 10;

/**
 * Página de detalhes da espécie — "palco" (Pokédex P3b, 2026-10-12).
 *
 * Server Component: todo o conteúdo chega renderizado; as únicas ilhas
 * cliente são a arte (estado de carregamento/fallback) e os atalhos de
 * teclado. Composição aprovada: arte protagonista no centro, número nacional
 * em contorno e anel da Pokédex atrás, luz do tipo primário (e do secundário),
 * identidade abaixo, medidas como anotações do palco no desktop e numa folha
 * de informações no mobile.
 */
export function SpeciesDetailView({
  species,
  hero,
  previous,
  next,
  total,
  context,
}: {
  species: PokedexSpeciesDetail;
  hero: SpeciesHeroArtwork | null;
  previous: SpeciesNeighbor | null;
  next: SpeciesNeighbor | null;
  total: number | null;
  context: PokedexContext;
}) {
  const number = formatDexNumber(species.national_dex_number);
  const primary = species.profile_available ? species.primary_type_code : null;
  const secondary = species.profile_available ? species.secondary_type_code : null;
  const stageStyle = { ...pokemonTypeStyle(primary, "t1"), ...pokemonTypeStyle(secondary ?? primary, "t2") };

  const displayUrl = speciesArtworkUrl(species.artwork_path);
  const originalUrl = speciesOriginalArtworkUrl(hero?.originalPath);
  const originalWidth = hero?.originalWidth ?? 475;
  const srcSet = displayUrl && originalUrl ? `${displayUrl} 320w, ${originalUrl} ${originalWidth}w` : undefined;

  const prevHref = previous ? speciesDetailHref(previous.national_dex_number, context) : null;
  const nextHref = next ? speciesDetailHref(next.national_dex_number, context) : null;
  const backHref = nationalPokedexHref(context, species.national_dex_number);

  const flags = [
    species.is_legendary ? "Lendário" : null,
    species.is_mythical ? "Mítico" : null,
    species.is_baby ? "Bebê" : null,
  ].filter((flag): flag is string => flag !== null);

  const hasMeasures = species.height_m !== null && species.weight_kg !== null;
  const height = species.height_m !== null ? `${formatMeasure(species.height_m)} m` : null;
  const weight = species.weight_kg !== null ? `${formatMeasure(species.weight_kg)} kg` : null;
  const generation = species.generation_ordinal;
  const descriptionLang = species.description_language ?? PAGE_LANGUAGE;
  const genusLang = species.genus_language ?? PAGE_LANGUAGE;
  const sourceNote = buildSourceNote(species);

  return (
    <section className={styles.stage} style={stageStyle} aria-labelledby="especie-nome">
      <SpeciesKeyboardNav prevHref={prevHref} nextHref={nextHref} />

      <div className={styles.topbar}>
        <Link href={backHref} className={styles.back}>
          <ChevronLeft className="h-4 w-4" aria-hidden="true" />
          Pokédex Nacional
        </Link>
        <div className={styles.position}>
          <span className="hidden items-center gap-1 sm:inline-flex" aria-hidden="true">
            <span className={styles.kbd}>←</span>
            <span className={styles.kbd}>→</span>
          </span>
          <SpeciesQuickSearch current={species.national_dex_number} total={total} context={context} />
        </div>
      </div>

      <div className={styles.heroRow}>
        {previous && prevHref ? (
          <NeighborLink neighbor={previous} href={prevHref} direction="previous" className={cn(styles.neighborDesktop, styles.neighborPrev)} />
        ) : (
          <span aria-hidden="true" />
        )}

        <div className={styles.artZone}>
          <span className={styles.numeral} aria-hidden="true">
            {number}
          </span>
          <PokedexLens className={styles.lens} />
          <span className={styles.floor} aria-hidden="true" />
          <div className={styles.artFrame}>
            {displayUrl ? (
              <SpeciesArtwork
                src={displayUrl}
                srcSet={srcSet}
                sizes="(min-width: 1024px) 440px, (min-width: 640px) 336px, 300px"
                width={originalUrl ? originalWidth : 320}
                height={originalUrl ? originalWidth : 320}
                alt={`Arte oficial de ${species.species_name}`}
                priority
                className={styles.art}
                fallbackClassName={styles.artFallback}
              />
            ) : (
              <Pokeball className={styles.artFallback} strokeWidth={1.1} role="img" aria-label={`${species.species_name}: arte indisponível`} />
            )}
          </div>

          {hasMeasures ? (
            <>
              <div className={cn(styles.callout, styles.calloutLeft)}>
                <span className={styles.measureValue}>{height}</span>
                <span className={styles.measureLabel}>Altura</span>
              </div>
              <div className={cn(styles.callout, styles.calloutRight)}>
                <span className={styles.measureValue}>{weight}</span>
                <span className={styles.measureLabel}>Peso</span>
              </div>
            </>
          ) : null}
        </div>

        {next && nextHref ? (
          <NeighborLink neighbor={next} href={nextHref} direction="next" className={cn(styles.neighborDesktop, styles.neighborNext)} />
        ) : (
          <span aria-hidden="true" />
        )}
      </div>

      <div className={styles.identity}>
        <p className={styles.meta}>
          <span>Nº {number}</span>
          <span className={styles.metaDot} aria-hidden="true" />
          <span>
            {species.region_name ? `${species.region_name}, ` : ""}
            {generation}ª geração
          </span>
          {flags.map((flag) => (
            <span key={flag} className={styles.flag}>
              {flag}
            </span>
          ))}
        </p>
        <h1 id="especie-nome" className={cn(styles.name, species.species_name.length > LONG_NAME_LENGTH && styles.nameLong)}>
          {species.species_name}
        </h1>
        {species.genus ? (
          <p className={styles.genus} lang={genusLang !== PAGE_LANGUAGE ? genusLang : undefined}>
            {species.genus}
          </p>
        ) : null}
        {primary && species.primary_type_label ? (
          <div className={styles.chips} role="list" aria-label="Tipos">
            <span role="listitem">
              <PokemonTypeChip code={primary} label={species.primary_type_label} slot="t1" />
            </span>
            {secondary && species.secondary_type_label ? (
              <span role="listitem">
                <PokemonTypeChip code={secondary} label={species.secondary_type_label} slot="t2" />
              </span>
            ) : null}
          </div>
        ) : null}
      </div>

      <div className={styles.sheet}>
        {hasMeasures ? (
          <dl className={styles.measuresMobile}>
            <div>
              <dt className={styles.measureLabel}>Altura</dt>
              <dd className={styles.measureValue}>{height}</dd>
            </div>
            <div>
              <dt className={styles.measureLabel}>Peso</dt>
              <dd className={styles.measureValue}>{weight}</dd>
            </div>
            <div>
              <dt className={styles.measureLabel}>{species.region_name ? `${generation}ª geração` : "Geração"}</dt>
              <dd className={styles.measureValue}>{species.region_name ?? `${generation}ª`}</dd>
            </div>
          </dl>
        ) : null}

        {species.description ? (
          <>
            <p className={styles.description} lang={descriptionLang !== PAGE_LANGUAGE ? descriptionLang : undefined}>
              {species.description}
            </p>
            {sourceNote ? <p className={styles.note}>{sourceNote}</p> : null}
          </>
        ) : !species.profile_available ? (
          <p className={styles.note}>Os dados de referência desta espécie ainda não foram carregados.</p>
        ) : null}

        <div className={styles.neighborMobileRow}>
          {previous && prevHref ? <NeighborLink neighbor={previous} href={prevHref} direction="previous" /> : <span aria-hidden="true" />}
          {next && nextHref ? <NeighborLink neighbor={next} href={nextHref} direction="next" className={styles.neighborNext} /> : null}
        </div>

        <p className={styles.credit}>Arte e textos © Nintendo, Creatures, GAME FREAK, The Pokémon Company.</p>
      </div>
    </section>
  );
}

function NeighborLink({
  neighbor,
  href,
  direction,
  className,
}: {
  neighbor: SpeciesNeighbor;
  href: string;
  direction: "previous" | "next";
  className?: string;
}) {
  const number = formatDexNumber(neighbor.national_dex_number);
  const thumb = speciesArtworkUrl(neighbor.artwork_path);
  const label = direction === "previous" ? "Anterior" : "Próximo";
  const round = (
    <span className={styles.neighborRound} aria-hidden="true">
      {thumb ? (
        // eslint-disable-next-line @next/next/no-img-element -- WebP 320 já otimizado, URL imutável
        <img src={thumb} alt="" width={36} height={36} loading="lazy" decoding="async" className={styles.neighborThumb} />
      ) : direction === "previous" ? (
        <ChevronLeft className="h-4 w-4" />
      ) : (
        <ChevronRight className="h-4 w-4" />
      )}
    </span>
  );
  return (
    <Link
      href={href}
      rel={direction === "previous" ? "prev" : "next"}
      aria-label={`${label}: Nº ${number}, ${neighbor.species_name}`}
      className={cn(styles.neighbor, className)}
    >
      {direction === "previous" ? round : null}
      <span className={styles.neighborText}>
        <small>
          {direction === "previous" ? "← " : null}
          {label}
          {direction === "next" ? " →" : null}
        </small>
        <strong>
          <span className={styles.neighborNumber}>{number}</span>
          {neighbor.species_name}
        </strong>
      </span>
      {direction === "next" ? round : null}
    </Link>
  );
}

function buildSourceNote(species: PokedexSpeciesDetail): string | null {
  const version = sourceVersionLabel(species.description_source_version);
  const official = species.description_is_official !== false;
  const genusForeign = !!species.genus_language && species.genus_language !== PAGE_LANGUAGE;
  const descriptionForeign = !!species.description_language && species.description_language !== PAGE_LANGUAGE;
  const from = version ? `, de ${version}` : "";

  if (!genusForeign && !descriptionForeign) {
    return version && official ? `Descrição oficial de ${version}.` : null;
  }
  const language = languageName(descriptionForeign ? species.description_language : species.genus_language);
  if (genusForeign && descriptionForeign) {
    return `Classificação e descrição ${official ? "oficiais " : ""}em ${language}${from}.`;
  }
  if (descriptionForeign) {
    return `Descrição ${official ? "oficial " : ""}em ${language}${from}.`;
  }
  return `Classificação ${species.genus_is_official !== false ? "oficial " : ""}em ${language}.`;
}
