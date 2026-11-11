/**
 * V1-14 — bloco Locais — relatórios da página Meus Locais de Armazenamento
 * (menu "De Meus locais"). Sem banco.
 *
 * - "Distribuição do Acervo por Local" (Quantidade de Exemplares por Local,
 *   D7 §4s): global, abre direto do menu;
 * - "Capacidade e Ocupação de Fichários" (D7 §4t): global, abre direto do menu.
 *
 * O "Inventário do Local" (D7 §4r) é de UM recipiente e não fica neste menu
 * (LOCATION INVENTORY ACCESS UX REFINEMENT-01): é emitido nas ações do próprio
 * local — "Imprimir inventário" no menu "…" da linha e "Gerar inventário deste
 * local" no painel —, as duas pela mesma prévia.
 */
import type { ReportMenuItem } from "./collection-checklist.ts";
import { BINDER_OCCUPANCY_TITLE } from "./binder-occupancy.ts";
import { LOCATION_DISTRIBUTION_TITLE } from "./location-distribution.ts";

export type LocationsReportId = "distribution" | "binders";

export const LOCATIONS_REPORT_PURPOSE = "Como todos os exemplares físicos estão distribuídos pelos seus locais.";
export const BINDER_OCCUPANCY_PURPOSE = "Bolsos configurados, ocupados e livres nos fichários digitais dos seus fichários físicos.";

export function locationsReportMenuItems(): ReportMenuItem[] {
  return [
    {
      id: "distribution",
      label: LOCATION_DISTRIBUTION_TITLE,
      icon: "distribution",
      href: null,
      metric: null,
      disabledReason: null,
    },
    {
      id: "binders",
      label: BINDER_OCCUPANCY_TITLE,
      icon: "booklet",
      href: null,
      metric: null,
      disabledReason: null,
    },
  ];
}
