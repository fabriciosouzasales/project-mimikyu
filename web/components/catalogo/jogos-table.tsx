"use client";

import { Pencil } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createGame, deleteGames, updateGame, type GameActionState } from "@/app/catalogo/jogos/actions";
import { AdminToolbar } from "@/components/catalogo/admin-toolbar";
import { BulkSelectionBar } from "@/components/catalogo/bulk-selection-bar";
import { ConfirmDeleteBar } from "@/components/catalogo/confirm-delete-bar";
import { SuccessBanner } from "@/components/catalogo/success-banner";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { cn } from "@/lib/utils";
import { formatarData } from "@/lib/format-date";
import type { JogoRow } from "@/lib/catalogo/queries";

const initialState: GameActionState = { error: null };

export function JogosTable({ jogos }: { jogos: JogoRow[] }) {
  const router = useRouter();
  const state = useAdminListState();

  const selectedJogos = jogos.filter((j) => state.selectedIds.has(j.id));
  const allSelected = jogos.length > 0 && state.selectedIds.size === jogos.length;

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  function handleDeleted() {
    state.onSuccess("Jogo(s) excluído(s) com sucesso.");
    router.refresh();
  }

  function handlePartialDeleteFailure() {
    // Alguns itens já foram removidos no banco — atualiza a tabela, mas a
    // barra de confirmação permanece aberta (cuidado de use-admin-list-state)
    // mostrando o motivo da falha nos itens restantes.
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <AdminToolbar title="Jogos" createLabel="Cadastrar novo jogo" onCreateClick={state.startCreate} />

      {state.successMessage && <SuccessBanner message={state.successMessage} />}

      {state.creating && (
        <CreateGameForm onSaved={handleSaved} onCancel={state.cancelCreate} />
      )}

      {!state.isFormOpen && state.selectedIds.size > 0 && !state.confirmingDelete && (
        <BulkSelectionBar
          count={state.selectedIds.size}
          nounSingular="jogo selecionado"
          nounPlural="jogos selecionados"
          onClear={state.clearSelection}
          onDeleteClick={state.startConfirmDelete}
        />
      )}

      {!state.isFormOpen && state.confirmingDelete && (
        <ConfirmDeleteBar
          items={selectedJogos.map((j) => ({ id: j.id, label: `${j.name} (${j.code})` }))}
          action={deleteGames}
          nounSingular="jogo"
          nounPlural="jogos"
          onDone={handleDeleted}
          onPartialSuccess={handlePartialDeleteFailure}
          onCancel={state.cancelConfirmDelete}
        />
      )}

      <Panel>
        <PanelHeader>
          <PanelTitle>Jogos cadastrados</PanelTitle>
        </PanelHeader>
        <PanelContent>
          {jogos.length === 0 ? (
            <div className="flex flex-col items-center gap-1 py-10 text-center">
              <p className="text-sm text-foreground">Nenhum jogo cadastrado ainda</p>
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                  <th className="w-8 py-1.5 pr-1">
                    <input
                      type="checkbox"
                      aria-label="Selecionar todos os jogos"
                      checked={allSelected}
                      disabled={state.isFormOpen}
                      onChange={() => state.toggleAll(jogos.map((j) => j.id))}
                      className={cn(
                        "h-3.5 w-3.5 rounded border-border accent-primary",
                        state.isFormOpen && "cursor-not-allowed opacity-40",
                      )}
                    />
                  </th>
                  <th className="py-1.5 pr-3 font-normal">Jogo</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Código</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Expansões</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Criado em</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Atualizado em</th>
                  <th className="py-1.5 font-normal" />
                </tr>
              </thead>
              <tbody>
                {jogos.map((jogo) =>
                  state.editingId === jogo.id ? (
                    <EditGameRow key={jogo.id} jogo={jogo} onSaved={handleSaved} onCancel={state.cancelEdit} />
                  ) : (
                    <tr
                      key={jogo.id}
                      className={cn(
                        "border-b border-border/60 transition-colors duration-700 last:border-b-0",
                        state.highlightId === jogo.id && "bg-primary/5",
                      )}
                    >
                      <td className="py-2 pr-1">
                        <input
                          type="checkbox"
                          aria-label={`Selecionar ${jogo.name}`}
                          checked={state.selectedIds.has(jogo.id)}
                          disabled={state.isFormOpen}
                          onChange={() => state.toggleOne(jogo.id)}
                          className={cn(
                            "h-3.5 w-3.5 rounded border-border accent-primary",
                            state.isFormOpen && "cursor-not-allowed opacity-40",
                          )}
                        />
                      </td>
                      <td className="py-2 pr-3 text-foreground">{jogo.name}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{jogo.code}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">
                        <Link
                          href={`/catalogo/expansoes?game=${jogo.code}`}
                          className="underline-offset-2 hover:text-foreground hover:underline"
                        >
                          {jogo.totalExpansoes}
                        </Link>
                      </td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{formatarData(jogo.createdAt)}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{formatarData(jogo.updatedAt)}</td>
                      <td className="py-2 text-right">
                        <Button
                          type="button"
                          variant="outline"
                          size="icon-sm"
                          aria-label={`Editar ${jogo.name}`}
                          onClick={() => state.startEdit(jogo.id)}
                        >
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          )}
        </PanelContent>
      </Panel>
    </div>
  );
}

function CreateGameForm({
  onSaved,
  onCancel,
}: {
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [state, formAction, pending] = useActionState(createGame, initialState);

  useEffect(() => {
    if (state.success) {
      onSaved("Jogo cadastrado com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction} className="space-y-3 rounded-md border border-border bg-surface-muted p-3">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="new-game-code">Código</Label>
          <Input id="new-game-code" name="code" placeholder="Ex.: POKEMON_TCG" required maxLength={50} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="new-game-name">Nome</Label>
          <Input id="new-game-name" name="name" placeholder="Ex.: Pokémon Trading Card Game" required maxLength={150} />
        </div>
      </div>

      {state.error && <p className="text-xs text-destructive">{state.error}</p>}

      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Jogo"}
        </Button>
      </div>
    </form>
  );
}

function EditGameRow({
  jogo,
  onSaved,
  onCancel,
}: {
  jogo: JogoRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [state, formAction, pending] = useActionState(updateGame, initialState);

  useEffect(() => {
    if (state.success) {
      onSaved("Jogo atualizado com sucesso.", jogo.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <tr className="border-b border-border/60 last:border-b-0 bg-surface-muted">
      <td className="py-2 pr-3" colSpan={7}>
        <form action={formAction} className="flex flex-wrap items-end gap-3">
          <input type="hidden" name="id" value={jogo.id} />
          <div className="space-y-1">
            <Label htmlFor={`edit-game-name-${jogo.id}`}>Nome</Label>
            <Input
              id={`edit-game-name-${jogo.id}`}
              name="name"
              defaultValue={jogo.name}
              required
              maxLength={150}
              className="min-w-[240px]"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-muted-foreground">Código (imutável)</Label>
            <Input value={jogo.code} disabled className="min-w-[160px]" />
          </div>

          {state.error && <p className="text-xs text-destructive">{state.error}</p>}

          <div className="ml-auto flex gap-2">
            <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
              Cancelar
            </Button>
            <Button type="submit" size="sm" disabled={pending}>
              {pending ? "Salvando…" : "Salvar"}
            </Button>
          </div>
        </form>
      </td>
    </tr>
  );
}
