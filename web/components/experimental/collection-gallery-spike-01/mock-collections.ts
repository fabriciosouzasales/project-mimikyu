/**
 * COLLECTION-GALLERY-SPIKE-01 (2026-08-29) — dados mockados, sem backend.
 *
 * 6 Collections curadas (nomes reais de Sets clássicos, só para dar
 * identidade visual ao spike) usadas como o conjunto FIXO de comparação
 * entre os dois modos (A — Visual Gallery / B — Premium Grid/List), como
 * pedido explicitamente por Fabrício ("exatamente os mesmos 5–7 mocks").
 *
 * `generateManyMockCollections()` existe só para exercitar o critério
 * "comportamento com poucas e muitas Collections" do próprio spike — não é
 * um segundo conjunto de curadoria, é uma variação sintética do mesmo pool
 * de 6 nomes, com progresso determinístico (sem `Math.random()`, para o
 * resultado ser estável entre reloads/SSR).
 *
 * `code` (NOVO, 2026-08-29 — COLLECTION-LIBRARY-VIEW-MODES-01): a
 * consolidação dos 3 modos oficiais (Lista/Cards/Carrossel) exige que todos
 * mostrem o MESMO núcleo de informação — Binder, nome, código, progresso —
 * e o Carrossel (Character Filmstrip + Binder MMKYU) já usava um código
 * curto por Collection desde as rodadas de discovery. Este campo só formaliza
 * essa mesma informação na fonte única de dados, para Lista/Cards passarem a
 * exibi-la também. Mesmos valores já usados no Carrossel (BASE/JUN/FOS/
 * ROCKET/GYM/NEO) — nenhuma mudança de identidade, só propagação.
 */

export interface MockCollection {
  id: string;
  name: string;
  code: string;
  totalCards: number;
  ownedCards: number;
}

export const MOCK_COLLECTIONS: MockCollection[] = [
  { id: "base-set", name: "Base Set", code: "BASE", totalCards: 102, ownedCards: 97 },
  { id: "jungle", name: "Jungle", code: "JUN", totalCards: 64, ownedCards: 41 },
  { id: "fossil", name: "Fossil", code: "FOS", totalCards: 62, ownedCards: 62 },
  { id: "team-rocket", name: "Team Rocket", code: "ROCKET", totalCards: 83, ownedCards: 15 },
  { id: "gym-heroes", name: "Gym Heroes", code: "GYM", totalCards: 132, ownedCards: 5 },
  { id: "neo-genesis", name: "Neo Genesis", code: "NEO", totalCards: 111, ownedCards: 73 },
];

export function collectionProgress(collection: MockCollection): number {
  if (collection.totalCards <= 0) return 0;
  return Math.round((collection.ownedCards / collection.totalCards) * 100);
}

/**
 * Gera um conjunto sintético maior (padrão: 24) só para o teste de escala —
 * cicla pelo pool de 6 nomes reais com um sufixo numérico e varia o
 * progresso de forma determinística (função do índice, não aleatória).
 */
export function generateManyMockCollections(count = 24): MockCollection[] {
  const pool = MOCK_COLLECTIONS;
  return Array.from({ length: count }, (_, i) => {
    // `i % pool.length` está sempre dentro do array (pool nunca é vazio) —
    // non-null assertion segura, `noUncheckedIndexedAccess` não consegue
    // provar isso sozinho a partir de um índice calculado.
    const base = pool[i % pool.length]!;
    const cycle = Math.floor(i / pool.length) + 1;
    const owned = Math.max(0, Math.round(base.ownedCards * (((i * 37) % 100) / 100)));
    return {
      id: `${base.id}-${cycle}-${i}`,
      name: cycle > 1 ? `${base.name} (${cycle})` : base.name,
      code: cycle > 1 ? `${base.code}-${cycle}` : base.code,
      totalCards: base.totalCards,
      ownedCards: Math.min(owned, base.totalCards),
    };
  });
}
