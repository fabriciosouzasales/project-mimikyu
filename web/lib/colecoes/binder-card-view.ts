/**
 * V1-08 — "Ver carta" no fichário: qual carta a lupa amplia para um bolso.
 * Regras puras, só com o que o bolso já carregou (nenhuma leitura nova).
 *
 * Decisões (V1-08):
 * - D1 gatilho: fichário editável → ação "Ver carta" na cápsula do bolso (o
 *   clique/toque na carta continua sendo de organização); somente leitura →
 *   clicar/tocar na carta abre a lupa.
 * - D2 (revisada em CATALOG CARD PREVIEW VISUAL ALIGNMENT CORRECTION-01):
 *   ampliação visual pura, idêntica à da página Cartas do Catálogo Editorial —
 *   sem painel nem texto. Substitui a D2 original (imagem + faixa de
 *   identificação contextual).
 * - D3 alcance: editável, somente leitura, compartilhado e arquivado; overlay,
 *   rota e tela cheia. A lupa é só consulta — nenhuma ação grava.
 *
 * Semântica do bolso:
 * - carta presente → a imagem do exemplar no bolso (prevalece sobre a reserva);
 * - reservado e vazio → a imagem da carta ESPERADA (o "Reservado — falta"
 *   fica no bolso, não na lupa);
 * - vazio, imagem personalizada ou mesclagem → sem lupa de carta.
 */
import { formatCollectorNumber } from "./acervo.ts";
import type { BinderSlot } from "./binder.ts";

export type CardViewModel = {
  kind: "present" | "reserved";
  name: string;
  imagePath: string | null;
  /** Só para o nome acessível ("025/165"). */
  number: string | null;
  setCode: string | null;
};

type ViewSlot = Pick<BinderSlot, "state" | "present" | "expected" | "expectedCardId" | "image" | "regionId">;

const OCCUPIED = new Set(["OCCUPIED_MATCH", "OCCUPIED_UNPLANNED", "OCCUPIED_MISMATCH"]);

/** O bolso tem carta para ver? (presente, ou esperada por reserva; nunca imagem ou mesclagem). */
export function canViewCard(slot: ViewSlot): boolean {
  return cardViewFor(slot) !== null;
}

export function cardViewFor(slot: ViewSlot): CardViewModel | null {
  if (slot.image || slot.regionId) return null;
  const face = OCCUPIED.has(slot.state) && slot.present ? slot.present : slot.state === "RESERVED_EMPTY" && slot.expectedCardId !== null ? slot.expected : null;
  if (!face) return null;
  return {
    kind: face === slot.present ? "present" : "reserved",
    name: face.cardName,
    imagePath: face.imagePath,
    number: face.collectorNumber ? formatCollectorNumber(face.collectorNumber, face.collectorTotal) : null,
    setCode: face.setCode,
  };
}

/** Nome acessível do diálogo e texto alternativo da imagem (nunca exibido como texto). */
export function cardViewAlt(view: CardViewModel): string {
  const parts = [view.name, view.number, view.setCode?.toUpperCase() ?? null].filter(Boolean);
  return view.kind === "reserved" ? `${parts.join(", ")} — reservada, ainda falta` : parts.join(", ");
}

/** `view-transition-name` do morph bolso → carta ampliada (custom-ident válido e único). */
export function cardViewTransitionName(slotId: string): string {
  return `binder-card-view-${slotId.replace(/[^A-Za-z0-9_-]/g, "-")}`;
}
