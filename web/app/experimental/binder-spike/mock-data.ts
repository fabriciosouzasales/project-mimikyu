import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";

/**
 * Dados mockados do spike "Binder-First" (pedido de Fabrício, 2026-08-28;
 * refinado na Rodada BINDER-VIS-02, mesma data). Sem persistência, sem
 * Inventory real — só o suficiente para dar volume visual a "alguns bolsos
 * ocupados, outros vazios" com cartas mock realistas (não Pokémon reais —
 * ver `mock-card-face.tsx` sobre por quê).
 */

export interface BinderSlotData {
  id: string;
  filled: boolean;
  card?: MockCardData;
}

export interface BinderPageData {
  id: string;
  pageNumber: number;
  slots: BinderSlotData[];
}

export const BINDER_NAME = "Binder — Base Set";
export const BINDER_SUBTITLE = "9 bolsos por página · 224 cartas";

/** Pequeno catálogo de criaturas originais — reaproveitado (com repetição) nos slots preenchidos. */
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

export const MOCK_BINDER_SPIKE_PAGES: BinderPageData[] = [
  {
    id: "page-1",
    pageNumber: 1,
    slots: [
      slot("p1-1", true, 0),
      slot("p1-2", true, 1),
      slot("p1-3", false),
      slot("p1-4", true, 2),
      slot("p1-5", false),
      slot("p1-6", true, 3),
      slot("p1-7", true, 4),
      slot("p1-8", false),
      slot("p1-9", false),
    ],
  },
  {
    id: "page-2",
    pageNumber: 2,
    slots: [
      slot("p2-1", true, 5),
      slot("p2-2", false),
      slot("p2-3", true, 6),
      slot("p2-4", false),
      slot("p2-5", true, 7),
      slot("p2-6", false),
      slot("p2-7", false),
      slot("p2-8", false),
      slot("p2-9", true, 0),
    ],
  },
];
