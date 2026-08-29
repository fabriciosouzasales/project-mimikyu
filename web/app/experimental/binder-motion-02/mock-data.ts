import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import type { BinderPageData, BinderSlotData } from "@/app/experimental/binder-spike/mock-data";

/**
 * Dados mockados do spike BINDER-MOTION-02 — Page Turn (pedido de
 * Fabrício, 2026-08-28). Mesmo catálogo de criaturas originais do
 * Binder-First (ver `binder-spike/mock-card-face.tsx`), agora só 3 spreads
 * (a metáfora de virada é o que está sendo validado, não volume de dados).
 */

const MOCK_CARDS: MockCardData[] = [
  { id: "emberling", name: "Emberling", hp: 60, hue: 12, attack: "Ember Burst", damage: 30, rarity: "N", energy: "flame" },
  { id: "aquafin", name: "Aquafin", hp: 70, hue: 205, attack: "Aqua Jet", damage: 40, rarity: "RH", energy: "drop" },
  { id: "verdil", name: "Verdil", hp: 80, hue: 140, attack: "Vine Snap", damage: 20, rarity: "N", energy: "leaf" },
  { id: "stonepaw", name: "Stonepaw", hp: 90, hue: 32, attack: "Rock Slam", damage: 50, rarity: "N", energy: "stone" },
  { id: "voltgnat", name: "Voltgnat", hp: 50, hue: 48, attack: "Static Shock", damage: 30, rarity: "H", energy: "bolt" },
  { id: "skyfeather", name: "Skyfeather", hp: 65, hue: 260, attack: "Gale Wing", damage: 20, rarity: "RH", energy: "wing" },
  { id: "cindrix", name: "Cindrix", hp: 100, hue: 350, attack: "Cinder Roar", damage: 60, rarity: "H", energy: "flame" },
  { id: "mossback", name: "Mossback", hp: 75, hue: 160, attack: "Bramble Guard", damage: 10, rarity: "N", energy: "leaf" },
];

function card(index: number): MockCardData {
  return MOCK_CARDS[index % MOCK_CARDS.length]!;
}

function slot(id: string, filled: boolean, cardIndex?: number): BinderSlotData {
  return { id, filled, card: filled && cardIndex !== undefined ? card(cardIndex) : undefined };
}

const FILL_PATTERNS: boolean[][] = [
  [true, true, false, true, false, true, true, false, false],
  [true, false, true, false, true, false, false, false, true],
  [false, true, true, false, false, true, true, false, true],
  [true, false, false, true, true, false, true, true, false],
];

function buildPage(id: string, pageNumber: number, patternIndex: number, cardStart: number): BinderPageData {
  const pattern = FILL_PATTERNS[patternIndex % FILL_PATTERNS.length]!;
  let cursor = cardStart;
  const slots: BinderSlotData[] = pattern.map((filled, i) => {
    const s = slot(`${id}-${i + 1}`, filled, filled ? cursor : undefined);
    if (filled) cursor += 1;
    return s;
  });
  return { id, pageNumber, slots };
}

export interface BinderSpreadData {
  id: string;
  left: BinderPageData;
  right: BinderPageData;
}

export const SPREAD_COUNT = 3;

export const MOCK_BINDER_MOTION_SPREADS: BinderSpreadData[] = Array.from({ length: SPREAD_COUNT }, (_, i) => {
  const leftPageNumber = i * 2 + 1;
  const rightPageNumber = i * 2 + 2;
  return {
    id: `spread-${i + 1}`,
    left: buildPage(`s${i + 1}-l`, leftPageNumber, i * 2, i * 5),
    right: buildPage(`s${i + 1}-r`, rightPageNumber, i * 2 + 1, i * 5 + 3),
  };
});
