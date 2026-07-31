"use client";

import { ChevronLeft, ChevronRight, Gamepad2, Pencil, Plus, Trash2 } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createGame, deleteGames, updateGame, type GameActionState } from "@/app/catalogo/jogos/actions";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { ConfirmDeleteBar } from "@/components/catalogo/confirm-delete-bar";
import { JogosStats } from "@/components/catalogo/jogos-stats";
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
import { JOGOS_PAGE_SIZE } from "@/lib/catalogo/queries";
import type { JogoRow } from "@/lib/catalogo/queries";

const initialState: GameActionState = { error: null };

/**
 * Tela Jogos — redesenhada em 2026-07-31 para o mesmo padrão das telas
 * Expansão/Card Set (pedido explícito de Fabrício): cadastro e edição
 * migraram de formulário/linha editável direto na página para `Dialog`
 * (`CreateGameDialog`/`EditGameDialog`, mesmo mecanismo de isolamento de
 * estado por abertura já usado em Expansão — montagem condicional do
 * formulário interno + `key` por entidade na edição). Cabeçalho da página
 * (título + ação "Novo Jogo") fica acima dos indicadores (`JogosStats`),
 * que por sua vez ficam acima da busca e da tabela — nessa ordem porque o
 * botão "Novo Jogo" precisa do mesmo estado (`useAdminListState`) que abre
 * os Dialogs, então todo o bloco vive neste componente cliente.
 *
 * Tabela: busca no topo (`CatalogoSearchBar`, mesmo componente/padrão da
 * tela Expansões — sem o dropdown de Jogo, que não faz sentido aqui, já
 * que Jogo é a própria entidade listada), paginação server-driven via
 * `?page=` (links simples, sem JS extra), cabeçalho com fundo destacado
 * (`bg-surface-muted`, diferente das linhas de dado) e ações rápidas
 * (editar/excluir) por linha — sem seleção em massa/checkboxes:
 * `state.startQuickDelete(id)` seleciona só aquele item e já abre a
 * confirmação inline (`ConfirmDeleteBar`, reaproveitado sem alteração).
 *
 * `AdminToolbar`/`SuccessBanner`/`BulkSelectionBar` deixam de ser usados
 * por esta tela (só ela os usava) — não removidos, ver relatório de
 * pendências.
 */
export function JogosTable({
  jogos,
  items,
  totalCount,
  page,
  query,
}: {
  /** Lista completa, sem paginação/filtro — só para `JogosStats`. */
  jogos: JogoRow[];
  /** Página atual da tabela (já filtrada/paginada pelo servidor). */
  items: JogoRow[];
  totalCount: number;
  page: number;
  query: string;
}) {
  const router = useRouter();
  const state = useAdminListState();

  const editingJogo = items.find((j) => j.id === state.editingId) ?? null;
  const jogoToDelete = items.find((j) => state.selectedIds.has(j.id)) ?? null;
  const totalPages = Math.max(1, Math.ceil(totalCount / JOGOS_PAGE_SIZE));

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  function handleDeleted() {
    state.onSuccess("Jogo excluído com sucesso.");
    router.refresh();
  }

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/catalogo/jogos?${qs}` : "/catalogo/jogos";
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Gamepad2 className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Jogos</PageTitle>
          </div>
          <PageDescription>Cadastro e edição de Jogos do catálogo.</PageDescription>
        </PageHeading>
      </PageHeader>

      <JogosStats jogos={jogos} />

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      {state.confirmingDelete && jogoToDelete && (
        <ConfirmDeleteBar
          items={[{ id: jogoToDelete.id, label: `${jogoToDelete.name} (${jogoToDelete.code})` }]}
          action={deleteGames}
          nounSingular="jogo"
          nounPlural="jogos"
          onDone={handleDeleted}
          onPartialSuccess={() => router.refresh()}
          onCancel={state.cancelConfirmDelete}
        />
      )}

      {/* Ajuste (2026-07-31, cópia fiel do modelo de referência): a busca
          deixa de ficar fora do card e passa a viver dentro dele, imediatamente
          acima do cabeçalho da tabela — separada só por uma borda inferior,
          no lugar do antigo cabeçalho "Jogos cadastrados" do card. "Novo
          Jogo" continua fora, mas com espaçamento apertado (space-y-2) até
          o card logo abaixo — é o card, agora, que é o "vizinho" próximo do
          botão, não mais a busca isoladamente. */}
      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Novo Jogo
          </Button>
        </div>

        <Card density="compact" className="overflow-hidden">
          <div className="border-b border-border p-4">
            <CatalogoSearchBar
              initialQuery={query}
              placeholder="Buscar por nome ou código do Jogo…"
              className="h-9 bg-surface-muted text-xs"
            />
          </div>
          {/* Sem padding aqui (px-0 pb-0): a tabela fica rente às bordas do
              card, como no modelo de referência — o inset de leitura vem do
              padding de cada célula (pl-4/pr-4 nas pontas), não mais de uma
              margem do container. */}
          <CardContent density="compact" className="px-0 pb-0">
            {items.length === 0 ? (
              query ? (
                <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome ou código." />
              ) : (
                <EmptyState
                  title="Nenhum jogo cadastrado ainda"
                  description='Use o botão "Novo Jogo" para começar.'
                />
              )
            ) : (
              <DataTable>
                <DataTableHead>
                  <DataTableHeadRow className="bg-surface-muted">
                    <DataTableHeadCell align="center" className="px-4">
                      Nome do Jogo
                    </DataTableHeadCell>
                    <DataTableHeadCell align="center">Código</DataTableHeadCell>
                    <DataTableHeadCell align="center">Expansões</DataTableHeadCell>
                    <DataTableHeadCell align="center">Criado em</DataTableHeadCell>
                    <DataTableHeadCell align="center">Atualizado em</DataTableHeadCell>
                    <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                      Ações
                    </DataTableHeadCell>
                  </DataTableHeadRow>
                </DataTableHead>
                <tbody>
                  {items.map((jogo) => (
                    <DataTableRow key={jogo.id} highlighted={state.highlightId === jogo.id}>
                      <DataTableCell className="pl-4 text-foreground">{jogo.name}</DataTableCell>
                      <DataTableCell align="center">{jogo.code}</DataTableCell>
                      <DataTableCell align="center">
                        <Link
                          href={`/catalogo/expansoes?game=${jogo.code}`}
                          className="underline-offset-2 hover:text-foreground hover:underline"
                        >
                          {jogo.totalExpansoes}
                        </Link>
                      </DataTableCell>
                      <DataTableCell align="center">{formatarData(jogo.createdAt)}</DataTableCell>
                      <DataTableCell align="center">{formatarData(jogo.updatedAt)}</DataTableCell>
                      <DataTableCell align="center" className="pr-4 last:pr-4">
                        <div className="flex justify-center gap-2">
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Editar ${jogo.name}`}
                            onClick={() => state.startEdit(jogo.id)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            className="text-destructive hover:bg-destructive/10 hover:text-destructive dark:text-destructive-foreground dark:hover:text-destructive-foreground"
                            aria-label={`Excluir ${jogo.name}`}
                            onClick={() => state.startQuickDelete(jogo.id)}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </DataTableCell>
                    </DataTableRow>
                  ))}
                </tbody>
              </DataTable>
            )}
          </CardContent>

        {/* Paginação dentro do próprio card da tabela (cópia fiel do
            modelo de referência anexado por Fabrício, 2026-07-31) — antes
            vivia numa linha separada, fora do card; a borda superior
            (`border-t`) faz a mesma função de separador que o modelo de
            referência usa, sem precisar de um segundo container. Setas em
            botão-ícone (Chevron) + "página atual/total" no lugar dos
            antigos botões de texto "Anterior"/"Próxima". */}
        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * JOGOS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * JOGOS_PAGE_SIZE, totalCount)}
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
        </Card>
      </div>

      <CreateGameDialog open={state.creating} onSaved={handleSaved} onCancel={state.cancelCreate} />

      <EditGameDialog
        open={editingJogo !== null}
        jogo={editingJogo}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}

function CreateGameDialog({
  open,
  onSaved,
  onCancel,
}: {
  open: boolean;
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
          <DialogTitle>Novo Jogo</DialogTitle>
          <DialogDescription>Cadastre um novo Jogo no catálogo.</DialogDescription>
        </DialogHeader>

        {/* Montagem condicional: o formulário só existe enquanto o Dialog
            está aberto, para que `useActionState` comece do zero a cada
            abertura — mesmo padrão de Expansão. `Dialog`/`DialogContent`
            continuam sempre montados, preservando a animação de saída. */}
        {open && <CreateGameForm onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />}
      </DialogContent>
    </Dialog>
  );
}

function CreateGameForm({
  onSaved,
  onCancel,
  onPendingChange,
}: {
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createGame, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Jogo cadastrado com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        {/* Ajuste de layout (2026-07-31, /impeccable layout): colunas
            assimétricas (Código menor, Nome maior) em vez de grid-cols-2
            (50/50) — Código é curto por natureza ("POKEMON_TCG"), Nome
            precisa de bem mais espaço ("Pokémon Trading Card Game"); um
            grid igual espremia justamente o campo que mais precisa de
            largura. Combinado com o Dialog mais largo (max-w-lg), acaba com
            o aperto apontado por Fabrício. */}
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-game-code">Código</Label>
            <Input id="new-game-code" name="code" placeholder="Ex.: POKEMON_TCG" required maxLength={50} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-game-name">Nome</Label>
            <Input id="new-game-name" name="name" placeholder="Ex.: Pokémon Trading Card Game" required maxLength={150} />
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Jogo"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function EditGameDialog({
  open,
  jogo,
  onSaved,
  onCancel,
}: {
  open: boolean;
  jogo: JogoRow | null;
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
          <DialogTitle>Editar Jogo</DialogTitle>
          <DialogDescription>Código é imutável após o cadastro.</DialogDescription>
        </DialogHeader>

        {/* `key={jogo.id}` isola o estado por entidade: trocar qual Jogo
            está sendo editado remonta o formulário — mesmo padrão de
            Expansão. */}
        {open && jogo && (
          <EditGameForm key={jogo.id} jogo={jogo} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditGameForm({
  jogo,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  jogo: JogoRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateGame, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Jogo atualizado com sucesso.", jogo.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={jogo.id} />
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-game-code-${jogo.id}`} className="text-muted-foreground">
              Código (imutável)
            </Label>
            <Input id={`edit-game-code-${jogo.id}`} value={jogo.code} disabled />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-game-name-${jogo.id}`}>Nome</Label>
            <Input
              id={`edit-game-name-${jogo.id}`}
              name="name"
              defaultValue={jogo.name}
              required
              maxLength={150}
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
