"use client";

import { ChevronLeft, ChevronRight, Eye, EyeOff, Pencil, Plus, Search, Sparkles } from "lucide-react";
import { useActionState, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  createCardVariantType,
  deactivateCardVariantType,
  reactivateCardVariantType,
  updateCardVariantType,
  type CardVariantTypeActionState,
} from "@/app/catalogo/tipos-variacao/actions";
import { Badge } from "@/components/ui/badge";
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
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { formatarData } from "@/lib/format-date";
import type { CardVariantTypeAdminRow } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

const initialState: CardVariantTypeActionState = { error: null };

// Paginação em memória (2026-08-15, pedido de Fabrício: "a tabela tem
// crescido a cada importação de variantes") — mesmo padrão de
// `CardSetsTable`/`ImportacoesTable`: este componente já recebe a lista
// inteira via prop (`getCardVariantTypesAdmin` traz tudo de uma vez, sem
// paginação no servidor), então pagina/filtra em memória sobre o array já
// carregado, com o mesmo footer visual (Mostrando X–Y de Z + setas ícone +
// página atual/total) usado em Card Sets/Importações — não o padrão
// server-side (`?page=`) de Jogos/Log de Atualizações, que pressupõe o
// componente receber só uma página por vez do servidor.
const TIPOS_VARIACAO_PAGE_SIZE = 10;

/**
 * Tela /catalogo/tipos-variacao (Incremento 2, ADR-028 — Governança da
 * Taxonomia de Card Variant Type). Mesmo esqueleto de `JogosTable`: cadastro
 * e edição em `Dialog` isolado por `useAdminListState`, sem seleção em
 * massa/exclusão — em vez de excluir, cada linha tem uma ação rápida de
 * inativar (com confirmação, `EyeOff`) ou reativar (direto, `Eye`), mesmo
 * par de ícones já usado em `cartas-gallery.tsx` para `card.is_active`.
 *
 * Sem exclusão física nesta versão (decisão explícita de Fabrício,
 * ADR-028 revisão 1.2) — não existe nenhum botão de excluir aqui.
 * Tipos inativos permanecem listados, identificados pelo badge de status —
 * nunca escondidos da administração (só somem do seletor de novos
 * cadastros/mappings, ver `getCardVariantTypesForJob`).
 *
 * Busca + paginação (2026-08-15, pedido de Fabrício: "a tabela tem crescido
 * a cada importação de variantes") — ver `TIPOS_VARIACAO_PAGE_SIZE` acima
 * para o raciocínio completo (mesmo padrão client-side de `CardSetsTable`).
 * Busca casa por nome, código ou descrição; muda de busca sempre volta para
 * a primeira página.
 */
export function TiposVariacaoTable({ tiposVariacao }: { tiposVariacao: CardVariantTypeAdminRow[] }) {
  const router = useRouter();
  const state = useAdminListState();
  const [deactivatingTipo, setDeactivatingTipo] = useState<CardVariantTypeAdminRow | null>(null);
  const [reactivatingId, setReactivatingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);

  const editingTipo = tiposVariacao.find((t) => t.id === state.editingId) ?? null;
  const nextDisplayOrder = tiposVariacao.reduce((max, t) => Math.max(max, t.displayOrder), 0) + 1;

  const filtrados = useMemo(() => {
    const termo = query.trim().toLowerCase();
    if (!termo) return tiposVariacao;
    return tiposVariacao.filter((tipo) =>
      [tipo.name, tipo.code, tipo.description].filter(Boolean).some((campo) => campo!.toLowerCase().includes(termo)),
    );
  }, [tiposVariacao, query]);

  const totalCount = filtrados.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / TIPOS_VARIACAO_PAGE_SIZE));
  const paginaAtual = Math.min(page, totalPages - 1);
  const itensPagina = filtrados.slice(
    paginaAtual * TIPOS_VARIACAO_PAGE_SIZE,
    paginaAtual * TIPOS_VARIACAO_PAGE_SIZE + TIPOS_VARIACAO_PAGE_SIZE,
  );

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  function handleDeactivated() {
    setDeactivatingTipo(null);
    state.onSuccess("Tipo de variação inativado com sucesso.");
    router.refresh();
  }

  /**
   * Reativação direta, sem Dialog de confirmação — mesmo raciocínio de
   * `handleReactivate` em `cartas-gallery.tsx`: o próprio botão já é o
   * "desfazer" de uma inativação, e `admin_reactivate_card_variant_type()`
   * (Query 2157) recusa reativar um tipo já ativo, então não há risco de
   * dano real num clique acidental duplo.
   */
  async function handleReactivate(tipo: CardVariantTypeAdminRow) {
    setActionError(null);
    setReactivatingId(tipo.id);
    const result = await reactivateCardVariantType(tipo.id);
    setReactivatingId(null);
    if (result.error) {
      setActionError(result.error);
      return;
    }
    state.onSuccess("Tipo de variação reativado com sucesso.", tipo.id);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Tipos de Variação</PageTitle>
          </div>
          <PageDescription>
            Taxonomia canônica de Card Variant Type — acabamentos e versões colecionáveis reconhecidas pelo
            catálogo (ex.: Holográfica, Holográfica Reversa, Poké Bola Reversa).
          </PageDescription>
        </PageHeading>
      </PageHeader>

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}
      {actionError && <InlineFeedback tone="error">{actionError}</InlineFeedback>}

      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Novo Tipo de Variação
          </Button>
        </div>

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
                placeholder="Buscar por nome, código ou descrição…"
                className="h-9 bg-surface-muted pl-9 text-xs"
                aria-label="Buscar Tipo de Variação"
              />
            </div>
          </div>

          <CardContent density="compact" className="px-0 pb-0">
            {tiposVariacao.length === 0 ? (
              <EmptyState
                title="Nenhum tipo de variação cadastrado ainda"
                description='Use o botão "Novo Tipo de Variação" para começar.'
              />
            ) : filtrados.length === 0 ? (
              <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome, código ou descrição." />
            ) : (
              <DataTable>
                <DataTableHead>
                  <DataTableHeadRow className="bg-surface-muted">
                    <DataTableHeadCell align="center" className="pl-4">
                      Nome
                    </DataTableHeadCell>
                    <DataTableHeadCell align="center">Código</DataTableHeadCell>
                    <DataTableHeadCell align="center">Descrição</DataTableHeadCell>
                    <DataTableHeadCell align="center">Ordem</DataTableHeadCell>
                    <DataTableHeadCell align="center">Status</DataTableHeadCell>
                    <DataTableHeadCell align="center">Atualizado em</DataTableHeadCell>
                    <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                      Ações
                    </DataTableHeadCell>
                  </DataTableHeadRow>
                </DataTableHead>
                <tbody>
                  {itensPagina.map((tipo) => (
                    <DataTableRow key={tipo.id} highlighted={state.highlightId === tipo.id}>
                      <DataTableCell align="center" className="pl-4 text-foreground">
                        {tipo.name}
                      </DataTableCell>
                      <DataTableCell align="center">
                        <code className="text-xs text-muted-foreground">{tipo.code}</code>
                      </DataTableCell>
                      <DataTableCell align="center" className="max-w-xs">
                        {tipo.description ? (
                          <span className="line-clamp-2 text-xs text-muted-foreground">{tipo.description}</span>
                        ) : (
                          <span className="text-xs text-muted-foreground">—</span>
                        )}
                      </DataTableCell>
                      <DataTableCell align="center">{tipo.displayOrder}</DataTableCell>
                      <DataTableCell align="center">
                        {tipo.isActive ? (
                          <Badge variant="outline">Ativo</Badge>
                        ) : (
                          <Badge variant="warning">Inativo</Badge>
                        )}
                      </DataTableCell>
                      <DataTableCell align="center">{formatarData(tipo.updatedAt)}</DataTableCell>
                      <DataTableCell align="center" className="pr-4 last:pr-4">
                        <div className="flex justify-center gap-2">
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Editar ${tipo.name}`}
                            onClick={() => state.startEdit(tipo.id)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          {tipo.isActive ? (
                            <Button
                              type="button"
                              variant="outline"
                              size="icon-sm"
                              aria-label={`Inativar ${tipo.name}`}
                              onClick={() => setDeactivatingTipo(tipo)}
                            >
                              <EyeOff className="h-3.5 w-3.5" />
                            </Button>
                          ) : (
                            <Button
                              type="button"
                              variant="outline"
                              size="icon-sm"
                              aria-label={`Reativar ${tipo.name}`}
                              disabled={reactivatingId === tipo.id}
                              onClick={() => handleReactivate(tipo)}
                            >
                              <Eye className="h-3.5 w-3.5" />
                            </Button>
                          )}
                        </div>
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
                Mostrando{" "}
                <span className="font-medium text-foreground">
                  {formatNumber(paginaAtual * TIPOS_VARIACAO_PAGE_SIZE + 1)}
                </span>
                –
                <span className="font-medium text-foreground">
                  {formatNumber(Math.min((paginaAtual + 1) * TIPOS_VARIACAO_PAGE_SIZE, totalCount))}
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
      </div>

      <CreateTipoVariacaoDialog
        open={state.creating}
        nextDisplayOrder={nextDisplayOrder}
        onSaved={handleSaved}
        onCancel={state.cancelCreate}
      />

      <EditTipoVariacaoDialog
        open={editingTipo !== null}
        tipo={editingTipo}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />

      <DeactivateTipoVariacaoDialog
        open={deactivatingTipo !== null}
        tipo={deactivatingTipo}
        onConfirmed={handleDeactivated}
        onCancel={() => setDeactivatingTipo(null)}
      />
    </div>
  );
}

function CreateTipoVariacaoDialog({
  open,
  nextDisplayOrder,
  onSaved,
  onCancel,
}: {
  open: boolean;
  nextDisplayOrder: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        className="max-w-lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Novo Tipo de Variação</DialogTitle>
          <DialogDescription>Cadastre um novo Card Variant Type canônico no catálogo.</DialogDescription>
        </DialogHeader>

        {open && (
          <CreateTipoVariacaoForm
            nextDisplayOrder={nextDisplayOrder}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function CreateTipoVariacaoForm({
  nextDisplayOrder,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  nextDisplayOrder: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createCardVariantType, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Tipo de variação cadastrado com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-variant-type-code">Código</Label>
            <Input
              id="new-variant-type-code"
              name="code"
              placeholder="Ex.: SET_LOGO_REVERSE"
              required
              maxLength={50}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-variant-type-name">Nome</Label>
            <Input
              id="new-variant-type-name"
              name="name"
              placeholder="Ex.: Logo da Coleção Reverso"
              required
              maxLength={100}
            />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-variant-type-description">Descrição (opcional)</Label>
          <textarea
            id="new-variant-type-description"
            name="description"
            placeholder="Explicação permanente do significado deste tipo de variação."
            maxLength={500}
            className={textareaClassName}
          />
        </div>

        <div className="grid grid-cols-[minmax(6rem,1fr)] gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-variant-type-order">Ordem</Label>
            <Input
              id="new-variant-type-order"
              name="displayOrder"
              type="number"
              min={1}
              defaultValue={nextDisplayOrder}
              required
            />
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Tipo de Variação"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function EditTipoVariacaoDialog({
  open,
  tipo,
  onSaved,
  onCancel,
}: {
  open: boolean;
  tipo: CardVariantTypeAdminRow | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        className="max-w-lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Tipo de Variação</DialogTitle>
          <DialogDescription>Código é imutável após o cadastro.</DialogDescription>
        </DialogHeader>

        {open && tipo && (
          <EditTipoVariacaoForm
            key={tipo.id}
            tipo={tipo}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditTipoVariacaoForm({
  tipo,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  tipo: CardVariantTypeAdminRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateCardVariantType, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Tipo de variação atualizado com sucesso.", tipo.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={tipo.id} />
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-variant-type-code-${tipo.id}`} className="text-muted-foreground">
              Código (imutável)
            </Label>
            <Input id={`edit-variant-type-code-${tipo.id}`} value={tipo.code} disabled />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-variant-type-name-${tipo.id}`}>Nome</Label>
            <Input
              id={`edit-variant-type-name-${tipo.id}`}
              name="name"
              defaultValue={tipo.name}
              required
              maxLength={100}
            />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-variant-type-description-${tipo.id}`}>Descrição (opcional)</Label>
          <textarea
            id={`edit-variant-type-description-${tipo.id}`}
            name="description"
            defaultValue={tipo.description ?? ""}
            maxLength={500}
            className={textareaClassName}
          />
        </div>

        <div className="grid grid-cols-[minmax(6rem,1fr)] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-variant-type-order-${tipo.id}`}>Ordem</Label>
            <Input
              id={`edit-variant-type-order-${tipo.id}`}
              name="displayOrder"
              type="number"
              min={1}
              defaultValue={tipo.displayOrder}
              required
            />
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function DeactivateTipoVariacaoDialog({
  open,
  tipo,
  onConfirmed,
  onCancel,
}: {
  open: boolean;
  tipo: CardVariantTypeAdminRow | null;
  onConfirmed: () => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) setError(null);
  }, [open]);

  async function handleConfirm() {
    if (!tipo) return;
    setPending(true);
    setError(null);
    const result = await deactivateCardVariantType(tipo.id);
    setPending(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    onConfirmed();
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Inativar Tipo de Variação</DialogTitle>
          <DialogDescription>
            {tipo ? `${tipo.name} (${tipo.code})` : "Este tipo de variação"} deixa de aparecer como opção em novos
            cadastros e mappings. Card Variants e mapeamentos externos já existentes com este tipo não são
            afetados — nenhum dado é apagado, e o tipo pode ser reativado a qualquer momento.
          </DialogDescription>
        </DialogHeader>

        {error && (
          <DialogBody>
            <InlineFeedback tone="error">{error}</InlineFeedback>
          </DialogBody>
        )}

        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
            Cancelar
          </Button>
          <Button type="button" variant="destructive" size="sm" onClick={handleConfirm} disabled={pending}>
            {pending ? "Inativando…" : "Inativar"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
