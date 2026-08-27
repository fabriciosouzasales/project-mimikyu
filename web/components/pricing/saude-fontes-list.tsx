import type { ReactNode } from "react";
import { AlertTriangle, CheckCircle2 } from "lucide-react";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { EmptyState } from "@/components/ui/empty-state";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import type { PricingSourceHealth } from "@/lib/pricing/queries";
import { humanizePricingErrorSummary } from "@/lib/pricing/pricing-error-summary";
import { formatNumber } from "@/lib/utils";

const RUN_TYPE_LABEL: Record<string, string> = {
  CARD_SYNC: "Descoberta/Matching",
  // v1.1 (2026-08-23) — "Refresh de Preços" → "Atualização de Preços",
  // feedback de Fabrício sobre a linguagem técnica da tela.
  PRICE_REFRESH: "Atualização de Preços",
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
  // P16.4.1 (migration 3952) — Set recém-confirmado sem primeira sincronização ainda
  // (onboarding) nunca eleva a fonte a "Com problema", só a "Atenção" — mesmo racional de
  // `recentFailedRuns` abaixo, nunca `danger`.
  if (source.sets.onboardingPending > 0) return { tone: "warning", label: "Atenção" };
  if (source.recentFailedRuns > 0) return { tone: "warning", label: "Atenção" };
  return { tone: "success", label: "Saudável" };
}

/**
 * Bloco de fato individual dentro de um card de fonte — label pequeno em
 * maiúsculas + conteúdo. Extraído em v1.1 (2026-08-23, feedback de
 * Fabrício: "visualmente um pouco 'tabela dentro de card'") para reforçar a
 * hierarquia entre o cabeçalho nome/status e os 4 blocos internos: mais
 * respiro vertical (`space-y-1.5`, era `space-y-1`) e um divisor vertical
 * muito sutil entre colunas em telas largas (`lg:border-l`, só onde os 4
 * blocos realmente ficam lado a lado).
 */
function SourceFactBlock({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="space-y-1.5 lg:border-l lg:border-border/60 lg:px-4 lg:first:border-l-0 lg:first:pl-0">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      {children}
    </div>
  );
}

/**
 * Saúde das Fontes (Bloco 3, Gerencial) — uma linha por `pricing_source`
 * (hoje só JUSTTCG), toda a agregação vem de `admin_get_pricing_source_health()`
 * (migration 3941). Layout em cartões (não tabela) porque cada fonte carrega
 * vários blocos de detalhe (cobertura, Sets, execuções, erros) — uma linha de
 * tabela ficaria ilegível; cartões escalam bem tanto para 1 fonte hoje quanto
 * para N fontes futuras.
 *
 * v1.1 (2026-08-23) — ajustes de conteúdo pedidos por Fabrício após ver o
 * Hero v1 em `next dev`: (1) `PanelContent` ganhou `border-t` separando o
 * cabeçalho nome/status dos 4 blocos, e os blocos usam `SourceFactBlock`
 * (divisores sutis + mais respiro, ver acima); (2) cobertura de mappings —
 * "Pendentes"/"Não encontrados" viraram badges pequenos em vez de texto
 * corrido; (3) Sets — quando não há problema/pausado, colapsa para
 * "X/Y saudáveis" em vez de repetir o total já dito no label; quando há,
 * mantém os badges detalhados, mas o badge de saudáveis também passa a
 * mostrar a razão X/Y; (4) Erros recentes — "rate limits" virou "bloqueios
 * por limite da API"; `lastErrorSummary` passa por
 * `humanizePricingErrorSummary()` (o código técnico bruto, tipo
 * `BUDGET_STOPPED(set=ME4)`, continua disponível só no tooltip); (5)
 * "Refresh de Preços" virou "Atualização de Preços" em `RUN_TYPE_LABEL`.
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
        const semProblemaOuPausa =
          source.sets.problem === 0 && source.sets.paused === 0 && source.sets.onboardingPending === 0;
        const errorSummaryHumanizado = humanizePricingErrorSummary(source.lastErrorSummary);

        return (
          <Panel key={source.pricingSourceId}>
            <PanelHeader className="flex-row flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <PanelTitle>{source.pricingSourceName}</PanelTitle>
                <span className="text-xs uppercase text-muted-foreground">({source.pricingSourceCode})</span>
              </div>
              <StateBadge tone={tone}>{label}</StateBadge>
            </PanelHeader>
            <PanelContent className="grid gap-x-4 gap-y-5 border-t border-border pt-4 sm:grid-cols-2 lg:grid-cols-4">
              <SourceFactBlock label="Última sincronização">
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
              </SourceFactBlock>

              <SourceFactBlock label="Cobertura de mappings">
                <p className="text-xs text-foreground">
                  {source.mappings.coveragePct !== null ? `${source.mappings.coveragePct}%` : "—"} confirmados
                </p>
                <p className="text-xs text-muted-foreground">
                  {formatNumber(source.mappings.confirmed)} de {formatNumber(source.mappings.total)}
                </p>
                {(source.mappings.pending > 0 || source.mappings.notFound > 0) && (
                  <div className="flex flex-wrap gap-1.5 pt-0.5">
                    {source.mappings.pending > 0 && (
                      <StateBadge tone="warning">{formatNumber(source.mappings.pending)} pendentes</StateBadge>
                    )}
                    {source.mappings.notFound > 0 && (
                      <StateBadge tone="muted">{formatNumber(source.mappings.notFound)} não encontrados</StateBadge>
                    )}
                  </div>
                )}
              </SourceFactBlock>

              <SourceFactBlock label="Sets">
                {semProblemaOuPausa ? (
                  <p className="text-xs text-foreground">
                    <span className="font-medium">
                      {formatNumber(source.sets.healthy)}/{formatNumber(source.sets.total)}
                    </span>{" "}
                    saudáveis
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    <StateBadge tone="success">
                      {formatNumber(source.sets.healthy)}/{formatNumber(source.sets.total)} saudáveis
                    </StateBadge>
                    {source.sets.problem > 0 && (
                      <StateBadge tone="danger">{formatNumber(source.sets.problem)} com problema</StateBadge>
                    )}
                    {source.sets.onboardingPending > 0 && (
                      <StateBadge tone="warning">
                        {formatNumber(source.sets.onboardingPending)} aguardando primeira sincronização
                      </StateBadge>
                    )}
                    {source.sets.paused > 0 && (
                      <StateBadge tone="muted">{formatNumber(source.sets.paused)} pausados</StateBadge>
                    )}
                  </div>
                )}
              </SourceFactBlock>

              <SourceFactBlock label="Erros recentes (7 dias)">
                <div className="flex items-center gap-1.5 text-xs">
                  {source.recentFailedRuns > 0 ? (
                    <AlertTriangle className="h-3.5 w-3.5 text-destructive" aria-hidden="true" />
                  ) : (
                    <CheckCircle2 className="h-3.5 w-3.5 text-success" aria-hidden="true" />
                  )}
                  <span className="text-foreground">
                    {formatNumber(source.recentFailedRuns)} execuções falhas ·{" "}
                    {formatNumber(source.recentRateLimitHits)} bloqueios por limite da API
                  </span>
                </div>
                {errorSummaryHumanizado && (
                  <p className="truncate text-xs text-muted-foreground" title={source.lastErrorSummary ?? undefined}>
                    {errorSummaryHumanizado}
                  </p>
                )}
              </SourceFactBlock>
            </PanelContent>
          </Panel>
        );
      })}
    </div>
  );
}
