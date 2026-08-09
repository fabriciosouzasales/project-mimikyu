"use client";

import Link from "next/link";
import { ChevronLeft, ChevronRight, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { StateBadge } from "@/components/catalogo/state-badge";
import type { StateTone } from "@/components/catalogo/state-badge";
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
import { Input } from "@/components/ui/input";
import type { ImportacaoPipeline, ImportacaoRow } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

/**
 * Idêntico ao `STATUS_LABEL` de `atividade-recente.tsx` — inclui
 * deliberadamente só os status de `asset_import_run`. Status exclusivos de
 * `catalog_import_job` (`STAGED`/`CONFIRMING`/`RECEIVED`/`PROCESSING`) caem
 * no fallback gracioso abaixo (mostra o texto bruto), mesma decisão já
 * tomada para a Visão Geral (pedido explícito de Fabrício de não tocar essa
 * parte da UI ainda) — não ampliada nesta rodada para manter as duas telas
 * consistentes entre si.
 */
const STATUS_LABEL: Record<string, { texto: string; tone: StateTone }> = {
  COMPLETED: { texto: "Concluída", tone: "success" },
  COMPLETED_WITH_ERRORS: { texto: "Com falhas", tone: "warning" },
  FAILED: { texto: "Falhou", tone: "danger" },
  RUNNING: { texto: "Em andamento", tone: "muted" },
  PENDING: { texto: "Pendente", tone: "muted" },
  CANCELLED: { texto: "Cancelada", tone: "muted" },
};

/** Cor do ponto de status antes da data — mesmo tom semântico do `StateBadge` (ver atividade-recente.tsx). */
const STATUS_DOT_CLASSES: Record<StateTone, string> = {
  success: "bg-success",
  warning: "bg-warning",
  danger: "bg-destructive",
  muted: "bg-muted-foreground/40",
};

const PIPELINE_LABEL: Record<ImportacaoPipeline, string> = {
  CARTAS: "Cartas",
  IMAGENS: "Imagens",
};

const IMPORTACOES_PAGE_SIZE = 10;

/**
 * Tabela do Histórico completo de importações (`/catalogo/importacoes`) —
 * reescrita em 2026-08-09 para adotar o mesmo modelo visual já aprovado do
 * bloco "Atividade Recente" da Visão Geral (`atividade-recente.tsx`): busca
 * no topo, `DataTable` com Data | Coleção | Execução | Operação | Resultado |
 * Status (nesta ordem), ponto colorido de status antes da data, "Coleção"
 * como link de duas linhas (Nome + Código) para o hub do Card Set,
 * "Execução" mantida como informação secundária (monospace, tom
 * `muted-foreground`), paginação com o mesmo footer de `card-sets-table.tsx`.
 * Substitui o `<table>` simples anterior desta tela, que ainda usava
 * "Card Set" (em vez de "Coleção") e colunas "Pipeline"/"Tipo"/"Fonte"
 * separadas — "Pipeline" virou o filtro de chips abaixo da busca (em vez de
 * coluna própria: já é visível dentro de "Operação" em cada linha) e
 * "Tipo"/"Fonte" foram removidos por não fazerem parte do modelo aprovado
 * (a nomenclatura de execução/fonte externa segue disponível, quando
 * relevante, dentro do próprio `runCode`/contexto da linha).
 *
 * Filtro de Pipeline (Cartas/Imagens) — único filtro de chip desta rodada,
 * mesmo padrão visual/comportamental de `FilterGroup` em `cartas-gallery.tsx`
 * (`Set` vazio = mostra tudo, seleção multi-toggle). Os filtros de URL já
 * existentes (`?atencao=1`, `?cardSet=`) continuam resolvidos no servidor
 * (`page.tsx`, antes de chegar aqui) — este componente só filtra em memória
 * por cima do que já recebeu, exatamente como a busca de texto.
 *
 * Semântica de "0 de 0" verificada antes desta rodada (pedido explícito de
 * Fabrício, não alterar a apresentação sem confirmar o significado): ocorre
 * quando `import-card-assets` encerra a run como `FAILED` antes de sequer
 * enumerar cartas a importar — Card Set não encontrado ou, mais comum na
 * prática, nenhuma `card_set_external_reference` ativa para aquele idioma
 * (`index.ts`, Edge Function, checagens `if (!cardSet)`/`if (!externalReference)`,
 * ambas encerram com `requested_count: 0`). É um resultado real e íntegro
 * ("a run não chegou a pedir nada"), não um dado quebrado — por isso mantido
 * no mesmo formato "X de Y" das demais linhas, sem tratamento especial.
 */
export function ImportacoesTable({ importacoes }: { importacoes: ImportacaoRow[] }) {
  const [query, setQuery] = useState("");
  const [selectedPipelines, setSelectedPipelines] = useState<Set<ImportacaoPipeline>>(new Set());
  const [page, setPage] = useState(0);

  const pipelineOptions = useMemo(() => {
    const counts = new Map<ImportacaoPipeline, number>();
    for (const item of importacoes) {
      counts.set(item.pipeline, (counts.get(item.pipeline) ?? 0) + 1);
    }
    return (["CARTAS", "IMAGENS"] as const)
      .filter((pipeline) => (counts.get(pipeline) ?? 0) > 0)
      .map((pipeline) => ({ pipeline, count: counts.get(pipeline) ?? 0 }));
  }, [importacoes]);

  function togglePipeline(pipeline: ImportacaoPipeline) {
    setSelectedPipelines((prev) => {
      const next = new Set(prev);
      if (next.has(pipeline)) next.delete(pipeline);
      else next.add(pipeline);
      return next;
    });
    setPage(0);
  }

  const filtradas = useMemo(() => {
    const termo = query.trim().toLowerCase();
    return importacoes.filter((item) => {
      if (selectedPipelines.size > 0 && !selectedPipelines.has(item.pipeline)) return false;
      if (!termo) return true;
      const status = STATUS_LABEL[item.status] ?? { texto: item.status, tone: "muted" as const };
      const operacao = PIPELINE_LABEL[item.pipeline];
      return [item.runCode, item.cardSetName, item.cardSetCode, operacao, item.languageCode, status.texto]
        .filter(Boolean)
        .some((campo) => campo!.toLowerCase().includes(termo));
    });
  }, [importacoes, query, selectedPipelines]);

  const totalCount = filtradas.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / IMPORTACOES_PAGE_SIZE));
  const paginaAtual = Math.min(page, totalPages - 1);
  const itensPagina = filtradas.slice(
    paginaAtual * IMPORTACOES_PAGE_SIZE,
    paginaAtual * IMPORTACOES_PAGE_SIZE + IMPORTACOES_PAGE_SIZE,
  );

  return (
    <Card density="compact" className="overflow-hidden">
      <div className="space-y-3 border-b border-border p-4">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(0);
            }}
            placeholder="Filtrar por execução, Coleção, operação ou status…"
            className="h-9 bg-surface-muted pl-9 text-xs"
            aria-label="Filtrar histórico de importações"
          />
        </div>

        {pipelineOptions.length > 1 && (
          <div className="flex flex-wrap gap-1.5">
            {pipelineOptions.map(({ pipeline, count }) => {
              const active = selectedPipelines.has(pipeline);
              return (
                <button
                  key={pipeline}
                  type="button"
                  onClick={() => togglePipeline(pipeline)}
                  aria-pressed={active}
                  className={cn(
                    "inline-flex shrink-0 items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    active
                      ? "border-primary/40 bg-primary/5 text-primary"
                      : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                  )}
                >
                  {PIPELINE_LABEL[pipeline]} ({count})
                </button>
              );
            })}
          </div>
        )}
      </div>

      <CardContent density="compact" className="px-0 pb-0">
        {importacoes.length === 0 ? (
          <EmptyState
            title="Nenhuma execução registrada ainda"
            description="Execuções de importação de Cartas e Imagens aparecem aqui conforme rodam."
          />
        ) : filtradas.length === 0 ? (
          <EmptyState
            title={query ? `Nenhum resultado para "${query}"` : "Nenhuma execução para este filtro"}
            description="Tente outro termo ou ajuste os filtros acima."
          />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Data
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Coleção</DataTableHeadCell>
                <DataTableHeadCell align="center">Execução</DataTableHeadCell>
                <DataTableHeadCell align="center">Operação</DataTableHeadCell>
                <DataTableHeadCell align="center">Resultado</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Status
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {itensPagina.map((item) => {
                const status = STATUS_LABEL[item.status] ?? { texto: item.status, tone: "muted" as const };
                const operacao = item.languageCode
                  ? `${PIPELINE_LABEL[item.pipeline]} (${item.languageCode})`
                  : PIPELINE_LABEL[item.pipeline];
                return (
                  <DataTableRow key={item.id}>
                    <DataTableCell className="whitespace-nowrap py-1 pl-4 text-xs text-foreground">
                      <span className="inline-flex items-center gap-1.5">
                        <span
                          className={cn("h-1.5 w-1.5 shrink-0 rounded-full", STATUS_DOT_CLASSES[status.tone])}
                          aria-hidden="true"
                        />
                        {new Date(item.createdAt).toLocaleString("pt-BR")}
                      </span>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-xs">
                      {item.cardSetCode ? (
                        <Link
                          href={`/catalogo/card-sets/${item.cardSetCode}`}
                          className="inline-flex flex-col leading-tight text-primary hover:underline"
                        >
                          <span>{item.cardSetName ?? item.cardSetCode}</span>
                          <span className="text-[11px] text-muted-foreground no-underline">{item.cardSetCode}</span>
                        </Link>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 font-mono text-[11px] text-muted-foreground">
                      {item.runCode}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-xs text-muted-foreground">
                      {operacao}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-xs tabular-nums text-muted-foreground">
                      {formatNumber(item.successCount)} de {formatNumber(item.requestedCount)}
                      {item.failedCount > 0 && (
                        <span className="text-destructive"> ({formatNumber(item.failedCount)} falhas)</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 pr-4 last:pr-4">
                      <StateBadge tone={status.tone}>{status.texto}</StateBadge>
                    </DataTableCell>
                  </DataTableRow>
                );
              })}
            </tbody>
          </DataTable>
        )}
      </CardContent>

      {totalCount > 0 && (
        <div className="flex items-center justify-between border-t border-border px-4 py-3">
          <span className="text-sm text-muted-foreground">
            Mostrando{" "}
            <span className="font-medium text-foreground">{formatNumber(paginaAtual * IMPORTACOES_PAGE_SIZE + 1)}</span>
            –
            <span className="font-medium text-foreground">
              {formatNumber(Math.min((paginaAtual + 1) * IMPORTACOES_PAGE_SIZE, totalCount))}
            </span>{" "}
            de <span className="font-medium text-foreground">{formatNumber(totalCount)}</span>
          </span>
          <div className="flex items-center gap-1.5">
            <Button
              type="button"
              variant="outline"
              size="icon-sm"
              disabled={paginaAtual === 0}
              onClick={() => setPage((p) => p - 1)}
              aria-label="Página anterior"
            >
              <ChevronLeft className="h-3.5 w-3.5" />
            </Button>
            <span className="min-w-[2.5rem] text-center text-sm text-muted-foreground">
              {paginaAtual + 1}/{totalPages}
            </span>
            <Button
              type="button"
              variant="outline"
              size="icon-sm"
              disabled={paginaAtual >= totalPages - 1}
              onClick={() => setPage((p) => p + 1)}
              aria-label="Próxima página"
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      )}
    </Card>
  );
}
