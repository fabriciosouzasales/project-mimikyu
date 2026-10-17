import { ADD_MAX_QUANTITY } from "./acervo-add.ts";

/**
 * Ajustar a quantidade de exemplares de uma carta no detalhe (INVENTORY-COPY-QUANTITY-01).
 *
 * Cada exemplar continua sendo um Physical Card individual: "quantidade" é só a
 * contagem deles. Aumentar registra exemplares novos (mesma variante e idioma);
 * diminuir remove exemplares — sempre os mais recentes que não estão em
 * nenhuma coleção (os alocados nunca são tocados aqui).
 */

export type QuantityCopy = { physicalCardId: string; copyNumber: number; inCollection: boolean };

export function quantityBounds(copies: readonly QuantityCopy[], total: number): { min: number; max: number } {
  const allocated = copies.filter((copy) => copy.inCollection).length;
  // Mínimo 1: zerar a carta é a lixeira do último exemplar, uma decisão explícita.
  return { min: Math.max(1, allocated), max: total + ADD_MAX_QUANTITY };
}

export function clampQuantity(value: number, bounds: { min: number; max: number }): number {
  if (!Number.isFinite(value)) return bounds.min;
  return Math.min(bounds.max, Math.max(bounds.min, Math.trunc(value)));
}

/** Exemplares a remover para reduzir em `count`: os de maior número, fora de coleção. */
export function copiesToRemove(copies: readonly QuantityCopy[], count: number): string[] {
  if (count <= 0) return [];
  return copies
    .filter((copy) => !copy.inCollection)
    .sort((a, b) => b.copyNumber - a.copyNumber)
    .slice(0, Math.min(count, ADD_MAX_QUANTITY))
    .map((copy) => copy.physicalCardId);
}

export function quantityChangeLabel(delta: number): string {
  if (delta > 0) return delta === 1 ? "1 exemplar novo será registrado" : `${delta} exemplares novos serão registrados`;
  const n = -delta;
  return n === 1
    ? "O exemplar mais recente sem coleção será removido"
    : `Os ${n} exemplares mais recentes sem coleção serão removidos`;
}
