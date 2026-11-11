/**
 * V1-14 — bloco Locais — relatórios da página Meus Locais de Armazenamento
 * (menu "De Meus locais"). Sem banco.
 *
 * - "Distribuição do Acervo por Local" (Quantidade de Exemplares por Local,
 *   D7 §4s): global, abre direto do menu;
 * - "Inventário do Local" (D7 §4r): é de UM recipiente — emitido no painel do
 *   local ("Gerar inventário deste local"); no menu aparece indisponível com o
 *   caminho, para ser descoberto sem mudar o fluxo homologado.
 * Capacidade e ocupação de fichários (relatório 3) não aparece antes de existir.
 */
import type { ReportMenuItem } from "./collection-checklist.ts";
import { LOCATION_DISTRIBUTION_TITLE } from "./location-distribution.ts";

export type LocationsReportId = "distribution";

export const LOCATIONS_REPORT_PURPOSE = "Como todos os exemplares físicos estão distribuídos pelos seus locais.";

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
      id: "inventory",
      label: "Inventário do Local",
      icon: "inventory",
      href: null,
      metric: null,
      disabledReason: "Abra um local e use “Gerar inventário deste local”.",
    },
  ];
}
