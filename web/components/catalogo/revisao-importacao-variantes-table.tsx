"use client";

import { Check, Link2, SkipForward, X } from "lucide-react";
import { useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { confirmarImportacaoVariantes, decidirLinhasVariantes } from "@/app/catalogo/importar-variantes/actions";
import { ResolverEixosDialog, type AxisCatalogCache } from "@/components/catalogo/resolver-eixos-dialog";
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
import {
  canDecideVariantRow,
  canResolveVariantRowMapping,
  classifyVariantRowScope,
  deriveVariantImportScopeCounters,
  isVariantRowDeferred,
  isVariantRowMappingPending,
  isVariantRowScopeLocked,
  isVariantRowSelectable,
  type VariantDecisionStatus,
} from "@/lib/catalogo/variant-size-scope";
import { cn, formatNumber } from "@/lib/utils";
import type { CardVariantTypeOption, CatalogVariantImportRowView } from "@/lib/catalogo/queries";


type MappingFilter = "all" | "mapped" | "unmapped" | "out-of-scope";

// Rótulos-padrão. NÃO são a última palavra: desde o guard de escopo por
// tamanho (2026-09-15), NEEDS_REVIEW e INVALID têm mais de um significado, e
// validationRubric() abaixo decide o rótulo real linha a linha.
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

/**
 * Rótulo + tom da coluna Validação, já considerando o eixo de TAMANHO.
 *
 * "Fora de escopo" usa tom `muted`, não `danger`: uma variante JUMBO não é
 * erro nem defeito de dado — é uma decisão do sistema. Pintá-la de vermelho
 * mandaria o administrador procurar um problema que não existe.
 *
 * "Tamanho desconhecido" fica em `warning`, como toda pendência humana, mas
 * com nome próprio — chamá-la de "sem mapeamento" mandaria o administrador
 * para uma tela que não resolve nada.
 */
function validationRubric(row: CatalogVariantImportRowView): { label: string; tone: StateTone } {
  switch (classifyVariantRowScope(row)) {
    case "OUT_OF_SCOPE":
      return { label: "Fora de escopo", tone: "muted" };
    case "UNSUPPORTED_SIZE":
      return { label: "Tamanho desconhecido", tone: "warning" };
    default:
      return {
        label: VALIDATION_LABEL[row.validationStatus] ?? row.validationStatus,
        tone: VALIDATION_TONE[row.validationStatus] ?? "muted",
      };
  }
}

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

/**
 * Chips type/foil/subtype/stamp exatamente como vieram do dataset-fonte
 * (raw_data, Query 2138) — mesmo espírito da coluna Raridade em
 * revisao-importacao-table.tsx (dado bruto, sem interpretação).
 *
 * `size` entra como chip APENAS quando decidiu alguma coisa. A esmagadora
 * maioria das variantes é `standard` (ou nem declara `size`), e mostrar esse
 * chip em todas as linhas seria um dado técnico repetido milhares de vezes
 * sem informar nada — exatamente o tipo de poluição que esta tela evita.
 */
function VariantRawChips({ row }: { row: CatalogVariantImportRowView }) {
  const chips = [row.rawType, row.rawFoil, row.rawSubtype, ...(row.rawStamp ?? [])].filter(
    (value): value is string => Boolean(value),
  );
  const sizeChip = classifyVariantRowScope(row) === "IN_SCOPE" ? null : (row.normalizedSize ?? row.rawSize);
  if (chips.length === 0 && !sizeChip) return <span className="text-xs text-muted-foreground">—</span>;
  return (
    <div className="flex flex-wrap gap-1">
      {chips.map((chip, index) => (
        <StateBadge key={`${chip}-${index}`} tone="muted">
          {chip}
        </StateBadge>
      ))}
      {sizeChip && <StateBadge tone="warning">{`tamanho: ${sizeChip}`}</StateBadge>}
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
  // Perfis/características de Impressão e Contexto: lidos uma vez por eixo
  // enquanto esta revisão estiver aberta (todas as linhas são do mesmo jogo).
  const axisCatalogCache = useRef<AxisCatalogCache>({});
  // Filtro "Mapeamento" (client-side, sem nova query — `rows` já vem
  // carregado por completo do servidor): "Todos" | "Mapeados" (variantTypeName
  // resolvido, ou seja, normalized_data.variant_type_id já preenchido) |
  // "Sem mapeamento" (validationStatus === NEEDS_REVIEW). Só afeta o que é
  // EXIBIDO na tabela — summary/approvableCount/decidir/confirmar continuam
  // calculados sobre `rows` inteiro, nunca sobre o recorte filtrado (regras
  // de decisão/confirmação não mudam com o filtro).
  const [mappingFilter, setMappingFilter] = useState<MappingFilter>("all");

  // "Fora de escopo" só existe como opção quando o job realmente produziu
  // linhas assim — um filtro permanentemente vazio seria ruído em todos os
  // jobs anteriores ao guard de tamanho.
  const hasOutOfScopeRows = useMemo(
    () => rows.some((row) => classifyVariantRowScope(row) === "OUT_OF_SCOPE"),
    [rows],
  );

  const filteredRows = useMemo(() => {
    if (mappingFilter === "mapped") return rows.filter((row) => row.variantTypeName !== null);
    // "Sem mapeamento" passa a significar literalmente isso: pendência que a
    // tela de Card Variant Type consegue resolver. Tamanho desconhecido e
    // fora de escopo ficam de fora — não são falta de mapeamento.
    if (mappingFilter === "unmapped") return rows.filter(isVariantRowMappingPending);
    if (mappingFilter === "out-of-scope") {
      return rows.filter((row) => classifyVariantRowScope(row) === "OUT_OF_SCOPE");
    }
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
    let deferidas = 0;
    let pendentes = 0;
    for (const row of rows) {
      // Fora de escopo é contada só na sua própria coluna. Ela chega já
      // SKIPPED; somá-la a "Pendentes" criaria um número que o administrador
      // nunca conseguiria zerar, porque não há decisão pendente nenhuma — o
      // sistema já decidiu não catalogar.
      if (isVariantRowScopeLocked(row)) continue;

      if (row.decisionStatus === "APPROVED") aprovadas++;
      else if (row.decisionStatus === "REJECTED") rejeitadas++;
      // SKIPPED saiu de "Pendentes" em 2026-09-16
      // (SV5-DEFERRED-UI-SEMANTICS-01). Pular é decisão FINAL do
      // administrador, tão final quanto aprovar ou rejeitar — contá-la como
      // pendência mantinha na tela um número que nenhuma ação zeraria, e foi
      // exatamente o que fez um job COMPLETED aparecer "com pendências".
      //
      // 2026-09-16 (SEMANTICS-02): o predicado é isVariantRowDeferred, NÃO
      // `decisionStatus === "SKIPPED"`. Linha MATCHED + SKIPPED é variante
      // que JÁ EXISTE — decisão automática do importador. Ela não é deferida
      // (ninguém adiou nada) e também não é pendente (não há o que decidir):
      // fica fora das quatro categorias, visível apenas em "Analisadas".
      else if (isVariantRowDeferred(row)) deferidas++;
      else if (row.decisionStatus === "PENDING") pendentes++;
    }
    // >>> MESMA FUNÇÃO DO PAINEL <<< (2026-09-16, BLOCKER-2/RISCO-3). Os três
    // números de escopo saem de deriveVariantImportScopeCounters sobre `rows`
    // — exatamente a coleção que o painel de conclusão também usa. Não existe
    // mais contagem paralela a divergir, e `rows` agora chega paginada
    // (getCatalogVariantImportRows), então isso vale acima de 1000 linhas.
    const escopo = deriveVariantImportScopeCounters(rows);
    return {
      total: rows.length,
      aprovadas,
      rejeitadas,
      pendentes,
      deferidas,
      semMapeamento: escopo.mappingPendingRows,
      tamanhoDesconhecido: escopo.unsupportedSizeRows,
      foraDeEscopo: escopo.outOfScopeRows,
    };
  }, [rows]);

  // "Selecionar todas" opera sobre o recorte visível (filteredRows) — mesmo
  // raciocínio de qualquer filtro de tabela: marcar "todas" com o filtro
  // "Sem mapeamento" ativo não deve arrastar para a seleção linhas já
  // mapeadas que nem aparecem na tela.
  //
  // 2026-09-16 (BLOCKER-1): e nunca arrasta linha FORA DE ESCOPO. Ela continua
  // visível — é informação legítima —, mas não é selecionável, então nenhuma
  // ação em lote a alcança. `selectableRows` é a população de seleção; a
  // exibição segue sendo `filteredRows`.
  const selectableRows = useMemo(() => filteredRows.filter(isVariantRowSelectable), [filteredRows]);
  const allSelected = selectableRows.length > 0 && selectableRows.every((row) => selected.has(row.id));

  function toggleRow(id: string) {
    // Guard de identidade, não só de aparência: mesmo que o checkbox fosse
    // alcançado por teclado ou por um estado obsoleto, a linha travada não
    // entra na seleção.
    const row = rows.find((r) => r.id === id);
    if (row && !isVariantRowSelectable(row)) return;
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
      const visibleIds = selectableRows.map((row) => row.id);
      const allVisibleSelected = visibleIds.length > 0 && visibleIds.every((id) => prev.has(id));
      if (allVisibleSelected) {
        const next = new Set(prev);
        for (const id of visibleIds) next.delete(id);
        return next;
      }
      return new Set([...prev, ...visibleIds]);
    });
  }

  function decidir(ids: string[], status: VariantDecisionStatus) {
    // >>> ÚLTIMA BARREIRA DO CLIENTE (BLOCKER-1) <<<
    // Nenhum id fora de escopo sai daqui com decisão diferente de SKIPPED,
    // venha ele de um botão individual, do lote, ou de seleção obsoleta.
    // A Server Action reconfere contra o banco e a Query 2199 (proposta)
    // garante no motor — isto aqui só evita a viagem inútil.
    const safeIds = ids.filter((id) => {
      const row = rows.find((r) => r.id === id);
      return !row || canDecideVariantRow(row, status);
    });
    if (safeIds.length === 0) return;
    setError(null);
    setConfirmSummary(null);
    startTransition(async () => {
      const result = await decidirLinhasVariantes(jobId, safeIds, status);
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
    const selectedRows = ids
      .map((id) => rows.find((row) => row.id === id))
      .filter((row): row is CatalogVariantImportRowView => Boolean(row));
    const approvableIds = selectedRows.filter((row) => row.validationStatus === "VALID").map((row) => row.id);

    // Mensagem por MOTIVO, não por contagem única: mandar o administrador
    // "resolver o mapeamento" de uma variante JUMBO seria enviá-lo a uma
    // tela que não tem como ajudá-lo.
    const bloqueadas = selectedRows.filter((row) => row.validationStatus !== "VALID");
    const semMapeamento = bloqueadas.filter(isVariantRowMappingPending).length;
    const tamanhoDesconhecido = bloqueadas.filter(
      (row) => classifyVariantRowScope(row) === "UNSUPPORTED_SIZE",
    ).length;
    const foraDeEscopo = bloqueadas.filter((row) => classifyVariantRowScope(row) === "OUT_OF_SCOPE").length;

    const motivos: string[] = [];
    if (semMapeamento > 0) {
      motivos.push(
        `${formatNumber(semMapeamento)} sem mapeamento — use Resolver mapeamento antes`,
      );
    }
    if (tamanhoDesconhecido > 0) {
      motivos.push(
        `${formatNumber(tamanhoDesconhecido)} com tamanho desconhecido — é decisão de escopo, não há mapeamento a resolver`,
      );
    }
    if (foraDeEscopo > 0) {
      motivos.push(`${formatNumber(foraDeEscopo)} fora de escopo (JUMBO) — o sistema não cataloga essas variantes`);
    }
    if (motivos.length > 0) {
      const total = bloqueadas.length;
      setError(
        `${formatNumber(total)} variante(s) não ${total === 1 ? "foi" : "foram"} aprovada(s): ${motivos.join("; ")}.`,
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
              {/* Tom `muted`, como "Fora de escopo": deferir é decisão
                  registrada, não alerta. Só aparece quando existe. */}
              {summary.deferidas > 0 && (
                <SummaryStat label="Deferidas" value={summary.deferidas} className="text-muted-foreground" />
              )}
              <SummaryStat label="Sem Mapeamento" value={summary.semMapeamento} className="text-destructive" />
              {summary.tamanhoDesconhecido > 0 && (
                <SummaryStat label="Tamanho Desconhecido" value={summary.tamanhoDesconhecido} className="text-warning" />
              )}
              {/* Sem cor de alerta: fora de escopo é informação, não problema. */}
              {summary.foraDeEscopo > 0 && (
                <SummaryStat label="Fora de Escopo" value={summary.foraDeEscopo} className="text-muted-foreground" />
              )}
            </div>

            <MapeamentoFilterGroup
              value={mappingFilter}
              onChange={setMappingFilter}
              showOutOfScope={hasOutOfScopeRows}
            />

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
                  // Controle editorial de mapeamento ≠ "não pode aprovar".
                  // Tamanho desconhecido e fora de escopo também não podem ser
                  // aprovados, mas o botão de mapeamento não os resolveria.
                  const canResolveMapping = canResolveVariantRowMapping(row);
                  const validation = validationRubric(row);
                  const scope = classifyVariantRowScope(row);
                  // Linha travada: decisão automática, imutável. Sem checkbox
                  // ativo e sem NENHUMA ação de decisão — nem Pular, que só
                  // repetiria o estado em que ela já nasceu.
                  const scopeLocked = isVariantRowScopeLocked(row);
                  const approveHint = canApprove
                    ? "Aprovar esta variante"
                    : scope === "OUT_OF_SCOPE"
                      ? "Fora de escopo — variante JUMBO não é catalogada pelo sistema"
                      : scope === "UNSUPPORTED_SIZE"
                        ? "Tamanho desconhecido — decisão de escopo, não há mapeamento a resolver"
                        : "Sem mapeamento — use Resolver mapeamento antes de aprovar";
                  return (
                    <DataTableRow key={row.id}>
                      <DataTableCell className="pl-4">
                        <input
                          type="checkbox"
                          checked={selected.has(row.id)}
                          onChange={() => toggleRow(row.id)}
                          disabled={scopeLocked}
                          aria-label={
                            scopeLocked
                              ? `${row.cardName} — fora de escopo por tamanho, decisão automática do sistema`
                              : `Selecionar ${row.cardName}`
                          }
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
                        <StateBadge tone={validation.tone}>{validation.label}</StateBadge>
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
                        {scopeLocked ? (
                          // Nenhuma ação. A decisão já foi tomada pelo sistema
                          // na importação, e a linha continua aqui para ser
                          // VISTA, não decidida. Botões desabilitados seriam
                          // ruído: sugeririam que existe algo a fazer.
                          <span className="text-xs text-muted-foreground">Decisão automática</span>
                        ) : (
                        <div className="flex justify-center gap-1">
                          {canResolveMapping && (
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
                              <TooltipContent>Resolver mapeamento — diagnosticar e classificar Acabamento, Impressão ou Contexto de Edição</TooltipContent>
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
                            <TooltipContent>{approveHint}</TooltipContent>
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
                        )}
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
      <ResolverEixosDialog
        row={resolvingRow}
        cardVariantTypes={cardVariantTypes}
        catalogCache={axisCatalogCache}
        onResolved={(summary) => {
          setResolvingRow(null);
          setError(null);
          setConfirmSummary(summary);
          onRefresh();
        }}
        onCancel={() => setResolvingRow(null)}
      />
    </Card>
  );
}

/**
 * Filtro "Mapeamento" (pedido de Fabrício, 2026-08-15): "Todos" | "Mapeados"
 * (linhas com `variant_type_id` já resolvido) | "Sem mapeamento" (combinação
 * externa ainda sem correspondência em `card_variant_type_external_mapping`)
 * | "Fora de escopo" (só aparece quando o job tem linhas assim). Mesma
 * linguagem visual de `VarianteFilterGroup` (cartas-gallery.tsx): chips
 * `rounded-full`, seleção única, `aria-pressed` reflete
 * `value === option.code`. Client-side sobre `rows` já carregado — nenhuma
 * query nova, nenhuma mudança em regra de decisão/confirmação/mapping.
 *
 * 2026-09-15: "Sem mapeamento" deixou de ser sinônimo de `NEEDS_REVIEW`.
 * Linhas com `size` desconhecido também são NEEDS_REVIEW e NÃO entram aqui —
 * ver isVariantRowMappingPending.
 */
function MapeamentoFilterGroup({
  value,
  onChange,
  showOutOfScope,
}: {
  value: MappingFilter;
  onChange: (value: MappingFilter) => void;
  showOutOfScope: boolean;
}) {
  const options: { code: MappingFilter; label: string }[] = [
    { code: "all", label: "Todos" },
    { code: "mapped", label: "Mapeados" },
    { code: "unmapped", label: "Sem mapeamento" },
    ...(showOutOfScope ? [{ code: "out-of-scope" as const, label: "Fora de escopo" }] : []),
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
