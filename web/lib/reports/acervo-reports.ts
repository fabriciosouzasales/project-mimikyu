/**
 * V1-14 R1-B/R1-C/R1-D/R1-E/R1-F — Relatórios do Meu acervo: catálogo aprovado (9 relatórios independentes, cada um
 * com finalidade, tela e folha próprias) e utilitários compartilhados pelas folhas de relatório
 * do acervo e de Minhas coleções. Sem banco, sem rede.
 *
 * Desde `CONTEXTUAL REPORT REALIGNMENT-05` o Meu acervo organiza seus inventários por Card Set do
 * catálogo: 01 "Inventário resumido por Card Set" (`acervo-set-summary.ts`) e 02 "Inventário
 * detalhado por Card Set" (`acervo-set-inventory.ts`). A análise por coleção do usuário,
 * "Distribuição do Acervo por coleção", pertence a Minhas coleções (`library-reports.ts`,
 * `collection-distribution.ts`). "Minhas favoritas" (R1-D, `favorites-report.ts`) é o 4º
 * relatório deste menu (localização definitiva: `REPORT LOCATION CORRECTION-01`); "Minha Lista de
 * Desejos" (R1-E, `wishlist-report.ts`) é o 5º e "Top 10 cartas mais valiosas" (R1-F, `top-cards.ts`), o 6º. Favorito e desejo não dependem de posse, por isso
 * os dois abrem mesmo com o acervo vazio.
 */
import type { ReportMenuIcon, ReportMenuItem } from "./collection-checklist.ts";

export type AcervoReportId =
  | "inventory-summary"
  | "inventory-sets"
  | "value"
  | "favorites"
  | "wishlist"
  | "top"
  | "duplicates"
  | "distribution"
  | "coverage";

export type AcervoReportEntry = {
  id: AcervoReportId;
  title: string;
  purpose: string;
  implemented: boolean;
};

/** Catálogo aprovado (ordem do contrato D7 §4b). Só `implemented` abre; o resto é "em preparação". */
export const ACERVO_REPORT_CATALOG: readonly AcervoReportEntry[] = [
  {
    id: "inventory-summary",
    title: "Inventário resumido por Card Set",
    purpose: "Exemplares, cartas diferentes e repetidas de cada Card Set do acervo.",
    implemented: true,
  },
  {
    id: "inventory-sets",
    title: "Inventário detalhado por Card Set",
    purpose: "Todo o acervo físico por Card Set, com quantidades e referência NM.",
    implemented: true,
  },
  {
    id: "value",
    title: "Valor estimado total",
    purpose: "Valor estimado dos exemplares cotados (referência NM), por Card Set, com cobertura.",
    implemented: true,
  },
  {
    id: "favorites",
    title: "Minhas favoritas",
    purpose: "Suas cartas favoritas por Card Set, com referência NM e posse no acervo.",
    implemented: true,
  },
  {
    id: "wishlist",
    title: "Minha Lista de Desejos",
    purpose: "Seus desejos por Card Set, com referência NM e situação no acervo.",
    implemented: true,
  },
  {
    id: "top",
    title: "Top 10 cartas mais valiosas",
    purpose: "As dez cartas do acervo de maior referência NM unitária, por variante e idioma.",
    implemented: true,
  },
  { id: "duplicates", title: "Cartas repetidas", purpose: "Exemplares além do primeiro de cada carta.", implemented: false },
  { id: "distribution", title: "Distribuição por Set, raridade e idioma", purpose: "Como o acervo se divide.", implemented: false },
  { id: "coverage", title: "Cobertura de preços", purpose: "Exemplares com e sem cotação.", implemented: false },
];

export function acervoReport(id: AcervoReportId): AcervoReportEntry {
  return ACERVO_REPORT_CATALOG.find((entry) => entry.id === id)!;
}

const MENU_ICON: Partial<Record<AcervoReportId, ReportMenuIcon>> = { "inventory-sets": "inventory-sets", value: "value", favorites: "favorite", wishlist: "wish", top: "top" };

/**
 * Menu "Do acervo": os relatórios implementados abrem; os aprovados ainda não implementados
 * aparecem numa única linha indisponível (nunca como se existissem), para o menu seguir compacto.
 */
export function acervoReportMenuItems(input: { totalCopies: number }): ReportMenuItem[] {
  const ready = ACERVO_REPORT_CATALOG.filter((entry) => entry.implemented);
  const upcoming = ACERVO_REPORT_CATALOG.filter((entry) => !entry.implemented);
  const items: ReportMenuItem[] = ready.map((entry) => ({
    id: entry.id,
    label: entry.title,
    icon: MENU_ICON[entry.id] ?? "inventory",
    href: null,
    metric: null,
    // Favorito e desejo independem de posse: abrem mesmo com o acervo vazio.
    disabledReason: entry.id === "favorites" || entry.id === "wishlist" || input.totalCopies > 0 ? null : "Adicione cartas ao acervo para gerar o relatório.",
  }));
  if (upcoming.length > 0) {
    items.push({
      id: "upcoming",
      label: `${upcoming.length} relatórios em preparação`,
      icon: "upcoming",
      href: null,
      metric: null,
      disabledReason: "Repetidas, distribuição e cobertura.",
    });
  }
  return items;
}

/** Resumo canônico do acervo (5160): diferentes = Card Variant + idioma; repetidas = cópias além da primeira. */
export type InventorySummaryInput = { totalCopies: number; distinctItems: number; distinctSets: number; duplicateCopies: number };

const NUMBER = new Intl.NumberFormat("pt-BR");

export function formatCount(n: number): string {
  return NUMBER.format(n);
}

export function plural(n: number, one: string, many: string): string {
  return `${formatCount(n)} ${n === 1 ? one : many}`;
}

/** Participação no acervo, truncada (nunca arredonda para 100% sem ser o total); "<1%" se mínima. */
export function shareText(part: number, total: number): string {
  if (total <= 0) return "—";
  if (part === total) return "100%";
  const floor = Math.floor((part / total) * 100);
  return part > 0 && floor === 0 ? "<1%" : `${floor}%`;
}
