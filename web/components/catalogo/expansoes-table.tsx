"use client";

import { Pencil, Plus } from "lucide-react";
import { useActionState, useEffect } from "react";
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
import { formatarData } from "@/lib/format-date";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

const initialState: ExpansionActionState = { error: null };

/**
 * Tela piloto da fundação visual (Ciclo C, 2026-07-30, ver STD-004) — mesma
 * lógica de `useAdminListState`/Server Actions de antes; criação e edição
 * migradas de formulário permanente (acima da tabela / linha expandida)
 * para `Dialog`. `Panel`/`AdminToolbar`/`SuccessBanner` (usados por Jogos)
 * não são tocados aqui — só deixam de ser usados nesta tela. Sem seleção em
 * massa/exclusão: ADR-023 não prevê para Expansion, só Game recebeu essa
 * emenda. `defaultGameId`, quando presente (filtro `?game=` da página),
 * pré-seleciona o Jogo no formulário de cadastro.
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
                  <DataTableHeadCell align="center">Jogo</DataTableHeadCell>
                  <DataTableHeadCell align="center">Ordem</DataTableHeadCell>
                  <DataTableHeadCell align="center">Card Sets</DataTableHeadCell>
                  <DataTableHeadCell align="center">Criado em</DataTableHeadCell>
                  <DataTableHeadCell align="center">Atualizado em</DataTableHeadCell>
                  <DataTableHeadCell />
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {expansoes.map((expansao) => (
                  <DataTableRow key={expansao.id} highlighted={state.highlightId === expansao.id}>
                    <DataTableCell className="text-foreground">{expansao.name}</DataTableCell>
                    <DataTableCell align="center">{expansao.code}</DataTableCell>
                    <DataTableCell align="center">{expansao.gameName}</DataTableCell>
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

function CreateExpansionDialog({
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
  const [state, formAction, pending] = useActionState(createExpansion, initialState);

  useEffect(() => {
    if (state.success) {
      onSaved("Expansão cadastrada com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

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
      </DialogContent>
    </Dialog>
  );
}

function EditExpansionDialog({
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
  const [state, formAction, pending] = useActionState(updateExpansion, initialState);

  useEffect(() => {
    if (state.success && expansao) {
      onSaved("Expansão atualizada com sucesso.", expansao.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

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

        {expansao && (
          <form action={formAction}>
            <input type="hidden" name="id" value={expansao.id} />
            <DialogBody className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label className="text-muted-foreground">Código (imutável)</Label>
                  <Input value={expansao.code} disabled />
                </div>
                <div className="space-y-1">
                  <Label className="text-muted-foreground">Jogo (imutável)</Label>
                  <Input value={expansao.gameName} disabled />
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
        )}
      </DialogContent>
    </Dialog>
  );
}
