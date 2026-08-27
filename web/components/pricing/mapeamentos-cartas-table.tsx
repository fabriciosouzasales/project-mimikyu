"use client";

import { ChevronLeft, ChevronRight, ShieldCheck } from "lucide-react";
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
  type PricingCardMappingIssueItem,
  type PricingCardSetOption,
  type PricingSource,
} from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  NOT_FOUND: "Não encontrado",
  REJECTED: "Rejeitado",
};

const STATUS_TONE: Record<string, StateTone> = {
  PENDING: "warning",
  NOT_FOUND: "muted",
  REJECTED: "danger",
};

const TIPO_PROBLEMA_LABEL: Record<string, string> = {
  PENDING: "Aguardando correspondência",
  NOT_FOUND: "Não encontrado na fonte",
  REJECTED: "Rejeitado — revisar",
};

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

function formatDate(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
}

/**
 * Fila operacional de Mapeamentos de Cartas (Bloco 4 do Pricing Admin,
 * migration 3942; convergência com Pendências em 2026-08-27, migrations
 * 3961/3962) — PENDING/NOT_FOUND/REJECTED, nunca CONFIRMED. Ação por linha
 * é condicional ao status: PENDING/NOT_FOUND levam para
 * `/pricing/resolucao-mapeamentos` (fluxo de atribuição de identidades,
 * Bloco 2); REJECTED abre o dialog de reclassificação para CONFIRMED, com
 * hardening no banco (migration 3962) que exige uma identity PRIMARY já
 * confirmada antes de aceitar. CONFIRMED→REJECTED não é mais uma ação
 * possível nesta tela — CONFIRMED nunca aparece na fila.
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
  items: PricingCardMappingIssueItem[];
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
  const [reclassifying, setReclassifying] = useState<PricingCardMappingIssueItem | null>(null);
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
              title={hasFilter ? "Nenhum mapeamento para este filtro" : "Nenhuma exceção pendente"}
              description={
                hasFilter
                  ? "Troque os filtros para ver outros mapeamentos."
                  : "Todos os mapeamentos conhecidos já foram confirmados."
              }
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-4">
                    <span className="sr-only">Imagem</span>
                  </DataTableHeadCell>
                  <DataTableHeadCell>Carta</DataTableHeadCell>
                  <DataTableHeadCell>Set</DataTableHeadCell>
                  <DataTableHeadCell>Fonte</DataTableHeadCell>
                  <DataTableHeadCell align="center">Status</DataTableHeadCell>
                  <DataTableHeadCell>Tipo de problema</DataTableHeadCell>
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
                      {item.thumbnailUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={item.thumbnailUrl}
                          alt=""
                          loading="lazy"
                          decoding="async"
                          className="h-14 w-10 rounded border border-border object-cover"
                        />
                      ) : (
                        <div className="flex h-14 w-10 items-center justify-center rounded border border-dashed border-border bg-surface-muted text-center text-[8px] leading-tight text-muted-foreground">
                          Sem imagem
                        </div>
                      )}
                    </DataTableCell>
                    <DataTableCell>
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
                      <StateBadge tone={STATUS_TONE[item.matchStatus] ?? "muted"}>
                        {STATUS_LABEL[item.matchStatus] ?? item.matchStatus}
                      </StateBadge>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs text-muted-foreground">
                        {TIPO_PROBLEMA_LABEL[item.matchStatus] ?? item.matchStatus}
                      </span>
                    </DataTableCell>
                    <DataTableCell align="center">
                      <span className="tabular-nums">{formatNumber(item.candidateCount)}</span>
                    </DataTableCell>
                    <DataTableCell>{formatDate(item.lastCheckedAt)}</DataTableCell>
                    <DataTableCell align="center" className="pr-4 last:pr-4">
                      <div className="flex justify-center gap-2">
                        {item.matchStatus === "REJECTED" ? (
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            aria-label={`Revisar/reclassificar mapeamento de ${item.cardName}`}
                            onClick={() => setReclassifying(item)}
                          >
                            <ShieldCheck className="mr-1 h-3.5 w-3.5" />
                            Revisar
                          </Button>
                        ) : (
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
  item: PricingCardMappingIssueItem | null;
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
          <DialogTitle>Confirmar Mapeamento de Carta</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardName} · ${item.cardSetCode} · ${item.pricingSourceCode}` : ""} — exige uma identidade
            PRIMARY já confirmada; informe o motivo, registrado no log de auditoria.
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
  item: PricingCardMappingIssueItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: ReclassificarMapeamentoCartaState = { error: null };
  const [state, formAction, pending] = useActionState(reclassificarMapeamentoCarta, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Mapeamento confirmado com sucesso.", item.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={item.id} />
      <input type="hidden" name="new_status" value="CONFIRMED" />
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
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Confirmar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
