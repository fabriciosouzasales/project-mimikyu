/**
 * V1-14 R1-B — Relatórios da página Minhas coleções (a estante do usuário; não confundir com os
 * relatórios de uma coleção individual, "Desta coleção", em `collection-checklist.ts`). Sem banco.
 *
 * Desde `CONTEXTUAL REPORT REALIGNMENT-05`: "Distribuição do Acervo por coleção" — o relatório
 * homologado antes chamado "Inventário geral e por coleção", realocado do Meu acervo sem mudar
 * regras, layout nem impressão (regras em `collection-distribution.ts`).
 */
import type { ReportMenuItem } from "./collection-checklist.ts";

export type LibraryReportId = "distribution";

export type LibraryReportEntry = { id: LibraryReportId; title: string; purpose: string; implemented: boolean };

export const LIBRARY_REPORT_CATALOG: readonly LibraryReportEntry[] = [
  {
    id: "distribution",
    title: "Distribuição do Acervo por coleção",
    purpose: "Onde estão os exemplares do acervo: em cada coleção ou sem coleção.",
    implemented: true,
  },
];

export function libraryReport(id: LibraryReportId): LibraryReportEntry {
  return LIBRARY_REPORT_CATALOG.find((entry) => entry.id === id)!;
}

/** Menu "De Minhas coleções": só relatórios implementados (sem linha "em preparação" por ora). */
export function libraryReportMenuItems(): ReportMenuItem[] {
  return LIBRARY_REPORT_CATALOG.filter((entry) => entry.implemented).map((entry) => ({
    id: entry.id,
    label: entry.title,
    icon: "collections",
    href: null,
    metric: null,
    disabledReason: null,
  }));
}
