import type { PricingAdminOverview } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

/** Tokens (não hex fixo) — mesmo racional de `pricing-sync-run-chart.tsx`: acabamento coerente em light/dark. */
const COR_SAUDAVEL = "hsl(var(--success))";
const COR_PROBLEMA = "hsl(var(--destructive))";
const COR_PAUSADO = "hsl(var(--muted-foreground))";

/**
 * Raio/espessura do donut — v3.1 (2026-08-23, ajuste pós-revisão): reduzidos
 * de 40/12 para 30/9 (container visual de 160px para 88px). O v3 original
 * tinha desenhado este card para uma coluna alta de 1/3 de largura ao lado
 * de um gráfico de linha grande; Fabrício pediu para os 3 gráficos voltarem
 * a uma única linha de colunas iguais, na densidade de
 * `log-atualizacoes-resumo.tsx` — um donut de 160px não cabe nessa altura
 * sem dominar o card sozinho.
 */
const RAIO = 30;
const ESPESSURA = 9;

/**
 * Gráfico C da Visão Geral v3 (2026-08-23, redesenho visual puro — ver
 * `pricing-overview-stats.tsx` para o racional completo; ZERO mudança de
 * dado aqui) — saúde dos Sets. SEM RPC nova: `pricing_set_refresh_state` é
 * uma tabela de estado atual, sem log histórico por dia (nenhum evento por
 * Set é registrado ao longo do tempo) — só existe o retrato do instante
 * presente, já devolvido por `get_pricing_admin_overview().sets` (migration
 * 3939). Por isso este é um retrato (donut), não uma série temporal como os
 * gráficos A/B — divergência sinalizada no relatório pré-implementação
 * original.
 *
 * v3.1: donut compacto (ver `RAIO`/`ESPESSURA` acima), legenda condensada
 * numa única linha (era 3 linhas empilhadas), caption explicativa removida
 * para manter a altura do card coerente com Evolução/Execuções — a mesma
 * informação ("retrato do instante atual") já está no `aria-label` do
 * donut.
 */
export function PricingSetHealthBar({ sets }: { sets: PricingAdminOverview["sets"] }) {
  if (sets.total === 0) {
    return <p className="py-4 text-center text-xs text-muted-foreground">Nenhum Set com sincronização configurada.</p>;
  }

  const healthyPct = (sets.healthy / sets.total) * 100;
  const problemPct = (sets.problem / sets.total) * 100;
  const pausedPct = (sets.paused / sets.total) * 100;

  const segments = [
    { pct: healthyPct, color: COR_SAUDAVEL, cumulative: 0 },
    { pct: problemPct, color: COR_PROBLEMA, cumulative: healthyPct },
    { pct: pausedPct, color: COR_PAUSADO, cumulative: healthyPct + problemPct },
  ].filter((s) => s.pct > 0);

  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className="relative"
        role="img"
        aria-label={`Retrato do instante atual: ${sets.healthy} de ${sets.total} Sets saudáveis, ${sets.problem} com problema, ${sets.paused} pausados.`}
      >
        <svg viewBox="0 0 100 100" className="h-[88px] w-[88px] -rotate-90">
          <circle cx={50} cy={50} r={RAIO} fill="none" stroke="hsl(var(--surface-muted))" strokeWidth={ESPESSURA} />
          {segments.map((seg) => (
            <circle
              key={seg.color}
              cx={50}
              cy={50}
              r={RAIO}
              fill="none"
              stroke={seg.color}
              strokeWidth={ESPESSURA}
              strokeLinecap="butt"
              pathLength={100}
              strokeDasharray={`${seg.pct} ${100 - seg.pct}`}
              strokeDashoffset={-seg.cumulative}
            />
          ))}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-lg font-semibold tabular-nums text-foreground">{formatNumber(sets.healthy)}</span>
          <span className="text-[9px] text-muted-foreground">de {formatNumber(sets.total)}</span>
        </div>
      </div>

      <div className="flex flex-wrap justify-center gap-x-3 gap-y-1 text-[10px]">
        <span className="inline-flex items-center gap-1 text-muted-foreground">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: COR_SAUDAVEL }} aria-hidden="true" />
          Saudáveis <span className="tabular-nums text-foreground">{formatNumber(sets.healthy)}</span>
        </span>
        <span className="inline-flex items-center gap-1 text-muted-foreground">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: COR_PROBLEMA }} aria-hidden="true" />
          Problema <span className="tabular-nums text-foreground">{formatNumber(sets.problem)}</span>
        </span>
        <span className="inline-flex items-center gap-1 text-muted-foreground">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: COR_PAUSADO }} aria-hidden="true" />
          Pausados <span className="tabular-nums text-foreground">{formatNumber(sets.paused)}</span>
        </span>
      </div>
    </div>
  );
}
