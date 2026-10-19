import Link from "next/link";
import type { PokedexGeneration } from "@/lib/pokedex/queries";
import { type PokedexOrigin, formatCount, generationRoman, pokedexHref } from "@/lib/pokedex/format";
import styles from "./generation-filter.module.css";

/**
 * Filtro por geração da Pokédex Nacional (Pokédex P1; régua premium P3c, 2026-10-12).
 *
 * Links simples (servidor, sem JavaScript), preservando a pesquisa e os tipos (P5a) atuais. No desktop
 * é uma régua: a largura de cada geração é proporcional ao número de espécies — a
 * própria régua mostra o tamanho de cada região. Em telas estreitas vira uma faixa
 * de pílulas com rolagem horizontal. Ativo em dourado (aria-current="page").
 */
export function GenerationFilter({
  generations,
  activeGeneration,
  query,
  types,
  totalSpecies,
  origin = null,
}: {
  generations: PokedexGeneration[];
  activeGeneration: number | null;
  query: string | null;
  types: readonly string[];
  totalSpecies: number;
  /** P6: na página Pokémon Favoritos, a régua fica dentro dela. */
  origin?: PokedexOrigin | null;
}) {
  function hrefFor(generation: number | null) {
    return pokedexHref({ query, generation, types, origin });
  }

  return (
    <nav aria-label="Filtrar por geração" className={styles.nav} data-pk-generation-nav="">
      <ul className={styles.track}>
        <li className={styles.all}>
          <Segment
            href={hrefFor(null)}
            active={activeGeneration === null}
            eyebrow="Todas"
            title="Nacional"
            detail={formatCount(totalSpecies)}
            label={`Todas as gerações, ${formatCount(totalSpecies)} espécies`}
          />
        </li>
        {generations.map((generation) => {
          const roman = generationRoman(generation.generation_code);
          return (
            <li key={generation.generation_code} className={styles.segment} style={{ flexGrow: Math.max(generation.species_count, 1) }}>
              <Segment
                href={hrefFor(generation.generation_ordinal)}
                active={activeGeneration === generation.generation_ordinal}
                eyebrow={roman}
                title={generation.region_name ?? `Geração ${roman}`}
                detail={formatCount(generation.species_count)}
                label={`Geração ${roman}${generation.region_name ? `, ${generation.region_name}` : ""}, ${formatCount(
                  generation.species_count,
                )} espécies`}
              />
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function Segment({
  href,
  active,
  eyebrow,
  title,
  detail,
  label,
}: {
  href: string;
  active: boolean;
  eyebrow: string;
  title: string;
  detail: string;
  label: string;
}) {
  return (
    <Link href={href} scroll={false} aria-current={active ? "page" : undefined} aria-label={label} className={styles.link}>
      <span className={styles.eyebrow} aria-hidden="true">
        {eyebrow}
      </span>
      <span className={styles.title} aria-hidden="true">
        {title}
      </span>
      <span className={styles.detail} aria-hidden="true">
        {detail}
      </span>
    </Link>
  );
}
