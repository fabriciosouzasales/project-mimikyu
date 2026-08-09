"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
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
import { Dialog, DialogBody, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { LogAtualizacoesFiltros } from "@/components/catalogo/log-atualizacoes-filtros";
import {
  ACTION_LABEL,
  CATEGORY_LABEL,
  ENTITY_TYPE_LABEL,
  humanizeMetadataKey,
} from "@/lib/catalogo/log-atualizacoes-labels";
import { LOG_ATUALIZACOES_PAGE_SIZE } from "@/lib/catalogo/queries";
import type { AdminUserOption, LogAtualizacoesItem } from "@/lib/catalogo/queries";

/**
 * Tabela + filtros + paginação de /catalogo/log-atualizacoes — escopo V1
 * aprovado por Fabrício (2026-08-09). Paginação server-driven via `?page=`
 * (links simples, mesmo padrão de JogosTable), não em memória — os dados já
 * chegam paginados/filtrados de `admin_list_catalog_action_log()`. Colunas
 * exatas aprovadas: Data | Quem | Entidade | Registro | Ação | Detalhes.
 * "Detalhes" abre um Dialog com o `metadata` já resolvido pelo backend —
 * nunca inventa um diff antes/depois que não esteja literalmente gravado.
 */
export function LogAtualizacoesTable({
  items,
  totalCount,
  page,
  search,
  entityType,
  action,
  actorId,
  usuarios,
}: {
  items: LogAtualizacoesItem[];
  totalCount: number;
  page: number;
  search: string;
  entityType: string;
  action: string;
  actorId: string;
  usuarios: AdminUserOption[];
}) {
  const [detalhe, setDetalhe] = useState<LogAtualizacoesItem | null>(null);
  const totalPages = Math.max(1, Math.ceil(totalCount / LOG_ATUALIZACOES_PAGE_SIZE));
  const semFiltroAtivo = !search && !entityType && !action && !actorId;

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (entityType) params.set("entidade", entityType);
    if (action) params.set("acao", action);
    if (actorId) params.set("usuario", actorId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/catalogo/log-atualizacoes?${qs}` : "/catalogo/log-atualizacoes";
  }

  return (
    <Card density="compact" className="overflow-hidden">
      <div className="border-b border-border p-4">
        <LogAtualizacoesFiltros
          initialSearch={search}
          entityType={entityType}
          action={action}
          actorId={actorId}
          usuarios={usuarios}
        />
      </div>

      <CardContent density="compact" className="px-0 pb-0">
        {items.length === 0 ? (
          semFiltroAtivo ? (
            <EmptyState
              title="Nenhum evento registrado ainda"
              description="Operações administrativas do Catálogo Editorial aparecem aqui conforme acontecem."
            />
          ) : (
            <EmptyState title="Nenhum resultado para os filtros atuais" description="Tente ajustar a busca ou os filtros." />
          )
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Data
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Quem</DataTableHeadCell>
                <DataTableHeadCell align="center">Entidade</DataTableHeadCell>
                <DataTableHeadCell align="center">Registro</DataTableHeadCell>
                <DataTableHeadCell align="center">Ação</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                  Detalhes
                </DataTableHeadCell>
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {items.map((item) => (
                <DataTableRow key={item.id}>
                  <DataTableCell className="whitespace-nowrap py-1 pl-4 text-xs text-foreground">
                    {new Date(item.createdAt).toLocaleString("pt-BR")}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1 text-xs text-muted-foreground">
                    {item.actorLabel ?? "Sistema"}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1 text-xs text-muted-foreground">
                    {ENTITY_TYPE_LABEL[item.entityType] ?? item.entityType}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1 text-xs text-foreground">
                    {item.entityLabel}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1 text-xs text-muted-foreground">
                    {ACTION_LABEL[item.action] ?? item.action}
                  </DataTableCell>
                  <DataTableCell align="center" className="py-1 pr-4 last:pr-4">
                    <Button type="button" variant="outline" size="sm" onClick={() => setDetalhe(item)}>
                      Ver detalhes
                    </Button>
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}
      </CardContent>

      {totalCount > 0 && (
        <div className="flex items-center justify-between border-t border-border px-4 py-3">
          <span className="text-sm text-muted-foreground">
            Mostrando <span className="font-medium text-foreground">{page * LOG_ATUALIZACOES_PAGE_SIZE + 1}</span>–
            <span className="font-medium text-foreground">
              {Math.min((page + 1) * LOG_ATUALIZACOES_PAGE_SIZE, totalCount)}
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

      <DetalhesDialog item={detalhe} onOpenChange={(open) => !open && setDetalhe(null)} />
    </Card>
  );
}

function formatMetadataScalar(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  return String(value);
}

function DetalhesDialog({
  item,
  onOpenChange,
}: {
  item: LogAtualizacoesItem | null;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Dialog open={item !== null} onOpenChange={onOpenChange}>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>{item ? (ACTION_LABEL[item.action] ?? item.action) : "Detalhes"}</DialogTitle>
          <DialogDescription>
            {item &&
              `${ENTITY_TYPE_LABEL[item.entityType] ?? item.entityType} · ${item.entityLabel} · ${CATEGORY_LABEL[item.category]}`}
          </DialogDescription>
        </DialogHeader>
        {item && (
          <DialogBody className="space-y-3">
            <div className="grid grid-cols-2 gap-x-4 gap-y-2 text-xs">
              <div>
                <p className="text-muted-foreground">Quando</p>
                <p className="text-foreground">{new Date(item.createdAt).toLocaleString("pt-BR")}</p>
              </div>
              <div>
                <p className="text-muted-foreground">Quem</p>
                <p className="text-foreground">{item.actorLabel ?? "Sistema"}</p>
              </div>
            </div>

            {item.metadata && Object.keys(item.metadata).length > 0 ? (
              <div className="space-y-2.5 border-t border-border pt-3">
                {Object.entries(item.metadata).map(([key, value]) => {
                  const isComplex = value !== null && typeof value === "object";
                  return (
                    <div key={key} className="space-y-1 text-xs">
                      <p className="text-muted-foreground">{humanizeMetadataKey(key)}</p>
                      {isComplex ? (
                        <pre className="overflow-x-auto whitespace-pre-wrap rounded-md bg-surface-muted p-2 text-[11px] text-foreground">
                          {JSON.stringify(value, null, 2)}
                        </pre>
                      ) : (
                        <p className="text-foreground">{formatMetadataScalar(value)}</p>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="border-t border-border pt-3 text-xs text-muted-foreground">
                Nenhum detalhe adicional registrado para este evento.
              </p>
            )}
          </DialogBody>
        )}
      </DialogContent>
    </Dialog>
  );
}
