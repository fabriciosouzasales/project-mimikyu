/**
 * V1-14 R1-A — Relatórios contextuais: "Checklist de completude" de uma coleção (regras puras).
 *
 * Contrato: `docs/domain-modeling/collections/reports-product-contract.md` (D7).
 * - Contexto = a coleção aberta; só o titular (as leituras `get_my_*` já restringem a
 *   `auth.uid()` e devolvem zero linhas para coleção alheia — sem enumerar).
 * - Completude canônica, sem recalcular regra no navegador:
 *     Set padrão  → uma posição por carta do Set (5169); satisfeita com ≥ 1 exemplar alocado.
 *     Master Set  → uma posição por carta + acabamento do objetivo (5189/5198); carta secreta
 *                   = posição genérica (qualquer acabamento vale).
 *   `is_satisfied` vem do banco; aqui só agrupamos, contamos e paginamos para o papel.
 * - Percentual de completude nunca se mistura com valor monetário (D7.5).
 * - Integridade do conjunto (D7.7): o relatório só é "completo" quando TODAS as posições do
 *   filtro foram lidas; caso contrário a impressão mostra a limitação, nunca dados parciais.
 */

import { progressPercent, progressPercentText } from "../colecoes/colecoes.ts";
import type { PositionFilter } from "../colecoes/colecoes.ts";

/** Lote por chamada — o teto das leituras de posição (5169/5198: p_limit 1..500). */
export const CHECKLIST_BATCH = 500;
/** Teto do relatório: acima disso o conjunto não é preparado (nunca truncado em silêncio). */
export const CHECKLIST_MAX_POSITIONS = 5000;

export type ChecklistKind = "STANDARD_SET" | "MASTER_SET";

/** Objetivo da coleção → tipo de checklist; `null` = não há checklist nesta fase (Pokédex, livre). */
export function checklistKindOf(completionPolicy: string | null | undefined): ChecklistKind | null {
  if (completionPolicy === "STANDARD_SET") return "STANDARD_SET";
  if (completionPolicy === "MASTER_SET") return "MASTER_SET";
  return null;
}

export type ChecklistRow = {
  key: string;
  number: string;
  name: string;
  /** Master Set: acabamento da posição; "Qualquer acabamento" na secreta. Set padrão: `null`. */
  finish: string | null;
  owned: boolean;
  /** Exemplares desta posição alocados à coleção. */
  copies: number;
  /** Falta na coleção, mas há exemplar livre no acervo. */
  inAcervo: boolean;
  /**
   * R2-B (Cartas faltantes) — campos só de leitura, já devolvidos por 5169/5198, sem efeito no
   * Checklist: carta da posição, exemplares livres no acervo que atendem ESTA posição
   * (`copies_available`) e frente da carta (`image_path`).
   */
  cardId?: string;
  available?: number;
  imagePath?: string | null;
};

type RawPosition = {
  card_id?: unknown;
  collector_number?: unknown;
  card_name?: unknown;
  variant_type_id?: unknown;
  variant_type_name?: unknown;
  is_satisfied?: unknown;
  copies_in_collection?: unknown;
  copies_available?: unknown;
  total_count?: unknown;
  image_path?: unknown;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function count(value: unknown): number {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : 0;
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/** Linhas cruas de 5169 (Set) ou 5189/5198 (Master Set) → linhas do checklist + total do filtro. */
export function parseChecklistRows(kind: ChecklistKind, data: unknown): { rows: ChecklistRow[]; total: number } | null {
  if (!Array.isArray(data)) return null;
  const rows: ChecklistRow[] = [];
  let total = 0;
  for (const raw of data as RawPosition[]) {
    if (typeof raw?.card_id !== "string" || !UUID.test(raw.card_id)) continue;
    const cardId = raw.card_id.toLowerCase();
    let finish: string | null = null;
    let finishKey = "";
    if (kind === "MASTER_SET") {
      const typeId = typeof raw.variant_type_id === "string" && UUID.test(raw.variant_type_id) ? raw.variant_type_id.toLowerCase() : null;
      const typeName = typeof raw.variant_type_name === "string" ? raw.variant_type_name.trim() : "";
      finish = typeId === null ? "Qualquer acabamento" : typeName || "Acabamento";
      finishKey = typeId ?? "secreta";
    }
    const owned = raw.is_satisfied === true;
    rows.push({
      key: kind === "MASTER_SET" ? `${cardId}:${finishKey}` : cardId,
      number: typeof raw.collector_number === "string" ? raw.collector_number : "",
      name: typeof raw.card_name === "string" ? raw.card_name : "",
      finish,
      owned,
      copies: count(raw.copies_in_collection),
      inAcervo: !owned && count(raw.copies_available) > 0,
      cardId,
      available: count(raw.copies_available),
      imagePath: typeof raw.image_path === "string" && raw.image_path.length > 0 ? raw.image_path : null,
    });
    total = Math.max(total, count(raw.total_count));
  }
  return { rows, total };
}

export type ChecklistLoad =
  | { status: "error" }
  | {
      status: "ready";
      rows: ChecklistRow[];
      /** Total de posições do filtro informado pelo banco. */
      total: number;
      /** `true` só quando `rows.length === total` — condição para imprimir. */
      complete: boolean;
      /** Por que não está completo (para a tela e para a folha). */
      incompleteReason: "too_large" | "partial_failure" | null;
    };

type FetchPage = (offset: number, limit: number) => Promise<unknown | null>;

/**
 * Lê o conjunto inteiro do filtro em lotes de 500 (o teto das RPCs), em ordem. Falha no
 * primeiro lote = erro; falha depois = conjunto parcial, marcado como incompleto. Acima do
 * teto do relatório não lê nada além do primeiro lote e marca "too_large".
 */
export async function loadChecklist(kind: ChecklistKind, fetchPage: FetchPage, cap = CHECKLIST_MAX_POSITIONS): Promise<ChecklistLoad> {
  const first = parseChecklistRows(kind, await fetchPage(0, CHECKLIST_BATCH));
  if (!first) return { status: "error" };
  const total = first.total;
  const rows = [...first.rows];
  if (total > cap) {
    return { status: "ready", rows, total, complete: false, incompleteReason: "too_large" };
  }
  let offset = CHECKLIST_BATCH;
  let lastSize = first.rows.length;
  while (rows.length < total && lastSize > 0 && offset < cap) {
    const page = parseChecklistRows(kind, await fetchPage(offset, CHECKLIST_BATCH));
    if (!page) return { status: "ready", rows, total, complete: false, incompleteReason: "partial_failure" };
    rows.push(...page.rows);
    lastSize = page.rows.length;
    offset += CHECKLIST_BATCH;
  }
  const unique = new Set(rows.map((row) => row.key)).size === rows.length;
  const complete = unique && rows.length === total;
  return { status: "ready", rows, total, complete, incompleteReason: complete ? null : "partial_failure" };
}

export type ChecklistSummary = {
  total: number;
  owned: number;
  missing: number;
  percent: number;
  percentText: string;
};

/** Resumo canônico da coleção (5188/5332): independe do filtro exibido. */
export function checklistSummary(totalPositions: number, satisfiedPositions: number): ChecklistSummary {
  const total = Math.max(0, Math.floor(totalPositions));
  const owned = Math.min(total, Math.max(0, Math.floor(satisfiedPositions)));
  return {
    total,
    owned,
    missing: total - owned,
    percent: progressPercent(owned, total),
    percentText: progressPercentText(owned, total),
  };
}

export function checklistFilterLabel(filter: PositionFilter): string {
  return filter === "tenho" ? "Somente possuídas" : filter === "faltam" ? "Somente faltantes" : "Todas as posições";
}

/** Rótulo curto do filtro para a folha impressa. */
export function checklistFilterShortLabel(filter: PositionFilter): string {
  return filter === "tenho" ? "Possuídas" : filter === "faltam" ? "Faltantes" : "Todas";
}

/**
 * Resumo objetivo da folha: "94% completo · 149 de 158 posições · 9 faltantes". Sempre a
 * partir dos números canônicos da coleção (nunca fixos), com singular/plural.
 */
export function checklistSummaryLine(total: number, satisfied: number): string {
  const summary = checklistSummary(total, satisfied);
  const n = new Intl.NumberFormat("pt-BR");
  const positions = summary.total === 1 ? "posição" : "posições";
  const missing = summary.missing === 1 ? "faltante" : "faltantes";
  return `${summary.percentText} completo · ${n.format(summary.owned)} de ${n.format(summary.total)} ${positions} · ${n.format(summary.missing)} ${missing}`;
}

export function checklistKindLabel(kind: ChecklistKind): string {
  return kind === "MASTER_SET" ? "Master Set (carta + acabamento)" : "Set padrão (uma posição por carta)";
}

export function checklistHref(collectionId: string, filter: PositionFilter = "todas"): string {
  const base = `/colecoes/colecoes/${collectionId}/relatorios/checklist`;
  return filter === "todas" ? base : `${base}?situacao=${filter}`;
}

/** `?situacao=` do relatório (mesmos valores do filtro da coleção). */
export function parseChecklistFilter(value: string | string[] | undefined): PositionFilter {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw === "tenho" || raw === "faltam" ? raw : "todas";
}

/**
 * Siglas de apresentação dos acabamentos na folha impressa do Master Set — só apresentação: dados,
 * regras e nomes canônicos (`card_variant_type.name`) não mudam. Chave = nome canônico
 * normalizado (sem acento, minúsculo). Só ganham sigla acabamentos com correspondência inequívoca
 * no catálogo (seed 850 + migrações 3924/2265); qualquer outro sai com o nome canônico por extenso
 * (nunca uma sigla inventada). "Qualquer acabamento" = posição de carta secreta do objetivo.
 */
export const CHECKLIST_FINISH_CODES: readonly { code: string; label: string }[] = [
  { code: "PA", label: "Padrão" },
  { code: "HO", label: "Holográfica" },
  { code: "HR", label: "Holográfica Reversa" },
  { code: "HC", label: "Holográfica Cosmos" },
  { code: "ER", label: "Energia Reversa" },
  { code: "PBR", label: "Poké Bola Reversa" },
  { code: "MBR", label: "Master Ball Reversa" },
  { code: "LBR", label: "Love Ball Reversa" },
  { code: "FBR", label: "Friend Ball Reversa" },
  { code: "QBR", label: "Quick Ball Reversa" },
  { code: "DBR", label: "Dusk Ball Reversa" },
  { code: "QA", label: "Qualquer acabamento" },
];

function normalizeFinish(name: string): string {
  return name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

const FINISH_BY_NAME = new Map(CHECKLIST_FINISH_CODES.map((entry) => [normalizeFinish(entry.label), entry]));

/** Sigla do acabamento pelo nome canônico; `null` = sem sigla oficial (imprime o nome por extenso). */
export function checklistFinishCode(finish: string | null): { code: string; label: string } | null {
  if (!finish) return null;
  return FINISH_BY_NAME.get(normalizeFinish(finish)) ?? null;
}

/** Siglas presentes no conjunto, na ordem fixa da tabela — legenda só do que aparece na folha. */
export function checklistFinishLegend(finishes: readonly (string | null)[]): { code: string; label: string }[] {
  const used = new Set(finishes.map((finish) => checklistFinishCode(finish)?.code).filter(Boolean));
  return CHECKLIST_FINISH_CODES.filter((entry) => used.has(entry.code));
}

/** Data/hora de emissão para a folha (pt-BR, fuso do servidor). */
export function issuedAtLabel(now: Date): string {
  return now.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export type ReportMenuIcon = "checklist" | "missing" | "value" | "wish" | "favorite" | "top" | "duplicates" | "distribution" | "inventory" | "inventory-sets" | "collections" | "upcoming" | "evolution" | "rarity" | "booklet";

export type ReportMenuItem = {
  id: string;
  label: string;
  icon: ReportMenuIcon;
  /** Acesso direto (rota auxiliar); o fluxo principal abre o relatório em sobreposição. */
  href: string | null;
  /** Prévia curta (ex.: "62% completo"). */
  metric: string | null;
  /** Indisponível: o motivo aparece no item (nunca some — memória espacial). */
  disabledReason: string | null;
};

/**
 * Relatórios da coleção para o menu de Relatórios da cápsula: Checklist de completude (R1-A ≡
 * R2-A), Cartas faltantes (R2-B), Cartas desejadas do Card Set (R2-C), Cartas favoritas do Card Set
 * (R2-D), Valor estimado (R2-E), Evolução da completude (R2-F), Distribuição por raridade (R2-G) e o Caderno de Cartas. Nenhum botão fictício. Coleção fora de Set padrão/Master Set
 * mostra os itens indisponíveis, com o motivo.
 */
export function collectionReportItems(input: {
  collectionId: string;
  completionPolicy: string;
  totalPositions: number;
  satisfiedPositions: number;
}): ReportMenuItem[] {
  const kind = checklistKindOf(input.completionPolicy);
  const summary = checklistSummary(input.totalPositions, input.satisfiedPositions);
  return [
    {
      id: "checklist",
      label: "Checklist de completude",
      icon: "checklist",
      href: kind ? checklistHref(input.collectionId) : null,
      metric: kind && summary.total > 0 ? summary.percentText : null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      id: "missing",
      label: "Cartas faltantes",
      icon: "missing",
      href: null,
      metric: kind && summary.total > 0 ? (summary.missing === 0 ? "Completa" : `${new Intl.NumberFormat("pt-BR").format(summary.missing)} faltam`) : null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      id: "set-wishlist",
      label: "Cartas desejadas do Card Set",
      icon: "wish",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      id: "set-favorites",
      label: "Cartas favoritas do Card Set",
      icon: "favorite",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      // R2-E (D7 §4m): valor estimado dos exemplares alocados a esta coleção.
      id: "collection-value",
      label: "Valor estimado",
      icon: "value",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      // R2-F (D7 §4n): evolução da completude por fechamento diário, a partir do primeiro fechamento.
      id: "completion-history",
      label: "Evolução da completude",
      icon: "evolution",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      // R2-G (D7 §4o): posições do objetivo por raridade da carta.
      id: "rarity-distribution",
      label: "Distribuição por raridade",
      icon: "rarity",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
    {
      // Caderno de Cartas (D7 §4p): peça editorial do Card Set completo.
      id: "card-booklet",
      label: "Caderno de Cartas",
      icon: "booklet",
      href: null,
      metric: null,
      disabledReason: kind ? null : "Para coleções de Set padrão e Master Set.",
    },
  ];
}

/** Fase 2 (D7 §4q): motivo dos relatórios aprovados que ainda não foram entregues. */
export const PHASE2_UPCOMING_REASON = "Em preparação.";

/**
 * Relatórios do menu da coleção Pokédex (D7 §4q). Só o que é aplicável à modalidade: Checklist da
 * Pokédex e Espécies faltantes (F2-2) e Valor estimado (F2-1) disponíveis; Composição da coleção
 * (F2-3) visível e indisponível até ser entregue. Sem Caderno, desejadas, favoritas nem evolução.
 */
export function pokedexReportItems(): ReportMenuItem[] {
  return [
    { id: "pokedex-checklist", label: "Checklist da Pokédex", icon: "checklist", href: null, metric: null, disabledReason: null },
    { id: "pokedex-missing", label: "Espécies faltantes", icon: "missing", href: null, metric: null, disabledReason: null },
    { id: "collection-value", label: "Valor estimado", icon: "value", href: null, metric: null, disabledReason: null },
    { id: "collection-composition", label: "Composição da coleção", icon: "distribution", href: null, metric: null, disabledReason: PHASE2_UPCOMING_REASON },
  ];
}

/**
 * Relatórios do menu da Coleção livre (D7 §4q, F2-1). Sem objetivo de completude: nada de checklist,
 * faltantes ou percentuais. Valor estimado disponível; Composição da coleção (F2-3) indisponível até
 * ser entregue.
 */
export function freeCollectionReportItems(): ReportMenuItem[] {
  return [
    { id: "collection-value", label: "Valor estimado", icon: "value", href: null, metric: null, disabledReason: null },
    { id: "collection-composition", label: "Composição da coleção", icon: "distribution", href: null, metric: null, disabledReason: PHASE2_UPCOMING_REASON },
  ];
}
