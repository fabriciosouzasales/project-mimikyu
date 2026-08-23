"use client";

import { Info } from "lucide-react";
import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import type { PricingCoverageTrendPoint } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const dateAxisFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" });
const dateTooltipFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

/**
 * Fix v3.4.2 (2026-08-23) — Fabrício pediu para os 3 gráficos sempre
 * mostrarem os 10 últimos dias, com ou sem dado (mesmo racional de
 * `buildJanelaFixa()` em `log-atualizacoes-resumo.tsx`: janela FIXA, não
 * variável conforme o volume disponível). Substitui o recorte anterior
 * (`EVOLUCAO_CONFIRMACOES_INICIO`, que escondia dias antes de 18/08) por uma
 * janela sempre de `JANELA_DIAS` dias terminando hoje — os dias sem dado
 * simplesmente aparecem com barra vazia, exatamente como no componente de
 * referência.
 */
const JANELA_DIAS = 10;

function toKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Os `JANELA_DIAS` dias fixos terminando hoje (mais antigo → mais recente) — sempre os mesmos, com ou sem dado em cada um. */
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
 * Fix v3.4.1 (2026-08-23) — Fabrício apontou, com captura real lado a lado
 * do Log de Atualizações, que este gráfico estava com barras douradas
 * (`hsl(var(--primary))`), destoando do verde usado em TODOS os gráficos de
 * barra única do sistema (`log-atualizacoes-resumo.tsx` e
 * `importacoes-tendencia.tsx`, ambos com `COR_BARRA/COR_SUCESSO = "#3FCF8E"`).
 * O comentário anterior ("mesma cor de destaque usada no restante do
 * módulo") estava errado — `--primary` é o dourado de marca/CTA, nunca foi a
 * cor usada nos gráficos de barra do Catálogo Editorial. Corrigido para o
 * mesmo hex literal dos 2 componentes de referência (cor fixa via `style`,
 * não token, porque não é um token do design system).
 */
const COR_BARRA = "#3FCF8E";

/**
 * Ajuste v3.4 (2026-08-23) — Fabrício rejeitou visualmente a v3.2/v3.3 e
 * pediu propagação EXATA do padrão de `log-atualizacoes-resumo.tsx`
 * (Catálogo Editorial > Log de Atualizações), não uma "reinterpretação":
 * mesmo `Card density="compact"`/`CardContent`, mesmo cabeçalho de uma linha
 * só (ícone + rótulo maiúsculo à esquerda, resumo à direita — sem
 * `PanelHeader` separado), mesma altura de gráfico (`CHART_HEIGHT_PX=56`,
 * era 64/140), mesma barra estreita centralizada na coluna
 * (`COLUNA_LARGURA_PX=18`, coluna em si `flex-1` — sempre ocupa a largura
 * total do card, dividida entre os dias, mesmo com poucos pontos), e o
 * tooltip por hover/foco no formato exato do componente de referência.
 *
 * Este gráfico também mudou de LINHA (SVG, área preenchida) para BARRAS —
 * pedido explícito de Fabrício ("não usar linha, área preenchida ou
 * curva"). Cada barra é `cumConfirmed` do dia (mesmo dado já usado pela
 * linha antes, só muda a representação visual) — a linha de referência
 * tracejada no total atual foi removida (o componente de referência não usa
 * grid/linha de referência nenhuma, só barras + rótulo de data), para as 3
 * colunas do dashboard pertencerem à mesma família visual. O total atual
 * (`currentTotal`) aparece no resumo do cabeçalho, à direita, no mesmo
 * formato de "X de Y" — nenhuma mudança de RPC/dado/regra nesta rodada.
 */
export function PricingCoverageTrendChart({
  points,
  currentTotal,
}: {
  points: PricingCoverageTrendPoint[] | null;
  currentTotal: number;
}) {
  const [aberto, setAberto] = useState<string | null>(null);

  const janela = buildJanela10Dias();
  const porDia = new Map((points ?? []).map((p) => [p.day, p.cumConfirmed] as const));
  /**
   * `cumConfirmed` é cumulativo — um dia sem ponto na RPC não significa
   * "zero confirmações", significa "sem leitura nova nesse dia". Carregar o
   * último valor conhecido adiante (em vez de cair para 0) evita um
   * dente-de-serra falso na barra para dias sem sincronização.
   */
  let ultimoValorConhecido = 0;
  const dias = janela.map((day) => {
    const valor = porDia.get(day);
    if (valor !== undefined) ultimoValorConhecido = valor;
    return { day, cumConfirmed: valor ?? ultimoValorConhecido };
  });

  const maior = Math.max(1, currentTotal, ...dias.map((d) => d.cumConfirmed));
  const ultimoDia = dias[dias.length - 1]!;

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-4 pt-4">
        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Info className="h-3.5 w-3.5" aria-hidden="true" />
            Evolução das Confirmações
          </span>
          <span className="text-xs tabular-nums text-muted-foreground">
            {formatNumber(ultimoDia.cumConfirmed)} de {formatNumber(currentTotal)} mappings
          </span>
        </div>

        <div className="space-y-1.5">
          <div className="flex items-end gap-1.5" style={{ height: 56 }}>
            {dias.map((dia) => {
              const px = dia.cumConfirmed > 0 ? Math.max(2, (dia.cumConfirmed / maior) * 56) : 0;
              const estaAberto = aberto === dia.day;
              const ehUltimoDia = dia.day === ultimoDia.day;
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
                    aria-label={`${dateAxisFormatter.format(new Date(`${dia.day}T00:00:00`))}: ${formatNumber(dia.cumConfirmed)} confirmações`}
                    className="flex h-full flex-col-reverse items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    style={{ width: "min(18px, 100%)" }}
                  >
                    <div style={{ height: px, width: "100%", backgroundColor: COR_BARRA }} />
                  </button>

                  {estaAberto && (
                    <div className="absolute bottom-full left-1/2 z-10 mb-2 w-36 -translate-x-1/2 rounded-md border border-border bg-surface p-3 text-left shadow-panel">
                      <p className="mb-1.5 text-xs font-medium text-foreground">
                        {dateTooltipFormatter.format(new Date(`${dia.day}T00:00:00`))}
                        {ehUltimoDia && <span className="ml-1.5 text-[10px] font-normal text-primary-ink">hoje</span>}
                      </p>
                      <p className="text-xs tabular-nums text-muted-foreground">
                        <span className="text-foreground">{formatNumber(dia.cumConfirmed)}</span> confirmações
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
