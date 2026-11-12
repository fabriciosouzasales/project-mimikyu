import { FavoriteHeartIcon } from "@/components/pokedex/favorite-heart";
import { favoriteToggleLabel } from "@/lib/favorites/card-favorites";
import styles from "./card-favorite.module.css";

/**
 * Botão-coração de uma carta (V1-10). Sem estado próprio: o estado inicial vai em
 * `aria-pressed` e o `CardFavoritesController` que envolve a grade cuida do clique por
 * delegação (padrão da P6 — nenhum componente cliente por carta). Serve tanto a grades
 * do servidor (Acervo, Cartas favoritas) quanto do cliente (Pesquisa).
 *
 * Deve ser IRMÃO do link/botão que abre a carta (botão dentro de link é HTML inválido)
 * e ficar dentro de um elemento posicionado com a classe `favoriteHostClass`.
 * Nome acessível constante ("Favoritar X"); o estado é anunciado por `aria-pressed`.
 */
export function CardFavoriteButton({
  cardId,
  cardName,
  isFavorite,
  indicator = "chip",
}: {
  cardId: string;
  cardName: string;
  isFavorite: boolean;
  /**
   * `chip` (padrão — Acervo, Pesquisa, Cartas favoritas): exatamente o de antes.
   * `corner` (página da coleção, padrão homologado no Fichário): em repouso, a favorita
   * mostra só um triângulo `--favorite` com coração vazado no vértice da moldura; o
   * coração aparece com hover/foco (o triângulo some). Mesmo botão, mesmo controlador.
   */
  indicator?: "chip" | "corner";
}) {
  return (
    <button
      type="button"
      className={indicator === "corner" ? `${styles.favorite} ${styles.corner}` : styles.favorite}
      data-card-fav={cardId}
      aria-pressed={isFavorite}
      aria-label={favoriteToggleLabel(cardName)}
    >
      <FavoriteHeartIcon className={styles.favoriteIcon} />
      {indicator === "corner" ? (
        <span className={styles.cornerMark} aria-hidden="true">
          <FavoriteHeartIcon className={styles.cornerHeart} />
        </span>
      ) : null}
    </button>
  );
}

/** Classe do elemento que hospeda o coração (hover/foco revelam o contorno no desktop). */
export const favoriteHostClass = styles.favoriteHost;
