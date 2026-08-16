"use client";

import { Check, Link2, SkipForward, X } from "lucide-react";
import { useMemo, useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  confirmarImportacaoVariantes,
  criarTipoVariacaoEResolverMapeamento,
  decidirLinhasVariantes,
  resolverMapeamentoVariante,
} from "@/app/catalogo/importar-variantes/actions";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn, formatNumber } from "@/lib/utils";
import type { CardVariantTypeOption, CatalogVariantImportRowView } from "@/lib/catalogo/queries";


// Mesma classe de tipos-variacao-table.tsx (textareaClassName) — não há
// componente Textarea compartilhado no repositório; reproduzida aqui em
// vez de importar entre módulos de tela distintos.
const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

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
  cardVariantTypes,
  onRefresh,
}: {
  jobId: string;
  rows: CatalogVariantImportRowView[];
  cardVariantTypes: CardVariantTypeOption[];
  onRefresh: () => void;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isPending, startTransition] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmSummary, setConfirmSummary] = useState<string | null>(null);
  const [resolvingRow, setResolvingRow] = useState<CatalogVariantImportRowView | null>(null);
  // Filtro "Mapeamento" (client-side, sem nova query — `rows` já vem
  // carregado por completo do servidor): "Todos" | "Mapeados" (variantTypeName
  // resolvido, ou seja, normalized_data.variant_type_id já preenchido) |
  // "Sem mapeamento" (validationStatus === NEEDS_REVIEW). Só afeta o que é
  // EXIBIDO na tabela — summary/approvableCount/decidir/confirmar continuam
  // calculados sobre `rows` inteiro, nunca sobre o recorte filtrado (regras
  // de decisão/confirmação não mudam com o filtro).
  const [mappingFilter, setMappingFilter] = useState<"all" | "mapped" | "unmapped">("all");

  const filteredRows = useMemo(() => {
    if (mappingFilter === "mapped") return rows.filter((row) => row.variantTypeName !== null);
    if (mappingFilter === "unmapped") return rows.filter((row) => row.validationStatus === "NEEDS_REVIEW");
    return rows;
  }, [rows, mappingFilter]);

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

  // "Selecionar todas" opera sobre o recorte visível (filteredRows) — mesmo
  // raciocínio de qualquer filtro de tabela: marcar "todas" com o filtro
  // "Sem mapeamento" ativo não deve arrastar para a seleção linhas já
  // mapeadas que nem aparecem na tela.
  const allSelected = filteredRows.length > 0 && filteredRows.every((row) => selected.has(row.id));

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
    setSelected((prev) => {
      const visibleIds = filteredRows.map((row) => row.id);
      const allVisibleSelected = visibleIds.length > 0 && visibleIds.every((id) => prev.has(id));
      if (allVisibleSelected) {
        const next = new Set(prev);
        for (const id of visibleIds) next.delete(id);
        return next;
      }
      return new Set([...prev, ...visibleIds]);
    });
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

            <MapeamentoFilterGroup value={mappingFilter} onChange={setMappingFilter} />

            {filteredRows.length === 0 ? (
              <EmptyState
                title="Nenhuma linha para este filtro"
                description='Troque o filtro "Mapeamento" para ver as demais linhas desta importação.'
              />
            ) : (
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
                {filteredRows.map((row) => {
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
                          {!canApprove && (
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <Button
                                  type="button"
                                  variant="outline"
                                  size="icon-sm"
                                  disabled={isPending}
                                  aria-label={`Resolver mapeamento da variante de ${row.cardName}`}
                                  onClick={() => setResolvingRow(row)}
                                >
                                  <Link2 className="h-3.5 w-3.5" />
                                </Button>
                              </TooltipTrigger>
                              <TooltipContent>Resolver mapeamento — associar a um Card Variant Type existente</TooltipContent>
                            </Tooltip>
                          )}
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
            )}
          </>
        )}
      </CardContent>
      <ResolverMapeamentoDialog
        row={resolvingRow}
        cardVariantTypes={cardVariantTypes}
        onResolved={(rowsUpdated, jobsAffected, createdTypeName) => {
          setResolvingRow(null);
          setError(null);
          const prefixo = createdTypeName
            ? `Tipo "${createdTypeName}" criado e mapeamento resolvido`
            : "Mapeamento resolvido";
          setConfirmSummary(
            `${prefixo}: ${formatNumber(rowsUpdated)} linha(s) em ${formatNumber(jobsAffected)} job${jobsAffected === 1 ? "" : "s"} revalidada(s) automaticamente.`,
          );
          onRefresh();
        }}
        onCancel={() => setResolvingRow(null)}
      />
    </Card>
  );
}

/**
 * Filtro "Mapeamento" (pedido de Fabrício, 2026-08-15): "Todos" | "Mapeados"
 * (linhas com `variant_type_id` já resolvido) | "Sem mapeamento" (linhas
 * `NEEDS_REVIEW` — combinação externa ainda sem correspondência em
 * `card_variant_type_external_mapping`). Mesma linguagem visual de
 * `VarianteFilterGroup` (cartas-gallery.tsx): chips `rounded-full`,
 * seleção única, `aria-pressed` reflete `value === option.code`.
 * Client-side sobre `rows` já carregado — nenhuma query nova, nenhuma
 * mudança em regra de decisão/confirmação/mapping.
 */
function MapeamentoFilterGroup({
  value,
  onChange,
}: {
  value: "all" | "mapped" | "unmapped";
  onChange: (value: "all" | "mapped" | "unmapped") => void;
}) {
  const options: { code: "all" | "mapped" | "unmapped"; label: string }[] = [
    { code: "all", label: "Todos" },
    { code: "mapped", label: "Mapeados" },
    { code: "unmapped", label: "Sem mapeamento" },
  ];

  return (
    <div className="space-y-1.5">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Mapeamento</p>
      <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por Mapeamento">
        {options.map((option) => {
          const active = value === option.code;
          return (
            <button
              key={option.code}
              type="button"
              onClick={() => onChange(option.code)}
              aria-pressed={active}
              className={cn(
                "inline-flex shrink-0 items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                active
                  ? "border-primary/40 bg-primary/5 text-primary-ink"
                  : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
              )}
            >
              {option.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

type ResolverMapeamentoMode = "existing" | "new";

/**
 * Dialog "Resolver mapeamento" — a partir de uma linha NEEDS_REVIEW, exibe
 * a combinação bruta recebida da fonte (type/foil/subtype/stamp, mesmos
 * chips de VariantRawChips) e dois modos de resolução (Incremento 3, ADR-028):
 *
 * - "Tipo existente" (original): associa a combinação a um Card Variant
 *   Type já cadastrado — resolverMapeamentoVariante() (Query 2150). O
 *   seletor só lista os já existentes e ativos no Game (cardVariantTypes,
 *   resolvido no servidor a partir do próprio job).
 * - "Novo tipo canônico" (novo): quando a combinação não corresponde a
 *   nenhum tipo existente, cadastra um Card Variant Type novo e resolve o
 *   mapeamento na mesma operação — criarTipoVariacaoEResolverMapeamento()
 *   (Query 2158, wrapper transacional). Nunca automático: code/name/
 *   description/displayOrder são sempre decisão explícita do
 *   administrador neste formulário, nunca inferidos da combinação
 *   recebida.
 *
 * Ambos chamam a action diretamente (mesmo padrão de chamada de
 * decidir()/confirmar() neste arquivo — sem useActionState, já que as
 * actions recebem argumentos posicionais, não FormData).
 */
function ResolverMapeamentoDialog({
  row,
  cardVariantTypes,
  onResolved,
  onCancel,
}: {
  row: CatalogVariantImportRowView | null;
  cardVariantTypes: CardVariantTypeOption[];
  onResolved: (rowsUpdated: number, jobsAffected: number, createdTypeName?: string) => void;
  onCancel: () => void;
}) {
  const [mode, setMode] = useState<ResolverMapeamentoMode>("existing");
  const [variantTypeId, setVariantTypeId] = useState("");
  const [newCode, setNewCode] = useState("");
  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [newDisplayOrder, setNewDisplayOrder] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function resetForm() {
    setMode("existing");
    setVariantTypeId("");
    setNewCode("");
    setNewName("");
    setNewDescription("");
    setNewDisplayOrder("");
    setError(null);
  }

  function handleOpenChange(next: boolean) {
    if (!next && !pending) {
      resetForm();
      onCancel();
    }
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!row) return;
    setError(null);

    if (mode === "existing") {
      if (!variantTypeId) return;
      setPending(true);
      resolverMapeamentoVariante(row.id, variantTypeId).then((result) => {
        setPending(false);
        if (result.error) {
          setError(result.error);
          return;
        }
        resetForm();
        onResolved(result.rowsUpdated ?? 0, result.jobsAffected ?? 0);
      });
      return;
    }

    const code = newCode.trim();
    const name = newName.trim();
    const displayOrder = Number.parseInt(newDisplayOrder, 10);
    if (!code || !name || !Number.isFinite(displayOrder)) {
      setError("Preencha código, nome e ordem de exibição do novo tipo.");
      return;
    }

    setPending(true);
    criarTipoVariacaoEResolverMapeamento(row.id, {
      code,
      name,
      description: newDescription.trim() || null,
      displayOrder,
    }).then((result) => {
      setPending(false);
      if (result.error) {
        setError(result.error);
        return;
      }
      resetForm();
      onResolved(result.rowsUpdated ?? 0, result.jobsAffected ?? 0, name);
    });
  }

  const canSubmit =
    mode === "existing" ? Boolean(variantTypeId) : Boolean(newCode.trim() && newName.trim() && newDisplayOrder);

  return (
    <Dialog open={row !== null} onOpenChange={handleOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Resolver mapeamento</DialogTitle>
          <DialogDescription>
            Associe esta combinação, exatamente como veio da fonte, a um Card Variant Type já cadastrado — ou
            cadastre um tipo canônico novo, se nenhum existente corresponder. O mapeamento é canônico para este Jogo
            e Fonte — outras linhas com a mesma combinação, em qualquer Coleção ainda em revisão, também serão
            resolvidas automaticamente.
          </DialogDescription>
        </DialogHeader>
        {row && (
          <form onSubmit={handleSubmit}>
            <DialogBody className="space-y-3">
              <div className="space-y-1.5">
                <Label>Combinação recebida da fonte</Label>
                <VariantRawChips row={row} />
              </div>

              <div className="flex gap-1.5 rounded-md border border-border bg-surface-muted/40 p-1" role="tablist">
                <button
                  type="button"
                  role="tab"
                  aria-selected={mode === "existing"}
                  onClick={() => setMode("existing")}
                  className={cn(
                    "flex-1 rounded px-2.5 py-1.5 text-xs font-medium transition-colors",
                    mode === "existing" ? "bg-surface text-foreground shadow-subtle" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  Tipo existente
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={mode === "new"}
                  onClick={() => setMode("new")}
                  className={cn(
                    "flex-1 rounded px-2.5 py-1.5 text-xs font-medium transition-colors",
                    mode === "new" ? "bg-surface text-foreground shadow-subtle" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  Novo tipo canônico
                </button>
              </div>

              {mode === "existing" ? (
                <div className="space-y-1">
                  <Label htmlFor="resolve-variant-type-id">Card Variant Type</Label>
                  <Select
                    id="resolve-variant-type-id"
                    required
                    value={variantTypeId}
                    onChange={(e) => setVariantTypeId(e.target.value)}
                  >
                    <option value="" disabled>
                      Selecione…
                    </option>
                    {cardVariantTypes.map((type) => (
                      <option key={type.id} value={type.id}>
                        {type.name} ({type.code})
                      </option>
                    ))}
                  </Select>
                </div>
              ) : (
                <div className="space-y-3">
                  <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
                    <div className="space-y-1">
                      <Label htmlFor="resolve-new-code">Código</Label>
                      <Input
                        id="resolve-new-code"
                        value={newCode}
                        onChange={(e) => setNewCode(e.target.value)}
                        placeholder="Ex.: SET_LOGO_STAFF"
                        maxLength={50}
                        required
                      />
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="resolve-new-name">Nome</Label>
                      <Input
                        id="resolve-new-name"
                        value={newName}
                        onChange={(e) => setNewName(e.target.value)}
                        placeholder="Ex.: Logo da Coleção Staff"
                        maxLength={100}
                        required
                      />
                    </div>
                  </div>

                  <div className="space-y-1">
                    <Label htmlFor="resolve-new-description">Descrição (opcional)</Label>
                    <textarea
                      id="resolve-new-description"
                      value={newDescription}
                      onChange={(e) => setNewDescription(e.target.value)}
                      placeholder="Explicação permanente do significado deste tipo de variação."
                      maxLength={500}
                      className={textareaClassName}
                    />
                  </div>

                  <div className="grid grid-cols-[minmax(6rem,1fr)] gap-3">
                    <div className="space-y-1">
                      <Label htmlFor="resolve-new-order">Ordem</Label>
                      <Input
                        id="resolve-new-order"
                        type="number"
                        min={1}
                        value={newDisplayOrder}
                        onChange={(e) => setNewDisplayOrder(e.target.value)}
                        required
                      />
                    </div>
                  </div>
                </div>
              )}

              {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
            </DialogBody>
            <DialogFooter>
              <Button type="button" variant="outline" size="sm" onClick={() => handleOpenChange(false)} disabled={pending}>
                Cancelar
              </Button>
              <Button type="submit" size="sm" disabled={pending || !canSubmit}>
                {pending ? "Resolvendo…" : mode === "new" ? "Criar tipo e resolver" : "Resolver"}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
