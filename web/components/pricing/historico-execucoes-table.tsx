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
import { formatManagerialDateTime, formatNumber } from "@/lib/utils";

// v1.1 (2026-08-23, feedback de Fabrício sobre a tela) — "Refresh de Preços"
// → "Atualização de Preços", mesma troca já aplicada em Saúde das Fontes
// (`saude-fontes-list.tsx`).
const RUN_TYPE_LABEL: Record<string, string> = {
  CARD_SYNC: "Descoberta/Matching",
  PRICE_REFRESH: "Atualização de Preços",
  FX_REFRESH: "Câmbio (PTAX)",
};

// COMPLETED_WITH_ERRORS → "Concluída com alertas" (era "com erros"): o badge
// já é vermelho/amarelo pela tonalidade (`STATUS_TONE`), o texto não precisa
// repetir a palavra "erros" para não soar mais grave do que o real (nem toda
// COMPLETED_WITH_ERRORS é uma falha visível ao usuário administrativo). O
// `StateBadge` já força `uppercase` via CSS — não precisa maiúscula aqui.
const STATUS_LABEL: Record<string, string> = {
  COMPLETED: "Concluída",
  COMPLETED_WITH_ERRORS: "Concluída com alertas",
  FAILED: "Falhou",
};

const STATUS_TONE: Record<string, StateTone> = {
  COMPLETED: "success",
  COMPLETED_WITH_ERRORS: "warning",
  FAILED: "danger",
};

/** Apresentação de `pricing_source_code` — só troca de caixa visual, nunca o código interno. */
const SOURCE_CODE_LABEL: Record<string, string> = {
  JUSTTCG: "JustTCG",
};

/**
 * Duração humana (2026-08-23, feedback de Fabrício: "não exibir precisão
 * técnica excessiva como 20.016752s"). `durationSeconds` vem do banco com
 * várias casas decimais — abaixo de 60s mostra 1 casa (vírgula PT-BR);
 * a partir de 60s vira "M min SS s" com segundos inteiros e zero-padded,
 * suficiente para leitura operacional sem ruído de microssegundos.
 */
function formatDuration(seconds: number | null): string {
  if (seconds === null) return "—";
  if (seconds < 60) {
    return `${seconds.toFixed(1).replace(".", ",")} s`;
  }
  const totalSeconds = Math.round(seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const rest = totalSeconds % 60;
  return `${minutes} min ${String(rest).padStart(2, "0")} s`;
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
                {/* v1.2 (2026-08-23) — Tipo com largura reduzida (`w-36`, sem truncar:
                    "Atualização de Preços" cabe em uma linha com `whitespace-nowrap`) para
                    dar mais respiro à coluna Set, pedido de Fabrício. */}
                <DataTableHeadCell align="center" className="w-36 pl-4">
                  Tipo
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Status</DataTableHeadCell>
                <DataTableHeadCell align="center">Fonte</DataTableHeadCell>
                <DataTableHeadCell align="center">Set</DataTableHeadCell>
                <DataTableHeadCell align="center">Início</DataTableHeadCell>
                <DataTableHeadCell align="center">Duração</DataTableHeadCell>
                <DataTableHeadCell align="center">Requisições</DataTableHeadCell>
                <DataTableHeadCell align="center">Limites da API</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Ações
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {items.map((item) => (
                <DataTableRow key={item.id}>
                  <DataTableCell className="pl-4">
                    <span className="whitespace-nowrap text-sm text-foreground">
                      {RUN_TYPE_LABEL[item.runType] ?? item.runType}
                    </span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <StateBadge tone={STATUS_TONE[item.status] ?? "muted"}>
                      {STATUS_LABEL[item.status] ?? item.status}
                    </StateBadge>
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs text-muted-foreground">
                      {item.pricingSourceCode ? (SOURCE_CODE_LABEL[item.pricingSourceCode] ?? item.pricingSourceCode) : "—"}
                    </span>
                  </DataTableCell>
                  <DataTableCell>
                    {item.cardSetCode ? (
                      <>
                        <span className="text-sm font-medium text-foreground">{item.cardSetName}</span>
                        <span className="ml-1 text-xs text-muted-foreground">({item.cardSetCode})</span>
                      </>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </DataTableCell>
                  <DataTableCell>
                    <span className="text-xs text-muted-foreground">
                      {item.startedAt ? formatManagerialDateTime(item.startedAt) : "—"}
                    </span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">{formatDuration(item.durationSeconds)}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <span className="tabular-nums text-xs">{item.requestsMade !== null ? formatNumber(item.requestsMade) : "—"}</span>
                  </DataTableCell>
                  <DataTableCell align="center">
                    {/* v1.2 (2026-08-23) — "0" quando o valor é efetivamente zero, "—" só
                        quando o dado está ausente: distinguir "nenhum bloqueio" de "sem dado" */}
                    <span className="tabular-nums text-xs">
                      {item.rateLimitHits !== null ? formatNumber(item.rateLimitHits) : "—"}
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
