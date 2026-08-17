/**
 * Helpers de formatação da Pesquisa Global de Cartas — deliberadamente
 * separados de `components/catalogo/cartas-gallery.tsx` (que tem os mesmos
 * helpers, não exportados) para não acoplar a página pública `/pesquisa` à
 * galeria administrativa do Catálogo. Pequena duplicação de funções puras,
 * preferível a extrair/reescrever a galeria admin neste incremento (ver
 * ADR-030, seção "Compatibilidade").
 */

export type PesquisaCard = {
  id: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSet: { id: string; code: string; name: string };
  category: { id: string | null; code: string; name: string | null } | null;
  rarity: { id: string | null; code: string; name: string | null; symbolCode: string | null } | null;
  imageUrlPt: string | null;
  imageUrlEn: string | null;
};

/** Número do colecionador, sempre exibido com 3 dígitos (mesmo padrão de `cartas-gallery.tsx`). */
export function formatCollectorNumber(collectorNumber: string): string {
  return collectorNumber.padStart(3, "0");
}

export function formatCollectorTotal(collectorTotal: number | null): string {
  return collectorTotal != null ? String(collectorTotal).padStart(3, "0") : "???";
}

/** "001/086" — mesmo formato de `cartaFullNumber()` na galeria administrativa. */
export function cartaFullNumber(collectorNumber: string, collectorTotal: number | null): string {
  return `${formatCollectorNumber(collectorNumber)}/${formatCollectorTotal(collectorTotal)}`;
}

/** Prioridade PT-BR com fallback para inglês — mesma regra vigente no Catálogo. */
export function cardImageUrl(card: Pick<PesquisaCard, "imageUrlPt" | "imageUrlEn">): string | null {
  return card.imageUrlPt ?? card.imageUrlEn ?? null;
}
