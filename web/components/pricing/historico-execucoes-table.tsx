"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { HistoricoExecucoesFiltros } from "@/components/pricing/historico-execucoes-filtros";
import { SyncRunDetailDialog, SyncRunDetailTriggerButton } from "@/components/pricing/sync-run-detail-dialog";
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
import { EmptyState } from "@/components/ui/empty-state";
import {
  PRICING_SYNC_RUNS_PAGE_SIZE,
  type PricingCardSetOption,
  type PricingSyncRunItem,
} from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const RUN_TYPE_LABEL: Record<string, string> = {
  CARD_SYNC: "Descoberta/Matching",
  PRICE_REFRESH: "Refresh de Preços",
  FX_REFRESH: "Câmbio (PTAX)",
};

const STATUS_LABEL: Record<string, string> = {
  COMPLETED: "Concluída",
  COMPLETED_WITH_ERRORS: "Concluída com erros",
  FAILED: "Falhou",
};

const STATUS_TONE: Record<string, StateTone> = {
  COMPLETED: "success",
  COMPLETED_WITH_ERRORS: "warning",
  FAILED: "danger",
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

function formatDuration(seconds: number | null): string {
  if (seconds === null) return "—";
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return rest > 0 ? `${minutes}min ${rest}s` : `${minutes}min`;
}

/**
 * Tabela de Histórico de Execuções — mesma arquitetura de `PendenciasTable`:
 * Card envolve filtros (topo) + DataTable + paginação (rodapé). Ação de
 * linha abre `SyncRunDetailDialog` (fetch sob demanda), não navega — o
 * detalhe de uma execução não precisa de URL própria nesta V1.
 */
export function HistoricoExecucoesTable({
  items,
  totalCount,
  page,
  status,
  cardSetId,
  dateFrom,
  dateTo,
  cardSets,
}: {
  items: PricingSyncRunItem[];
  totalCount: number;
  page: number;
  status: string;
  cardSetId: string;
  dateFrom: string;
  dateTo: string;
  cardSets: PricingCardSetOption[];
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_SYNC_RUNS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (status) params.set("status", status);
    if (cardSetId) params.set("set", cardSetId);
    if (dateFrom) params.set("de", dateFrom);
    if (dateTo) params.set("ate", dateTo);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/historico-execucoes?${qs}` : "/pricing/historico-execucoes";
  }

  const hasFilter = Boolean(status || cardSetId || dateFrom || dateTo);

  return (
    <Card>
      <div className="border-b border-border px-4 py-3">
        <HistoricoExecucoesFiltros status={status} cardSetId={cardSetId} dateFrom={dateFrom} dateTo={dateTo} cardSets={cardSets} />
      </div>
      <CardContent className="p-0">
        {items.length === 0 ? (
          <EmptyState
            title={hasFilter ? "Nenhuma execução para este filtro" : "Nenhuma execução registrada ainda"}
            description={hasFilter ? "Troque os filtros para ver outras execuções." : undefined}
            className="py-10"
          />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell className="pl-4">Tipo</DataTableHeadCell>
                <DataTableHeadCell align="center">Status</DataTableHeadCell>
                <DataTableHeadCell>Fonte</DataTableHeadCell>
                <DataTableHeadCell>Set</DataTableHeadCell>
                <DataTableHeadCell>Início</DataTableHeadCell>
                <DataTableHeadCell align="center">Duração</DataTableHeadCell>
                <DataTableHeadCell align="center">Requisições</DataTableHeadCell>
                <DataTableHeadCell align="center">Rate limits</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Ações
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {items.map((item) => (
                <DataTableRow key={item.id}>
                  <DataTableCell className="pl-4">
                    <span className="text-sm text-foreground">{RUN_TYPE_LABEL[item.runType] ?? item.runType}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <StateBadge tone={STATUS_TONE[item.status] ?? "muted"}>
                      {STATUS_LABEL[item.status] ?? item.status}
                    </StateBadge>
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs uppercase text-muted-foreground">{item.pricingSourceCode ?? "—"}</span>
                  </DataTableCell>
                  <DataTableCell>
                    {item.cardSetCode ? (
                      <>
                        <span className="text-xs text-foreground">{item.cardSetName}</span>
                        <span className="ml-1 text-xs text-muted-foreground">({item.cardSetCode})</span>
                      </>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs text-muted-foreground">{formatDateTime(item.startedAt)}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">{formatDuration(item.durationSeconds)}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">{item.requestsMade !== null ? formatNumber(item.requestsMade) : "—"}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">
                      {item.rateLimitHits !== null && item.rateLimitHits > 0 ? formatNumber(item.rateLimitHits) : "—"}
                    </span>
                  </DataTableCell>
                  <DataTableCell align="center" className="pr-4 last:pr-4">
                    <SyncRunDetailDialog runId={item.id} trigger={<SyncRunDetailTriggerButton />} />
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_SYNC_RUNS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_SYNC_RUNS_PAGE_SIZE, totalCount)}
              </span>{" "}
              de <span className="font-medium text-foreground">{totalCount}</span>
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
      </CardContent>
    </Card>
  );
}
