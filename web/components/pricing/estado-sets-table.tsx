"use client";

import { ChevronLeft, ChevronRight, Lock } from "lucide-react";
import Link from "next/link";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { EstadoSetsFiltros } from "@/components/pricing/estado-sets-filtros";
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
  PRICING_SET_REFRESH_STATES_PAGE_SIZE,
  type PricingRefreshPolicyItem,
  type PricingSetRefreshStateItem,
} from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

// P16.4.1 (revisão final, migration 3952) — 2 buckets novos (ONBOARDING_PENDING/PROCESSING),
// mesmos rótulos/tons já usados em `estado-sets-filtros.tsx` e `deriveRowStatus()` de
// `mapeamentos-sets-table.tsx` para consistência entre telas. Nenhum dos dois é "danger" —
// nunca é falha operacional, ver cabeçalho da migration 3952.
const STATUS_LABEL: Record<string, string> = {
  ONBOARDING_PENDING: "Aguardando primeira sincronização",
  PROCESSING: "Sincronizando",
  HEALTHY: "Saudável",
  PROBLEM: "Com problema",
  PAUSED: "Pausado",
};

const STATUS_TONE: Record<string, StateTone> = {
  ONBOARDING_PENDING: "warning",
  PROCESSING: "warning",
  HEALTHY: "success",
  PROBLEM: "danger",
  PAUSED: "muted",
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
 * Estado dos Sets — visão operacional por `pricing_set_refresh_state`
 * (`admin_list_pricing_set_refresh_states`), paginada/filtrada server-side
 * mesmo com só 45 Sets hoje. Só leitura: nenhuma ação de linha aqui —
 * pausar/retomar/recalcular `next_due_at` ficam fora desta V1 (constraint
 * explícita de Fabrício, ver `docs/development/HANDOFF-2026-08-21.md`).
 */
export function EstadoSetsTable({
  items,
  totalCount,
  page,
  search,
  status,
  pricingSourceId,
  sources,
}: {
  items: PricingSetRefreshStateItem[];
  totalCount: number;
  page: number;
  search: string;
  status: string;
  pricingSourceId: string;
  sources: PricingRefreshPolicyItem[];
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_SET_REFRESH_STATES_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (status) params.set("status", status);
    if (pricingSourceId) params.set("source", pricingSourceId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/sincronizacoes?${qs}` : "/pricing/sincronizacoes";
  }

  const hasFilter = Boolean(search || status || pricingSourceId);

  return (
    <Card>
      <div className="border-b border-border px-4 py-3">
        <EstadoSetsFiltros initialSearch={search} status={status} pricingSourceId={pricingSourceId} sources={sources} />
      </div>
      <CardContent className="p-0">
        {items.length === 0 ? (
          <EmptyState
            title={hasFilter ? "Nenhum Set para este filtro" : "Nenhum Set com estado de refresh ainda"}
            description={hasFilter ? "Troque os filtros para ver outros Sets." : undefined}
            className="py-10"
          />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell className="pl-4">Set</DataTableHeadCell>
                <DataTableHeadCell>Fonte</DataTableHeadCell>
                <DataTableHeadCell align="center">Status</DataTableHeadCell>
                <DataTableHeadCell>Última execução</DataTableHeadCell>
                <DataTableHeadCell>Próxima prevista</DataTableHeadCell>
                <DataTableHeadCell align="center">Tentativas</DataTableHeadCell>
                <DataTableHeadCell align="center">Cobertura</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Lease
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {items.map((item) => (
                <DataTableRow key={item.id}>
                  <DataTableCell className="pl-4">
                    <span className="text-sm text-foreground">{item.cardSetName}</span>
                    <span className="ml-1 text-xs text-muted-foreground">({item.cardSetCode})</span>
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs uppercase text-muted-foreground">{item.pricingSourceCode}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <div className="flex flex-col items-center gap-0.5">
                      {/* P16.4.1 (revisão final) — badge lê refreshBucket (taxonomia central), não mais o derivedStatus binário legado. */}
                      <StateBadge tone={STATUS_TONE[item.refreshBucket] ?? "muted"}>
                        {STATUS_LABEL[item.refreshBucket] ?? item.refreshBucket}
                      </StateBadge>
                      {item.isPaused && item.pauseReason && (
                        <span className="max-w-[10rem] truncate text-[10px] text-muted-foreground" title={item.pauseReason}>
                          {item.pauseReason}
                        </span>
                      )}
                    </div>
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs text-muted-foreground">
                      {item.lastOutcome ? `${item.lastOutcome} — ` : ""}
                      {formatDateTime(item.lastStartedAt)}
                    </span>
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs text-muted-foreground">{formatDateTime(item.nextDueAt)}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">{formatNumber(item.attemptCount)}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">
                      {formatNumber(item.mappingsConfirmed)}/{formatNumber(item.mappingsTotal)}
                    </span>
                  </DataTableCell>
                  <DataTableCell align="center" className="pr-4 last:pr-4">
                    {item.leaseUntil && new Date(item.leaseUntil).getTime() > Date.now() ? (
                      <span className="inline-flex items-center gap-1 text-xs text-warning" title={`Até ${formatDateTime(item.leaseUntil)}`}>
                        <Lock className="h-3 w-3" aria-hidden="true" />
                        Em execução
                      </span>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_SET_REFRESH_STATES_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_SET_REFRESH_STATES_PAGE_SIZE, totalCount)}
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
