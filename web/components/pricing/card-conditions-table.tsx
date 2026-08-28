"use client";

import { Link2, Pencil, Plus } from "lucide-react";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  salvarCondicao,
  salvarMapeamentoCondicao,
  type SalvarCondicaoState,
  type SalvarMapeamentoCondicaoState,
} from "@/app/pricing/condicoes/actions";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { CardCondition, PricingSource } from "@/lib/pricing/queries";

/**
 * Cadastro de Condições (Bloco 4 do Pricing Admin, migration 3942) —
 * vocabulário canônico de conservação (`card_condition`) + vínculo por fonte
 * externa (`pricing_condition_mapping`), hoje 5 condições × 1 fonte
 * (JUSTTCG). Sem paginação (volume baixo e estável, mesmo raciocínio de
 * `PricingSourcesTable`). `is_active=false` sempre permitido mesmo com
 * `hasDependentObservations=true` — desativar preserva histórico, é o
 * propósito do campo (decisão de Fabrício); nunca há exclusão física de
 * condição ou de vínculo aqui.
 *
 * Rodada de refinamento visual (2026-08-28, pedido explícito de Fabrício):
 * nome da condição ganha mais peso e o código (NM/LP/MP/HP/DMG) vira pill
 * discreto ao lado, com o badge de status associado à própria linha do nome
 * (coluna "Status" isolada removida); o `Pencil` fica reservado
 * exclusivamente para "editar condição" (coluna Ações) — o mapeamento por
 * fonte externa usa `Link2` num controle explícito (código + ícone +
 * tooltip "Editar mapeamento {fonte}"), nunca o mesmo ícone da edição da
 * condição, para eliminar a ambiguidade entre as duas ações.
 *
 * Ajuste de densidade (2026-08-28, mesma rodada, aprovação com um único
 * refinamento): altura/padding vertical das linhas aumentado (`py-2` →
 * `py-3.5` nas células de dado, `py-2` no cabeçalho, de `py-1.5` padrão de
 * `DataTableHeadCell`) só dentro desta tabela — override local via
 * `className`, sem tocar nos primitives compartilhados `DataTableCell`/
 * `DataTableHeadCell` nem qualquer outra tabela do app. Nenhuma coluna,
 * ação ou hierarquia alterada nesta rodada.
 *
 * Padronização de CTAs primários do Pricing (2026-08-28, pedido explícito
 * de Fabrício, revoga a decisão acima): o botão "Nova Condição" volta de
 * `outline` para `default` (dourado) — mesmo padrão visual já aprovado no
 * Catálogo Editorial para ações primárias de criação (referência: "+ Nova
 * Raridade" em `raridades-table.tsx`, `Button` sem `variant` = CTA dourado
 * `ctaStyles.cta` de `button-cta.module.css`). Reusa o mesmo componente/
 * variant do Catálogo — nenhum estilo novo duplicado. Único CTA primário de
 * criação identificado em todo o módulo Pricing nesta auditoria: as demais
 * ações com ícone (`Pencil`/`Link2`/`PencilLine` em Mapeamentos de Cartas,
 * Preços Manuais, Fontes) são edição inline ou contextuais por linha, fora
 * do escopo desta padronização.
 */
export function CardConditionsTable({ conditions, sources }: { conditions: CardCondition[]; sources: PricingSource[] }) {
  const router = useRouter();
  const state = useAdminListState();
  const [mappingContext, setMappingContext] = useState<{ condition: CardCondition; source: PricingSource } | null>(null);
  const editingCondition = conditions.find((c) => c.id === state.editingId) ?? null;
  const nextOrder = conditions.reduce((max, c) => Math.max(max, c.conditionOrder), 0) + 1;

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <div className="flex justify-end">
        <Button type="button" size="sm" onClick={state.startCreate}>
          <Plus className="h-3.5 w-3.5" />
          Nova Condição
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {conditions.length === 0 ? (
            <EmptyState title="Nenhuma condição cadastrada ainda" description='Use o botão "Nova Condição" para começar.' className="py-10" />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="py-2 pl-4">Condição</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="py-2">
                    Ordem
                  </DataTableHeadCell>
                  {sources.map((source) => (
                    <DataTableHeadCell key={source.id} align="center" className="py-2">
                      Mapeamento {source.code}
                    </DataTableHeadCell>
                  ))}
                  <DataTableHeadCell align="center" className="py-2 pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {conditions.map((condition) => (
                  <DataTableRow key={condition.id} highlighted={state.highlightId === condition.id}>
                    <DataTableCell className="py-3.5 pl-4">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="text-sm font-semibold text-foreground">{condition.name}</p>
                        <code className="rounded-full border border-border bg-surface-muted px-1.5 py-0.5 text-[10px] uppercase text-muted-foreground">
                          {condition.code}
                        </code>
                        {condition.isActive ? <Badge variant="outline">Ativa</Badge> : <Badge variant="warning">Inativa</Badge>}
                      </div>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-3.5">
                      {condition.conditionOrder}
                    </DataTableCell>
                    {sources.map((source) => {
                      const mapping = condition.mappings.find((m) => m.pricingSourceId === source.id) ?? null;
                      return (
                        <DataTableCell key={source.id} align="center" className="py-3.5">
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <button
                                type="button"
                                className="inline-flex items-center gap-1.5 rounded-full border border-border bg-surface-muted px-2.5 py-1 text-xs text-foreground transition-colors hover:border-primary/40 hover:bg-primary/5"
                                aria-label={`${mapping ? "Editar" : "Vincular"} mapeamento de ${condition.name} em ${source.name}`}
                                onClick={() => setMappingContext({ condition, source })}
                              >
                                <code className="text-xs text-muted-foreground">{mapping?.externalConditionCode ?? "—"}</code>
                                <Link2 className="h-3 w-3 text-muted-foreground" aria-hidden="true" />
                              </button>
                            </TooltipTrigger>
                            <TooltipContent>Editar mapeamento {source.name}</TooltipContent>
                          </Tooltip>
                        </DataTableCell>
                      );
                    })}
                    <DataTableCell align="center" className="py-3.5 pr-4 last:pr-4">
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Editar ${condition.name}`}
                            onClick={() => state.startEdit(condition.id)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>Editar condição</TooltipContent>
                      </Tooltip>
                    </DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}
        </CardContent>
      </Card>

      <CreateConditionDialog open={state.creating} nextOrder={nextOrder} onSaved={handleSaved} onCancel={state.cancelCreate} />

      <EditConditionDialog open={editingCondition !== null} condition={editingCondition} onSaved={handleSaved} onCancel={state.cancelEdit} />

      <ConditionMappingDialog
        open={mappingContext !== null}
        context={mappingContext}
        onSaved={(message) => {
          setMappingContext(null);
          handleSaved(message);
        }}
        onCancel={() => setMappingContext(null)}
      />
    </div>
  );
}

function CreateConditionDialog({
  open,
  nextOrder,
  onSaved,
  onCancel,
}: {
  open: boolean;
  nextOrder: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Nova Condição</DialogTitle>
          <DialogDescription>Cadastre uma nova condição de conservação canônica.</DialogDescription>
        </DialogHeader>

        {open && <ConditionForm nextOrder={nextOrder} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />}
      </DialogContent>
    </Dialog>
  );
}

function EditConditionDialog({
  open,
  condition,
  onSaved,
  onCancel,
}: {
  open: boolean;
  condition: CardCondition | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Condição</DialogTitle>
          <DialogDescription>
            {condition?.hasDependentObservations
              ? "Já existe histórico de preço usando esta condição — desativar não apaga nada, só impede novo vínculo."
              : "Código é imutável após o cadastro."}
          </DialogDescription>
        </DialogHeader>

        {open && condition && (
          <ConditionForm key={condition.id} condition={condition} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ConditionForm({
  condition,
  nextOrder,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  condition?: CardCondition;
  nextOrder?: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: SalvarCondicaoState = { error: null };
  const [state, formAction, pending] = useActionState(salvarCondicao, initialState);
  const idSuffix = condition?.id ?? "new";

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved(condition ? "Condição atualizada com sucesso." : "Condição cadastrada com sucesso.", state.id ?? condition?.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      {condition && <input type="hidden" name="id" value={condition.id} />}
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`condition-code-${idSuffix}`}>Código {condition && <span className="text-muted-foreground">(imutável)</span>}</Label>
            <Input
              id={`condition-code-${idSuffix}`}
              name="code"
              defaultValue={condition?.code}
              placeholder="Ex.: NM"
              readOnly={Boolean(condition)}
              aria-readonly={Boolean(condition)}
              className={condition ? "cursor-not-allowed bg-surface-muted opacity-70" : undefined}
              required
              maxLength={20}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`condition-name-${idSuffix}`}>Nome</Label>
            <Input id={`condition-name-${idSuffix}`} name="name" defaultValue={condition?.name} placeholder="Ex.: Near Mint" required maxLength={100} />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`condition-order-${idSuffix}`}>Ordem</Label>
            <Input
              id={`condition-order-${idSuffix}`}
              name="condition_order"
              type="number"
              min={1}
              defaultValue={condition?.conditionOrder ?? nextOrder}
              required
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`condition-active-${idSuffix}`}>Status</Label>
            <Select id={`condition-active-${idSuffix}`} name="is_active" defaultValue={condition?.isActive ?? true ? "on" : ""}>
              <option value="on">Ativa</option>
              <option value="">Inativa</option>
            </Select>
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : condition ? "Salvar" : "Cadastrar Condição"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function ConditionMappingDialog({
  open,
  context,
  onSaved,
  onCancel,
}: {
  open: boolean;
  context: { condition: CardCondition; source: PricingSource } | null;
  onSaved: (message: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Código externo em {context?.source.code}</DialogTitle>
          <DialogDescription>
            {context ? `Vínculo de "${context.condition.name}" com o código de condição usado por ${context.source.name}.` : ""}
          </DialogDescription>
        </DialogHeader>

        {open && context && (
          <ConditionMappingForm key={`${context.condition.id}-${context.source.id}`} context={context} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ConditionMappingForm({
  context,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  context: { condition: CardCondition; source: PricingSource };
  onSaved: (message: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: SalvarMapeamentoCondicaoState = { error: null };
  const [state, formAction, pending] = useActionState(salvarMapeamentoCondicao, initialState);
  const existing = context.condition.mappings.find((m) => m.pricingSourceId === context.source.id) ?? null;

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Código externo salvo com sucesso.");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      {existing && <input type="hidden" name="id" value={existing.id} />}
      <input type="hidden" name="pricing_source_id" value={context.source.id} />
      <input type="hidden" name="condition_id" value={context.condition.id} />
      <DialogBody className="space-y-3">
        {!context.condition.isActive && (
          <InlineFeedback tone="warning">
            Esta condição está inativa — reative-a antes de vincular um código externo.
          </InlineFeedback>
        )}
        <div className="space-y-1">
          <Label htmlFor={`mapping-external-code-${context.condition.id}-${context.source.id}`}>Código externo</Label>
          <Input
            id={`mapping-external-code-${context.condition.id}-${context.source.id}`}
            name="external_condition_code"
            defaultValue={existing?.externalConditionCode ?? ""}
            placeholder="Ex.: Near Mint"
            required
            maxLength={100}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending || !context.condition.isActive}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
