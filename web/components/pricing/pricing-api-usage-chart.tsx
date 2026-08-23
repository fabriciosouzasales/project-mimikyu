"use client";

import { Info } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { PricingApiUsagePoint } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Fix v3.4.1 (2026-08-23) — mesma correção de `pricing-coverage-trend-chart.tsx`:
 * Fabrício apontou barras douradas (`hsl(var(--primary))`) destoando do verde
 * usado em todos os gráficos de barra única do sistema. Corrigido para o
 * mesmo hex literal de `log-atualizacoes-resumo.tsx`/`importacoes-tendencia.tsx`
 * (`#3FCF8E`) — cor fixa via `style`, não token, porque não é um token do
 * design system. O comentário anterior ("token, não hex fixo") estava
 * exatamente invertido: os 2 componentes de referência usam hex fixo, não
 * token.
 */
const COR_REQUESTS = "#3FCF8E";

const dateAxisFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" });
const dateTooltipFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

/**
 * Fix v3.4.2 (2026-08-23) — janela FIXA de `JANELA_DIAS` dias terminando
 * hoje, com ou sem requests em cada dia (mesmo racional de
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

/**
 * Ajuste v3.4 (2026-08-23) — mesma propagação exata do padrão de
 * `log-atualizacoes-resumo.tsx` aplicada a este gráfico (ver
 * `pricing-coverage-trend-chart.tsx` para o racional completo da rodada):
 * `Card density="compact"`, cabeçalho de uma linha só (ícone + rótulo à
 * esquerda), `CHART_HEIGHT_PX=56` (era 64), barra estreita centralizada por
 * coluna (`COLUNA_LARGURA_PX=18`, mesma técnica de `LogAtualizacoesResumo`).
 *
 * O resumo Total/Média/Pico (pedido por Fabrício na v3.2, mantido aqui)
 * migrou da faixa inferior ancorada por `justify-between` para o próprio
 * cabeçalho, à direita — mesma posição que os outros 2 gráficos desta linha
 * usam para seus resumos ("X de Y mappings"/"X% com problema"). Isso
 * elimina a necessidade do wrapper `flex h-full justify-between`: sem
 * rodapé, as 3 colunas do dashboard voltam a ter estrutura idêntica
 * (cabeçalho + gráfico + rótulos de data), então o grid (`items-stretch`)
 * as mantém na mesma altura por construção.
 *
 * Fonte: `admin_get_pricing_api_usage_daily` (migration 3947), soma de
 * `pricing_sync_run.requests_made` por dia — sem `generate_series`, dias
 * sem execução simplesmente não aparecem (nenhum preenchimento artificial).
 * Nenhuma mudança de dado/RPC/regra nesta rodada.
 *
 * Fix v3.6 (2026-08-23) — Fabrício pediu para validar matematicamente
 * Total/Média/Pico e não apresentar uma média calculada sobre uma
 * quantidade de dias diferente da rotulada. Antes: `media = total /
 * dias.length` — `dias.length` é sempre 10 (a janela fixa da v3.4.2, com ou
 * sem consumo em cada dia), então em qualquer janela com dias ociosos a
 * média subestimava o consumo típico de um dia realmente ativo. Corrigido
 * para `média apenas dos dias com consumo` (`diasComConsumo = dias.filter(d
 * => d.requests > 0)`), com o rótulo explícito "/dia ativo" para não deixar
 * ambíguo qual denominador está sendo usado. `Total` (soma bruta) e `Pico`
 * (maior valor diário) não mudaram — já eram corretos independente da
 * janela.
 */
export function PricingApiUsageChart({ points }: { points: PricingApiUsagePoint[] | null }) {
  const [aberto, setAberto] = useState<string | null>(null);

  const porDia = new Map((points ?? []).map((p) => [p.day, p.requests] as const));
  const dias = buildJanela10Dias().map((day) => ({ day, requests: porDia.get(day) ?? 0 }));
  const temDados = dias.some((d) => d.requests > 0);
  const maiorValor = Math.max(1, ...dias.map((d) => d.requests));
  const ultimoDia = dias[dias.length - 1]!.day;

  const total = dias.reduce((acc, d) => acc + d.requests, 0);
  const diasComConsumo = dias.filter((d) => d.requests > 0);
  const media = diasComConsumo.length > 0 ? Math.round(total / diasComConsumo.length) : 0;
  const pico = dias.reduce((max, d) => (d.requests > max.requests ? d : max), dias[0]!);

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-4 pt-4">
        <div className="flex items-center justify-between gap-2">
          <span className="inline-flex shrink-0 items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            Consumo da API
          </span>
          <span className="truncate text-xs tabular-nums text-muted-foreground">
            {temDados ? (
              <>
                Total <span className="text-foreground">{formatNumber(total)}</span> · Média{" "}
                <span className="text-foreground">{formatNumber(media)}</span>/dia ativo · Pico{" "}
                <span className="text-foreground">{formatNumber(pico!.requests)}</span>
              </>
            ) : (
              "—"
            )}
          </span>
        </div>

        <div className="space-y-1.5">
          <div className="flex items-end gap-1.5" style={{ height: 56 }}>
            {dias.map((dia) => {
              const alturaPx = dia.requests > 0 ? Math.max(2, (dia.requests / maiorValor) * 56) : 0;
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
                    aria-label={`${dateAxisFormatter.format(new Date(`${dia.day}T00:00:00`))}: ${formatNumber(dia.requests)} requests`}
                    className="flex h-full flex-col-reverse items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    style={{ width: "min(18px, 100%)" }}
                  >
                    <div style={{ height: alturaPx, width: "100%", backgroundColor: COR_REQUESTS }} />
                  </button>

                  {estaAberto && (
                    <div className="absolute bottom-full left-1/2 z-10 mb-2 w-36 -translate-x-1/2 rounded-md border border-border bg-surface p-3 text-left shadow-panel">
                      <p className="mb-1 text-xs font-medium text-foreground">
                        {dateTooltipFormatter.format(new Date(`${dia.day}T00:00:00`))}
                        {ehUltimoDia && <span className="ml-1.5 text-[10px] font-normal text-primary-ink">hoje</span>}
                      </p>
                      <p className="text-xs tabular-nums text-muted-foreground">
                        <span className="text-foreground">{formatNumber(dia.requests)}</span> requests
                      </p>
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
