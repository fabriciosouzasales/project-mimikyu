"use client";

import { Pencil } from "lucide-react";
import { useEffect, useState } from "react";
import { useActionState } from "react";
import { useRouter } from "next/navigation";
import { alterarFrequenciaSincronizacao, type AlterarFrequenciaState } from "@/app/pricing/sincronizacoes/actions";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import type { PricingRefreshPolicyItem } from "@/lib/pricing/queries";

const FREQUENCY_OPTIONS = [1, 2, 3, 5];

const initialState: AlterarFrequenciaState = { error: null };

function formatUpdatedAt(value: string | null): string {
  if (!value) return "Nunca alterada";
  return `Alterada em ${new Date(value).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" })}`;
}

/**
 * Política de Sincronização — frequência de refresh por fonte
 * (`pricing_refresh_policy`, editável via `admin_set_pricing_refresh_frequency`,
 * migrations 3937/3938 já validadas, não novas deste Bloco 3). Cada
 * alteração passa por um Dialog de confirmação explícita — nunca inline —
 * porque muda o comportamento futuro do dispatcher automático, não é um
 * campo de cadastro comum.
 */
export function PoliticaSincronizacaoPanel({ policies }: { policies: PricingRefreshPolicyItem[] }) {
  const [editing, setEditing] = useState<PricingRefreshPolicyItem | null>(null);

  return (
    <Panel>
      <PanelHeader>
        <PanelTitle>Política de Sincronização</PanelTitle>
      </PanelHeader>
      <PanelContent>
        {policies.length === 0 ? (
          <EmptyState title="Nenhuma fonte de preço cadastrada" />
        ) : (
          <div className="divide-y divide-border">
            {policies.map((policy) => (
              <div key={policy.pricingSourceId} className="flex items-center justify-between gap-3 py-2 first:pt-0 last:pb-0">
                <div className="min-w-0">
                  <p className="text-sm text-foreground">
                    {policy.pricingSourceName} <span className="text-xs uppercase text-muted-foreground">({policy.pricingSourceCode})</span>
                  </p>
                  <p className="text-[11px] text-muted-foreground">{formatUpdatedAt(policy.updatedAt)}</p>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <span className="inline-flex items-center rounded-full border border-border bg-surface-muted px-2.5 py-1 text-xs font-medium tabular-nums text-foreground">
                    a cada {policy.frequencyDays} {policy.frequencyDays === 1 ? "dia" : "dias"}
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="icon-sm"
                    aria-label={`Alterar frequência de ${policy.pricingSourceName}`}
                    onClick={() => setEditing(policy)}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </PanelContent>

      <AlterarFrequenciaDialog policy={editing} onClose={() => setEditing(null)} />
    </Panel>
  );
}

function AlterarFrequenciaDialog({
  policy,
  onClose,
}: {
  policy: PricingRefreshPolicyItem | null;
  onClose: () => void;
}) {
  const router = useRouter();
  const [state, formAction, pending] = useActionState(alterarFrequenciaSincronizacao, initialState);
  const [frequencyDays, setFrequencyDays] = useState(policy?.frequencyDays ?? 1);

  useEffect(() => {
    if (policy) setFrequencyDays(policy.frequencyDays);
  }, [policy]);

  useEffect(() => {
    if (state.success) {
      router.refresh();
      onClose();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <Dialog open={policy !== null} onOpenChange={(next) => !next && !pending && onClose()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Alterar frequência de sincronização</DialogTitle>
          <DialogDescription>
            {policy && (
              <>
                Muda a frequência de refresh automático de <strong>{policy.pricingSourceName}</strong>. O
                dispatcher passa a usar o novo valor a partir do próximo ciclo — execuções já agendadas não são
                recalculadas retroativamente.
              </>
            )}
          </DialogDescription>
        </DialogHeader>

        {policy && (
          <form action={formAction}>
            <input type="hidden" name="pricingSourceId" value={policy.pricingSourceId} />
            <DialogBody className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="frequencyDays">Frequência</Label>
                <Select
                  id="frequencyDays"
                  name="frequencyDays"
                  value={String(frequencyDays)}
                  onChange={(event) => setFrequencyDays(Number.parseInt(event.target.value, 10))}
                >
                  {FREQUENCY_OPTIONS.map((days) => (
                    <option key={days} value={days}>
                      A cada {days} {days === 1 ? "dia" : "dias"}
                    </option>
                  ))}
                </Select>
              </div>

              {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
            </DialogBody>
            <DialogFooter>
              <Button type="button" variant="outline" size="sm" onClick={onClose} disabled={pending}>
                Cancelar
              </Button>
              <Button type="submit" size="sm" disabled={pending || frequencyDays === policy.frequencyDays}>
                {pending ? "Salvando…" : "Confirmar alteração"}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
