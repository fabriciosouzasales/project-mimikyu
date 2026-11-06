/**
 * V1-14 R1-B — regras puras do relatório "Distribuição do Acervo por coleção" (página Minhas
 * coleções; antes "Inventário geral e por coleção" no Meu acervo — realocado sem mudar regras em
 * `CONTEXTUAL REPORT REALIGNMENT-05`). Sem banco, sem rede.
 *
 * Leituras existentes, nenhuma SQL nova:
 *  - 5160 `get_my_inventory_summary`: exemplares, diferentes (Card Variant + idioma), Sets, repetidas;
 *  - 5182 `get_my_collections` (ativas + arquivadas): `copies_count` = exemplares alocados a cada coleção;
 *  - 5159 `get_my_inventory_items` com `p_without_collection`: `total_copies` = exemplares sem coleção.
 * Um exemplar está em no máximo UMA coleção (`collection_allocation.physical_card_id` UNIQUE, 5040),
 * então Σ(por coleção) + sem coleção = total — conferido aqui; se não fechar, o relatório é
 * marcado incompleto (impressão bloqueada, D7.8), nunca "ajustado".
 */
import { collectionKindBadge } from "../colecoes/colecoes.ts";
import { type InventorySummaryInput, plural } from "./acervo-reports.ts";

export type DistributionCollectionRow = {
  id: string;
  name: string;
  kindLabel: string;
  archived: boolean;
  copies: number;
};

export type CollectionDistributionReport = {
  totalCopies: number;
  distinctItems: number;
  distinctSets: number;
  duplicateCopies: number;
  allocatedCopies: number;
  unallocatedCopies: number;
  collectionCount: number;
  /** Coleções com exemplares, por quantidade (desc) e nome; vazias ficam só na contagem. */
  collections: DistributionCollectionRow[];
  emptyCollectionCount: number;
  /** Σ(por coleção) + sem coleção = total, e o conjunto de coleções foi lido inteiro. */
  complete: boolean;
  incompleteReason: "mismatch" | "truncated" | null;
};

export type DistributionCollectionInput = { id: string; name: string; completionPolicy: string | null; lifecycleStatus: string; copiesCount: number };

const COLLATOR = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });

export function buildCollectionDistributionReport(input: {
  summary: InventorySummaryInput;
  collections: readonly DistributionCollectionInput[];
  unallocatedCopies: number;
  /** Todas as páginas de coleções foram lidas. */
  collectionsComplete: boolean;
}): CollectionDistributionReport {
  const { summary } = input;
  const withCopies = input.collections.filter((c) => c.copiesCount > 0);
  const allocated = input.collections.reduce((sum, c) => sum + Math.max(0, c.copiesCount), 0);
  const rows = withCopies
    .map((c) => ({
      id: c.id,
      name: c.name,
      kindLabel: collectionKindBadge(c.completionPolicy)?.label ?? "Coleção",
      archived: c.lifecycleStatus === "ARCHIVED",
      copies: c.copiesCount,
    }))
    .sort((a, b) => b.copies - a.copies || COLLATOR.compare(a.name, b.name) || a.id.localeCompare(b.id));
  const balanced = allocated + input.unallocatedCopies === summary.totalCopies;
  const incompleteReason = !input.collectionsComplete ? "truncated" : !balanced ? "mismatch" : null;
  return {
    totalCopies: summary.totalCopies,
    distinctItems: summary.distinctItems,
    distinctSets: summary.distinctSets,
    duplicateCopies: summary.duplicateCopies,
    allocatedCopies: allocated,
    unallocatedCopies: input.unallocatedCopies,
    collectionCount: input.collections.length,
    collections: rows,
    emptyCollectionCount: input.collections.length - withCopies.length,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function collectionDistributionSummaryLine(report: CollectionDistributionReport): string {
  return [
    plural(report.totalCopies, "exemplar", "exemplares"),
    plural(report.distinctItems, "diferente", "diferentes"),
    plural(report.collections.length, "coleção com cartas", "coleções com cartas"),
  ].join(" · ");
}

export function collectionDistributionIncompleteText(reason: CollectionDistributionReport["incompleteReason"]): string | null {
  if (reason === "truncated") return "Há mais coleções do que esta versão consegue listar; a impressão fica indisponível para não sair incompleta.";
  if (reason === "mismatch") return "As contagens por coleção não fecharam com o total do acervo no momento da leitura. Tente novamente; a impressão fica indisponível.";
  return null;
}
