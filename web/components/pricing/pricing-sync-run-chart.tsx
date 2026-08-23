"use client";

import { Info } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { PricingSyncRunDailyPoint } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Fix v3.4.1 (2026-08-23) — `COR_SUCESSO` alinhado ao hex literal exato
 * (`#3FCF8E`) usado por `log-atualizacoes-resumo.tsx`/`importacoes-tendencia.tsx`,
 * em vez do token `hsl(var(--success))` (uma tonalidade de verde diferente,
 * mais escura/saturada). Fabrício pediu "a mesma cor das barras do gráfico
 * para todo sistema" — a segmentação concluído/com erros/falhas não tem
 * precedente nos 2 componentes de referência (que só desenham uma cor de
 * sucesso), então `COR_AVISO`/`COR_FALHA` continuam vindo dos tokens
 * semânticos (`--warning`/`--destructive`), única extensão necessária para
 * representar os 2 estados de problema que não existiam antes.
 *
 * Fix v3.6.1 (2026-08-23) — Fabrício apontou, com captura real em `next dev`
 * escuro, que o segmento de "Falhas" ficava quase invisível — contraste
 * calculado ~1,2:1 contra `--surface` escuro. Causa: `--destructive` no
 * tema escuro (`6 64% 20%`) é deliberadamente um vermelho quase preto — um
 * "wash" de fundo pensado para badges/alerts com `--destructive-foreground`
 * claro por cima (ex.: `Alert variant="destructive"`), nunca para ser
 * desenhado sozinho como preenchimento gráfico sólido. `COR_AVISO`
 * (`--warning`) não tem esse problema porque `--warning` já é claro nos dois
 * temas (`38 92% 50/58%`). Corrigido com a mesma técnica já usada em
 * `COR_SUCESSO`: literal HSL fixo (o valor de `--destructive` no tema
 * CLARO, `10 80% 44%`), igual nos dois temas — contraste recalculado ~3,1:1
 * contra o fundo escuro (era ~1,2:1) e continua legível no claro (é
 * literalmente o token que já era usado lá).
 */
const COR_SUCESSO = "#3FCF8E";
const COR_AVISO = "hsl(var(--warning))";
const COR_FALHA = "hsl(10 80% 44%)";

const dateAxisFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" });

/**
 * Fix v3.4.2 (2026-08-23) — janela FIXA de `JANELA_DIAS` dias terminando
 * hoje, com ou sem execução em cada dia (mesmo racional de
 * `buildJanelaFixa()` em `log-atualizacoes-resumo.tsx`) — substitui a janela
 * variável anterior, que só desenhava os dias com execução real.
 */
const JANELA_DIAS = 10;

function toKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function buildJanela10Dias(): string[] {
  const hoje = new Date();
  const dias: string[] = [];
  for (let i = JANELA_DIAS - 1; i >= 0; i--) {
    const dia = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate() - i);
    dias.push(toKey(dia));
  }
  return dias;
}

type DiaAgregado = {
  day: string;
  completed: number;
  completedWithErrors: number;
  failed: number;
};

function agruparPorDia(pontos: PricingSyncRunDailyPoint[]): DiaAgregado[] {
  const buckets = new Map<string, DiaAgregado>();
  for (const ponto of pontos) {
    let bucket = buckets.get(ponto.day);
    if (!bucket) {
      bucket = { day: ponto.day, completed: 0, completedWithErrors: 0, failed: 0 };
      buckets.set(ponto.day, bucket);
    }
    if (ponto.status === "COMPLETED") bucket.completed += ponto.count;
    else if (ponto.status === "COMPLETED_WITH_ERRORS") bucket.completedWithErrors += ponto.count;
    else if (ponto.status === "FAILED") bucket.failed += ponto.count;
  }
  return buildJanela10Dias().map((day) => buckets.get(day) ?? { day, completed: 0, completedWithErrors: 0, failed: 0 });
}

/**
 * Ajuste v3.4 (2026-08-23) — mesma propagação exata do padrão de
 * `log-atualizacoes-resumo.tsx` aplicada a este gráfico (ver
 * `pricing-coverage-trend-chart.tsx` para o racional completo da rodada):
 * `Card density="compact"`, cabeçalho de uma linha só (ícone + rótulo à
 * esquerda, resumo à direita — mesmo idioma de `ImportacoesTendencia`, que
 * mostra "% de falhas" com um indicador colorido), `CHART_HEIGHT_PX=56`
 * (era 64), barra estreita centralizada por coluna (`COLUNA_LARGURA_PX=18`,
 * mesma técnica de `LogAtualizacoesResumo` — aqui empilhando os 3
 * segmentos de status dentro da mesma barra de 18px, em vez de uma barra
 * cheia por coluna).
 *
 * A legenda fixa de 3 linhas (sempre visível, abaixo do gráfico) foi
 * removida — nenhum dos 2 componentes de referência mantém uma legenda
 * permanente separada; a composição/breakdown por status vive só no
 * tooltip (mesmo padrão do tooltip de `ImportacoesTendencia`, que também só
 * mostra o detalhe por categoria ao passar o mouse). O `wrapper` "flex
 * h-full justify-between" da v3.2 (que existia só para ancorar aquela
 * legenda na borda inferior do card) também saiu — sem legenda fixa, as 3
 * colunas do dashboard voltam a ter estrutura idêntica (cabeçalho + gráfico
 * + rótulos de data, sem rodapé), então o grid (`items-stretch`) as
 * mantém na mesma altura por construção, sem precisar de nenhum truque de
 * flex.
 *
 * Janela de dados já é só a real, sem preenchimento artificial: a RPC
 * (`admin_get_pricing_sync_run_daily`, migration 3945/3946) agrega direto
 * de `pricing_sync_run`, sem `generate_series` — dias sem execução
 * simplesmente não aparecem no resultado. Nenhuma mudança de dado/RPC/regra
 * nesta rodada.
 *
 * Fix v3.6 (2026-08-23) — Fabrício pediu para confirmar exatamente quais
 * status entram no resumo "X% com problema" e corrigir o rótulo se ele não
 * representar fielmente o cálculo. Conferido: `totalComProblema =
 * completedWithErrors + failed` — ou seja, o percentual agrega dois status
 * reais (`COMPLETED_WITH_ERRORS` e `FAILED`), nunca "problema" genérico.
 * Rótulo trocado para "X% com erro ou falha", que nomeia exatamente as 2
 * categorias somadas (mesmos nomes já usados no detalhe do tooltip, "Com
 * erros"/"Falhas") — sem introduzir um terceiro termo vago.
 */
export function PricingSyncRunChart({ points }: { points: PricingSyncRunDailyPoint[] | null }) {
  const dias = agruparPorDia(points ?? []);
  const [aberto, setAberto] = useState<string | null>(null);

  const maiorTotal = Math.max(1, ...dias.map((d) => d.completed + d.completedWithErrors + d.failed));
  const ultimoDia = dias[dias.length - 1]!.day;

  const totalGeral = dias.reduce((soma, d) => soma + d.completed + d.completedWithErrors + d.failed, 0);
  const totalComProblema = dias.reduce((soma, d) => soma + d.completedWithErrors + d.failed, 0);
  const percentualProblema = totalGeral > 0 ? (totalComProblema / totalGeral) * 100 : 0;

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-4 pt-4">
        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            Execuções de Sincronização
          </span>
          <span className="inline-flex items-center gap-1.5 text-xs tabular-nums text-muted-foreground">
            {totalComProblema > 0 && <span className="h-2 w-2 shrink-0" style={{ backgroundColor: COR_FALHA }} aria-hidden="true" />}
            {totalGeral === 0 ? "—" : totalComProblema > 0 ? `${percentualProblema.toFixed(1)}% com erro ou falha` : "tudo concluído"}
          </span>
        </div>

        <div className="space-y-1.5">
          <div className="flex items-end gap-1.5" style={{ height: 56 }}>
            {dias.map((dia) => {
              const total = dia.completed + dia.completedWithErrors + dia.failed;
              const completedPx = dia.completed > 0 ? Math.max(2, (dia.completed / maiorTotal) * 56) : 0;
              const erroPx = dia.completedWithErrors > 0 ? Math.max(2, (dia.completedWithErrors / maiorTotal) * 56) : 0;
              const falhaPx = dia.failed > 0 ? Math.max(2, (dia.failed / maiorTotal) * 56) : 0;
              const estaAberto = aberto === dia.day;
              const ehUltimoDia = dia.day === ultimoDia;
              return (
                <div
                  key={dia.day}
                  className="relative flex h-full min-w-0 flex-1 flex-col-reverse items-center"
                  onMouseEnter={() => setAberto(dia.day)}
                  onMouseLeave={() => setAberto(null)}
                >
                  <button
                    type="button"
                    onFocus={() => setAberto(dia.day)}
                    onBlur={() => setAberto(null)}
                    aria-expanded={estaAberto}
                    aria-label={`${dateAxisFormatter.format(new Date(`${dia.day}T00:00:00`))}: ${formatNumber(total)} execuções`}
                    className="flex h-full flex-col-reverse items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    style={{ width: "min(18px, 100%)" }}
                  >
                    <div style={{ height: completedPx, width: "100%", backgroundColor: COR_SUCESSO }} />
                    <div style={{ height: erroPx, width: "100%", backgroundColor: COR_AVISO }} />
                    <div style={{ height: falhaPx, width: "100%", backgroundColor: COR_FALHA }} />
                  </button>

                  {estaAberto && (
                    <div className="absolute bottom-full left-1/2 z-10 mb-2 w-40 -translate-x-1/2 rounded-md border border-border bg-surface p-2.5 text-left shadow-panel">
                      <p className="mb-1.5 text-xs font-medium text-foreground">
                        {dateAxisFormatter.format(new Date(`${dia.day}T00:00:00`))}
                        {ehUltimoDia && <span className="ml-1.5 text-[10px] font-normal text-primary-ink">hoje</span>}
                      </p>
                      <div className="space-y-1">
                        <div className="flex items-center justify-between gap-2 text-xs">
                          <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                            <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: COR_SUCESSO }} aria-hidden="true" />
                            Concluídas
                          </span>
                          <span className="tabular-nums text-foreground">{formatNumber(dia.completed)}</span>
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                          <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                            <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: COR_AVISO }} aria-hidden="true" />
                            Com erros
                          </span>
                          <span className="tabular-nums text-foreground">{formatNumber(dia.completedWithErrors)}</span>
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                          <span className="inline-flex items-center gap-1.5 text-muted-foreground">
                            <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: COR_FALHA }} aria-hidden="true" />
                            Falhas
                          </span>
                          <span className="tabular-nums text-foreground">{formatNumber(dia.failed)}</span>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          <div className="flex gap-1.5">
            {dias.map((dia) => (
              <span
                key={dia.day}
                className="min-w-0 flex-1 overflow-hidden whitespace-nowrap text-center text-[9px] leading-tight tabular-nums text-muted-foreground"
              >
                {dateAxisFormatter.format(new Date(`${dia.day}T00:00:00`))}
              </span>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
