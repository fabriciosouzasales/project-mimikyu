// Referência mínima de Card Variant para a galeria de `/catalogo/cartas`
// (VARIANT-GALLERY-REACT-KEY-01).
//
// A tooltip de variantes da galeria usava o NOME do tipo como chave React.
// Duas Card Variants distintas podem compartilhar o mesmo tipo (ex.: Dark
// Alakazam: "Holográfica" e "Holográfica" + 1ª Edição), o que gerava chaves
// duplicadas. A identidade de uma Card Variant é o seu `card_variant.id`;
// este módulo transporta esse id até a UI sem alterar ordem, quantidade nem
// o texto exibido. A semântica definitiva de rótulos (F1,
// `card-variant-display.ts`) NÃO é aplicada aqui.

export type CartaVariantRawRow = {
  id: string;
  card_variant_type: { name: string; display_order: number } | null;
};

export type CartaVariantRef = {
  /** `card_variant.id` — identidade persistente; usada como chave React. */
  id: string;
  /** Nome do `card_variant_type` — mesmo texto exibido antes desta correção. */
  name: string;
};

/**
 * Mesma regra de antes para `variantNames`: descarta Variants sem tipo
 * embutido e ordena por `card_variant_type.display_order` (sort estável —
 * empates mantêm a ordem recebida, exatamente como antes). Não deduplica.
 */
export function mapCartaVariants(rows: readonly CartaVariantRawRow[] | null | undefined): CartaVariantRef[] {
  return (rows ?? [])
    .filter(
      (variant): variant is CartaVariantRawRow & { card_variant_type: { name: string; display_order: number } } =>
        variant.card_variant_type !== null,
    )
    .sort((a, b) => a.card_variant_type.display_order - b.card_variant_type.display_order)
    .map((variant) => ({ id: variant.id, name: variant.card_variant_type.name }));
}
