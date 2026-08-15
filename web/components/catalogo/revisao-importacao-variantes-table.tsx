"use client";

import { Check, SkipForward, X } from "lucide-react";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { confirmarImportacaoVariantes, decidirLinhasVariantes } from "@/app/catalogo/importar-variantes/actions";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn, formatNumber } from "@/lib/utils";
import type { CatalogVariantImportRowView } from "@/lib/catalogo/queries";

const VALIDATION_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  VALID: "Válida",
  NEEDS_REVIEW: "Sem mapeamento",
  INVALID: "Inválida",
};

const VALIDATION_TONE: Record<string, StateTone> = {
  PENDING: "muted",
  VALID: "success",
  NEEDS_REVIEW: "warning",
  INVALID: "danger",
};

// "Já existe" em vez de "Atualização" (vocabulário de MATCH_LABEL em
// revisao-importacao-table.tsx): diferença estrutural real de Card Variant
// frente a Card — não há conteúdo para divergir/atualizar, MATCHED é sempre
// um no-op (UNCHANGED na confirmação, Query 2145).
const MATCH_LABEL: Record<string, string> = {
  NEW: "Nova",
  MATCHED: "Já existe",
  CONFLICT: "Conflito",
};

const MATCH_TONE: Record<string, StateTone> = {
  NEW: "success",
  MATCHED: "muted",
  CONFLICT: "danger",
};

const DECISION_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  APPROVED: "Aprovada",
  REJECTED: "Rejeitada",
  SKIPPED: "Pulada",
};

const DECISION_TONE: Record<string, StateTone> = {
  PENDING: "muted",
  APPROVED: "success",
  REJECTED: "danger",
  SKIPPED: "warning",
};

function SummaryStat({ label, value, className }: { label: string; value: number; className?: string }) {
  return (
    <div>
      <p className={cn("text-lg font-semibold leading-none tabular-nums", className ?? "text-foreground")}>
        {formatNumber(value)}
      </p>
      <p className="mt-1 text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
    </div>
  );
}

/** Chips type/foil/subtype/stamp exatamente como vieram do dataset-fonte (raw_data, Query 2138) — mesmo espírito da coluna Raridade em revisao-importacao-table.tsx (dado bruto, sem interpretação). */
function VariantRawChips({ row }: { row: CatalogVariantImportRowView }) {
  const chips = [row.rawType, row.rawFoil, row.rawSubtype, ...(row.rawStamp ?? [])].filter(
    (value): value is string => Boolean(value),
  );
  if (chips.length === 0) return <span className="text-xs text-muted-foreground">—</span>;
  return (
    <div className="flex flex-wrap gap-1">
      {chips.map((chip, index) => (
        <StateBadge key={`${chip}-${index}`} tone="muted">
          {chip}
        </StateBadge>
      ))}
    </div>
  );
}

/**
 * Tela de Revisão de Importar Variantes (Incremento 4, ADR-028) — mesmo
 * papel/interação de RevisaoImportacaoTable (revisao-importacao-table.tsx),
 * adaptada aos campos reais de catalog_variant_import_row: uma Carta pode
 * ter várias linhas (uma por variante proposta), sem coluna de Persistência
 * pelo mesmo motivo de lá (só sai de PENDING depois de confirmar(), quando a
 * tabela some da tela).
 *
 * Aprovar em massa filtra automaticamente linhas NEEDS_REVIEW da seleção
 * antes de chamar a RPC: admin_decide_catalog_variant_import_row (Query
 * 2144) recusa o lote INTEIRO se qualquer uma das linhas passadas para
 * APPROVED estiver sem mapeamento — sem o filtro aqui, uma seleção mista
 * (VALID + NEEDS_REVIEW) bloquearia até as linhas válidas. Botão individual
 * de Aprovar já nasce desabilitado nessas linhas, com tooltip explicando o
 * motivo — a garantia real continua sendo a RPC, isto é só UX.
 */
export function RevisaoImportacaoVariantesTable({
  jobId,
  rows,
  onRefresh,
}: {
  jobId: string;
  rows: CatalogVariantImportRowView[];
  onRefresh: () => void;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isPending, startTransition] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmSummary, setConfirmSummary] = useState<string | null>(null);

  const approvableCount = useMemo(
    () =>
      rows.filter(
        (row) =>
          row.persistenceStatus === "PENDING" && (row.decisionStatus === "APPROVED" || row.decisionStatus === "SKIPPED"),
      ).length,
    [rows],
  );

  const summary = useMemo(() => {
    let aprovadas = 0;
    let rejeitadas = 0;
    let pendentes = 0;
    let semMapeamento = 0;
    for (const row of rows) {
      if (row.decisionStatus === "APPROVED") aprovadas++;
      else if (row.decisionStatus === "REJECTED") rejeitadas++;
      else pendentes++; // PENDING ou SKIPPED — nenhuma decisão final ainda
      if (row.validationStatus === "NEEDS_REVIEW") semMapeamento++;
    }
    return { total: rows.length, aprovadas, rejeitadas, pendentes, semMapeamento };
  }, [rows]);

  const allSelected = rows.length > 0 && selected.size === rows.length;

  function toggleRow(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  function toggleAll() {
    setSelected((prev) => (prev.size === rows.length ? new Set() : new Set(rows.map((row) => row.id))));
  }

  function decidir(ids: string[], status: "APPROVED" | "REJECTED" | "SKIPPED" | "PENDING") {
    if (ids.length === 0) return;
    setError(null);
    setConfirmSummary(null);
    startTransition(async () => {
      const result = await decidirLinhasVariantes(jobId, ids, status);
      if (result.error) {
        setError(result.error);
        return;
      }
      setSelected(new Set());
      onRefresh();
    });
  }

  function aprovarSelecionadas() {
    const ids = Array.from(selected);
    const approvableIds = ids.filter((id) => rows.find((row) => row.id === id)?.validationStatus === "VALID");
    const blockedCount = ids.length - approvableIds.length;
    if (blockedCount > 0) {
      setError(
        `${formatNumber(blockedCount)} variante(s) sem mapeamento não ${blockedCount === 1 ? "foi" : "foram"} aprovada(s) — resolva o mapeamento em Card Variant Type antes.`,
      );
    }
    decidir(approvableIds, "APPROVED");
  }

  function confirmar() {
    setError(null);
    setConfirmSummary(null);
    setConfirming(true);
    startTransition(async () => {
      const result = await confirmarImportacaoVariantes(jobId);
      setConfirming(false);
      if (result.error) {
        setError(result.error);
        return;
      }
      setConfirmSummary(
        `Confirmado: ${result.insertedCount} inserida(s), ${result.unchangedCount} inalterada(s), ${result.failedCount} com falha.`,
      );
      onRefresh();
      router.refresh();
    });
  }

  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-2 space-y-0">
        <p className="text-sm font-semibold text-foreground">Revisão de Variantes</p>
        <div className="flex flex-wrap items-center gap-2">
          {selected.size > 0 && (
            <>
              <Button type="button" variant="outline" size="sm" disabled={isPending} onClick={aprovarSelecionadas}>
                Aprovar selecionadas ({formatNumber(selected.size)})
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={isPending}
                onClick={() => decidir(Array.from(selected), "REJECTED")}
              >
                Rejeitar
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={isPending}
                onClick={() => decidir(Array.from(selected), "SKIPPED")}
              >
                Pular
              </Button>
            </>
          )}
          <Button type="button" size="sm" disabled={isPending || confirming || approvableCount === 0} onClick={confirmar}>
            <Check className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
            {confirming
              ? "Confirmando…"
              : `Confirmar ${formatNumber(approvableCount)} variante${approvableCount === 1 ? "" : "s"}`}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
        {confirmSummary && <InlineFeedback tone="success">{confirmSummary}</InlineFeedback>}

        {rows.length === 0 ? (
          <EmptyState title="Nenhuma linha para revisar" description="Este job não gerou nenhuma proposta de variante." />
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-x-6 gap-y-3 rounded-md border border-border bg-surface-muted/40 px-4 py-3">
              <SummaryStat label="Analisadas" value={summary.total} />
              <SummaryStat label="Aprovadas" value={summary.aprovadas} className="text-success" />
              <SummaryStat label="Rejeitadas" value={summary.rejeitadas} className="text-destructive" />
              <SummaryStat label="Pendentes" value={summary.pendentes} className="text-warning" />
              <SummaryStat label="Sem Mapeamento" value={summary.semMapeamento} className="text-destructive" />
            </div>

            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="w-8 pl-4">
                    <input type="checkbox" checked={allSelected} onChange={toggleAll} aria-label="Selecionar todas" />
                  </DataTableHeadCell>
                  <DataTableHeadCell>Carta</DataTableHeadCell>
                  <DataTableHeadCell>Variante Proposta</DataTableHeadCell>
                  <DataTableHeadCell align="center">Validação</DataTableHeadCell>
                  <DataTableHeadCell align="center">Correspondência</DataTableHeadCell>
                  <DataTableHeadCell align="center">Decisão</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {rows.map((row) => {
                  const canApprove = row.validationStatus === "VALID";
                  return (
                    <DataTableRow key={row.id}>
                      <DataTableCell className="pl-4">
                        <input
                          type="checkbox"
                          checked={selected.has(row.id)}
                          onChange={() => toggleRow(row.id)}
                          aria-label={`Selecionar ${row.cardName}`}
                        />
                      </DataTableCell>
                      <DataTableCell>
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-foreground">{row.cardName}</p>
                          <p className="text-xs tabular-nums text-muted-foreground">
                            {row.collectorNumber}
                            {row.collectorTotal ? `/${row.collectorTotal}` : ""}
                          </p>
                        </div>
                      </DataTableCell>
                      <DataTableCell>
                        <div className="space-y-1.5">
                          <p className="text-sm text-foreground">{row.variantTypeName ?? "—"}</p>
                          <VariantRawChips row={row} />
                        </div>
                      </DataTableCell>
                      <DataTableCell align="center">
                        <StateBadge tone={VALIDATION_TONE[row.validationStatus] ?? "muted"}>
                          {VALIDATION_LABEL[row.validationStatus] ?? row.validationStatus}
                        </StateBadge>
                      </DataTableCell>
                      <DataTableCell align="center">
                        <StateBadge tone={MATCH_TONE[row.matchStatus] ?? "muted"}>
                          {MATCH_LABEL[row.matchStatus] ?? row.matchStatus}
                        </StateBadge>
                      </DataTableCell>
                      <DataTableCell align="center">
                        <StateBadge tone={DECISION_TONE[row.decisionStatus] ?? "muted"}>
                          {DECISION_LABEL[row.decisionStatus] ?? row.decisionStatus}
                        </StateBadge>
                      </DataTableCell>
                      <DataTableCell align="center" className="pr-4 last:pr-4">
                        <div className="flex justify-center gap-1">
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <span>
                                <Button
                                  type="button"
                                  variant="outline"
                                  size="icon-sm"
                                  disabled={isPending || !canApprove}
                                  aria-label={`Aprovar variante de ${row.cardName}`}
                                  onClick={() => decidir([row.id], "APPROVED")}
                                >
                                  <Check className="h-3.5 w-3.5" />
                                </Button>
                              </span>
                            </TooltipTrigger>
                            <TooltipContent>
                              {canApprove ? "Aprovar esta variante" : "Sem mapeamento — resolva em Card Variant Type antes de aprovar"}
                            </TooltipContent>
                          </Tooltip>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                type="button"
                                variant="outline"
                                size="icon-sm"
                                disabled={isPending}
                                aria-label={`Rejeitar variante de ${row.cardName}`}
                                onClick={() => decidir([row.id], "REJECTED")}
                              >
                                <X className="h-3.5 w-3.5" />
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>Rejeitar esta variante</TooltipContent>
                          </Tooltip>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Button
                                type="button"
                                variant="outline"
                                size="icon-sm"
                                disabled={isPending}
                                aria-label={`Pular variante de ${row.cardName}`}
                                onClick={() => decidir([row.id], "SKIPPED")}
                              >
                                <SkipForward className="h-3.5 w-3.5" />
                              </Button>
                            </TooltipTrigger>
                            <TooltipContent>Pular esta variante (não decide agora)</TooltipContent>
                          </Tooltip>
                        </div>
                      </DataTableCell>
                    </DataTableRow>
                  );
                })}
              </tbody>
            </DataTable>
          </>
        )}
      </CardContent>
    </Card>
  );
}
