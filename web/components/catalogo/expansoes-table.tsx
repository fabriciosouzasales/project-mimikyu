"use client";

import { Pencil, Plus } from "lucide-react";
import { Fragment, useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createExpansion, updateExpansion, type ExpansionActionState } from "@/app/catalogo/expansoes/actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
import { PageActions, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { cn } from "@/lib/utils";
import { formatarData } from "@/lib/format-date";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

const initialState: ExpansionActionState = { error: null };

/** Colunas de dado da tabela (usado no `colSpan` do separador de grupo). */
const TABLE_COLUMN_COUNT = 7;

/**
 * Tela piloto da fundação visual (Ciclo C, 2026-07-30, ver STD-004) — mesma
 * lógica de `useAdminListState`/Server Actions de antes; criação e edição
 * migradas de formulário permanente (acima da tabela / linha expandida)
 * para `Dialog`. `Panel`/`AdminToolbar`/`SuccessBanner` (usados por Jogos)
 * não são tocados aqui — só deixam de ser usados nesta tela. Sem seleção em
 * massa/exclusão: ADR-023 não prevê para Expansion, só Game recebeu essa
 * emenda. `defaultGameId`, quando presente (filtro `?game=` da página),
 * pré-seleciona o Jogo no formulário de cadastro.
 *
 * Ciclo D.2 (2026-07-30, correção pós-auditoria): tabela agrupada por Jogo
 * — grupos ordenados por nome, Expansions por `releaseOrder` dentro de cada
 * grupo. Sem essa separação, a "ordem de lançamento" de Jogos diferentes
 * ficava intercalada sem sentido (ordem 1 de um Jogo não se compara à de
 * outro). A coluna "Jogo" foi removida da tabela — o cabeçalho de cada
 * grupo já identifica o Jogo, a coluna virou repetição; ela continua
 * aparecendo, como campo imutável, no Dialog de edição.
 */
export function ExpansoesTable({
  expansoes,
  jogos,
  defaultGameId,
}: {
  expansoes: ExpansaoRow[];
  jogos: GameOption[];
  defaultGameId?: string;
}) {
  const router = useRouter();
  const state = useAdminListState();

  const editingExpansao = expansoes.find((e) => e.id === state.editingId) ?? null;
  const groups = groupByGame(expansoes);

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Expansões</PageTitle>
          <PageDescription>Cadastro e edição de Expansões vinculadas a um Jogo.</PageDescription>
        </PageHeading>
        <PageActions>
          <Button type="button" variant="outline-primary" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Nova expansão
          </Button>
        </PageActions>
      </PageHeader>

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card density="compact">
        <CardHeader density="compact">
          <CardTitle density="compact">Expansões cadastradas</CardTitle>
        </CardHeader>
        <CardContent density="compact">
          {expansoes.length === 0 ? (
            <EmptyState title="Nenhuma expansão cadastrada ainda" />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow>
                  <DataTableHeadCell>Expansão</DataTableHeadCell>
                  <DataTableHeadCell align="center">Código</DataTableHeadCell>
                  <DataTableHeadCell align="center">Ordem</DataTableHeadCell>
                  <DataTableHeadCell align="center">Coleções</DataTableHeadCell>
                  <DataTableHeadCell align="center">Criado em</DataTableHeadCell>
                  <DataTableHeadCell align="center">Atualizado em</DataTableHeadCell>
                  <DataTableHeadCell />
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {groups.map((group, index) => (
                  <Fragment key={group.gameName}>
                    <tr className={cn(index > 0 && "border-t border-border/60")}>
                      <td
                        colSpan={TABLE_COLUMN_COUNT}
                        className="pb-1.5 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground"
                      >
                        {group.gameName}
                      </td>
                    </tr>
                    {group.items.map((expansao) => (
                      <DataTableRow key={expansao.id} highlighted={state.highlightId === expansao.id}>
                        <DataTableCell className="text-foreground">{expansao.name}</DataTableCell>
                        <DataTableCell align="center">{expansao.code}</DataTableCell>
                        <DataTableCell align="center">{expansao.releaseOrder}</DataTableCell>
                        <DataTableCell align="center">{expansao.totalCardSets}</DataTableCell>
                        <DataTableCell align="center">{formatarData(expansao.createdAt)}</DataTableCell>
                        <DataTableCell align="center">{formatarData(expansao.updatedAt)}</DataTableCell>
                        <DataTableCell align="right">
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Editar ${expansao.name}`}
                            onClick={() => state.startEdit(expansao.id)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                        </DataTableCell>
                      </DataTableRow>
                    ))}
                  </Fragment>
                ))}
              </tbody>
            </DataTable>
          )}
        </CardContent>
      </Card>

      <CreateExpansionDialog
        open={state.creating}
        jogos={jogos}
        defaultGameId={defaultGameId}
        onSaved={handleSaved}
        onCancel={state.cancelCreate}
      />

      <EditExpansionDialog
        open={editingExpansao !== null}
        expansao={editingExpansao}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}

/** Agrupa por Jogo (nome), grupos ordenados alfabeticamente; Expansions ordenadas por `releaseOrder` dentro de cada grupo. Puramente de apresentação — não altera o array recebido nem a query que o produziu. */
function groupByGame(expansoes: ExpansaoRow[]) {
  const byGame = new Map<string, ExpansaoRow[]>();
  for (const expansao of expansoes) {
    const group = byGame.get(expansao.gameName) ?? [];
    group.push(expansao);
    byGame.set(expansao.gameName, group);
  }
  return Array.from(byGame.entries())
    .sort(([a], [b]) => a.localeCompare(b, "pt-BR"))
    .map(([gameName, items]) => ({
      gameName,
      items: [...items].sort((a, b) => a.releaseOrder - b.releaseOrder),
    }));
}

/**
 * Exportado (2026-07-31) para reuso pelo redesenho da própria tela de
 * Expansões (`expansoes-gallery.tsx`, substitui `ExpansoesTable`/o layout de
 * tabela por uma galeria de cards, mesma linguagem visual da tela Catálogo)
 * e potencialmente por outras entidades — Dialog, guardas de `pending` e
 * isolamento de estado por abertura continuam idênticos.
 */
export function CreateExpansionDialog({
  open,
  jogos,
  defaultGameId,
  onSaved,
  onCancel,
}: {
  open: boolean;
  jogos: GameOption[];
  defaultGameId?: string;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Nova expansão</DialogTitle>
          <DialogDescription>Vincule a expansão a um Jogo já cadastrado.</DialogDescription>
        </DialogHeader>

        {/* Montagem condicional (Ciclo D.1, correção pós-auditoria): o
            formulário só existe enquanto o Dialog está aberto, para que
            `useActionState` comece do zero a cada abertura — sem isso, erro
            de um envio anterior ficava visível ao reabrir. `Dialog`/
            `DialogContent` continuam sempre montados, preservando o
            Presence do Radix e a animação de saída. */}
        {open && (
          <CreateExpansionForm
            jogos={jogos}
            defaultGameId={defaultGameId}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

/**
 * Exportado (2026-07-31) para reuso pela tela Catálogo (`novo-catalogo-dialog.tsx`),
 * que precisa do mesmo formulário de Expansão dentro de um Dialog próprio,
 * como uma das opções da ação "Novo" que cobre o domínio inteiro (Jogo/
 * Expansão/Card Set). Sem mudança de comportamento — só a visibilidade do
 * export.
 */
export function CreateExpansionForm({
  jogos,
  defaultGameId,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  jogos: GameOption[];
  defaultGameId?: string;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createExpansion, initialState);

  // Reporta `pending` para o Dialog (fora deste componente), que precisa
  // dele para bloquear Esc/clique fora enquanto o envio está em voo.
  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Expansão cadastrada com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor="new-expansion-game">Jogo</Label>
          <select
            id="new-expansion-game"
            name="game_id"
            required
            defaultValue={defaultGameId ?? ""}
            className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
          >
            <option value="" disabled>
              Selecione…
            </option>
            {jogos.map((jogo) => (
              <option key={jogo.id} value={jogo.id}>
                {jogo.name}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-expansion-code">Código</Label>
            <Input id="new-expansion-code" name="code" placeholder="Ex.: ME" required maxLength={50} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-expansion-release-order">Ordem de lançamento</Label>
            <Input
              id="new-expansion-release-order"
              name="release_order"
              type="number"
              min={1}
              step={1}
              placeholder="Ex.: 1"
              required
            />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-expansion-name">Nome</Label>
          <Input id="new-expansion-name" name="name" placeholder="Ex.: Mega Evolution" required maxLength={150} />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>

      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Expansão"}
        </Button>
      </DialogFooter>
    </form>
  );
}

/** Exportado (2026-07-31) pelo mesmo motivo de `CreateExpansionDialog` acima. */
export function EditExpansionDialog({
  open,
  expansao,
  onSaved,
  onCancel,
}: {
  open: boolean;
  expansao: ExpansaoRow | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar expansão</DialogTitle>
          <DialogDescription>Código e Jogo são imutáveis após o cadastro.</DialogDescription>
        </DialogHeader>

        {/* `key={expansao.id}` isola o estado por entidade (Ciclo D.1,
            correção pós-auditoria): trocar qual Expansion está sendo
            editada remonta o formulário — `useActionState` sempre começa
            limpo, nunca reaproveita erro/sucesso da Expansion anterior. */}
        {open && expansao && (
          <EditExpansionForm
            key={expansao.id}
            expansao={expansao}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditExpansionForm({
  expansao,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  expansao: ExpansaoRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateExpansion, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Expansão atualizada com sucesso.", expansao.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={expansao.id} />
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-expansion-code-${expansao.id}`} className="text-muted-foreground">
              Código (imutável)
            </Label>
            <Input id={`edit-expansion-code-${expansao.id}`} value={expansao.code} disabled />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-expansion-game-${expansao.id}`} className="text-muted-foreground">
              Jogo (imutável)
            </Label>
            <Input id={`edit-expansion-game-${expansao.id}`} value={expansao.gameName} disabled />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-expansion-name-${expansao.id}`}>Nome</Label>
          <Input
            id={`edit-expansion-name-${expansao.id}`}
            name="name"
            defaultValue={expansao.name}
            required
            maxLength={150}
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-expansion-order-${expansao.id}`}>Ordem de lançamento</Label>
          <Input
            id={`edit-expansion-order-${expansao.id}`}
            name="release_order"
            type="number"
            min={1}
            step={1}
            defaultValue={expansao.releaseOrder}
            required
          />
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
