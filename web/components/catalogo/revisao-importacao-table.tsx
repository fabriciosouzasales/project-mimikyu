"use client";

import { Check, ImageOff, SkipForward, X } from "lucide-react";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  confirmarImportacao,
  decidirLinhasImportacao,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";
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
import { cn } from "@/lib/utils";
import type { CatalogImportRowView } from "@/lib/catalogo/queries";

const VALIDATION_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  VALID: "Válida",
  NEEDS_REVIEW: "Revisar",
  INVALID: "Inválida",
};

const VALIDATION_TONE: Record<string, StateTone> = {
  PENDING: "muted",
  VALID: "success",
  NEEDS_REVIEW: "warning",
  INVALID: "danger",
};

// Rótulos de Correspondência simplificados para o vocabulário pedido por
// Fabrício ("Nova", "Atualização", "Conflito" — nona rodada, 2026-08-01).
// `MATCHED` tecnicamente é um no-op quando os dados batem 100% com o que já
// existe (ver admin_confirm_catalog_import, Query 2082: só grava algo se
// houver diferença) — "Atualização" é uma simplificação deliberada para o
// momento da revisão (o card corresponde a um já existente e será
// conferido/atualizado), não uma promessa de escrita garantida. Sem risco de
// contradição visual na mesma tabela: a coluna Persistência (que mostraria o
// resultado real, INSERTED/UPDATED/UNCHANGED) foi removida nesta mesma
// rodada (ver comentário mais abaixo).
const MATCH_LABEL: Record<string, string> = {
  NEW: "Nova",
  MATCHED: "Atualização",
  CONFLICT: "Conflito",
};

const MATCH_TONE: Record<string, StateTone> = {
  NEW: "success",
  MATCHED: "warning",
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

const CATEGORY_LABEL: Record<string, string> = {
  POKEMON: "Pokémon",
  TRAINER: "Treinador",
  ENERGY: "Energia",
};

/** Bloco "valor grande + rótulo pequeno" do resumo no topo da revisão. */
function SummaryStat({ label, value, className }: { label: string; value: number; className?: string }) {
  return (
    <div>
      <p className={cn("text-lg font-semibold leading-none tabular-nums", className ?? "text-foreground")}>{value}</p>
      <p className="mt-1 text-[11px] uppercase tracking-wide text-muted-foreground">{label}</p>
    </div>
  );
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
 * `router.refresh()` voltou (oitava rodada, 2026-08-01) — mas só dentro de
 * `confirmar()`, não em `decidir()`. Motivo: depois que a persistência real
 * acontece (`admin_confirm_catalog_import`), a Coleção pode sair da lista
 * "pendente de importação" do seletor em `/catalogo/importar-cartas`
 * (`cardSetsParaImportar`, dado de Server Component em `page.tsx`) —
 * pedido de Fabrício: "o combobox deveria ser recarregado com a lista
 * atualizada". `router.refresh()` refaz só a árvore de Server Components
 * (busca `cardSets` de novo), **sem remontar nada** — diferente de
 * `redirect()`/`router.push()`, que trocam a URL e por isso destroem
 * estado de componente cliente (ver comentário grande em
 * `useAnalyzeJob`); aqui a URL não muda, então o progresso/etapa de
 * confirmação (`ImportProgress`) continua visível durante e depois do
 * refresh. `decidir()` não precisa disso — aprovar/rejeitar/pular uma
 * linha não muda `cardsCatalogados` de ninguém, só `confirmar()` persiste
 * de verdade.
 *
 * Botões de Ações ganharam Tooltip (era só `aria-label`, sem nada visível
 * ao passar o mouse — pedido de Fabrício) — `title` nativo do navegador foi
 * descartado de propósito neste projeto (ver comentário em app/layout.tsx:
 * "demorava ~1s e parecia quebrado"), usa o mesmo Tooltip/TooltipProvider
 * já usado em theme-toggle.tsx.
 *
 * Refinamento visual (nona rodada, 2026-08-01, pedido de Fabrício: "a
 * revisão deve parecer uma revisão de cartas, não uma tabela de banco de
 * dados"). Puramente apresentação — nenhuma mudança de fluxo, arquitetura,
 * banco, Edge Function ou regra de negócio:
 * - Colunas Nº + Nome viraram uma coluna "Carta" (miniatura da TCGdex via
 *   `imageBaseUrl` + `/low.webp`, mesma convenção de sufixo de
 *   `buildTcgdexHighImageUrl`, só que na variante leve por ser miniatura de
 *   tabela — ver comentário de `imageBaseUrl` em queries.ts).
 * - Categoria/Raridade/Validação/Correspondência/Decisão viraram chips
 *   (`StateBadge`, já usado noutras telas do Catálogo) em vez de texto/Badge
 *   genérico — cores success/warning/danger/muted já mapeadas nas CSS vars
 *   do projeto, não inventadas aqui.
 * - Coluna "Persistência" removida: `persistenceStatus` só sai de PENDING
 *   depois de `confirmar()` rodar — e nesse momento o job muda de status e
 *   esta tabela inteira some da tela (ver parágrafo acima). Ou seja, a
 *   coluna sempre mostrava "Pendente" enquanto visível — zero informação,
 *   exatamente o que Fabrício apontou.
 * - Resumo (Total/Aprovadas/Rejeitadas/Pendentes/Erros) computado em memória
 *   a partir de `rows`, sem chamada nova — "Pendentes" agrupa PENDING e
 *   SKIPPED (nenhuma decisão final ainda); "Erros" conta validationStatus
 *   === "INVALID" (persistenceStatus, como acima, não tem erro real visível
 *   nesta tela ainda).
 * - Botão Confirmar passou a exibir a contagem por extenso
 *   ("Confirmar N cartas") — mesmo `approvableCount` de antes, só o texto
 *   mudou.
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
    let erros = 0;
    for (const row of rows) {
      if (row.decisionStatus === "APPROVED") aprovadas++;
      else if (row.decisionStatus === "REJECTED") rejeitadas++;
      else pendentes++; // PENDING ou SKIPPED — nenhuma decisão final ainda
      if (row.validationStatus === "INVALID") erros++;
    }
    return { total: rows.length, aprovadas, rejeitadas, pendentes, erros };
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
      // Ver comentário grande da função acima — refaz `cardSets` no
      // servidor sem remontar o Client Component, então o progresso
      // continua visível.
      router.refresh();
    });
  }

  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-2 space-y-0">
        <p className="text-sm font-semibold text-foreground">Revisão de Cartas</p>
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
            {confirming ? "Confirmando…" : `Confirmar ${approvableCount} carta${approvableCount === 1 ? "" : "s"}`}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
        {confirmSummary && <InlineFeedback tone="success">{confirmSummary}</InlineFeedback>}

        {rows.length === 0 ? (
          <EmptyState title="Nenhuma linha para revisar" description="Este job não gerou nenhuma proposta de carta." />
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-x-6 gap-y-3 rounded-md border border-border bg-surface-muted/40 px-4 py-3">
              <SummaryStat label="Analisadas" value={summary.total} />
              <SummaryStat label="Aprovadas" value={summary.aprovadas} className="text-success" />
              <SummaryStat label="Rejeitadas" value={summary.rejeitadas} className="text-destructive" />
              <SummaryStat label="Pendentes" value={summary.pendentes} className="text-warning" />
              <SummaryStat label="Erros" value={summary.erros} className="text-destructive" />
            </div>

            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="w-8 pl-4">
                    <input type="checkbox" checked={allSelected} onChange={toggleAll} aria-label="Selecionar todas" />
                  </DataTableHeadCell>
                  <DataTableHeadCell>Carta</DataTableHeadCell>
                  <DataTableHeadCell>Categoria</DataTableHeadCell>
                  <DataTableHeadCell>Raridade</DataTableHeadCell>
                  <DataTableHeadCell align="center">Validação</DataTableHeadCell>
                  <DataTableHeadCell align="center">Correspondência</DataTableHeadCell>
                  <DataTableHeadCell align="center">Decisão</DataTableHeadCell>
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
                    <DataTableCell>
                      <div className="flex items-center gap-3">
                        <div className="aspect-[5/7] w-9 shrink-0 overflow-hidden rounded-md border border-border bg-surface-muted">
                          {row.imageBaseUrl ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              src={`${row.imageBaseUrl}/low.webp`}
                              alt=""
                              loading="lazy"
                              decoding="async"
                              className="h-full w-full object-cover"
                            />
                          ) : (
                            <div className="flex h-full w-full items-center justify-center text-muted-foreground">
                              <ImageOff className="h-3 w-3" aria-hidden="true" />
                            </div>
                          )}
                        </div>
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-foreground">{row.name}</p>
                          <p className="text-xs tabular-nums text-muted-foreground">
                            {row.collectorNumber}
                            {row.collectorTotal ? `/${row.collectorTotal}` : ""}
                          </p>
                          {row.reviewNotes.length > 0 && (
                            <p className="text-xs text-muted-foreground">{row.reviewNotes.join(" · ")}</p>
                          )}
                        </div>
                      </div>
                    </DataTableCell>
                    <DataTableCell>
                      <div className="flex flex-wrap items-center gap-1">
                        <StateBadge tone="muted">{row.category ? (CATEGORY_LABEL[row.category] ?? row.category) : "—"}</StateBadge>
                        {row.categorySource && row.categorySource !== "API" && (
                          <StateBadge tone="warning">heurística</StateBadge>
                        )}
                      </div>
                    </DataTableCell>
                    <DataTableCell>
                      <StateBadge tone="muted">{row.rawRarity ?? "—"}</StateBadge>
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
          </>
        )}
      </CardContent>
    </Card>
  );
}
