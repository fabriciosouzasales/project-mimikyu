"use client";

import { ChevronLeft, ChevronRight, Lock, Pencil, ShieldCheck, ShieldX } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  atualizarDetalhesMapeamentoSet,
  reclassificarMapeamentoSet,
  type AtualizarDetalhesMapeamentoSetState,
  type ReclassificarMapeamentoSetState,
} from "@/app/pricing/mapeamentos-sets/actions";
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
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { MapeamentosSetsFiltros } from "@/components/pricing/mapeamentos-sets-filtros";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import {
  PRICING_SET_MAPPINGS_PAGE_SIZE,
  type PricingSetMappingItem,
  type PricingSource,
} from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const STATUS_LABEL: Record<string, string> = {
  CONFIRMED: "Confirmado",
  PENDING: "Pendente",
  NOT_FOUND: "Não encontrado",
  REJECTED: "Rejeitado",
};

const STATUS_TONE: Record<string, StateTone> = {
  CONFIRMED: "success",
  PENDING: "warning",
  NOT_FOUND: "muted",
  REJECTED: "danger",
};

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

function formatDate(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
}

/**
 * Cadastro de Mapeamentos de Sets (Bloco 4 do Pricing Admin, migration
 * 3942) — todos os 4 status (diferente de `/pricing/pendencias`, que trava
 * em PENDING/NOT_FOUND). `external_set_name` sempre editável;
 * `external_set_id` e a reclassificação CONFIRMED→REJECTED ficam
 * bloqueados quando `hasDependency` (ícone de cadeado) — a mesma fonte
 * única de verdade da migration 3942 (`pricing_set_mapping_dependency_exists`),
 * a UI só espelha o que a RPC decide.
 */
export function MapeamentosSetsTable({
  items,
  totalCount,
  page,
  search,
  status,
  pricingSourceId,
  sources,
}: {
  items: PricingSetMappingItem[];
  totalCount: number;
  page: number;
  search: string;
  status: string;
  pricingSourceId: string;
  sources: PricingSource[];
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [reclassifying, setReclassifying] = useState<PricingSetMappingItem | null>(null);
  const editingItem = items.find((i) => i.id === state.editingId) ?? null;
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_SET_MAPPINGS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (status) params.set("status", status);
    if (pricingSourceId) params.set("source", pricingSourceId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/mapeamentos-sets?${qs}` : "/pricing/mapeamentos-sets";
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  const hasFilter = Boolean(search || status || pricingSourceId);

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card>
        <div className="border-b border-border px-4 py-3">
          <MapeamentosSetsFiltros initialSearch={search} status={status} pricingSourceId={pricingSourceId} sources={sources} />
        </div>
        <CardContent className="p-0">
          {items.length === 0 ? (
            <EmptyState
              title={hasFilter ? "Nenhum mapeamento para este filtro" : "Nenhum mapeamento de Set cadastrado"}
              description={hasFilter ? "Troque os filtros para ver outros mapeamentos." : undefined}
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-4">Set</DataTableHeadCell>
                  <DataTableHeadCell>Fonte</DataTableHeadCell>
                  <DataTableHeadCell>ID externo</DataTableHeadCell>
                  <DataTableHeadCell>Nome externo</DataTableHeadCell>
                  <DataTableHeadCell align="center">Status</DataTableHeadCell>
                  <DataTableHeadCell>Última verificação</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {items.map((item) => (
                  <DataTableRow key={item.id} highlighted={state.highlightId === item.id}>
                    <DataTableCell className="pl-4">
                      <span className="text-sm text-foreground">{item.cardSetName}</span>
                      <span className="ml-1 text-xs text-muted-foreground">({item.cardSetCode})</span>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs uppercase text-muted-foreground">{item.pricingSourceCode}</span>
                    </DataTableCell>
                    <DataTableCell>
                      <div className="flex items-center gap-1.5">
                        <code className="text-xs text-muted-foreground">{item.externalSetId ?? "—"}</code>
                        {item.hasDependency && (
                          <Lock className="h-3 w-3 shrink-0 text-muted-foreground" aria-label="Protegido por dependência" />
                        )}
                      </div>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs text-muted-foreground">{item.externalSetName ?? "—"}</span>
                    </DataTableCell>
                    <DataTableCell align="center">
                      <StateBadge tone={STATUS_TONE[item.matchStatus] ?? "muted"}>
                        {STATUS_LABEL[item.matchStatus] ?? item.matchStatus}
                      </StateBadge>
                    </DataTableCell>
                    <DataTableCell>{formatDate(item.lastCheckedAt)}</DataTableCell>
                    <DataTableCell align="center" className="pr-4 last:pr-4">
                      <div className="flex justify-center gap-2">
                        <Button
                          type="button"
                          variant="outline"
                          size="icon-sm"
                          aria-label={`Editar ${item.cardSetName}`}
                          onClick={() => state.startEdit(item.id)}
                        >
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        {item.matchStatus === "CONFIRMED" && (
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Rejeitar mapeamento de ${item.cardSetName}`}
                            disabled={item.hasDependency}
                            title={item.hasDependency ? "Protegido: existe mapeamento de carta confirmado ou dado de preço vinculado a este Set." : undefined}
                            onClick={() => setReclassifying(item)}
                          >
                            <ShieldX className="h-3.5 w-3.5" />
                          </Button>
                        )}
                        {item.matchStatus === "REJECTED" && (
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Confirmar mapeamento de ${item.cardSetName}`}
                            onClick={() => setReclassifying(item)}
                          >
                            <ShieldCheck className="h-3.5 w-3.5" />
                          </Button>
                        )}
                      </div>
                    </DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}
        </CardContent>

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_SET_MAPPINGS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_SET_MAPPINGS_PAGE_SIZE, totalCount)}
              </span>{" "}
              de <span className="font-medium text-foreground">{formatNumber(totalCount)}</span>
            </span>
            <div className="flex items-center gap-1.5">
              {page === 0 ? (
                <Button type="button" variant="outline" size="icon-sm" disabled aria-label="Página anterior">
                  <ChevronLeft className="h-3.5 w-3.5" />
                </Button>
              ) : (
                <Button asChild variant="outline" size="icon-sm" aria-label="Página anterior">
                  <Link href={buildPageHref(page - 1)}>
                    <ChevronLeft className="h-3.5 w-3.5" />
                  </Link>
                </Button>
              )}
              <span className="min-w-[2.5rem] text-center text-sm text-muted-foreground">
                {page + 1}/{totalPages}
              </span>
              {page >= totalPages - 1 ? (
                <Button type="button" variant="outline" size="icon-sm" disabled aria-label="Próxima página">
                  <ChevronRight className="h-3.5 w-3.5" />
                </Button>
              ) : (
                <Button asChild variant="outline" size="icon-sm" aria-label="Próxima página">
                  <Link href={buildPageHref(page + 1)}>
                    <ChevronRight className="h-3.5 w-3.5" />
                  </Link>
                </Button>
              )}
            </div>
          </div>
        )}
      </Card>

      <EditSetMappingDialog open={editingItem !== null} item={editingItem} onSaved={handleSaved} onCancel={state.cancelEdit} />

      <ReclassifySetMappingDialog
        open={reclassifying !== null}
        item={reclassifying}
        onSaved={(message, id) => {
          setReclassifying(null);
          handleSaved(message, id);
        }}
        onCancel={() => setReclassifying(null)}
      />
    </div>
  );
}

function EditSetMappingDialog({
  open,
  item,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingSetMappingItem | null;
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
          <DialogTitle>Editar Mapeamento de Set</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardSetName} (${item.cardSetCode}) · ${item.pricingSourceCode}` : "Identidade externa deste Set."}
          </DialogDescription>
        </DialogHeader>

        {open && item && <EditSetMappingForm key={item.id} item={item} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />}
      </DialogContent>
    </Dialog>
  );
}

function EditSetMappingForm({
  item,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingSetMappingItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: AtualizarDetalhesMapeamentoSetState = { error: null };
  const [state, formAction, pending] = useActionState(atualizarDetalhesMapeamentoSet, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Mapeamento de Set atualizado com sucesso.", item.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={item.id} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor={`edit-set-mapping-external-id-${item.id}`}>
            ID externo {item.hasDependency && <span className="text-muted-foreground">(protegido)</span>}
          </Label>
          <Input
            id={`edit-set-mapping-external-id-${item.id}`}
            name="external_set_id"
            defaultValue={item.externalSetId ?? ""}
            readOnly={item.hasDependency}
            aria-readonly={item.hasDependency}
            className={item.hasDependency ? "cursor-not-allowed bg-surface-muted opacity-70" : undefined}
          />
          {item.hasDependency && (
            <p className="text-xs text-muted-foreground">
              Este Set já tem mapeamento de carta confirmado ou dado de preço vinculado a esta fonte — o identificador externo
              não pode mais ser alterado por aqui.
            </p>
          )}
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-set-mapping-external-name-${item.id}`}>Nome externo (descritivo)</Label>
          <Input
            id={`edit-set-mapping-external-name-${item.id}`}
            name="external_set_name"
            defaultValue={item.externalSetName ?? ""}
            maxLength={200}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function ReclassifySetMappingDialog({
  open,
  item,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingSetMappingItem | null;
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
          <DialogTitle>{item?.matchStatus === "CONFIRMED" ? "Rejeitar" : "Confirmar"} Mapeamento de Set</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardSetName} (${item.cardSetCode}) · ${item.pricingSourceCode}` : ""} — informe o motivo desta
            reclassificação, registrado no log de auditoria.
          </DialogDescription>
        </DialogHeader>

        {open && item && (
          <ReclassifySetMappingForm key={item.id} item={item} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ReclassifySetMappingForm({
  item,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingSetMappingItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: ReclassificarMapeamentoSetState = { error: null };
  const [state, formAction, pending] = useActionState(reclassificarMapeamentoSet, initialState);
  const newStatus = item.matchStatus === "CONFIRMED" ? "REJECTED" : "CONFIRMED";

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved(newStatus === "REJECTED" ? "Mapeamento rejeitado com sucesso." : "Mapeamento confirmado com sucesso.", item.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={item.id} />
      <input type="hidden" name="new_status" value={newStatus} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor={`reclassify-set-mapping-reason-${item.id}`}>Motivo</Label>
          <textarea
            id={`reclassify-set-mapping-reason-${item.id}`}
            name="reason"
            required
            maxLength={500}
            placeholder="Explique por que este mapeamento está sendo reclassificado."
            className={textareaClassName}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" variant={newStatus === "REJECTED" ? "destructive" : "default"} disabled={pending}>
          {pending ? "Salvando…" : newStatus === "REJECTED" ? "Rejeitar" : "Confirmar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
