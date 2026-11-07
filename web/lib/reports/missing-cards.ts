/**
 * V1-14 R2-B — "Cartas faltantes" de uma coleção (regras puras, sem banco, sem rede). Contrato:
 * D7 v1.42 §4j.
 *
 * Completude = a do Checklist homologado (R1-A ≡ R2-A), sem regra nova: as posições faltantes vêm
 * das leituras canônicas com o filtro `MISSING` (5169 Set padrão; 5198 Master Set), lidas por
 * `loadChecklist`/`parseChecklistRows`; posição faltante = `is_satisfied` falso, decidido pelo
 * banco. Aqui só agrupamos e contamos — sempre por POSIÇÃO.
 *
 * Grupos, nesta ordem, cada um na ordem original do Set:
 *  1. "No acervo — disponível para alocar": `copies_available > 0` (exemplar livre — fora de
 *     qualquer coleção — que atende a posição; por 5198/5187 os conjuntos de exemplares que
 *     atendem posições diferentes são disjuntos: nenhum exemplar é contado para duas posições);
 *  2. "Sem exemplar disponível": nenhum exemplar livre identificado pelas leituras — NÃO significa
 *     que o colecionador não tem a carta nem que precisa comprá-la (pode estar em outra coleção).
 * Master Set: os acabamentos faltantes da mesma carta ficam agrupados VISUALMENTE numa linha por
 * grupo, cada acabamento com a própria disponibilidade; a carta pode aparecer nos dois grupos.
 * Integridade: posições lidas = `total_count` do filtro = "faltam" do resumo canônico (5332), e
 * nenhuma posição satisfeita no conjunto; senão incompleto (impressão bloqueada).
 */
import { type ChecklistKind, type ChecklistLoad, type ChecklistRow, checklistFinishCode, checklistSummary } from "./collection-checklist.ts";

export type MissingGroupId = "available" | "unavailable";

export const MISSING_GROUP_TITLE: Record<MissingGroupId, string> = {
  available: "No acervo — disponível para alocar",
  unavailable: "Sem exemplar disponível",
};

/** Um acabamento faltante (Master Set) com a disponibilidade da PRÓPRIA posição. */
export type MissingFinish = { key: string; label: string; code: string | null; available: number };

export type MissingLine = {
  /** Chave da linha (grupo + carta): uma por carta em cada grupo. */
  key: string;
  cardId: string;
  number: string;
  name: string;
  imagePath: string | null;
  /** Master Set: acabamentos faltantes DESTE grupo; Set padrão: vazio. */
  finishes: MissingFinish[];
  /** Posições faltantes representadas pela linha (Set padrão: 1; Master Set: nº de acabamentos). */
  positions: number;
  /** Σ exemplares livres das posições da linha (só informativo; nunca vira contagem de posições). */
  available: number;
};

export type MissingGroup = { id: MissingGroupId; title: string; lines: MissingLine[]; positions: number };

export type MissingIncompleteReason = "too_large" | "partial_failure" | "mismatch" | null;

export type MissingCardsReport = {
  kind: ChecklistKind;
  /** Resumo canônico da coleção (5332) — total, possuídas, faltam, percentual. */
  summary: ReturnType<typeof checklistSummary>;
  /** Posições faltantes lidas. */
  missingPositions: number;
  availablePositions: number;
  unavailablePositions: number;
  /** Master Set: cartas distintas com pendência; Set padrão: = posições. */
  pendingCards: number;
  groups: MissingGroup[];
  /** "list" = há faltantes; "complete" = coleção completa; "empty" = objetivo sem posições. */
  state: "list" | "complete" | "empty";
  complete: boolean;
  incompleteReason: MissingIncompleteReason;
};

export function buildMissingCardsReport(input: { kind: ChecklistKind; load: Extract<ChecklistLoad, { status: "ready" }>; totalPositions: number; satisfiedPositions: number }): MissingCardsReport {
  const { kind, load } = input;
  const summary = checklistSummary(input.totalPositions, input.satisfiedPositions);
  const rows = load.rows;
  const byGroup: Record<MissingGroupId, Map<string, MissingLine>> = { available: new Map(), unavailable: new Map() };
  const positionsByGroup: Record<MissingGroupId, number> = { available: 0, unavailable: 0 };
  const pendingCards = new Set<string>();
  let satisfiedInSet = 0;

  for (const row of rows) {
    if (row.owned) {
      satisfiedInSet += 1; // filtro MISSING nunca devolve satisfeita — se vier, é inconsistência
      continue;
    }
    const group: MissingGroupId = (row.available ?? 0) > 0 ? "available" : "unavailable";
    const cardId = row.cardId ?? row.key;
    pendingCards.add(cardId);
    positionsByGroup[group] += 1;
    const lineKey = kind === "MASTER_SET" ? `${group}:${cardId}` : `${group}:${row.key}`;
    let line = byGroup[group].get(lineKey);
    if (!line) {
      line = { key: lineKey, cardId, number: row.number, name: row.name, imagePath: row.imagePath ?? null, finishes: [], positions: 0, available: 0 };
      byGroup[group].set(lineKey, line);
    }
    line.positions += 1;
    line.available += row.available ?? 0;
    if (kind === "MASTER_SET") line.finishes.push(finishOf(row));
  }

  const groups: MissingGroup[] = (["available", "unavailable"] as const)
    .map((id) => ({ id, title: MISSING_GROUP_TITLE[id], lines: [...byGroup[id].values()], positions: positionsByGroup[id] }))
    .filter((group) => group.lines.length > 0);

  const missingPositions = positionsByGroup.available + positionsByGroup.unavailable;
  const consistent = satisfiedInSet === 0 && rows.length === load.total && load.total === summary.missing && missingPositions === summary.missing;
  const incompleteReason: MissingIncompleteReason = !load.complete ? (load.incompleteReason ?? "partial_failure") : !consistent ? "mismatch" : null;
  const state: MissingCardsReport["state"] = summary.total === 0 ? "empty" : summary.missing === 0 && missingPositions === 0 ? "complete" : "list";

  return {
    kind,
    summary,
    missingPositions,
    availablePositions: positionsByGroup.available,
    unavailablePositions: positionsByGroup.unavailable,
    pendingCards: pendingCards.size,
    groups,
    state,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

function finishOf(row: ChecklistRow): MissingFinish {
  const label = row.finish ?? "Acabamento";
  return { key: row.key, label, code: checklistFinishCode(label)?.code ?? null, available: row.available ?? 0 };
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

const N = new Intl.NumberFormat("pt-BR");
const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;

/** Situação de uma posição/linha: "No acervo · 2 livres" ou "Sem exemplar disponível". */
export function missingAvailabilityText(available: number): string {
  return available > 0 ? `No acervo · ${plural(available, "livre", "livres")}` : "Sem exemplar disponível";
}

/** Nome do acabamento para a linha: sigla homologada (ou o nome por extenso, sem sigla inventada). */
export function missingFinishText(finish: MissingFinish): string {
  return finish.code ?? finish.label;
}

export function missingSummaryLine(report: Pick<MissingCardsReport, "summary">): string {
  const { summary } = report;
  return `${summary.percentText} completo · ${plural(summary.missing, "posição faltante", "posições faltantes")} de ${N.format(summary.total)}`;
}

/**
 * Linha de metadados do cabeçalho impresso — curta o bastante para nunca ser truncada (D7 §2: texto
 * de metadado nunca é cortado): "Set padrão · 94% completo · 9 faltantes de 158 · Emitido em …".
 */
export function missingHeaderLine(report: Pick<MissingCardsReport, "kind" | "summary">, issuedAt: string): string {
  const kind = report.kind === "MASTER_SET" ? "Master Set" : "Set padrão";
  const { summary } = report;
  return `${kind} · ${summary.percentText} completo · ${N.format(summary.missing)} ${summary.missing === 1 ? "faltante" : "faltantes"} de ${N.format(summary.total)} · Emitido em ${issuedAt}`;
}

export function missingIncompleteText(reason: MissingIncompleteReason): string | null {
  if (reason === "too_large") return "A coleção tem mais posições do que este relatório consegue preparar; a lista não está completa e a impressão fica indisponível.";
  if (reason === "partial_failure") return "Parte das posições não pôde ser lida agora; a lista não está completa e a impressão fica indisponível. Tente novamente.";
  if (reason === "mismatch")
    return "As posições faltantes não fecharam com o resumo da coleção no momento da leitura (a coleção mudou durante a leitura?). Tente novamente; a impressão fica indisponível.";
  return null;
}

/** Filtros da TELA (não alteram o conjunto impresso). */
export type MissingScreenFilter = "all" | MissingGroupId;
export const MISSING_SCREEN_FILTERS: readonly { value: MissingScreenFilter; label: string }[] = [
  { value: "all", label: "Todas" },
  { value: "available", label: "No acervo" },
  { value: "unavailable", label: "Sem exemplar disponível" },
];

/** Grupos visíveis na tela para o filtro; a impressão sempre usa `report.groups` inteiro. */
export function missingGroupsForScreen(groups: readonly MissingGroup[], filter: MissingScreenFilter): MissingGroup[] {
  return filter === "all" ? [...groups] : groups.filter((group) => group.id === filter);
}

/** Impressão em duas colunas: pares em ordem de leitura (esquerda → direita, depois a linha de baixo). */
export function missingPrintPairs<T>(lines: readonly T[]): [T, T | null][] {
  const pairs: [T, T | null][] = [];
  for (let i = 0; i < lines.length; i += 2) pairs.push([lines[i] as T, (lines[i + 1] as T | undefined) ?? null]);
  return pairs;
}
