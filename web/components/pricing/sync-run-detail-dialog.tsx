"use client";

import { Loader2 } from "lucide-react";
import { useState } from "react";
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

const OUTCOME_TONE: Record<string, StateTone> = {
  SUCCESS: "success",
  ERROR: "danger",
  RATE_LIMITED: "warning",
};

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
                  <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Fonte</p>
                  <p className="text-foreground">{detail.run.pricingSourceCode ?? "—"}</p>
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
                <p className="mb-1.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                  Chamadas ({detail.calls.length})
                </p>
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
                          <StateBadge tone={OUTCOME_TONE[call.outcome] ?? "muted"}>{call.outcome}</StateBadge>
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

export function SyncRunDetailTriggerButton() {
  return (
    <Button type="button" variant="outline" size="sm">
      Ver detalhes
    </Button>
  );
}
