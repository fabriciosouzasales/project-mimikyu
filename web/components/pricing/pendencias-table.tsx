"use client";

import { ArrowRight, ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
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
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { PendenciasFiltros } from "@/components/pricing/pendencias-filtros";
import { PRICING_PENDING_MAPPINGS_PAGE_SIZE, type PricingCardSetOption, type PricingPendingMappingItem } from "@/lib/pricing/queries";
import { formatNumber } from "@/lib/utils";

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  NOT_FOUND: "Não encontrado",
};

const STATUS_TONE: Record<string, StateTone> = {
  PENDING: "warning",
  NOT_FOUND: "danger",
};

function formatDate(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
}

/**
 * Tabela de Pendências — mesma arquitetura de `LogAtualizacoesTable`: Card
 * envolve filtros (topo) + DataTable + paginação (rodapé, `?page=` via
 * `Link`, mesmo cálculo "Mostrando X–Y de Z"). Ação de linha é sempre
 * "Resolver" -> navega para `/pricing/resolucao-mapeamentos?mapping=<id>`,
 * onde a decisão de fato acontece (esta tela é só leitura/triagem, nunca
 * escreve).
 */
export function PendenciasTable({
  items,
  totalCount,
  page,
  search,
  status,
  cardSetId,
  cardSets,
}: {
  items: PricingPendingMappingItem[];
  totalCount: number;
  page: number;
  search: string;
  status: string;
  cardSetId: string;
  cardSets: PricingCardSetOption[];
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_PENDING_MAPPINGS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (status) params.set("status", status);
    if (cardSetId) params.set("set", cardSetId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/pendencias?${qs}` : "/pricing/pendencias";
  }

  const hasFilter = Boolean(search || status || cardSetId);

  return (
    <Card>
      <div className="border-b border-border px-4 py-3">
        <PendenciasFiltros initialSearch={search} status={status} cardSetId={cardSetId} cardSets={cardSets} />
      </div>
      <CardContent className="p-0">
        {items.length === 0 ? (
          <EmptyState
            title={hasFilter ? "Nenhuma pendência para este filtro" : "Nenhuma pendência no momento"}
            description={
              hasFilter
                ? "Troque os filtros para ver outras pendências."
                : "Todos os mapeamentos conhecidos já foram confirmados ou rejeitados."
            }
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
                <DataTableRow key={item.id}>
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
                    <StateBadge tone={STATUS_TONE[item.matchStatus] ?? "muted"}>
                      {STATUS_LABEL[item.matchStatus] ?? item.matchStatus}
                    </StateBadge>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums">{formatNumber(item.identityCount)}</span>
                  </DataTableCell>
                  <DataTableCell>{formatDate(item.lastCheckedAt)}</DataTableCell>
                  <DataTableCell align="center" className="pr-4 last:pr-4">
                    <Button asChild variant="outline" size="sm">
                      <Link href={`/pricing/resolucao-mapeamentos?mapping=${item.id}`}>
                        Resolver
                        <ArrowRight className="ml-1 h-3.5 w-3.5" aria-hidden="true" />
                      </Link>
                    </Button>
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_PENDING_MAPPINGS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_PENDING_MAPPINGS_PAGE_SIZE, totalCount)}
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
