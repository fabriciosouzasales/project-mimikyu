/**
 * V1-14 R1-B — regras puras do relatório 01 do Meu acervo, "Inventário resumido por Card Set"
 * (`CONTEXTUAL REPORT REALIGNMENT-05`). Sem banco, sem rede, sem SQL nova.
 *
 * Fonte: os mesmos grupos Card Variant + idioma do relatório 02 (5159 em `SET_NUMBER`, todas as
 * páginas, sem filtro de coleção), na ordem canônica do Acervo (Set: lançamento mais recente
 * primeiro), e o resumo canônico 5160. Por Card Set:
 *  - exemplares = Σ cópias dos grupos do Set;
 *  - diferentes = nº de grupos variante + idioma do Set (cada grupo pertence a um único Set, então
 *    Σ por Set = diferentes do acervo, sem contagem dupla);
 *  - repetidas = exemplares − diferentes (cópias além da primeira de cada identidade);
 *  - % = exemplares do Set / exemplares do acervo (truncado; nunca 100% sem ser o total).
 * Conferência com 5160 (exemplares, diferentes, repetidas e nº de Sets); se não fechar →
 * incompleto (impressão bloqueada, D7.8), nunca "ajustado".
 */
import { type InventorySummaryInput, plural } from "./acervo-reports.ts";

/** O mínimo que o resumo precisa de cada grupo variante + idioma. */
export type SetSummaryItemInput = { cardSetCode: string; cardSetName: string; copies: number };

export type SetSummaryRow = { code: string; name: string; copies: number; distinct: number; duplicates: number };

export type SetSummaryReport = {
  totalCopies: number;
  distinctItems: number;
  distinctSets: number;
  duplicateCopies: number;
  sets: SetSummaryRow[];
  complete: boolean;
  incompleteReason: "mismatch" | "too_large" | null;
};

export function buildSetSummaryReport(input: {
  summary: InventorySummaryInput;
  items: readonly SetSummaryItemInput[];
  /** Todas as páginas foram lidas (sem teto). */
  itemsComplete: boolean;
}): SetSummaryReport {
  const groups = new Map<string, SetSummaryRow>();
  for (const item of input.items) {
    let row = groups.get(item.cardSetCode);
    if (!row) {
      row = { code: item.cardSetCode, name: item.cardSetName, copies: 0, distinct: 0, duplicates: 0 };
      groups.set(item.cardSetCode, row);
    }
    row.copies += item.copies;
    row.distinct += 1;
    row.duplicates += item.copies - 1;
  }
  const sets = [...groups.values()];
  const { summary } = input;
  const sum = (pick: (row: SetSummaryRow) => number) => sets.reduce((total, row) => total + pick(row), 0);
  const balanced =
    sum((r) => r.copies) === summary.totalCopies &&
    sum((r) => r.distinct) === summary.distinctItems &&
    sum((r) => r.duplicates) === summary.duplicateCopies &&
    sets.length === summary.distinctSets;
  const incompleteReason = !input.itemsComplete ? "too_large" : !balanced ? "mismatch" : null;
  return {
    totalCopies: summary.totalCopies,
    distinctItems: summary.distinctItems,
    distinctSets: summary.distinctSets,
    duplicateCopies: summary.duplicateCopies,
    sets,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function setSummaryLine(report: SetSummaryReport): string {
  return [
    plural(report.totalCopies, "exemplar", "exemplares"),
    plural(report.distinctItems, "diferente", "diferentes"),
    plural(report.distinctSets, "Card Set", "Card Sets"),
  ].join(" · ");
}

export function setSummaryIncompleteText(reason: SetSummaryReport["incompleteReason"]): string | null {
  if (reason === "too_large") return "O acervo tem mais itens do que esta versão consegue listar; a impressão fica indisponível para não sair incompleta.";
  if (reason === "mismatch") return "As contagens por Card Set não fecharam com os totais do acervo no momento da leitura. Tente novamente; a impressão fica indisponível.";
  return null;
}
