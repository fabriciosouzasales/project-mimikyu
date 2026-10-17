/**
 * Acabamento (cor) do fichário de uma coleção — regras puras
 * (MY-COLLECTIONS-LIBRARY-VISUAL-02).
 *
 * A cor faz parte da identidade da coleção. Persistência: proposta
 * `database/proposals/2026-10-17-collection-cover-finish/` (coluna
 * `collection.cover_finish` + RPC `set_my_collection_cover_finish`), NÃO
 * executada. Enquanto não estiver no LIVE, cada coleção usa um acabamento
 * padrão estável derivado do próprio id — a mesma coleção tem sempre a mesma
 * cor, em qualquer dispositivo — e o seletor não aparece.
 *
 * As chaves espelham o CHECK proposto no banco; mudar aqui exige mudar lá.
 */

export const BINDER_FINISHES = [
  { key: "onix", label: "Ônix" },
  { key: "vinho", label: "Vinho" },
  { key: "floresta", label: "Floresta" },
  { key: "marinho", label: "Marinho" },
  { key: "caramelo", label: "Caramelo" },
  { key: "perola", label: "Pérola" },
] as const;

export type BinderFinish = (typeof BINDER_FINISHES)[number]["key"];

const KEYS = new Set<string>(BINDER_FINISHES.map((finish) => finish.key));

export function isBinderFinish(value: unknown): value is BinderFinish {
  return typeof value === "string" && KEYS.has(value);
}

export function finishLabel(finish: BinderFinish): string {
  return BINDER_FINISHES.find((item) => item.key === finish)?.label ?? finish;
}

/**
 * Acabamento padrão estável: FNV-1a do id da coleção. Determinístico (mesmo
 * resultado no servidor e no cliente, sem estado), distribuído entre as cores.
 */
export function defaultFinish(collectionId: string): BinderFinish {
  let hash = 0x811c9dc5;
  for (let index = 0; index < collectionId.length; index += 1) {
    hash ^= collectionId.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  const finish = BINDER_FINISHES[hash % BINDER_FINISHES.length];
  return finish ? finish.key : "onix";
}

/** Escolha gravada quando válida; senão o padrão estável. */
export function resolveFinish(collectionId: string, stored: unknown): BinderFinish {
  return isBinderFinish(stored) ? stored : defaultFinish(collectionId);
}
