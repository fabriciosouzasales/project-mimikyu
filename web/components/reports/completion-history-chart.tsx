"use client";

import { useEffect, useMemo, useState } from "react";
import * as echarts from "echarts/core";
import { LineChart, ScatterChart } from "echarts/charts";
import { GridComponent, MarkAreaComponent, TooltipComponent } from "echarts/components";
import type { EChartsCoreOption } from "echarts/core";
import { MMKYUChart } from "@/components/charts/mmkyu-chart";
import type { CompletionReport } from "@/lib/reports/completion-history";
import { completionChartAria, completionChartOption } from "@/lib/reports/completion-history-chart";

// ADR-033: cada consumidor registra só o que a própria `option` usa.
echarts.use([LineChart, ScatterChart, GridComponent, TooltipComponent, MarkAreaComponent]);

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(true);
  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  return reduced;
}

/**
 * Gráfico da "Evolução da completude" (D10/D11) sobre o `MMKYUChart` (SVG). `print` = instância de
 * impressão: largura fixa A4, sem animação nem dica, legível em escala de cinza. `nowMs` vem da
 * emissão do relatório (o ponto "agora" não se move enquanto a folha está aberta).
 */
export function CompletionHistoryChart({ report, nowMs, print = false, height }: { report: CompletionReport; nowMs: number; print?: boolean; height: number }) {
  const reduced = usePrefersReducedMotion();
  const option = useMemo(() => completionChartOption(report, { nowMs, print, animate: !reduced }) as EChartsCoreOption, [report, nowMs, print, reduced]);
  return <MMKYUChart option={option} ariaLabel={completionChartAria(report)} height={height} printSafe={print} />;
}
