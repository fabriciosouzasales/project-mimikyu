"use client";

import { Loader2 } from "lucide-react";
import { forwardRef, useState } from "react";
import type { ButtonHTMLAttributes } from "react";
import { getPricingSyncRunDetailAction } from "@/app/pricing/historico-execucoes/actions";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import type { PricingSyncRunDetail } from "@/lib/pricing/queries";
import {
  RUN_TYPE_LABEL,
  SOURCE_CODE_LABEL,
  STATUS_LABEL,
  STATUS_TONE,
  TRIGGERED_BY_LABEL,
  computeSyncRunDurationSeconds,
  formatSyncRunDuration,
} from "@/lib/pricing/sync-run-labels";

const OUTCOME_TONE: Record<string, StateTone> = {
  SUCCESS: "success",
  ERROR: "danger",
  RATE_LIMITED: "warning",
};

const OUTCOME_LABEL: Record<string, string> = {
  SUCCESS: "Sucesso",
  ERROR: "Erro",
  RATE_LIMITED: "Rate limit",
};

/**
 * Contagem de chamadas por `outcome` — "contadores relevantes" pedidos por
 * Fabrício além de `requests_made`/`rate_limit_hits` (já vêm prontos do
 * `run`). Derivado 100% client-side do array `calls` já carregado pelo
 * Dialog — nenhuma query adicional.
 */
function summarizeCallOutcomes(calls: PricingSyncRunDetail["calls"]): Record<string, number> {
  const summary: Record<string, number> = {};
  for (const call of calls) {
    summary[call.outcome] = (summary[call.outcome] ?? 0) + 1;
  }
  return summary;
}

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

/**
 * Detalhe de uma execução (`pricing_sync_run` + array de
 * `pricing_sync_run_call`) — Dialog sob demanda, mesma disciplina de
 * "carregar só quando aberto" já usada nos demais Dialogs do Pricing Admin.
 * Busca via `getPricingSyncRunDetailAction` (Server Action só-leitura em
 * `historico-execucoes/actions.ts`) porque o Dialog é Client Component.
 */
export function SyncRunDetailDialog({ runId, trigger }: { runId: string; trigger: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<PricingSyncRunDetail | null>(null);

  function handleOpenChange(next: boolean) {
    setOpen(next);
    if (next && !detail && !loading) {
      setLoading(true);
      setError(null);
      getPricingSyncRunDetailAction(runId)
        .then((result) => {
          setLoading(false);
          if (!result) {
            setError("Não foi possível carregar o detalhe desta execução.");
            return;
          }
          setDetail(result);
        })
        .catch(() => {
          setLoading(false);
          setError("Não foi possível carregar o detalhe desta execução.");
        });
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>Detalhe da Execução</DialogTitle>
        </DialogHeader>
        <DialogBody className="max-h-[70vh] space-y-3 overflow-y-auto">
          {loading && (
            <div className="flex items-center justify-center gap-2 py-8 text-xs text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              Carregando…
            </div>
          )}
          {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
          {detail && (
            <>
              <div className="grid gap-2 rounded-md border border-border bg-surface-muted/40 p-3 text-xs sm:grid-cols-2">
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Tipo</p>
                  <p className="text-foreground">{RUN_TYPE_LABEL[detail.run.runType] ?? detail.run.runType}</p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Status</p>
                  <StateBadge tone={STATUS_TONE[detail.run.status] ?? "muted"}>
                    {STATUS_LABEL[detail.run.status] ?? detail.run.status}
                  </StateBadge>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Fonte</p>
                  <p className="text-foreground">
                    {detail.run.pricingSourceCode
                      ? (SOURCE_CODE_LABEL[detail.run.pricingSourceCode] ?? detail.run.pricingSourceCode)
                      : (detail.run.fxSourceCode ?? "—")}
                  </p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Set</p>
                  <p className="text-foreground">
                    {detail.run.cardSetName ? `${detail.run.cardSetName} (${detail.run.cardSetCode})` : "—"}
                  </p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Início</p>
                  <p className="text-foreground">{formatDateTime(detail.run.startedAt)}</p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Fim</p>
                  <p className="text-foreground">{formatDateTime(detail.run.finishedAt)}</p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Duração</p>
                  <p className="text-foreground">
                    {formatSyncRunDuration(computeSyncRunDurationSeconds(detail.run.startedAt, detail.run.finishedAt))}
                  </p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Acionador</p>
                  <p className="text-foreground">{TRIGGERED_BY_LABEL[detail.run.triggeredBy] ?? detail.run.triggeredBy}</p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Requisições</p>
                  <p className="text-foreground">
                    {detail.run.requestsMade ?? "—"} feitas · {detail.run.requestsRemainingAtEnd ?? "—"} restantes
                  </p>
                </div>
                <div>
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Rate limits</p>
                  <p className="text-foreground">{detail.run.rateLimitHits ?? 0}</p>
                </div>
                {detail.run.errorSummary && (
                  <div className="sm:col-span-2">
                    <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Erro</p>
                    <p className="text-destructive">{detail.run.errorSummary}</p>
                  </div>
                )}
              </div>

              <div>
                <div className="mb-1.5 flex flex-wrap items-center justify-between gap-1.5">
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                    Chamadas ({detail.calls.length})
                  </p>
                  {detail.calls.length > 0 && (
                    <p className="text-[11px] text-muted-foreground">
                      {Object.entries(summarizeCallOutcomes(detail.calls))
                        .map(([outcome, count]) => `${count} ${(OUTCOME_LABEL[outcome] ?? outcome).toLowerCase()}`)
                        .join(" · ")}
                    </p>
                  )}
                </div>
                {detail.calls.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Nenhuma chamada registrada para esta execução.</p>
                ) : (
                  <div className="space-y-1.5">
                    {detail.calls.map((call) => (
                      <div
                        key={call.id}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border px-2.5 py-1.5 text-xs"
                      >
                        <div className="flex items-center gap-2">
                          <span className="tabular-nums text-muted-foreground">#{call.sequenceNumber}</span>
                          <span className="truncate text-foreground" title={call.endpoint}>
                            {call.endpoint}
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          {call.httpStatusCode && (
                            <span className="tabular-nums text-muted-foreground">{call.httpStatusCode}</span>
                          )}
                          <StateBadge tone={OUTCOME_TONE[call.outcome] ?? "muted"}>
                            {OUTCOME_LABEL[call.outcome] ?? call.outcome}
                          </StateBadge>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

/**
 * v1.1 (2026-08-23, feedback de Fabrício sobre Histórico de Execuções):
 * "Ver detalhes" era `variant="outline"` — pesado para uma ação repetida em
 * toda linha da tabela. `ghost` + texto `muted-foreground` (escurece no
 * hover) mantém a ação claramente clicável sem competir visualmente com
 * status/Set/dados principais da linha.
 *
 * v1.2 (2026-08-26, correção de bug real — "Ver detalhes" sem ação):
 * `DialogTrigger asChild` usa o `Slot` do Radix para clonar este elemento
 * injetando `onClick`/`aria-haspopup`/`aria-expanded`/`data-state`/`ref`.
 * A versão anterior era um componente sem props (`function
 * SyncRunDetailTriggerButton()`), então essas props injetadas caíam no
 * vazio — o botão renderizado nunca tinha `onClick` nenhum, por mouse ou
 * teclado, sem gerar erro/warning (prop dropped silenciosamente). Confirmado
 * via inspeção real do DOM: o `<button>` em produção não tinha nenhum dos
 * atributos que o Radix injeta. Precisa ser `forwardRef` e repassar todas as
 * props recebidas para o `Button` interno.
 */
export const SyncRunDetailTriggerButton = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement>>(
  function SyncRunDetailTriggerButton(props, ref) {
    return (
      <Button
        ref={ref}
        type="button"
        variant="ghost"
        size="sm"
        className="text-muted-foreground hover:text-foreground"
        {...props}
      >
        Ver detalhes
      </Button>
    );
  },
);
