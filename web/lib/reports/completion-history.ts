/**
 * V1-14 R2-F (B2) — "Evolução da completude" (D7 v1.63 §4n, D1–D12). Núcleo PURO do relatório:
 * interpreta a leitura do titular (`get_my_collection_completion_history`, 5358) e a completude
 * ATUAL canônica (5332 → 5188) e devolve tudo o que a folha mostra — indicadores, trechos do
 * gráfico, mudanças registradas e lacunas. Nenhuma regra de completude aqui: os números vêm da
 * 5188 (gravados no fechamento ou lidos agora); este módulo só compara e formata.
 *
 * Invariantes (D2/D3/D6/D7):
 *  - nada antes do primeiro fechamento; a série parte do valor real dele (nunca de zero);
 *  - um trecho por intervalo de cobertura; trechos separados por lacuna NUNCA se ligam;
 *  - diferença através de lacuna = período ("entre dd/mm e dd/mm"), nunca data exata;
 *  - causa só quando gravada nas duas fotografias (modalidade, Card Set, acabamentos, situação);
 *  - fechamento rotulado "fechamento de dd/mm" + "lido em dd/mm às hh:mm" — nunca "23h59";
 *  - posições satisfeitas ≠ exemplares físicos (o texto sempre diz "posições").
 */

export const COMPLETION_HISTORY_TITLE = "Evolução da completude";
const TZ = "America/Sao_Paulo";
const DAY_MS = 86_400_000;
/** Janela de validade do fechamento (D4): a captura de D vale até 03h00 de D+1. */
const CLOSING_WINDOW_HOUR = 3;

const N = new Intl.NumberFormat("pt-BR");
const PP = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

// ---------------------------------------------------------------------------------------------
// Leitura (forma da 5358) — validada; qualquer incoerência vira erro, nunca série inventada.
// ---------------------------------------------------------------------------------------------

export type CompletionSnapshot = {
  /** Dia de referência do fechamento (AAAA-MM-DD, America/Sao_Paulo). */
  day: string;
  /** Instante efetivo da leitura (ISO). */
  capturedAt: string;
  policy: string;
  cardSetId: string | null;
  finishIds: string[];
  lifecycle: string;
  total: number;
  satisfied: number;
  /** Primeiro fechamento depois de uma lacuna (ou o primeiro de todos). */
  opensCoverage: boolean;
};

export type CoverageInterval = { from: string; to: string };

export type CompletionHistory = {
  trackingSince: string | null;
  lastCoveredDay: string | null;
  coverage: CoverageInterval[];
  snapshots: CompletionSnapshot[];
};

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

function isDay(value: unknown): value is string {
  if (typeof value !== "string" || !DAY_RE.test(value)) return false;
  const t = dayIndex(value);
  return Number.isFinite(t) && dayFromIndex(t) === value;
}

function count(value: unknown): number | null {
  const v = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

/** Dia → índice de dias desde 1970-01-01 (aritmética de calendário, sem fuso). */
export function dayIndex(day: string): number {
  const [y, m, d] = day.split("-").map(Number);
  return Math.round(Date.UTC(y ?? NaN, (m ?? NaN) - 1, d ?? NaN) / DAY_MS);
}

export function dayFromIndex(index: number): string {
  return new Date(index * DAY_MS).toISOString().slice(0, 10);
}

/**
 * Interpreta a resposta da 5358. Devolve `null` (→ estado de erro) quando a forma não confere ou
 * quando fotografias e cobertura não são coerentes entre si (fotografia fora da cobertura,
 * intervalo sem fotografia de abertura, ordem ou sobreposição inválida, satisfeitas > total).
 */
export function parseCompletionHistory(raw: unknown): CompletionHistory | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const obj = raw as Record<string, unknown>;
  if (!Array.isArray(obj.coverage) || !Array.isArray(obj.snapshots)) return null;

  const coverage: CoverageInterval[] = [];
  for (const item of obj.coverage as unknown[]) {
    if (!item || typeof item !== "object") return null;
    const { from, to } = item as Record<string, unknown>;
    if (!isDay(from) || !isDay(to) || to < from) return null;
    const prev = coverage[coverage.length - 1];
    // Intervalos ordenados, disjuntos e não contíguos (contíguos seriam um só intervalo).
    if (prev && dayIndex(from) <= dayIndex(prev.to) + 1) return null;
    coverage.push({ from, to });
  }

  const snapshots: CompletionSnapshot[] = [];
  for (const item of obj.snapshots as unknown[]) {
    if (!item || typeof item !== "object") return null;
    const s = item as Record<string, unknown>;
    const total = count(s.total);
    const satisfied = count(s.satisfied);
    if (!isDay(s.day) || total === null || satisfied === null || satisfied > total) return null;
    if (typeof s.captured_at !== "string" || !Number.isFinite(Date.parse(s.captured_at))) return null;
    if (typeof s.completion_policy !== "string" || typeof s.lifecycle_status !== "string") return null;
    if (s.card_set_id !== null && typeof s.card_set_id !== "string") return null;
    const finishes = s.finish_type_ids ?? [];
    if (!Array.isArray(finishes) || finishes.some((f) => typeof f !== "string")) return null;
    const prev = snapshots[snapshots.length - 1];
    if (prev && s.day <= prev.day) return null;
    snapshots.push({
      day: s.day,
      capturedAt: s.captured_at,
      policy: s.completion_policy,
      cardSetId: (s.card_set_id as string | null) ?? null,
      finishIds: [...(finishes as string[])].map((f) => f.toLowerCase()).sort(),
      lifecycle: s.lifecycle_status,
      total,
      satisfied,
      opensCoverage: s.opens_coverage === true,
    });
  }

  // Coerência entre cobertura e fotografias (D2/D6).
  if ((coverage.length === 0) !== (snapshots.length === 0)) return null;
  for (const snap of snapshots) {
    if (!coverage.some((k) => snap.day >= k.from && snap.day <= k.to)) return null;
  }
  for (const k of coverage) {
    if (!snapshots.some((s) => s.day === k.from)) return null;
  }
  const trackingSince = coverage[0]?.from ?? null;
  const lastCoveredDay = coverage[coverage.length - 1]?.to ?? null;
  if (obj.tracking_since !== undefined && obj.tracking_since !== null && obj.tracking_since !== trackingSince) return null;
  if (obj.last_covered_day !== undefined && obj.last_covered_day !== null && obj.last_covered_day !== lastCoveredDay) return null;
  return { trackingSince, lastCoveredDay, coverage, snapshots };
}

// ---------------------------------------------------------------------------------------------
// Relatório
// ---------------------------------------------------------------------------------------------

/** Completude atual canônica (5332 → 5188), lida agora. */
export type CompletionNow = {
  satisfied: number;
  total: number;
  policy: string;
  lifecycle: string;
  cardSetId: string | null;
};

export type ChartPoint = { day: string; satisfied: number; total: number };
/** Um trecho contínuo de cobertura: pontos nos dias com fotografia + fim do intervalo. */
export type ChartSegment = { from: string; to: string; points: ChartPoint[] };

export type ChangeCause = { kind: "policy" | "card-set" | "finishes" | "lifecycle"; text: string };

export type CompletionChange =
  | {
      kind: "start";
      day: string;
      capturedAt: string;
      satisfied: number;
      total: number;
    }
  | {
      /** Mudança observada entre dois fechamentos do MESMO intervalo de cobertura (data exata do fechamento). */
      kind: "change";
      day: string;
      capturedAt: string;
      satisfied: number;
      total: number;
      prevSatisfied: number;
      prevTotal: number;
      causes: ChangeCause[];
    }
  | {
      /** Retomada depois de lacuna: diferença apresentada como período, nunca data exata. */
      kind: "resume";
      day: string;
      capturedAt: string;
      /** Último dia comprovado antes da lacuna. */
      since: string;
      satisfied: number;
      total: number;
      prevSatisfied: number;
      prevTotal: number;
      causes: ChangeCause[];
    };

export type CompletionGap = { from: string; to: string; days: number; open: boolean };

export type CompletionReportState = "no_history" | "single" | "tracked";

export type CompletionReport = {
  state: CompletionReportState;
  now: CompletionNow;
  trackingSince: string | null;
  lastCoveredDay: string | null;
  /** Fotografia vigente no último dia comprovado. */
  lastClosing: CompletionSnapshot | null;
  first: CompletionSnapshot | null;
  /** Fotografias em ordem crescente (pontos do gráfico). */
  snapshots: CompletionSnapshot[];
  /** Variação AGORA × primeiro fechamento (D1); `null` sem acompanhamento. */
  delta: { satisfied: number; total: number; pp: number } | null;
  /** Agora × último fechamento (o que ainda não foi registrado). */
  sinceLastClosing: { satisfied: number; total: number; policyChanged: boolean; lifecycleChanged: boolean } | null;
  segments: ChartSegment[];
  /** Mudanças registradas, ordem cronológica DECRESCENTE (D10). */
  changes: CompletionChange[];
  /** Lacunas (inclui a aberta depois do último dia comprovado, quando o fechamento esperado já passou). */
  gaps: CompletionGap[];
  gapDays: number;
  /** Há mudança registrada depois do início? (`false` → "Sem mudanças desde dd/mm"). */
  hasChanges: boolean;
};

/** Percentual exato (0–100) — base da variação em p.p.; a exibição do percentual atual segue `progressPercent`. */
export function exactPercent(satisfied: number, total: number): number {
  return total > 0 ? (satisfied / total) * 100 : 0;
}

function sameList(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

export function policyLabel(policy: string): string {
  if (policy === "MASTER_SET") return "Master Set";
  if (policy === "STANDARD_SET") return "Set padrão";
  return "outra modalidade";
}

export function lifecycleArchived(status: string): boolean {
  return status.toUpperCase() === "ARCHIVED";
}

/** Causas COMPROVADAS por dado gravado nas duas fotografias (D7). Nunca atribuição inferida. */
export function recordedCauses(prev: CompletionSnapshot, cur: CompletionSnapshot): ChangeCause[] {
  const causes: ChangeCause[] = [];
  if (prev.policy !== cur.policy) causes.push({ kind: "policy", text: `Modalidade: ${policyLabel(prev.policy)} → ${policyLabel(cur.policy)}` });
  if ((prev.cardSetId ?? "") !== (cur.cardSetId ?? "")) causes.push({ kind: "card-set", text: "Card Set de referência alterado" });
  else if (prev.policy === "MASTER_SET" && cur.policy === "MASTER_SET" && !sameList(prev.finishIds, cur.finishIds)) {
    causes.push({
      kind: "finishes",
      text: `Acabamentos adotados alterados (${N.format(prev.finishIds.length)} → ${N.format(cur.finishIds.length)})`,
    });
  }
  if (lifecycleArchived(prev.lifecycle) !== lifecycleArchived(cur.lifecycle)) {
    causes.push({ kind: "lifecycle", text: lifecycleArchived(cur.lifecycle) ? "Coleção arquivada" : "Coleção reativada" });
  }
  return causes;
}

/** Partes de data/hora em America/Sao_Paulo (sem depender do fuso do servidor ou do navegador). */
function zonedParts(date: Date): { day: string; hour: number; minute: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return { day: `${get("year")}-${get("month")}-${get("day")}`, hour: Number(get("hour")), minute: Number(get("minute")) };
}

/**
 * Último dia cujo fechamento JÁ deveria existir agora (D3/D4): depois das 03h00 de Brasília, ontem;
 * antes disso, anteontem (o fechamento de ontem ainda pode estar dentro da janela).
 */
export function expectedLastClosingDay(now: Date): string {
  const { day, hour } = zonedParts(now);
  return dayFromIndex(dayIndex(day) - (hour < CLOSING_WINDOW_HOUR ? 2 : 1));
}

export function buildCompletionReport(input: { history: CompletionHistory; now: CompletionNow; at: Date }): CompletionReport {
  const { history, now, at } = input;
  const { snapshots, coverage } = history;
  const first = snapshots[0] ?? null;
  const lastClosing = snapshots[snapshots.length - 1] ?? null;

  // Trechos do gráfico: um por intervalo de cobertura, nunca ligados entre si (D6).
  const segments: ChartSegment[] = coverage.map((k) => {
    const inside = snapshots.filter((s) => s.day >= k.from && s.day <= k.to);
    const points: ChartPoint[] = inside.map((s) => ({ day: s.day, satisfied: s.satisfied, total: s.total }));
    const last = inside[inside.length - 1];
    // Dia comprovado sem mudança vale o valor da última fotografia (D6) — a linha segue até o fim do intervalo.
    if (last && last.day !== k.to) points.push({ day: k.to, satisfied: last.satisfied, total: last.total });
    return { from: k.from, to: k.to, points };
  });

  // Lacunas entre intervalos e, se já passou o fechamento esperado, a aberta depois do último dia comprovado.
  const gaps: CompletionGap[] = [];
  for (let i = 1; i < coverage.length; i += 1) {
    const prev = coverage[i - 1]!;
    const cur = coverage[i]!;
    const from = dayIndex(prev.to) + 1;
    const to = dayIndex(cur.from) - 1;
    gaps.push({ from: dayFromIndex(from), to: dayFromIndex(to), days: to - from + 1, open: false });
  }
  if (history.lastCoveredDay) {
    const from = dayIndex(history.lastCoveredDay) + 1;
    const to = dayIndex(expectedLastClosingDay(at));
    if (to >= from) gaps.push({ from: dayFromIndex(from), to: dayFromIndex(to), days: to - from + 1, open: true });
  }
  const gapDays = gaps.reduce((sum, g) => sum + g.days, 0);

  // Mudanças registradas (crescente para montar; a folha recebe decrescente).
  const ascending: CompletionChange[] = [];
  snapshots.forEach((cur, index) => {
    if (index === 0) {
      ascending.push({ kind: "start", day: cur.day, capturedAt: cur.capturedAt, satisfied: cur.satisfied, total: cur.total });
      return;
    }
    const prev = snapshots[index - 1]!;
    const causes = recordedCauses(prev, cur);
    const intervalIndex = coverage.findIndex((k) => k.from === cur.day);
    if (intervalIndex > 0) {
      ascending.push({
        kind: "resume",
        day: cur.day,
        capturedAt: cur.capturedAt,
        since: coverage[intervalIndex - 1]!.to,
        satisfied: cur.satisfied,
        total: cur.total,
        prevSatisfied: prev.satisfied,
        prevTotal: prev.total,
        causes,
      });
      return;
    }
    ascending.push({
      kind: "change",
      day: cur.day,
      capturedAt: cur.capturedAt,
      satisfied: cur.satisfied,
      total: cur.total,
      prevSatisfied: prev.satisfied,
      prevTotal: prev.total,
      causes,
    });
  });
  const hasChanges = ascending.some((c) => c.kind === "change" || (c.kind === "resume" && (c.satisfied !== c.prevSatisfied || c.total !== c.prevTotal || c.causes.length > 0)));

  const delta = first
    ? {
        satisfied: now.satisfied - first.satisfied,
        total: now.total - first.total,
        pp: roundPp(exactPercent(now.satisfied, now.total) - exactPercent(first.satisfied, first.total)),
      }
    : null;
  const sinceLastClosing = lastClosing
    ? {
        satisfied: now.satisfied - lastClosing.satisfied,
        total: now.total - lastClosing.total,
        policyChanged: now.policy !== lastClosing.policy,
        lifecycleChanged: lifecycleArchived(now.lifecycle) !== lifecycleArchived(lastClosing.lifecycle),
      }
    : null;

  const state: CompletionReportState =
    snapshots.length === 0 ? "no_history" : snapshots.length === 1 && history.trackingSince === history.lastCoveredDay ? "single" : "tracked";

  return {
    state,
    now,
    trackingSince: history.trackingSince,
    lastCoveredDay: history.lastCoveredDay,
    lastClosing,
    first,
    snapshots,
    delta,
    sinceLastClosing,
    segments,
    changes: ascending.reverse(),
    gaps: [...gaps].reverse(),
    gapDays,
    hasChanges,
  };
}

/** Arredonda para 1 casa (evita "-0,0" e ruído de ponto flutuante). */
function roundPp(value: number): number {
  const r = Math.round(value * 10) / 10;
  return Object.is(r, -0) ? 0 : r;
}

// ---------------------------------------------------------------------------------------------
// Textos (pt-BR) — mesmos na tela e na impressão
// ---------------------------------------------------------------------------------------------

/** "2026-11-08" → "08/11/2026". */
export function dayText(day: string): string {
  const [y, m, d] = day.split("-");
  return `${d}/${m}/${y}`;
}

/** "2026-11-08" → "08/11". */
export function shortDayText(day: string): string {
  const [, m, d] = day.split("-");
  return `${d}/${m}`;
}

/** "Fechamento de dd/mm/aaaa" — nunca "às 23h59" (D3). */
export function closingText(day: string): string {
  return `Fechamento de ${dayText(day)}`;
}

/** Instante efetivo da leitura em Brasília: "lido em 09/11 às 00:05" (D3). */
export function readAtText(capturedAt: string): string {
  const date = new Date(capturedAt);
  const { day, hour, minute } = zonedParts(date);
  return `lido em ${shortDayText(day)} às ${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

export function signed(n: number): string {
  if (n === 0) return "0";
  return `${n > 0 ? "+" : "−"}${N.format(Math.abs(n))}`;
}

export function signedPp(pp: number): string {
  if (pp === 0) return "0,0 p.p.";
  return `${pp > 0 ? "+" : "−"}${PP.format(Math.abs(pp))} p.p.`;
}

export function positionsText(n: number): string {
  return `${N.format(n)} ${Math.abs(n) === 1 ? "posição" : "posições"}`;
}

/** "120 de 295 posições". */
export function ofText(satisfied: number, total: number): string {
  return `${N.format(satisfied)} de ${positionsText(total)}`;
}

/** Transição objetiva "120 → 123" (D7). */
export function arrow(prev: number, cur: number): string {
  return `${N.format(prev)} → ${N.format(cur)}`;
}

/** Rótulo da linha de mudança: data exata do fechamento ou período (através de lacuna). */
export function changeWhenText(change: CompletionChange): string {
  if (change.kind === "resume") return `Entre ${dayText(change.since)} e ${dayText(change.day)} (período sem registro)`;
  return closingText(change.day);
}

export function changeTitleText(change: CompletionChange): string {
  if (change.kind === "start") return "Início do acompanhamento";
  if (change.kind === "resume") {
    const same = change.satisfied === change.prevSatisfied && change.total === change.prevTotal;
    return same ? "Registro retomado · sem diferença" : "Registro retomado · diferença observada";
  }
  return "Mudança observada";
}

/** Linhas objetivas da mudança ("Posições satisfeitas: 120 → 123"; "Total esperado: 295 → 298"). */
export function changeFacts(change: CompletionChange): string[] {
  if (change.kind === "start") return [`${ofText(change.satisfied, change.total)} satisfeitas`];
  const facts: string[] = [];
  if (change.satisfied !== change.prevSatisfied) facts.push(`Posições satisfeitas: ${arrow(change.prevSatisfied, change.satisfied)}`);
  if (change.total !== change.prevTotal) facts.push(`Total esperado: ${arrow(change.prevTotal, change.total)}`);
  if (facts.length === 0) facts.push(`${ofText(change.satisfied, change.total)} satisfeitas · sem diferença nos números`);
  return facts;
}

export function gapText(gap: CompletionGap): string {
  const days = `${N.format(gap.days)} ${gap.days === 1 ? "dia" : "dias"}`;
  if (gap.open) return gap.days === 1 ? `${dayText(gap.from)} · sem registro (${days})` : `Desde ${dayText(gap.from)} · sem registro (${days})`;
  return gap.days === 1 ? `${dayText(gap.from)} · sem registro (${days})` : `Entre ${dayText(gap.from)} e ${dayText(gap.to)} · sem registro (${days})`;
}

export function gapNoticeText(report: CompletionReport): string | null {
  if (report.gapDays === 0) return null;
  const days = `${N.format(report.gapDays)} ${report.gapDays === 1 ? "dia" : "dias"} sem registro`;
  return `${days} no período acompanhado. Nesses dias não há valor: o gráfico é interrompido e nada é estimado.`;
}

/** Frase do "agora" × último fechamento (o que ainda não entrou num fechamento). */
export function sinceLastClosingText(report: CompletionReport): string | null {
  const s = report.sinceLastClosing;
  if (!s || !report.lastClosing) return null;
  const base = `desde o ${closingText(report.lastClosing.day).toLowerCase()}`;
  if (s.policyChanged) return `A modalidade mudou ${base}; o próximo fechamento registra a nova referência.`;
  if (s.satisfied === 0 && s.total === 0) return `Sem diferença ${base}.`;
  const parts: string[] = [];
  if (s.satisfied !== 0) parts.push(`${signed(s.satisfied)} ${Math.abs(s.satisfied) === 1 ? "posição satisfeita" : "posições satisfeitas"}`);
  if (s.total !== 0) parts.push(`total esperado ${signed(s.total)}`);
  return `Agora: ${parts.join(" · ")} ${base} — entra no próximo fechamento.`;
}

export type CompletionEntry = { key: string; sort: string; change?: CompletionChange; gap?: CompletionGap };

/** Mudanças e lacunas numa só lista, em ordem cronológica DECRESCENTE (D10); lacuna antes da retomada que a encerra. */
export function completionEntries(report: CompletionReport): CompletionEntry[] {
  const entries: CompletionEntry[] = [
    ...report.changes.map((change) => ({ key: `c.${change.day}`, sort: `${change.day}.0`, change })),
    ...report.gaps.map((gap) => ({ key: `g.${gap.from}`, sort: `${gap.to}.1`, gap })),
  ];
  return entries.sort((a, b) => (a.sort < b.sort ? 1 : a.sort > b.sort ? -1 : 0));
}

export const COMPLETION_HISTORY_NOTES: readonly string[] = [
  "Completude pela regra oficial da coleção: posições do objetivo (cartas do Set ou, no Master Set, cartas × acabamentos adotados) com ao menos um exemplar alocado. Posições não são exemplares físicos.",
  "Um fechamento por dia (horário de Brasília), lido logo depois da meia-noite: alterações feitas entre a meia-noite e a leitura entram no fechamento do dia anterior. Nada é reconstruído antes do primeiro fechamento.",
  "Uma diferença entre fechamentos mostra o que mudou, não o motivo; a causa só aparece quando registrada (modalidade, Card Set, acabamentos ou arquivamento). Dias sem registro interrompem o gráfico e nunca são estimados.",
  "Percentual atual arredondado para baixo, como no restante do produto; a variação em pontos percentuais usa os valores exatos.",
];
