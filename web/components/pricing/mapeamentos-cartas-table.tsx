"use client";

import { ChevronLeft, ChevronRight, Lock, ShieldCheck, ShieldX } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  reclassificarMapeamentoCarta,
  type ReclassificarMapeamentoCartaState,
} from "@/app/pricing/mapeamentos-cartas/actions";
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
import { Label } from "@/components/ui/label";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { MapeamentosCartasFiltros } from "@/components/pricing/mapeamentos-cartas-filtros";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import {
  PRICING_CARD_MAPPINGS_PAGE_SIZE,
  type PricingCardMappingItem,
  type PricingCardSetOption,
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
 * Cadastro de Mapeamentos de Cartas (Bloco 4 do Pricing Admin, migration
 * 3942) — todos os 4 status (diferente de `/pricing/pendencias`, que trava
 * em PENDING/NOT_FOUND, e de `/pricing/resolucao-mapeamentos`, que resolve
 * um mapping por vez com atribuição de identidades). Aqui só existe consulta
 * + reclassificação pontual CONFIRMED↔REJECTED; CONFIRMED→REJECTED fica
 * bloqueada (ícone de cadeado) quando `hasDependency` — já existe
 * `pricing_product` vinculado (decisão de Fabrício: reclassificação direta
 * nunca desfaz dado de preço já publicado).
 */
export function MapeamentosCartasTable({
  items,
  totalCount,
  page,
  search,
  status,
  cardSetId,
  pricingSourceId,
  cardSets,
  sources,
}: {
  items: PricingCardMappingItem[];
  totalCount: number;
  page: number;
  search: string;
  status: string;
  cardSetId: string;
  pricingSourceId: string;
  cardSets: PricingCardSetOption[];
  sources: PricingSource[];
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [reclassifying, setReclassifying] = useState<PricingCardMappingItem | null>(null);
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_CARD_MAPPINGS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (status) params.set("status", status);
    if (cardSetId) params.set("set", cardSetId);
    if (pricingSourceId) params.set("source", pricingSourceId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/mapeamentos-cartas?${qs}` : "/pricing/mapeamentos-cartas";
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  const hasFilter = Boolean(search || status || cardSetId || pricingSourceId);

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card>
        <div className="border-b border-border px-4 py-3">
          <MapeamentosCartasFiltros
            initialSearch={search}
            status={status}
            cardSetId={cardSetId}
            pricingSourceId={pricingSourceId}
            cardSets={cardSets}
            sources={sources}
          />
        </div>
        <CardContent className="p-0">
          {items.length === 0 ? (
            <EmptyState
              title={hasFilter ? "Nenhum mapeamento para este filtro" : "Nenhum mapeamento de carta cadastrado"}
              description={hasFilter ? "Troque os filtros para ver outros mapeamentos." : undefined}
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-4">Carta</DataTableHeadCell>
                  <DataTableHeadCell>Set</DataTableHeadCell>
                  <DataTableHeadCell>Fonte</DataTableHeadCell>
                  <DataTableHeadCell align="center">Status</DataTableHeadCell>
                  <DataTableHeadCell align="center">Candidatas</DataTableHeadCell>
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
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-foreground">{item.cardName}</p>
                        <p className="text-xs tabular-nums text-muted-foreground">
                          {item.collectorNumber}
                          {item.collectorTotal ? `/${item.collectorTotal}` : ""}
                        </p>
                      </div>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs text-foreground">{item.cardSetName}</span>
                      <span className="ml-1 text-xs text-muted-foreground">({item.cardSetCode})</span>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs uppercase text-muted-foreground">{item.pricingSourceCode}</span>
                    </DataTableCell>
                    <DataTableCell align="center">
                      <div className="flex items-center justify-center gap-1.5">
                        <StateBadge tone={STATUS_TONE[item.matchStatus] ?? "muted"}>
                          {STATUS_LABEL[item.matchStatus] ?? item.matchStatus}
                        </StateBadge>
                        {item.hasDependency && (
                          <Lock className="h-3 w-3 shrink-0 text-muted-foreground" aria-label="Protegido por dependência" />
                        )}
                      </div>
                    </DataTableCell>
                    <DataTableCell align="center">
                      <span className="tabular-nums">{formatNumber(item.identityCount)}</span>
                    </DataTableCell>
                    <DataTableCell>{formatDate(item.lastCheckedAt)}</DataTableCell>
                    <DataTableCell align="center" className="pr-4 last:pr-4">
                      <div className="flex justify-center gap-2">
                        {item.matchStatus === "CONFIRMED" && (
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Rejeitar mapeamento de ${item.cardName}`}
                            disabled={item.hasDependency}
                            title={item.hasDependency ? "Protegido: já existe produto/observação de preço vinculado." : undefined}
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
                            aria-label={`Confirmar mapeamento de ${item.cardName}`}
                            onClick={() => setReclassifying(item)}
                          >
                            <ShieldCheck className="h-3.5 w-3.5" />
                          </Button>
                        )}
                        {(item.matchStatus === "PENDING" || item.matchStatus === "NOT_FOUND") && (
                          <Button asChild variant="outline" size="sm">
                            <Link href={`/pricing/resolucao-mapeamentos?mapping=${item.id}`}>Resolver</Link>
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
              Mostrando <span className="font-medium text-foreground">{page * PRICING_CARD_MAPPINGS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_CARD_MAPPINGS_PAGE_SIZE, totalCount)}
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

      <ReclassifyCardMappingDialog
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

function ReclassifyCardMappingDialog({
  open,
  item,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingCardMappingItem | null;
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
          <DialogTitle>{item?.matchStatus === "CONFIRMED" ? "Rejeitar" : "Confirmar"} Mapeamento de Carta</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardName} · ${item.cardSetCode} · ${item.pricingSourceCode}` : ""} — informe o motivo, registrado
            no log de auditoria.
          </DialogDescription>
        </DialogHeader>

        {open && item && (
          <ReclassifyCardMappingForm key={item.id} item={item} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ReclassifyCardMappingForm({
  item,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingCardMappingItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: ReclassificarMapeamentoCartaState = { error: null };
  const [state, formAction, pending] = useActionState(reclassificarMapeamentoCarta, initialState);
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
          <Label htmlFor={`reclassify-card-mapping-reason-${item.id}`}>Motivo</Label>
          <textarea
            id={`reclassify-card-mapping-reason-${item.id}`}
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
