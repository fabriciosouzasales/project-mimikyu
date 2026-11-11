/**
 * V1-14 — bloco Locais — "Capacidade e Ocupação de Fichários" (D7 §4t).
 * Regras puras; sem banco.
 *
 * Universo: os locais do tipo canônico Fichário físico (`BINDER`, 5212) do
 * titular, lidos na 5219 (com os exemplares físicos guardados em cada um).
 * Capacidade e ocupação vêm do FICHÁRIO DIGITAL vinculado ao local
 * (`collection_layout.storage_container_id`, único por local — 5247) pela
 * leitura homologada do painel "Informações do Fichário" (5245
 * `get_my_binder_occupancy`): cada bolso existe como registro e cai em UM
 * estado, nesta precedência — com carta > com imagem > em mesclagem >
 * reservado vazio > livre. A trava é atributo do bolso, não estado.
 *
 * Capacidade = capacidade CONFIGURADA no fichário digital (páginas × grade),
 * não capacidade física comprovada. Ocupados = com carta + com imagem + em
 * mesclagem; percentual inteiro, a MESMA regra do painel (`occupancyPercent`).
 * Fichário físico sem fichário digital → capacidade desconhecida (nunca 0,
 * nunca estimada). Um exemplar ocupa no máximo um bolso e só ocupa bolso do
 * próprio local (5248): exemplares fora de bolsos = exemplares do local −
 * bolsos com carta; diferença negativa ou estados que não somam a capacidade →
 * relatório inconsistente (impressão bloqueada), nunca ajustado.
 */
import { type BinderOccupancy, occupancyPercent } from "../colecoes/binder-identity.ts";
import { splitLocationCode } from "../colecoes/storage-locations.ts";

export const BINDER_OCCUPANCY_TITLE = "Capacidade e Ocupação de Fichários";
export const BINDER_KIND_CODE = "BINDER";

export type BinderOccupancyInput = {
  id: string;
  name: string;
  /** Exemplares físicos guardados no local (5219 `card_count`). */
  storedCopies: number;
  /** Ocupação do fichário digital vinculado (5245); `null` = sem fichário digital vinculado. */
  occupancy: Pick<BinderOccupancy, "columns" | "rows" | "pages" | "pockets" | "cards" | "images" | "merged" | "reservedEmpty" | "free"> | null;
};

export type BinderRowState = "configured" | "no_pockets" | "unlinked";

export type BinderOccupancyRow = {
  id: string;
  code: string | null;
  title: string;
  state: BinderRowState;
  storedCopies: number;
  /** "3×3 · 40 páginas" (colunas × linhas, como no painel); `null` sem fichário digital. */
  configuration: string | null;
  capacity: number | null;
  cards: number | null;
  /** Bolsos com imagem + em mesclagem (elementos visuais). */
  visual: number | null;
  reservedEmpty: number | null;
  free: number | null;
  occupied: number | null;
  /** Inteiro (0–100) só com capacidade > 0; `null` caso contrário. */
  percent: number | null;
  /** Exemplares do local fora de bolsos (só com fichário digital). */
  outsidePockets: number | null;
};

export type BinderOccupancyReport = {
  binders: number;
  configured: number;
  noPockets: number;
  unlinked: number;
  capacity: number;
  cards: number;
  visual: number;
  reservedEmpty: number;
  free: number;
  occupied: number;
  /** Ocupação consolidada (inteiro) entre os fichários com capacidade configurada; `null` se nenhum. */
  percent: number | null;
  outsidePockets: number;
  /** Exemplares guardados em fichários sem estrutura de bolsos configurada. */
  unstructuredCopies: number;
  rows: BinderOccupancyRow[];
  complete: boolean;
  incompleteReason: "read" | "mismatch" | null;
};

const NAME_ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const INT = new Intl.NumberFormat("pt-BR");

function configurationLabel(o: NonNullable<BinderOccupancyInput["occupancy"]>): string {
  return `${o.columns}×${o.rows} · ${INT.format(o.pages)} ${o.pages === 1 ? "página" : "páginas"}`;
}

export function buildBinderOccupancy(input: { binders: readonly BinderOccupancyInput[]; readComplete: boolean }): BinderOccupancyReport {
  let mismatch = false;
  const rows: BinderOccupancyRow[] = input.binders.map((b) => {
    const { code, title } = splitLocationCode(b.name);
    const base = { id: b.id, code, title: code ? title : b.name, storedCopies: b.storedCopies };
    const o = b.occupancy;
    if (!o) {
      return { ...base, state: "unlinked", configuration: null, capacity: null, cards: null, visual: null, reservedEmpty: null, free: null, occupied: null, percent: null, outsidePockets: null };
    }
    const occupied = o.cards + o.images + o.merged;
    const outside = b.storedCopies - o.cards;
    // Reconciliação dos estados (cada bolso uma vez) e do posicionamento físico (5248).
    if (o.pockets !== occupied + o.reservedEmpty + o.free || outside < 0) mismatch = true;
    return {
      ...base,
      state: o.pockets > 0 ? "configured" : "no_pockets",
      configuration: configurationLabel(o),
      capacity: o.pockets,
      cards: o.cards,
      visual: o.images + o.merged,
      reservedEmpty: o.reservedEmpty,
      free: o.free,
      occupied,
      percent: o.pockets > 0 ? occupancyPercent(o) : null,
      outsidePockets: outside,
    };
  });

  const rank: Record<BinderRowState, number> = { configured: 0, no_pockets: 1, unlinked: 2 };
  rows.sort(
    (a, b) =>
      rank[a.state] - rank[b.state] ||
      (b.percent ?? -1) - (a.percent ?? -1) ||
      NAME_ORDER.compare(a.code ?? a.title, b.code ?? b.title) ||
      NAME_ORDER.compare(a.title, b.title) ||
      (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );

  const configured = rows.filter((r) => r.state === "configured");
  const sum = (key: "capacity" | "cards" | "visual" | "reservedEmpty" | "free" | "occupied") => configured.reduce((n, r) => n + (r[key] ?? 0), 0);
  const capacity = sum("capacity");
  const occupied = sum("occupied");
  const linked = rows.filter((r) => r.state !== "unlinked");
  const incompleteReason = !input.readComplete ? "read" : mismatch ? "mismatch" : null;

  return {
    binders: rows.length,
    configured: configured.length,
    noPockets: rows.filter((r) => r.state === "no_pockets").length,
    unlinked: rows.filter((r) => r.state === "unlinked").length,
    capacity,
    cards: sum("cards"),
    visual: sum("visual"),
    reservedEmpty: sum("reservedEmpty"),
    free: sum("free"),
    occupied,
    // Ponderada pela capacidade (nunca média dos percentuais), mesma regra de arredondamento do painel.
    percent: capacity > 0 ? occupancyPercent({ pockets: capacity, cards: occupied, images: 0, merged: 0 }) : null,
    outsidePockets: linked.reduce((n, r) => n + Math.max(r.outsidePockets ?? 0, 0), 0),
    unstructuredCopies: rows.filter((r) => r.state === "unlinked").reduce((n, r) => n + r.storedCopies, 0),
    rows,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function binderOccupancyIncompleteText(reason: BinderOccupancyReport["incompleteReason"]): string | null {
  if (reason === "read") return "A leitura dos seus fichários veio incompleta agora — a impressão fica bloqueada. Tente novamente em instantes.";
  if (reason === "mismatch") return "Os bolsos e os exemplares de algum fichário não conferem agora — a impressão fica bloqueada. Tente novamente em instantes.";
  return null;
}

export function binderOccupancySummaryLine(report: BinderOccupancyReport): string {
  const fisicos = `${INT.format(report.binders)} ${report.binders === 1 ? "fichário físico" : "fichários físicos"}`;
  const digitais = `${INT.format(report.binders - report.unlinked)} com fichário digital`;
  return `${fisicos} · ${digitais}`;
}
