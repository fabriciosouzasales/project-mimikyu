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
export function CardFavoriteButton({ cardId, cardName, isFavorite }: { cardId: string; cardName: string; isFavorite: boolean }) {
  return (
    <button
      type="button"
      className={styles.favorite}
      data-card-fav={cardId}
      aria-pressed={isFavorite}
      aria-label={favoriteToggleLabel(cardName)}
    >
      <FavoriteHeartIcon className={styles.favoriteIcon} />
    </button>
  );
}

/** Classe do elemento que hospeda o coração (hover/foco revelam o contorno no desktop). */
export const favoriteHostClass = styles.favoriteHost;
