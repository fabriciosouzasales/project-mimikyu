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
import type { AtividadeRecenteItem } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const STATUS_LABEL: Record<string, { texto: string; tone: StateTone }> = {
  COMPLETED: { texto: "Concluída", tone: "success" },
  COMPLETED_WITH_ERRORS: { texto: "Com falhas", tone: "warning" },
  FAILED: { texto: "Falhou", tone: "danger" },
  RUNNING: { texto: "Em andamento", tone: "muted" },
  PENDING: { texto: "Pendente", tone: "muted" },
  CANCELLED: { texto: "Cancelada", tone: "muted" },
};

/** Cor do ponto de status antes da data — mesmo tom semântico do `StateBadge`. */
const STATUS_DOT_CLASSES: Record<StateTone, string> = {
  success: "bg-success",
  warning: "bg-warning",
  danger: "bg-destructive",
  muted: "bg-muted-foreground/40",
};

const EXECUTION_CONTEXT_LABEL: Record<string, string> = {
  MANUAL: "Manual",
  API: "API Externa",
  SCHEDULED: "Agendado",
  SYSTEM: "Sistema",
};

/**
 * Log de importações da Visão Geral — reconstruído como tabela de verdade
 * (2026-07-31, pedido de Fabrício, referência visual: log viewer do
 * Supabase). Era uma `<ul>` de frases em linguagem natural, sem cabeçalho,
 * sem filtro e sem colunas estruturadas; vira `Card` + `DataTable`, mesmo
 * padrão de busca integrada/cabeçalho destacado já usado em
 * `card-sets-table.tsx`.
 *
 * Colunas novas pedidas: "Método" (`execution_context` — Manual/API
 * Externa/Agendado/Sistema, rótulo em `EXECUTION_CONTEXT_LABEL`) e "Cartas"
 * (`successCount/requestedCount`, com nota de falhas quando houver). Ponto
 * colorido antes da data ("sinalização em verde ou amarela, dependendo do
 * status") reaproveita o mesmo tom do `StateBadge` — inclui vermelho para
 * `FAILED`, não só verde/amarelo, para não perder o único status realmente
 * negativo do domínio. Badge de status mantido ao lado (mais legível que só
 * o ponto, com os 6 estados possíveis aqui, não só 2-3 como em HTTP logs).
 *
 * Fonte reduzida (`text-xs`/`text-[11px]`) e código de execução em
 * `font-mono`, ambos para aproximar da densidade do log de referência.
 * Filtro é local (mesmo motivo de `card-sets-table.tsx`: lista já vem
 * inteira e pequena). `getAtividadeRecente` passou a buscar 50 execuções
 * (era 8, chamada em `page.tsx`) para a paginação abaixo ter o que mostrar
 * — histórico completo continua em /catalogo/importacoes.
 *
 * Paginação (2026-07-31, pedido de Fabrício: "no mesmo padrão que usamos na
 * tabela de Jogos") — mesmo footer visual de `card-sets-table.tsx`
 * (Mostrando X–Y de Z + setas ícone), em memória sobre a lista já
 * filtrada, mesmo raciocínio: não há round-trip ao servidor aqui. Página
 * volta para a primeira sempre que o filtro muda.
 *
 * Alinhamento (2026-07-31, `/impeccable layout`, pedido de Fabrício):
 * cabeçalho de todas as colunas centralizado; dados centralizados em todas
 * as colunas exceto a primeira (Data) — mesma convenção já usada em
 * "Nome do Jogo"/"Card Set" nas outras tabelas (rótulo centralizado, valor
 * âncora à esquerda para a coluna que carrega a identidade da linha).
 */
const ATIVIDADE_PAGE_SIZE = 10;

export function AtividadeRecente({ atividades }: { atividades: AtividadeRecenteItem[] }) {
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);

  const filtradas = useMemo(() => {
    const termo = query.trim().toLowerCase();
    if (!termo) return atividades;
    return atividades.filter((item) => {
      const status = STATUS_LABEL[item.status] ?? { texto: item.status, tone: "muted" as const };
      const metodo = EXECUTION_CONTEXT_LABEL[item.executionContext] ?? item.executionContext;
      return [item.runCode, item.cardSetName, item.cardSetCode, metodo, status.texto]
        .filter(Boolean)
        .some((campo) => campo!.toLowerCase().includes(termo));
    });
  }, [atividades, query]);

  const totalCount = filtradas.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / ATIVIDADE_PAGE_SIZE));
  const paginaAtual = Math.min(page, totalPages - 1);
  const itensPagina = filtradas.slice(
    paginaAtual * ATIVIDADE_PAGE_SIZE,
    paginaAtual * ATIVIDADE_PAGE_SIZE + ATIVIDADE_PAGE_SIZE,
  );

  return (
    <Card density="compact" className="overflow-hidden">
      <div className="border-b border-border p-4">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(0);
            }}
            placeholder="Filtrar por execução, Coleção, método ou status…"
            className="h-9 bg-surface-muted pl-9 text-xs"
            aria-label="Filtrar atividade recente"
          />
        </div>
      </div>

      <CardContent density="compact" className="px-0 pb-0">
        {atividades.length === 0 ? (
          <EmptyState
            title="Nenhuma atividade registrada"
            description="Importações de imagens aparecem aqui conforme rodam."
          />
        ) : filtradas.length === 0 ? (
          <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro termo." />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Data
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Execução</DataTableHeadCell>
                <DataTableHeadCell align="center">Método</DataTableHeadCell>
                <DataTableHeadCell align="center">Coleção</DataTableHeadCell>
                <DataTableHeadCell align="center">Cartas</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Status
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {itensPagina.map((item) => {
                const status = STATUS_LABEL[item.status] ?? { texto: item.status, tone: "muted" as const };
                const metodo = EXECUTION_CONTEXT_LABEL[item.executionContext] ?? item.executionContext;
                return (
                  <DataTableRow key={item.id}>
                    <DataTableCell className="whitespace-nowrap pl-4 text-xs text-foreground">
                      <span className="inline-flex items-center gap-1.5">
                        <span
                          className={cn("h-1.5 w-1.5 shrink-0 rounded-full", STATUS_DOT_CLASSES[status.tone])}
                          aria-hidden="true"
                        />
                        {new Date(item.createdAt).toLocaleString("pt-BR")}
                      </span>
                    </DataTableCell>
                    <DataTableCell align="center" className="font-mono text-[11px] text-muted-foreground">
                      {item.runCode}
                    </DataTableCell>
                    <DataTableCell align="center" className="text-xs text-muted-foreground">
                      {metodo}
                    </DataTableCell>
                    <DataTableCell align="center" className="text-xs">
                      {item.cardSetCode ? (
                        <Link
                          href={`/catalogo/card-sets/${item.cardSetCode}`}
                          className="text-primary hover:underline"
                        >
                          {item.cardSetName ?? item.cardSetCode}
                        </Link>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="text-xs tabular-nums text-muted-foreground">
                      {formatNumber(item.successCount)}/{formatNumber(item.requestedCount)}
                      {item.failedCount > 0 && (
                        <span className="text-destructive"> ({formatNumber(item.failedCount)} falhas)</span>
                      )}
                    </DataTableCell>
                    <DataTableCell align="center" className="pr-4 last:pr-4">
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
            <span className="font-medium text-foreground">{formatNumber(paginaAtual * ATIVIDADE_PAGE_SIZE + 1)}</span>
            –
            <span className="font-medium text-foreground">
              {formatNumber(Math.min((paginaAtual + 1) * ATIVIDADE_PAGE_SIZE, totalCount))}
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
