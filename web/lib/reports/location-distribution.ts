/**
 * V1-14 — bloco Locais — "Quantidade de Exemplares por Local" (título editorial
 * "Distribuição do Acervo por Local"). Regras puras; sem banco.
 *
 * Fonte: a MESMA leitura homologada de Meus locais (5219):
 * `get_my_storage_locations` (todos os locais do titular, com `card_count` =
 * exemplares físicos diretamente no local, agregado no banco, sem limite) e
 * `get_my_storage_summary` (total, com local, sem localização, nº de locais).
 * Unidade = exemplar físico; um exemplar está em no máximo um local.
 *
 * Reconciliação (D7 §4s): total = com local + sem localização; Σ exemplares dos
 * locais = com local; nº de locais lidos = nº de locais do resumo. Qualquer
 * divergência → relatório incompleto (impressão bloqueada), nunca ajustado.
 *
 * Percentuais: todos sobre o MESMO denominador — o acervo físico total — com
 * uma casa decimal (as regras de Meus locais: `shareTenths`). A barra de cada
 * local é só comparação gráfica (relativa ao local com mais exemplares) e a
 * folha diz isso; o número escrito é sempre a participação no acervo.
 * Sem capacidade, bolsos ou ocupação (relatório 3, pendente).
 */
import { acervoShareText, organizationShareText, splitLocationCode } from "../colecoes/storage-locations.ts";

export const LOCATION_DISTRIBUTION_TITLE = "Distribuição do Acervo por Local";
export const LOCATION_DISTRIBUTION_SUBTITLE = "Quantidade de Exemplares por Local";

export type DistributionLocationInput = {
  id: string;
  name: string;
  kindCode: string | null;
  kindLabel: string | null;
  cardCount: number;
};

export type DistributionSummaryInput = {
  totalCards: number;
  locatedCards: number;
  unlocatedCards: number;
  locationCount: number;
};

export type DistributionLocationRow = {
  id: string;
  /** Código do colecionador no início do nome ("BX001"), quando existe — nunca inventado. */
  code: string | null;
  title: string;
  kindLabel: string;
  copies: number;
  /** Participação no acervo físico total ("14,2%", "0,0%", "<0,1%"). */
  share: string;
  /** Comprimento da barra (0–100) relativo ao local com mais exemplares. */
  bar: number;
};

export type DistributionKindRow = {
  /** Código canônico do tipo (5212); `null` = locais sem tipo definido. */
  code: string | null;
  label: string;
  locations: number;
  copies: number;
  share: string;
};

export type LocationDistributionReport = {
  totalCopies: number;
  locatedCopies: number;
  unlocatedCopies: number;
  /** "98,7%" / "—" (acervo vazio). */
  organization: string;
  unlocatedShare: string;
  kinds: DistributionKindRow[];
  locations: DistributionLocationRow[];
  emptyLocations: number;
  complete: boolean;
  incompleteReason: "read" | "mismatch" | null;
};

export const UNTYPED_KIND_LABEL = "Sem tipo definido";

const NAME_ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });

/** Participação no acervo físico total; local/tipo vazio = "0,0%"; acervo vazio = "—". */
export function distributionShareText(copies: number, totalCopies: number): string {
  if (totalCopies <= 0) return "—";
  if (copies <= 0) return "0,0%";
  return acervoShareText(copies, totalCopies) ?? "0,0%";
}

export function buildLocationDistribution(input: {
  locations: readonly DistributionLocationInput[];
  summary: DistributionSummaryInput;
  /** A leitura dos locais veio inteira (nenhuma linha fora do formato). */
  readComplete: boolean;
}): LocationDistributionReport {
  const { summary } = input;
  const total = summary.totalCards;
  const located = input.locations.reduce((n, l) => n + l.cardCount, 0);

  const maxCopies = input.locations.reduce((m, l) => Math.max(m, l.cardCount), 0);
  const locations: DistributionLocationRow[] = [...input.locations]
    .sort((a, b) => b.cardCount - a.cardCount || NAME_ORDER.compare(a.name, b.name) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((l) => {
      const { code, title } = splitLocationCode(l.name);
      return {
        id: l.id,
        code,
        title: code ? title : l.name,
        kindLabel: l.kindCode ? (l.kindLabel ?? l.kindCode) : UNTYPED_KIND_LABEL,
        copies: l.cardCount,
        share: distributionShareText(l.cardCount, total),
        bar: maxCopies > 0 && l.cardCount > 0 ? (l.cardCount * 100) / maxCopies : 0,
      };
    });

  // Agrupa pelo CÓDIGO canônico do tipo (nunca pelo texto); rótulo do catálogo.
  const groups = new Map<string, DistributionKindRow>();
  for (const l of input.locations) {
    const key = l.kindCode ?? "";
    const group = groups.get(key) ?? {
      code: l.kindCode,
      label: l.kindCode ? (l.kindLabel ?? l.kindCode) : UNTYPED_KIND_LABEL,
      locations: 0,
      copies: 0,
      share: "",
    };
    group.locations += 1;
    group.copies += l.cardCount;
    groups.set(key, group);
  }
  const kinds = [...groups.values()]
    .map((g) => ({ ...g, share: distributionShareText(g.copies, total) }))
    .sort((a, b) => b.copies - a.copies || (a.code === null ? 1 : 0) - (b.code === null ? 1 : 0) || NAME_ORDER.compare(a.label, b.label));

  const reconciled =
    summary.totalCards === summary.locatedCards + summary.unlocatedCards &&
    located === summary.locatedCards &&
    input.locations.length === summary.locationCount;
  const incompleteReason = !input.readComplete ? "read" : !reconciled ? "mismatch" : null;

  return {
    totalCopies: total,
    locatedCopies: summary.locatedCards,
    unlocatedCopies: summary.unlocatedCards,
    organization: organizationShareText(summary),
    unlocatedShare: distributionShareText(summary.unlocatedCards, total),
    kinds,
    locations,
    emptyLocations: input.locations.filter((l) => l.cardCount === 0).length,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function locationDistributionIncompleteText(reason: LocationDistributionReport["incompleteReason"]): string | null {
  if (reason === "read") return "A leitura dos seus locais veio incompleta agora — a impressão fica bloqueada. Tente novamente em instantes.";
  if (reason === "mismatch") return "Os totais dos locais não conferem com o total do acervo agora — a impressão fica bloqueada. Tente novamente em instantes.";
  return null;
}

/** Linha de resumo do cabeçalho institucional. */
export function locationDistributionSummaryLine(report: LocationDistributionReport): string {
  const exemplares = `${new Intl.NumberFormat("pt-BR").format(report.totalCopies)} ${report.totalCopies === 1 ? "exemplar físico" : "exemplares físicos"}`;
  const locais = `${report.locations.length} ${report.locations.length === 1 ? "local" : "locais"}`;
  return `${LOCATION_DISTRIBUTION_SUBTITLE} · ${exemplares} · ${locais}`;
}
