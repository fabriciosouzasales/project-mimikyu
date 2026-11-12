/**
 * V1-10 (extensão) — Favoritos no Fichário Digital. Regras puras.
 *
 * O favorito é da CARTA (C-82) e do USUÁRIO (C-83): nunca variante, acabamento,
 * idioma, exemplar, coleção ou bolso; não exige posse (C-84) nem depende de
 * coleção/layout (C-85). No fichário, o bolso só diz QUAL carta mostra:
 * - carta presente → a carta presente (uma reserva divergente não conta);
 * - reservado e vazio → a carta reservada (o acabamento da reserva é ignorado);
 * - vazio, só espécie (Pokédex), imagem personalizada ou mesclagem → nenhuma.
 *
 * Decisões (BINDER FAVORITES INTEGRATION IMPLEMENTATION-01):
 * - D1 marcador no canto superior direito, ao lado do da Lista de desejos;
 * - D2 só no fichário do titular (inclusive arquivado); compartilhado e vitrine
 *   sem coração — decisão de apresentação, não de permissão.
 */
import type { BinderSlot } from "./binder.ts";

const OCCUPIED = new Set(["OCCUPIED_MATCH", "OCCUPIED_UNPLANNED", "OCCUPIED_MISMATCH"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type FavoriteSlot = Pick<BinderSlot, "state" | "presentCardId" | "expectedCardId" | "image" | "regionId">;

/** Carta favoritável do bolso (id em minúsculas) ou `null`. */
export function binderFavoriteCardId(slot: FavoriteSlot): string | null {
  if (slot.image || slot.regionId) return null;
  const id = OCCUPIED.has(slot.state) ? slot.presentCardId : slot.state === "RESERVED_EMPTY" ? slot.expectedCardId : null;
  return id && UUID.test(id) ? id.toLowerCase() : null;
}

/** Cartas a ler (deduplicadas, só as ainda não pedidas): uma leitura em lote por conjunto novo, nunca por bolso. */
export function binderFavoriteReadIds(slots: readonly FavoriteSlot[], alreadyRequested: ReadonlySet<string>): string[] {
  const ids = new Set<string>();
  for (const slot of slots) {
    const id = binderFavoriteCardId(slot);
    if (id && !alreadyRequested.has(id)) ids.add(id);
  }
  return [...ids];
}

/** Limite por chamada de `readCardFavoriteIds` (a ação recusa acima disso). */
export const FAVORITE_READ_MAX = 2000;

/**
 * Canto superior direito com os dois marcadores (Desejos no canto, Favorito ao lado).
 * Os marcadores NUNCA encolhem (mesmo tamanho e mesma área de toque de sempre —
 * `size + 8`, margem −4, como o "Selecionar").
 *
 * - Linha (padrão): Favorito à esquerda do Desejos. Só quando a linha inteira cabe
 *   sem que as áreas de toque encostem na do "Selecionar" (canto superior esquerdo):
 *   `0,92·bolso ≥ 3·control + gap + 8`.
 * - Coluna (bolso estreito, ex.: 5×4 no celular): Favorito logo ABAIXO do Desejos, e
 *   os selos (trava, divergência) passam para a coluna ESQUERDA, sob o "Selecionar",
 *   nas mesmas alturas de antes — nenhuma área de toque se sobrepõe e nada desce
 *   mais do que já descia.
 *
 * `shift` = quanto os selos descem (uma linha, como já desciam com o marcador de Desejos).
 */
export type MarkerLayout = {
  size: number;
  gap: number;
  shift: number;
  /** Favorito abaixo do Desejos (em vez de ao lado). */
  stacked: boolean;
  /** Lado dos selos de trava/divergência. */
  badgeSide: "left" | "right";
};

export const MARKER_GAP = 8;

/** A linha [Selecionar … Favorito Desejos] cabe sem encostar as áreas de toque? */
export function markerRowFits(control: number, pocket: number): boolean {
  return pocket * 0.92 >= 3 * control + MARKER_GAP + 8;
}

export function binderMarkerLayout(input: { control: number; pocket: number; wish: boolean; favorite: boolean }): MarkerLayout {
  const { control, pocket, wish, favorite } = input;
  if (!wish && !favorite) return { size: control, gap: MARKER_GAP, shift: 0, stacked: false, badgeSide: "right" };
  const stacked = wish && favorite && !markerRowFits(control, pocket);
  return { size: control, gap: MARKER_GAP, shift: control + 4, stacked, badgeSide: stacked ? "left" : "right" };
}

/**
 * Indicador passivo de favorita (FAVORITES CORNER INDICATOR CORRECTION-01): triângulo no
 * vértice superior direito da moldura do bolso, com um coração vazado. Cateto ≈ 7% do
 * bolso (8–14 px): fica sobre a borda impressa da carta, longe de nome, HP e tipo.
 */
export function binderFavoriteCornerSize(pocket: number): number {
  return Math.min(14, Math.max(8, Math.round(pocket * 0.07)));
}
