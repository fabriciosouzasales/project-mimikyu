import { type CompletionReport, dayIndex, dayText, lifecycleArchived, ofText, readAtText, recordedCauses, shortDayText } from "./completion-history.ts";

/**
 * V1-14 R2-F (B2) — `option` do gráfico "Evolução da completude" (D10/D11), PURA (sem ECharts aqui;
 * o componente registra só `LineChart`, `ScatterChart`, `GridComponent`, `TooltipComponent` e
 * `MarkAreaComponent`). Testável sem navegador.
 *
 * - Posições satisfeitas: linha em DEGRAUS (`step: "end"` — o valor vale até o fechamento seguinte).
 * - Total esperado: degraus TRACEJADOS (teto).
 * - Um trecho por intervalo de cobertura; entre trechos, um valor vazio (`null`) interrompe a linha:
 *   lacunas nunca são ligadas nem estimadas (D6).
 * - Fechamentos com fotografia: pontos; mudança de objetivo/situação comprovada: losango (D7).
 * - "Agora" (ao vivo, 5332/5188): ponto vazado SEPARADO, nunca ligado ao último fechamento.
 * - Trechos arquivados (D8): faixa clara a partir do fechamento em que o arquivamento foi observado.
 * - Cores explícitas e neutras na própria `option` (a folha é sempre branca, também no tema escuro);
 *   legível em escala de cinza: sólido × tracejado × formas diferentes (D11).
 */

const DAY_MS = 86_400_000;
/** Dia de referência no eixo: meio-dia UTC (posição estável, sem saltos de fuso). */
export function dayX(day: string): number {
  return dayIndex(day) * DAY_MS + DAY_MS / 2;
}

const MONTHS = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

export const COMPLETION_CHART_COLORS = {
  satisfied: "#8c5d1d", // dourado de conteúdo (--primary-ink claro): escuro também em cinza
  total: "#8a8a8a",
  text: "#404040",
  muted: "#737373",
  grid: "#e5e5e5",
  axis: "#d4d4d4",
  marker: "#171717",
  now: "#dca54b",
  archived: "rgba(115, 115, 115, 0.10)",
  surface: "#ffffff",
} as const;

type Pair = [number, number | null];
type Point = { value: [number, number]; tip: string; symbol?: string; symbolSize?: number };

export type CompletionChartModel = {
  satisfied: Pair[];
  total: Pair[];
  closings: Point[];
  objective: Point[];
  now: Point;
  archived: Array<[number, number]>;
  xMin: number;
  xMax: number;
  yMax: number;
  yInterval: number;
  spanDays: number;
};

/** Escala do eixo das posições: até 5 divisões "redondas" (1/2/2,5/5 × 10ⁿ) e teto múltiplo delas, acima do maior total. */
export function yScale(maxTotal: number): { max: number; interval: number } {
  const padded = Math.max(4, maxTotal * 1.06);
  const raw = padded / 5;
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  const interval = [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((step) => step >= raw && Number.isInteger(step)) ?? 10 * magnitude;
  return { max: Math.ceil(padded / interval) * interval, interval };
}

/** Modelo do gráfico a partir do relatório (só fechamentos registrados + "agora"). */
export function completionChartModel(report: CompletionReport, nowMs: number): CompletionChartModel {
  const satisfied: Pair[] = [];
  const total: Pair[] = [];
  report.segments.forEach((segment, index) => {
    if (index > 0) {
      // Valor vazio no primeiro dia sem registro: a linha para aqui e recomeça no próximo trecho.
      const breakX = dayX(report.segments[index - 1]!.to) + DAY_MS;
      satisfied.push([breakX, null]);
      total.push([breakX, null]);
    }
    for (const point of segment.points) {
      satisfied.push([dayX(point.day), point.satisfied]);
      total.push([dayX(point.day), point.total]);
    }
  });

  const closings: Point[] = [];
  const objective: Point[] = [];
  report.snapshots.forEach((snap, i) => {
    const causes = i > 0 ? recordedCauses(report.snapshots[i - 1]!, snap) : [];
    const tip = `Fechamento de ${dayText(snap.day)} · ${ofText(snap.satisfied, snap.total)} satisfeitas · ${readAtText(snap.capturedAt)}`;
    if (causes.length > 0) objective.push({ value: [dayX(snap.day), snap.satisfied], tip: `${tip} · ${causes.map((c) => c.text).join(" · ")}` });
    else closings.push({ value: [dayX(snap.day), snap.satisfied], tip });
  });

  // "Agora" (ao vivo): ponto separado, nunca ligado à linha dos fechamentos.
  const now: Point = { value: [nowMs, report.now.satisfied], tip: `Agora (ao vivo) · ${ofText(report.now.satisfied, report.now.total)} satisfeitas · ainda não é um fechamento` };

  // Trechos arquivados (D8), a partir do fechamento em que o arquivamento foi observado, sem atravessar lacunas.
  const archived: Array<[number, number]> = [];
  for (const segment of report.segments) {
    const inside = report.snapshots.filter((snap) => snap.day >= segment.from && snap.day <= segment.to);
    inside.forEach((snap, i) => {
      if (!lifecycleArchived(snap.lifecycle)) return;
      const next = inside[i + 1];
      archived.push([dayX(snap.day), next ? dayX(next.day) : dayX(segment.to) + DAY_MS / 2]);
    });
  }

  const firstX = report.trackingSince ? dayX(report.trackingSince) : nowMs;
  const lastX = Math.max(report.lastCoveredDay ? dayX(report.lastCoveredDay) : firstX, nowMs);
  const spanDays = Math.max(1, Math.round((lastX - firstX) / DAY_MS));
  const pad = Math.max(DAY_MS / 2, (lastX - firstX) * 0.04);
  const maxTotal = Math.max(report.now.total, ...total.map(([, v]) => v ?? 0));
  const y = yScale(maxTotal);
  return { satisfied, total, closings, objective, now, archived, xMin: firstX - pad, xMax: lastX + pad, yMax: y.max, yInterval: y.interval, spanDays };
}

/** Rótulo do eixo do tempo, adaptado ao período (D10): dias no início; meses quando crescer. */
export function axisLabel(ms: number, spanDays: number): string {
  const d = new Date(ms);
  if (spanDays <= 75) return shortDayText(d.toISOString().slice(0, 10));
  return `${MONTHS[d.getUTCMonth()]}/${String(d.getUTCFullYear()).slice(2)}`;
}

/** Descrição textual do gráfico (leitor de tela). A lista de mudanças é a alternativa completa. */
export function completionChartAria(report: CompletionReport): string {
  if (!report.first || !report.trackingSince || !report.lastCoveredDay) return "Gráfico da evolução da completude: ainda sem fechamentos.";
  const last = report.lastClosing!;
  const gaps = report.gapDays > 0 ? ` ${report.gapDays} ${report.gapDays === 1 ? "dia" : "dias"} sem registro interrompem a linha.` : "";
  return `Gráfico em degraus das posições satisfeitas por fechamento diário, de ${dayText(report.trackingSince)} a ${dayText(report.lastCoveredDay)}: de ${ofText(report.first.satisfied, report.first.total)} para ${ofText(last.satisfied, last.total)}; agora ${ofText(report.now.satisfied, report.now.total)}.${gaps}`;
}

export function completionChartOption(report: CompletionReport, opts: { nowMs: number; print: boolean; animate: boolean }): Record<string, unknown> {
  const m = completionChartModel(report, opts.nowMs);
  const C = COMPLETION_CHART_COLORS;
  const fontSize = opts.print ? 9 : 11;
  return {
    animation: opts.animate && !opts.print,
    animationDuration: 260,
    backgroundColor: "transparent",
    textStyle: { color: C.text, fontFamily: "inherit" },
    grid: { left: 8, right: 16, top: 16, bottom: 4, containLabel: true },
    tooltip: opts.print
      ? { show: false }
      : {
          trigger: "item",
          backgroundColor: C.surface,
          borderColor: C.axis,
          textStyle: { color: C.text, fontSize: 11 },
          formatter: (p: { data?: { tip?: string } }) => p.data?.tip ?? "",
        },
    xAxis: {
      type: "time",
      min: m.xMin,
      max: m.xMax,
      minInterval: DAY_MS,
      axisLine: { lineStyle: { color: C.axis } },
      axisTick: { show: false },
      splitLine: { show: false },
      axisLabel: { color: C.muted, fontSize, hideOverlap: true, formatter: (value: number) => axisLabel(value, m.spanDays) },
    },
    yAxis: {
      type: "value",
      min: 0,
      max: m.yMax,
      interval: m.yInterval,
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { lineStyle: { color: C.grid } },
      axisLabel: { color: C.muted, fontSize, formatter: (v: number) => new Intl.NumberFormat("pt-BR").format(v) },
    },
    series: [
      {
        name: "Total esperado",
        type: "line",
        step: "end",
        data: m.total,
        connectNulls: false,
        showSymbol: false,
        silent: true,
        lineStyle: { color: C.total, width: 1.25, type: [5, 4] },
        z: 1,
      },
      {
        name: "Posições satisfeitas",
        type: "line",
        step: "end",
        data: m.satisfied,
        connectNulls: false,
        showSymbol: false,
        silent: true,
        lineStyle: { color: C.satisfied, width: 2.25 },
        areaStyle: opts.print ? undefined : { color: "rgba(220, 165, 75, 0.10)" },
        markArea:
          m.archived.length > 0
            ? {
                silent: true,
                itemStyle: { color: C.archived },
                label: { show: true, position: "insideTop", color: C.muted, fontSize: 9, formatter: "arquivada" },
                data: m.archived.map(([a, b]) => [{ xAxis: a }, { xAxis: b }]),
              }
            : undefined,
        z: 2,
      },
      {
        name: "Fechamentos com mudança",
        type: "scatter",
        data: m.closings,
        symbol: "circle",
        symbolSize: opts.print ? 4 : 6,
        itemStyle: { color: C.satisfied, borderColor: C.surface, borderWidth: 1 },
        z: 3,
      },
      {
        name: "Mudança de objetivo ou situação",
        type: "scatter",
        data: m.objective,
        symbol: "diamond",
        symbolSize: opts.print ? 8 : 11,
        itemStyle: { color: C.marker, borderColor: C.surface, borderWidth: 1 },
        z: 4,
      },
      {
        name: "Agora",
        type: "scatter",
        data: [m.now],
        symbol: "circle",
        symbolSize: opts.print ? 8 : 11,
        itemStyle: { color: C.surface, borderColor: opts.print ? C.marker : C.now, borderWidth: 2.25 },
        label: { show: true, position: "top", color: C.text, fontSize: opts.print ? 8 : 10, fontWeight: 600, formatter: "agora" },
        z: 5,
      },
    ],
  };
}
