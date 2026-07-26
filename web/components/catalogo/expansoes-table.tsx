"use client";

import { Pencil } from "lucide-react";
import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createExpansion, updateExpansion, type ExpansionActionState } from "@/app/catalogo/expansoes/actions";
import { AdminToolbar } from "@/components/catalogo/admin-toolbar";
import { SuccessBanner } from "@/components/catalogo/success-banner";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { cn } from "@/lib/utils";
import { formatarData } from "@/lib/format-date";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

const initialState: ExpansionActionState = { error: null };

/**
 * Tela de cadastro/edição de Expansões — mesmo padrão vertical de
 * `jogos-table.tsx` (useAdminListState, AdminToolbar, SuccessBanner,
 * destaque de linha), mas sem seleção em massa/exclusão: ADR-023 não prevê
 * (nem foi pedida) exclusão de Expansion, só Game recebeu essa emenda.
 * `defaultGameId`, quando presente (vindo do filtro `?game=` da página),
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

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <AdminToolbar title="Expansões" createLabel="Cadastrar nova expansão" onCreateClick={state.startCreate} />

      {state.successMessage && <SuccessBanner message={state.successMessage} />}

      {state.creating && (
        <CreateExpansionForm jogos={jogos} defaultGameId={defaultGameId} onSaved={handleSaved} onCancel={state.cancelCreate} />
      )}

      <Panel>
        <PanelHeader>
          <PanelTitle>Expansões cadastradas</PanelTitle>
        </PanelHeader>
        <PanelContent>
          {expansoes.length === 0 ? (
            <div className="flex flex-col items-center gap-1 py-10 text-center">
              <p className="text-sm text-foreground">Nenhuma expansão cadastrada ainda</p>
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                  <th className="py-1.5 pr-3 font-normal">Expansão</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Código</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Jogo</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Ordem</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Card Sets</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Criado em</th>
                  <th className="py-1.5 pr-3 text-center font-normal">Atualizado em</th>
                  <th className="py-1.5 font-normal" />
                </tr>
              </thead>
              <tbody>
                {expansoes.map((expansao) =>
                  state.editingId === expansao.id ? (
                    <EditExpansionRow
                      key={expansao.id}
                      expansao={expansao}
                      onSaved={handleSaved}
                      onCancel={state.cancelEdit}
                    />
                  ) : (
                    <tr
                      key={expansao.id}
                      className={cn(
                        "border-b border-border/60 transition-colors duration-700 last:border-b-0",
                        state.highlightId === expansao.id && "bg-primary/5",
                      )}
                    >
                      <td className="py-2 pr-3 text-foreground">{expansao.name}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{expansao.code}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{expansao.gameName}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{expansao.releaseOrder}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">{expansao.totalCardSets}</td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">
                        {formatarData(expansao.createdAt)}
                      </td>
                      <td className="py-2 pr-3 text-center text-muted-foreground">
                        {formatarData(expansao.updatedAt)}
                      </td>
                      <td className="py-2 text-right">
                        <Button
                          type="button"
                          variant="outline"
                          size="icon-sm"
                          aria-label={`Editar ${expansao.name}`}
                          disabled={state.isFormOpen}
                          onClick={() => state.startEdit(expansao.id)}
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

function CreateExpansionForm({
  jogos,
  defaultGameId,
  onSaved,
  onCancel,
}: {
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
    <form action={formAction} className="space-y-3 rounded-md border border-border bg-surface-muted p-3">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
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
        <div className="space-y-1">
          <Label htmlFor="new-expansion-code">Código</Label>
          <Input id="new-expansion-code" name="code" placeholder="Ex.: ME" required maxLength={50} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="new-expansion-name">Nome</Label>
          <Input id="new-expansion-name" name="name" placeholder="Ex.: Mega Evolution" required maxLength={150} />
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

      {state.error && <p className="text-xs text-destructive">{state.error}</p>}

      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Expansão"}
        </Button>
      </div>
    </form>
  );
}

function EditExpansionRow({
  expansao,
  onSaved,
  onCancel,
}: {
  expansao: ExpansaoRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [state, formAction, pending] = useActionState(updateExpansion, initialState);

  useEffect(() => {
    if (state.success) {
      onSaved("Expansão atualizada com sucesso.", expansao.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <tr className="border-b border-border/60 last:border-b-0 bg-surface-muted">
      <td className="py-2 pr-3" colSpan={8}>
        <form action={formAction} className="flex flex-wrap items-end gap-3">
          <input type="hidden" name="id" value={expansao.id} />
          <div className="space-y-1">
            <Label htmlFor={`edit-expansion-name-${expansao.id}`}>Nome</Label>
            <Input
              id={`edit-expansion-name-${expansao.id}`}
              name="name"
              defaultValue={expansao.name}
              required
              maxLength={150}
              className="min-w-[220px]"
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
              className="w-28"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-muted-foreground">Código (imutável)</Label>
            <Input value={expansao.code} disabled className="w-32" />
          </div>
          <div className="space-y-1">
            <Label className="text-muted-foreground">Jogo (imutável)</Label>
            <Input value={expansao.gameName} disabled className="min-w-[160px]" />
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
