import { Bookmark } from "lucide-react";
import { wishToggleLabel } from "@/lib/wishlist/wishlist";
import styles from "./wishlist.module.css";

/**
 * Marcador da Lista de desejos (V1-11 W1, bookmark — D7). Sem estado próprio: o estado
 * inicial vai em `aria-pressed` e o `WishlistController` que envolve a grade cuida do
 * clique por delegação (mesmo padrão do coração de Favoritos — nenhum componente
 * cliente por carta).
 *
 * Dois alvos:
 * - `variantId`: a variante é conhecida (Acervo) — clique define o desejo da variante;
 * - `cardId`: só a carta é conhecida (Pesquisa) — clique abre a escolha explícita de
 *   variante, ou age direto quando a carta tem uma única variante ativa (C-212).
 * - `cardId` + `finish` (W3, Master Set): a posição é carta + acabamento — só as
 *   variantes ativas desse acabamento entram na decisão (`"*"` = carta secreta,
 *   qualquer acabamento).
 *
 * Deve ser IRMÃO do link/botão que abre a carta e ficar dentro de um elemento
 * posicionado com a classe `wishHostClass`. Nome acessível constante com carta e
 * variante; o estado é anunciado por `aria-pressed`.
 */
export function WishButton({
  cardName,
  variantLabel = null,
  variantId,
  cardId,
  finish,
  isWished,
  corner = false,
}: {
  cardName: string;
  variantLabel?: string | null;
  variantId?: string;
  cardId?: string;
  /** W3: acabamento da posição (id ou `"*"`); só com `cardId`. */
  finish?: string;
  isWished: boolean;
  /** Sem coração no card (página Lista de desejos): ocupa o canto. */
  corner?: boolean;
}) {
  return (
    <button
      type="button"
      className={corner ? `${styles.wish} ${styles.wishCorner}` : styles.wish}
      data-wish-variant={variantId}
      data-wish-card={variantId ? undefined : cardId}
      data-wish-finish={variantId ? undefined : finish}
      data-wish-name={cardName}
      aria-pressed={isWished}
      aria-label={wishToggleLabel(cardName, variantLabel)}
    >
      <Bookmark className={styles.wishIcon} strokeWidth={2} aria-hidden="true" />
    </button>
  );
}

/** Classe do elemento que hospeda o marcador (hover/foco revelam o contorno no desktop). */
export const wishHostClass = styles.wishHost;
