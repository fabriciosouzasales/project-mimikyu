import type { CSSProperties } from "react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import type { PokedexHeroPokemon } from "@/lib/colecoes/pokedex";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import heroStyles from "./collection-hero.module.css";
import styles from "./pokedex.module.css";

/**
 * Palco do hero da Pokédex (UX-07): o Mimikyu — que dá nome ao MMKYU — ao
 * centro, para todos, e ao redor a equipe de 6: favoritos do colecionador
 * (sorteados a cada visita), completados pelos iniciais da geração em destaque.
 * Formação em arco sobre um disco de Pokébola; a arte do Mimikyu,
 * desfocada, tinge o palco. O palco celebra; a régua ao lado mede.
 *
 * Server Component, sem JS no cliente. Mesmas URLs WebP 320 da grade (cache).
 * Entrada e flutuação só com transform/opacity, desligadas em
 * prefers-reduced-motion.
 */
export function PokedexHeroBackdrop({ lineup }: { lineup: readonly PokedexHeroPokemon[] }) {
  const src = lineup[0] ? speciesArtworkUrl(lineup[0].artworkPath) : null;
  if (!src) return null;
  return (
    <span className={heroStyles.backdrop} aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- mesma URL pública da grade, só tinge o palco */}
      <img src={src} alt="" width={320} height={320} decoding="async" fetchPriority="low" draggable={false} />
    </span>
  );
}

export function PokedexHeroStage({ lineup, label }: { lineup: readonly PokedexHeroPokemon[]; label: string }) {
  if (lineup.length === 0) return null;
  const names = lineup.map((pokemon) => pokemon.name).join(", ");

  return (
    <figure className={`${heroStyles.fan} ${styles.stage}`} aria-label={`${label}: ${names}`}>
      <div className={styles.stageFloor}>
        <Pokeball className={styles.stageDisc} strokeWidth={0.5} aria-hidden="true" />
        {lineup.map((pokemon, index) => {
          const src = speciesArtworkUrl(pokemon.artworkPath);
          if (!src) return null;
          return (
            <span
              key={pokemon.number}
              className={styles.mon}
              data-slot={index}
              style={{ "--i": index } as CSSProperties}
            >
              <span className={styles.monFloat}>
                {/* eslint-disable-next-line @next/next/no-img-element -- WebP 320 já otimizado no pipeline, URL pública imutável */}
                <img
                  src={src}
                  alt=""
                  width={320}
                  height={320}
                  className={styles.monArt}
                  loading="eager"
                  decoding="async"
                  fetchPriority={index === 0 ? "high" : "low"}
                  draggable={false}
                />
              </span>
            </span>
          );
        })}
      </div>
    </figure>
  );
}
