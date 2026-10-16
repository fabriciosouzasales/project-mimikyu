/**
 * Coração de "Espécie favorita" (Pokédex P6, 2026-10-15) — símbolo oficial aprovado (D6):
 * contorno quando não favorita, preenchido em vermelho (`--favorite`, distinto do vermelho
 * de erro) quando favorita. O preenchimento é decidido pelo CSS a partir de
 * `aria-pressed` do botão, então a mesma forma serve aos dois estados sem trocar o SVG.
 *
 * Na galeria (1.025 cards) o desenho existe uma vez por página (`FavoriteHeartSprite`) e
 * cada botão usa `<use>`, como os ícones de tipo — HTML mínimo por card.
 */

export const FAVORITE_HEART_SYMBOL_ID = "pk-favorite-heart";

/** Mesmo traçado do ícone "heart" do Lucide (viewBox 24). */
const HEART_PATH =
  "M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z";

export function FavoriteHeartSprite() {
  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true" focusable="false">
      <symbol id={FAVORITE_HEART_SYMBOL_ID} viewBox="0 0 24 24">
        <path d={HEART_PATH} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      </symbol>
    </svg>
  );
}

/** Coração por referência ao sprite (galeria). */
export function FavoriteHeartUse({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <use href={`#${FAVORITE_HEART_SYMBOL_ID}`} />
    </svg>
  );
}

/** Coração autônomo (ficha — um único por página). */
export function FavoriteHeartIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={HEART_PATH} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
