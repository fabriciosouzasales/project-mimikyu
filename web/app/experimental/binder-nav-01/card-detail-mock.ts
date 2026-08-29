import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import type { RealCardData } from "./mock-data";

/**
 * CARD-DETAIL-01 (2026-08-29) — dados mockados exclusivos do painel de
 * detalhe da carta (`card-detail-modal.tsx`). Pedido de Fabrício: "Binder =
 * contexto de organização, Card Detail = contexto de informação da carta" —
 * este arquivo é a fonte desses dados de informação, isolada do resto do
 * BINDER-NAV-01 (que só lida com organização/slots).
 *
 * Tudo aqui é determinístico — hash simples do próprio `card.id`, nunca
 * `Math.random()` — para que reabrir a MESMA carta sempre mostre os mesmos
 * números (quantidade possuída, preço, variant). Sem leitura de
 * Inventory/Pricing/Card Variant reais, sem persistência: escopo explícito
 * desta rodada é "não alterar domínio... não integrar backend real ainda".
 */

function hashCardId(id: string): number {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (Math.imul(hash, 31) + id.charCodeAt(i)) >>> 0;
  }
  return hash;
}

export interface CardDetailPricingMock {
  brl: number;
  usd: number;
}

/**
 * Preço fictício em BRL (R$5,00–R$454,99) + uma segunda referência em USD
 * (item 5 do pedido: "pode haver uma segunda referência internacional
 * discreta") — aproximação fixa só para ilustrar a hierarquia visual, SEM
 * qualquer leitura de câmbio real (isso pertence ao domínio de Pricing, fora
 * de escopo aqui).
 */
export function getCardPricingMock(cardId: string): CardDetailPricingMock {
  const hash = hashCardId(cardId);
  const brl = Math.round(500 + (hash % 45000)) / 100;
  const usd = Math.round((brl / 5.4) * 100) / 100;
  return { brl, usd };
}

/** Cópias possuídas fictícias (1 a 5) — "repetida" (item 4) quando > 1. */
export function getCardCopiesOwnedMock(cardId: string): number {
  return 1 + (hashCardId(cardId) % 5);
}

const MOCK_VARIANT_LABELS = ["Holofoil", "Reverse Holofoil"] as const;

export interface CardDetailSetInfo {
  setCode: string;
  setName: string;
  number: string;
  /** Só presente numa fração das cartas — "Variant/printing quando aplicável" (item 3). */
  variantLabel?: string;
}

/** Set/número/variant mockados a partir do id da carta — sem leitura de card_variant real. */
export function getCardSetInfoMock(card: MockCardData | RealCardData): CardDetailSetInfo {
  const hash = hashCardId(card.id);
  if ("imageUrl" in card) {
    const match = /me2-(\d+)/.exec(card.id);
    const number = match ? match[1]! : "—";
    // ~1 em cada 3 cartas ganha um selo de variant fictício, só para validar
    // a hierarquia visual pedida — não é uma leitura real de Card Variant.
    const variantLabel = hash % 3 === 0 ? MOCK_VARIANT_LABELS[hash % MOCK_VARIANT_LABELS.length] : undefined;
    return { setCode: "ME2", setName: "Fogo Fantasmagórico", number, variantLabel };
  }
  return { setCode: "MOCK", setName: "Coleção de Teste", number: card.id.slice(0, 3).toUpperCase() };
}

export interface ParsedBinderSlotId {
  pageNumber: number;
  slotNumber: number;
}

/**
 * Extrai página/slot a partir do id físico do slot (formato `p{página}-{slot}`,
 * definido em `mock-data.ts`) — evita ter que propagar `pageNumber`/`slotNumber`
 * como props novas por toda a árvore (`BinderPagesNav` → `SlotsGrid` →
 * `BinderSlotFull`) só para o Card Detail conseguir montar "Página X · Slot Y".
 */
export function parseBinderSlotId(slotId: string): ParsedBinderSlotId | null {
  const match = /^p(\d+)-(\d+)$/.exec(slotId);
  if (!match) return null;
  return { pageNumber: Number(match[1]), slotNumber: Number(match[2]) };
}
