"use client";

import { Check, SkipForward, X } from "lucide-react";
import { useMemo, useState, useTransition } from "react";
import {
  confirmarImportacao,
  decidirLinhasImportacao,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";
import { Badge } from "@/components/ui/badge";
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
import type { CatalogImportRowView } from "@/lib/catalogo/queries";

const VALIDATION_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  VALID: "Válida",
  NEEDS_REVIEW: "Revisar",
  INVALID: "Inválida",
};

const MATCH_LABEL: Record<string, string> = {
  NEW: "Nova",
  MATCHED: "Já existe (idêntica)",
  CONFLICT: "Conflito",
};

const DECISION_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  APPROVED: "Aprovada",
  REJECTED: "Rejeitada",
  SKIPPED: "Pulada",
};

const PERSISTENCE_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  INSERTED: "Inserida",
  UPDATED: "Atualizada",
  UNCHANGED: "Inalterada",
  FAILED: "Falhou",
};

const CATEGORY_LABEL: Record<string, string> = {
  POKEMON: "Pokémon",
  TRAINER: "Treinador",
  ENERGY: "Energia",
};

function validationBadgeClassName(status: string): string | undefined {
  if (status === "INVALID") return "border-destructive/40 bg-destructive/5 text-destructive";
  if (status === "NEEDS_REVIEW") return undefined; // usa variant="warning"
  return undefined;
}

/**
 * Tela de Revisão (Ciclo 2, Sprint 2b, ADR-024) — aprovar/rejeitar/pular
 * linhas de staging de um job (admin_decide_catalog_import_row, Query 2081)
 * e confirmar a persistência real em public.card
 * (admin_confirm_catalog_import, Query 2082, em lotes — ver
 * confirmarImportacao em actions.ts). Renderizada por quem chama (ver
 * `useAnalyzeJob`/`CandidateAnalyzeCard` em importar-tcgdex-view.tsx, e
 * `ImportarCartasView`) só enquanto o job está em STAGED ou CONFIRMING —
 * some sozinha quando o status muda para COMPLETED/COMPLETED_WITH_ERRORS
 * após onRefresh() (ver abaixo — busca job/linhas de novo e atualiza o
 * estado React de quem chama).
 *
 * Sem paginação: sets do piloto do Ciclo 2 são pequenos (SVE = 24 cartas);
 * revisitar se uma Coleção muito grande tornar a rolagem inconveniente.
 *
 * Raridade mostrada é raw_data.rarity (texto bruto da TCGdex, ver
 * getCatalogImportRows) — não um nome canônico resolvido contra
 * public.rarity, por desenho (ver comentário na query).
 *
 * `onRefresh` (2026-08-01, terceira rodada — era `router.refresh()`): o
 * fluxo de importação parou de navegar/usar `?jobId=` na URL (ver
 * comentário de iniciarImportacaoTcgdex em tcgdex/actions.ts), então não há
 * mais Server Component nem URL pra um `router.refresh()` reagir — quem
 * chama (importar-tcgdex-view.tsx) passa uma função que busca job+linhas de
 * novo via getImportacaoJobData e atualiza o próprio estado React.
 *
 * Botões de Ações ganharam Tooltip (era só `aria-label`, sem nada visível
 * ao passar o mouse — pedido de Fabrício) — `title` nativo do navegador foi
 * descartado de propósito neste projeto (ver comentário em app/layout.tsx:
 * "demorava ~1s e parecia quebrado"), usa o mesmo Tooltip/TooltipProvider
 * já usado em theme-toggle.tsx.
 */
export function RevisaoImportacaoTable({
  jobId,
  rows,
  onRefresh,
}: {
  jobId: string;
  rows: CatalogImportRowView[];
  onRefresh: () => void;
}) {
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
      const result = await decidirLinhasImportacao(jobId, ids, status);
      if (result.error) {
        setError(result.error);
        return;
      }
      setSelected(new Set());
      onRefresh();
    });
  }

  function confirmar() {
    setError(null);
    setConfirmSummary(null);
    setConfirming(true);
    startTransition(async () => {
      const result = await confirmarImportacao(jobId);
      setConfirming(false);
      if (result.error) {
        setError(result.error);
        return;
      }
      setConfirmSummary(
        `Confirmado: ${result.insertedCount} inserida(s), ${result.updatedCount} atualizada(s), ${result.unchangedCount} inalterada(s), ${result.failedCount} com falha.`,
      );
      onRefresh();
    });
  }

  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-2 space-y-0">
        <p className="text-sm font-semibold text-foreground">Revisão ({rows.length} linhas)</p>
        <div className="flex flex-wrap items-center gap-2">
          {selected.size > 0 && (
            <>
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={isPending}
                onClick={() => decidir(Array.from(selected), "APPROVED")}
              >
                Aprovar selecionadas ({selected.size})
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
            {confirming ? "Confirmando…" : `Confirmar (${approvableCount})`}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
        {confirmSummary && <InlineFeedback tone="success">{confirmSummary}</InlineFeedback>}

        {rows.length === 0 ? (
          <EmptyState title="Nenhuma linha para revisar" description="Este job não gerou nenhuma proposta de carta." />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell className="w-8 pl-4">
                  <input type="checkbox" checked={allSelected} onChange={toggleAll} aria-label="Selecionar todas" />
                </DataTableHeadCell>
                <DataTableHeadCell>Nº</DataTableHeadCell>
                <DataTableHeadCell>Nome</DataTableHeadCell>
                <DataTableHeadCell>Categoria</DataTableHeadCell>
                <DataTableHeadCell>Raridade</DataTableHeadCell>
                <DataTableHeadCell align="center">Validação</DataTableHeadCell>
                <DataTableHeadCell align="center">Correspondência</DataTableHeadCell>
                <DataTableHeadCell align="center">Decisão</DataTableHeadCell>
                <DataTableHeadCell align="center">Persistência</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Ações
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {rows.map((row) => (
                <DataTableRow key={row.id}>
                  <DataTableCell className="pl-4">
                    <input
                      type="checkbox"
                      checked={selected.has(row.id)}
                      onChange={() => toggleRow(row.id)}
                      aria-label={`Selecionar ${row.name}`}
                    />
                  </DataTableCell>
                  <DataTableCell className="tabular-nums text-foreground">
                    {row.collectorNumber}
                    {row.collectorTotal ? `/${row.collectorTotal}` : ""}
                  </DataTableCell>
                  <DataTableCell className="text-foreground">
                    {row.name}
                    {row.reviewNotes.length > 0 && (
                      <p className="text-xs text-muted-foreground">{row.reviewNotes.join(" · ")}</p>
                    )}
                  </DataTableCell>
                  <DataTableCell>
                    {row.category ? (CATEGORY_LABEL[row.category] ?? row.category) : "—"}
                    {row.categorySource && row.categorySource !== "API" && (
                      <Badge variant="warning" className="ml-1.5">
                        heurística
                      </Badge>
                    )}
                  </DataTableCell>
                  <DataTableCell>{row.rawRarity ?? "—"}</DataTableCell>
                  <DataTableCell align="center">
                    <Badge
                      variant={row.validationStatus === "VALID" ? "primary" : "warning"}
                      className={validationBadgeClassName(row.validationStatus)}
                    >
                      {VALIDATION_LABEL[row.validationStatus] ?? row.validationStatus}
                    </Badge>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <Badge variant={row.matchStatus === "CONFLICT" ? "warning" : "outline"}>
                      {MATCH_LABEL[row.matchStatus] ?? row.matchStatus}
                    </Badge>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <Badge
                      variant={row.decisionStatus === "APPROVED" ? "primary" : "outline"}
                      className={row.decisionStatus === "REJECTED" ? "border-destructive/40 bg-destructive/5 text-destructive" : undefined}
                    >
                      {DECISION_LABEL[row.decisionStatus] ?? row.decisionStatus}
                    </Badge>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <Badge
                      variant="outline"
                      className={row.persistenceStatus === "FAILED" ? "border-destructive/40 bg-destructive/5 text-destructive" : undefined}
                      title={row.errorDetail ?? undefined}
                    >
                      {PERSISTENCE_LABEL[row.persistenceStatus] ?? row.persistenceStatus}
                    </Badge>
                  </DataTableCell>
                  <DataTableCell align="center" className="pr-4 last:pr-4">
                    <div className="flex justify-center gap-1">
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            disabled={isPending}
                            aria-label={`Aprovar ${row.name}`}
                            onClick={() => decidir([row.id], "APPROVED")}
                          >
                            <Check className="h-3.5 w-3.5" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>Aprovar esta carta</TooltipContent>
                      </Tooltip>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            disabled={isPending}
                            aria-label={`Rejeitar ${row.name}`}
                            onClick={() => decidir([row.id], "REJECTED")}
                          >
                            <X className="h-3.5 w-3.5" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>Rejeitar esta carta</TooltipContent>
                      </Tooltip>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            disabled={isPending}
                            aria-label={`Pular ${row.name}`}
                            onClick={() => decidir([row.id], "SKIPPED")}
                          >
                            <SkipForward className="h-3.5 w-3.5" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>Pular esta carta (não decide agora)</TooltipContent>
                      </Tooltip>
                    </div>
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}
      </CardContent>
    </Card>
  );
}
