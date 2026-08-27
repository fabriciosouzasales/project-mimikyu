"use client";

import { ChevronLeft, ChevronRight, PencilLine } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { definirPrecoManual, type DefinirPrecoManualState } from "@/app/pricing/precos-manuais/actions";
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
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { StateBadge } from "@/components/catalogo/state-badge";
import { PrecosManuaisFiltros } from "@/components/pricing/precos-manuais-filtros";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import {
  PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE,
  type CardCondition,
  type PricingCardSetOption,
  type PricingManualPriceCandidateItem,
  type PricingManualPriceCandidateReason,
} from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

// Motivo único desde a migration 3970 (elegibilidade = match_status='NOT_FOUND'
// estrito) — Record de 1 chave preservado, não um literal solto, para não
// exigir troca em cascata caso um segundo motivo real volte a existir.
const REASON_LABEL: Record<PricingManualPriceCandidateReason, string> = {
  NO_EXTERNAL_MATCH: "Sem correspondência externa encontrada",
};

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

/** Mesmo padrão local de `preco-por-carta-report.tsx` — `formatMoney` não é utilitário compartilhado em `lib/utils`. */
function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

/** Formato aceito por `<input type="datetime-local">` — horário local, sem timezone. */
function toDatetimeLocalValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/**
 * Preços Manuais (migrations 3967-3969, frontend 2026-08-27) — fallback
 * manual do preço automático. Toda a tela trabalha sempre na condição
 * selecionada (`conditionId`, seletor no topo via `PrecosManuaisFiltros`):
 * a carta some da lista sozinha quando existir automático utilizável naquela
 * condição — nenhuma ação de remoção existe aqui. Escrita é sempre um novo
 * INSERT (`admin_set_manual_price`, append-only) — "Atualizar preço" nunca
 * edita o registro anterior, só cria um novo que passa a valer.
 */
export function PrecosManuaisTable({
  items,
  totalCount,
  page,
  search,
  conditionId,
  cardSetId,
  conditions,
  cardSets,
}: {
  items: PricingManualPriceCandidateItem[];
  totalCount: number;
  page: number;
  search: string;
  conditionId: string;
  cardSetId: string;
  conditions: CardCondition[];
  cardSets: PricingCardSetOption[];
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [editing, setEditing] = useState<PricingManualPriceCandidateItem | null>(null);
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE));
  const selectedCondition = conditions.find((c) => c.id === conditionId) ?? null;

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (conditionId) params.set("condition", conditionId);
    if (cardSetId) params.set("set", cardSetId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/precos-manuais?${qs}` : "/pricing/precos-manuais";
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  const hasFilter = Boolean(search || cardSetId);

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card>
        <div className="border-b border-border px-4 py-2.5">
          <PrecosManuaisFiltros
            initialSearch={search}
            conditionId={conditionId}
            cardSetId={cardSetId}
            conditions={conditions}
            cardSets={cardSets}
          />
        </div>
        <CardContent className="p-0">
          {items.length === 0 ? (
            <EmptyState
              title={hasFilter ? "Nenhuma carta para este filtro" : "Nenhuma carta elegível nesta condição"}
              description={
                hasFilter
                  ? "Troque os filtros para ver outras cartas."
                  : "Todas as cartas conhecidas já têm preço automático utilizável nesta condição."
              }
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell align="center" className="w-16 pl-4">
                    <span className="sr-only">Imagem</span>
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="min-w-[12rem]">
                    Carta
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="min-w-[9rem]">
                    Set
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="max-w-[13rem]">
                    Motivo
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="w-16">
                    Condição
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="min-w-[9rem]">
                    Último preço
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="whitespace-nowrap">
                    Observado em
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="w-20">
                    Autoria
                  </DataTableHeadCell>
                  <DataTableHeadCell align="center" className="w-40 pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {items.map((item) => (
                  <DataTableRow key={item.cardId} highlighted={state.highlightId === item.cardId}>
                    <DataTableCell className="py-0.5 pl-4 align-middle">
                      {item.thumbnailUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={item.thumbnailUrl}
                          alt=""
                          loading="lazy"
                          decoding="async"
                          className="h-16 w-auto aspect-[63/88] object-contain"
                        />
                      ) : (
                        <div className="flex h-16 w-auto aspect-[63/88] items-center justify-center rounded border border-dashed border-border bg-surface-muted text-center text-[8px] leading-tight text-muted-foreground">
                          Sem imagem
                        </div>
                      )}
                    </DataTableCell>
                    <DataTableCell className="py-1.5 align-middle">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-foreground">{item.cardName}</p>
                        <p className="text-xs tabular-nums text-muted-foreground">
                          {item.collectorNumber}
                          {item.collectorTotal ? `/${item.collectorTotal}` : ""}
                        </p>
                      </div>
                    </DataTableCell>
                    <DataTableCell className="py-1.5 align-middle">
                      <span className="text-xs text-foreground">{item.cardSetName}</span>
                      <span className="ml-1 whitespace-nowrap text-xs text-muted-foreground">
                        ({item.cardSetCode})
                      </span>
                    </DataTableCell>
                    <DataTableCell className="max-w-[13rem] py-1.5 align-middle">
                      <span className="line-clamp-2 text-xs leading-snug text-muted-foreground">
                        {REASON_LABEL[item.reason] ?? item.reason}
                      </span>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1.5 align-middle">
                      <span className="text-xs uppercase text-muted-foreground">{selectedCondition?.code ?? "—"}</span>
                    </DataTableCell>
                    <DataTableCell align="right" className="py-1.5 align-middle">
                      {item.manualPrice !== null ? (
                        <div className="flex items-center justify-end gap-1.5 whitespace-nowrap">
                          <StateBadge tone="warning">MANUAL</StateBadge>
                          <span className="tabular-nums text-sm font-medium text-foreground">
                            {formatMoney(item.manualPrice, item.manualCurrencyCode ?? "BRL")}
                          </span>
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">Sem preço manual</span>
                      )}
                    </DataTableCell>
                    <DataTableCell className="whitespace-nowrap py-1.5 align-middle text-xs">
                      {formatDateTime(item.manualObservedAt)}
                    </DataTableCell>
                    <DataTableCell className="py-1.5 align-middle">
                      {item.manualActorId ? (
                        <span className="text-xs tabular-nums text-muted-foreground" title={item.manualActorId}>
                          {item.manualActorId.slice(0, 8)}
                        </span>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="w-40 py-1.5 pr-4 align-middle last:pr-4">
                      <div className="flex justify-center">
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="w-full min-w-[9.5rem] justify-center"
                          aria-label={`${item.manualPrice !== null ? "Atualizar" : "Definir"} preço manual de ${item.cardName}`}
                          onClick={() => setEditing(item)}
                        >
                          <PencilLine className="mr-1 h-3.5 w-3.5 shrink-0" />
                          {item.manualPrice !== null ? "Atualizar preço" : "Definir preço"}
                        </Button>
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
              Mostrando{" "}
              <span className="font-medium text-foreground">{page * PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_MANUAL_PRICE_CANDIDATES_PAGE_SIZE, totalCount)}
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

      <ManualPriceDialog
        open={editing !== null}
        item={editing}
        conditionId={conditionId}
        conditionName={selectedCondition?.name ?? ""}
        onSaved={(message, id) => {
          setEditing(null);
          handleSaved(message, id);
        }}
        onCancel={() => setEditing(null)}
      />
    </div>
  );
}

function ManualPriceDialog({
  open,
  item,
  conditionId,
  conditionName,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingManualPriceCandidateItem | null;
  conditionId: string;
  conditionName: string;
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
          <DialogTitle>{item?.manualPrice !== null && item ? "Atualizar preço manual" : "Definir preço manual"}</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardName} · ${item.cardSetCode} · Condição ${conditionName}` : ""} — o novo valor gera um
            registro novo, o anterior é preservado no histórico.
          </DialogDescription>
        </DialogHeader>

        {open && item && (
          <ManualPriceForm
            key={`${item.cardId}-${conditionId}`}
            item={item}
            conditionId={conditionId}
            conditionName={conditionName}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ManualPriceForm({
  item,
  conditionId,
  conditionName,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingManualPriceCandidateItem;
  conditionId: string;
  conditionName: string;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: DefinirPrecoManualState = { error: null };
  const [state, formAction, pending] = useActionState(definirPrecoManual, initialState);
  const defaultObservedAt = toDatetimeLocalValue(new Date());

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved(
        item.manualPrice !== null ? "Preço manual atualizado com sucesso." : "Preço manual definido com sucesso.",
        item.cardId,
      );
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="card_id" value={item.cardId} />
      <input type="hidden" name="condition_id" value={conditionId} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label>Condição</Label>
          <p className="text-sm text-muted-foreground">{conditionName} — mesma condição selecionada na tabela.</p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`manual-price-value-${item.cardId}`}>Valor</Label>
            <Input
              id={`manual-price-value-${item.cardId}`}
              name="price"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              required
              defaultValue={item.manualPrice ?? undefined}
              placeholder="0,00"
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`manual-price-currency-${item.cardId}`}>Moeda</Label>
            <Select
              id={`manual-price-currency-${item.cardId}`}
              name="currency_code"
              defaultValue={item.manualCurrencyCode ?? "BRL"}
              required
            >
              <option value="BRL">BRL</option>
              <option value="USD">USD</option>
            </Select>
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor={`manual-price-observed-at-${item.cardId}`}>Data de referência</Label>
          <Input
            id={`manual-price-observed-at-${item.cardId}`}
            name="observed_at"
            type="datetime-local"
            required
            defaultValue={defaultObservedAt}
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor={`manual-price-reason-${item.cardId}`}>Motivo</Label>
          <textarea
            id={`manual-price-reason-${item.cardId}`}
            name="reason"
            required
            maxLength={500}
            placeholder="Explique a origem/justificativa deste preço manual."
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
          {pending ? "Salvando…" : item.manualPrice !== null ? "Atualizar preço" : "Definir preço"}
        </Button>
      </DialogFooter>
    </form>
  );
}
