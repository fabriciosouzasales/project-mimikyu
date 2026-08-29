/**
 * Dados 100% mockados/locais para o spike visual "Visual Collection Space"
 * (pedido de Fabrício, 2026-08-28) — nenhuma tabela, RPC ou fetch real.
 * Nada aqui deriva do domínio Collections real (`docs/domain-modeling/
 * collections/`); os campos existem só para dar forma visual aos
 * containers do carrossel. Não usar como referência de schema.
 */

export type StorageContainerType = "binder" | "etb" | "storage-box" | "deck-box";

export interface MockStorageContainer {
  id: string;
  type: StorageContainerType;
  name: string;
  subtitle: string;
  /** Matiz HSL base (sem alpha) — só para variar o acento visual por item, não é token do design system. */
  accentHue: number;
  itemCount: number;
  /** Só o Binder é interativo nesta rodada (ver instrução de Fabrício). */
  interactive: boolean;
}

export const MOCK_STORAGE_CONTAINERS: MockStorageContainer[] = [
  {
    id: "binder-base-set",
    type: "binder",
    name: "Binder — Base Set",
    subtitle: "9 bolsos · 24 páginas",
    accentHue: 37,
    itemCount: 186,
    interactive: true,
  },
  {
    id: "etb-obsidian-flames",
    type: "etb",
    name: "ETB — Obsidian Flames",
    subtitle: "Elite Trainer Box",
    accentHue: 8,
    itemCount: 42,
    interactive: false,
  },
  {
    id: "storage-box-vault",
    type: "storage-box",
    name: "Storage Box — Vault",
    subtitle: "Caixa de gradação",
    accentHue: 205,
    itemCount: 310,
    interactive: false,
  },
  {
    id: "binder-shining-legends",
    type: "binder",
    name: "Binder — Shining Legends",
    subtitle: "4 bolsos · 12 páginas",
    accentHue: 142,
    itemCount: 64,
    interactive: false,
  },
  {
    id: "deck-box-standard",
    type: "deck-box",
    name: "Deck Box — Standard",
    subtitle: "Deck competitivo",
    accentHue: 280,
    itemCount: 60,
    interactive: false,
  },
  {
    id: "etb-paldea-evolved",
    type: "etb",
    name: "ETB — Paldea Evolved",
    subtitle: "Elite Trainer Box",
    accentHue: 265,
    itemCount: 38,
    interactive: false,
  },
];

/** Duas páginas mockadas do interior do Binder — só para dar volume visual, sem slot funcional. */
export const MOCK_BINDER_PAGES = [
  {
    id: "page-1",
    slots: Array.from({ length: 9 }, (_, index) => ({
      id: `p1-slot-${index}`,
      filled: [0, 1, 2, 4, 5, 7].includes(index),
    })),
  },
  {
    id: "page-2",
    slots: Array.from({ length: 9 }, (_, index) => ({
      id: `p2-slot-${index}`,
      filled: [0, 3, 4, 5, 6, 8].includes(index),
    })),
  },
];
