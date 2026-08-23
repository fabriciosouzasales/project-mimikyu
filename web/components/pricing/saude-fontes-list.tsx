import { AlertTriangle, CheckCircle2 } from "lucide-react";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { EmptyState } from "@/components/ui/empty-state";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import type { PricingSourceHealth } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const RUN_TYPE_LABEL: Record<string, string> = {
  CARD_SYNC: "Descoberta/Matching",
  PRICE_REFRESH: "Refresh de Preços",
  FX_REFRESH: "Câmbio (PTAX)",
};

const RUN_STATUS_LABEL: Record<string, string> = {
  COMPLETED: "Concluída",
  COMPLETED_WITH_ERRORS: "Concluída com erros",
  FAILED: "Falhou",
};

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Deriva a saúde geral de uma fonte a partir dos números já agregados em
 * SQL (nenhum cálculo de negócio aqui, só o mapeamento para tom visual):
 * qualquer Set com problema é `danger`; sem Set com problema mas com falha
 * recente (7 dias) é `warning`; caso contrário `success`. Fonte inativa
 * (`is_active=false`) é sempre `muted`, independente do resto.
 */
function deriveSourceTone(source: PricingSourceHealth): { tone: StateTone; label: string } {
  if (!source.isActive) return { tone: "muted", label: "Inativa" };
  if (source.sets.problem > 0) return { tone: "danger", label: "Com problema" };
  if (source.recentFailedRuns > 0) return { tone: "warning", label: "Atenção" };
  return { tone: "success", label: "Saudável" };
}

/**
 * Saúde das Fontes (Bloco 3, Gerencial) — uma linha por `pricing_source`
 * (hoje só JUSTTCG), toda a agregação vem de `admin_get_pricing_source_health()`
 * (migration 3941). Layout em cartões (não tabela) porque cada fonte carrega
 * vários blocos de detalhe (cobertura, Sets, execuções, erros) — uma linha de
 * tabela ficaria ilegível; cartões escalam bem tanto para 1 fonte hoje quanto
 * para N fontes futuras.
 */
export function SaudeFontesList({ sources }: { sources: PricingSourceHealth[] }) {
  if (sources.length === 0) {
    return (
      <Panel>
        <PanelContent>
          <EmptyState title="Nenhuma fonte de preço cadastrada" />
        </PanelContent>
      </Panel>
    );
  }

  return (
    <div className="space-y-3">
      {sources.map((source) => {
        const { tone, label } = deriveSourceTone(source);
        return (
          <Panel key={source.pricingSourceId}>
            <PanelHeader className="flex-row flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <PanelTitle>{source.pricingSourceName}</PanelTitle>
                <span className="text-xs uppercase text-muted-foreground">({source.pricingSourceCode})</span>
              </div>
              <StateBadge tone={tone}>{label}</StateBadge>
            </PanelHeader>
            <PanelContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div className="space-y-1">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                  Última sincronização
                </p>
                {source.lastRun ? (
                  <>
                    <p className="text-xs text-foreground">
                      {RUN_TYPE_LABEL[source.lastRun.runType] ?? source.lastRun.runType} —{" "}
                      {RUN_STATUS_LABEL[source.lastRun.status] ?? source.lastRun.status}
                    </p>
                    <p className="text-xs text-muted-foreground">{formatDateTime(source.lastRun.finishedAt)}</p>
                  </>
                ) : (
                  <p className="text-xs text-muted-foreground">Nenhuma execução concluída ainda.</p>
                )}
              </div>

              <div className="space-y-1">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                  Cobertura de mappings
                </p>
                <p className="text-xs text-foreground">
                  {source.mappings.coveragePct !== null ? `${source.mappings.coveragePct}%` : "—"} confirmados
                </p>
                <p className="text-xs text-muted-foreground">
                  {formatNumber(source.mappings.confirmed)} de {formatNumber(source.mappings.total)} · Pendentes{" "}
                  {formatNumber(source.mappings.pending)} · Não encontrados {formatNumber(source.mappings.notFound)}
                </p>
              </div>

              <div className="space-y-1">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                  Sets ({formatNumber(source.sets.total)} no total)
                </p>
                <div className="flex flex-wrap gap-1.5">
                  <StateBadge tone="success">{formatNumber(source.sets.healthy)} saudáveis</StateBadge>
                  {source.sets.problem > 0 && (
                    <StateBadge tone="danger">{formatNumber(source.sets.problem)} com problema</StateBadge>
                  )}
                  {source.sets.paused > 0 && (
                    <StateBadge tone="muted">{formatNumber(source.sets.paused)} pausados</StateBadge>
                  )}
                </div>
              </div>

              <div className="space-y-1">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                  Erros recentes (7 dias)
                </p>
                <div className="flex items-center gap-1.5 text-xs">
                  {source.recentFailedRuns > 0 ? (
                    <AlertTriangle className="h-3.5 w-3.5 text-destructive" aria-hidden="true" />
                  ) : (
                    <CheckCircle2 className="h-3.5 w-3.5 text-success" aria-hidden="true" />
                  )}
                  <span className="text-foreground">
                    {formatNumber(source.recentFailedRuns)} execuções falhas · {formatNumber(source.recentRateLimitHits)}{" "}
                    rate limits
                  </span>
                </div>
                {source.lastErrorSummary && (
                  <p className="truncate text-xs text-muted-foreground" title={source.lastErrorSummary}>
                    {source.lastErrorSummary}
                  </p>
                )}
              </div>
            </PanelContent>
          </Panel>
        );
      })}
    </div>
  );
}
