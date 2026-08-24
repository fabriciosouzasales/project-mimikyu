"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
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
import {
  PRICING_REPORT_SET_CARDS_PAGE_SIZE,
  type PricingReportSetCardItem,
  type PricingReportSetCardStatus,
} from "@/lib/pricing/queries";

const STATUS_LABEL: Record<PricingReportSetCardStatus, string> = {
  PRICED: "Com preço",
  FX_UNAVAILABLE: "Câmbio indisponível",
  NO_PRICE: "Sem cotação",
};

const STATUS_TONE: Record<PricingReportSetCardStatus, StateTone> = {
  PRICED: "success",
  FX_UNAVAILABLE: "warning",
  NO_PRICE: "danger",
};

// Mesmo formatador de "Preço por Carta" (`preco-por-carta-report.tsx`) — só
// data civil, sem hora (consistência de formatação de data em Pricing Admin).
const dateFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatPercent(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%";
}

/**
 * Lista de cartas do relatório "Valor por Set" (Bloco 5, migration 3944) —
 * mesma arquitetura de paginação de `PendenciasTable` (`?page=` via `Link`,
 * "Mostrando X–Y de Z"), preservando os parâmetros de navegação da tela
 * (Jogo/Expansão/Set/condição/moeda) em cada link de página.
 *
 * Ordenação (correção de direção de produto, 2026-08-23, migration 3949) —
 * esta tela NÃO é um ranking econômico: é um relatório de composição de
 * custo/valor do Set em ordem editorial da coleção. A RPC
 * `admin_get_pricing_report_set_cards` ordena por `collector_order ASC
 * NULLS LAST`, não mais por valor. `ranking`/`participationPct` continuam
 * calculados internamente pela RPC (útil como dado, não como ordenação) e
 * só existem para status PRICED — nunca sobre FX_UNAVAILABLE/NO_PRICE; a
 * coluna mostra "—" nesses casos em vez de 0 (ausência de preço nunca vira
 * zero).
 */
export function ValorPorSetCardsTable({
  items,
  totalCount,
  page,
  baseParams,
}: {
  items: PricingReportSetCardItem[];
  totalCount: number;
  page: number;
  /** Parâmetros da URL atual (game/expansion/set/condition/currency) a preservar em cada link de página. */
  baseParams: Record<string, string>;
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_REPORT_SET_CARDS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(baseParams)) {
      if (value) params.set(key, value);
    }
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/relatorios/valor-por-set?${qs}` : "/pricing/relatorios/valor-por-set";
  }

  return (
    <Card>
      <div className="border-b border-border px-4 py-3">
        <p className="text-sm font-medium text-foreground">Cartas do Set</p>
        <p className="text-xs text-muted-foreground">Composição do valor estimado do Set em ordem da coleção.</p>
      </div>
      <CardContent className="p-0">
        {items.length === 0 ? (
          <EmptyState title="Nenhuma carta ativa neste Set" description="Verifique o Set selecionado." className="py-10" />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Carta
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Variante</DataTableHeadCell>
                <DataTableHeadCell align="center">Status</DataTableHeadCell>
                <DataTableHeadCell align="center">Preço</DataTableHeadCell>
                <DataTableHeadCell align="center">Última Atualização</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Participação
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {items.map((item) => (
                <DataTableRow key={item.cardId}>
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
                    <span className="text-xs text-muted-foreground">{item.printingLabel ?? "—"}</span>
                    {item.pricingSourceCode && (
                      <span className="ml-1 text-xs uppercase text-muted-foreground">({item.pricingSourceCode})</span>
                    )}
                  </DataTableCell>
                  <DataTableCell align="center">
                    <StateBadge tone={STATUS_TONE[item.status]}>{STATUS_LABEL[item.status]}</StateBadge>
                  </DataTableCell>
                  <DataTableCell align="right">
                    <span className="tabular-nums text-sm text-foreground">
                      {item.priceDisplay !== null ? formatMoney(item.priceDisplay, item.currency) : "—"}
                    </span>
                    {item.fxStatus === "FX_RATE_UNAVAILABLE" && (
                      <p className="text-[11px] text-warning">Câmbio indisponível na data</p>
                    )}
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="text-xs tabular-nums text-muted-foreground">
                      {item.observedAt ? dateFormatter.format(new Date(item.observedAt)) : "—"}
                    </span>
                  </DataTableCell>
                  <DataTableCell align="right" className="pr-4 last:pr-4">
                    {/* v2 (2026-08-23, refinamento aprovado por Fabrício) — barra
                        visual discreta de participação, usando o mesmo
                        `participationPct` já retornado pela RPC 3944 (sem novo
                        fetch). Só aparece quando há percentual real (PRICED);
                        o número continua sendo a fonte de verdade, a barra é
                        só reforço de leitura rápida/comparação entre linhas. */}
                    <div className="flex items-center justify-end gap-2">
                      {item.participationPct !== null && (
                        <span
                          className="h-1.5 w-12 overflow-hidden rounded-full bg-surface-muted"
                          role="presentation"
                        >
                          <span
                            className="block h-full rounded-full bg-primary"
                            style={{ width: `${Math.min(100, Math.max(0, item.participationPct))}%` }}
                          />
                        </span>
                      )}
                      <span className="tabular-nums text-xs text-muted-foreground">
                        {item.participationPct !== null ? formatPercent(item.participationPct) : "—"}
                      </span>
                    </div>
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_REPORT_SET_CARDS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_REPORT_SET_CARDS_PAGE_SIZE, totalCount)}
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
