"use client";

import { useActionState, useEffect, useState } from "react";
import { updateCardSet } from "@/app/catalogo/card-sets/actions";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { CardSetActionState } from "@/app/catalogo/card-sets/actions";
import type { CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";

const initialState: CardSetActionState = { error: null };

/**
 * Dialog de edição de Card Set — novo em 2026-07-31 (pedido de Fabrício:
 * "inclusão dos botões de edição e exclusão em cada Card Set... mesmo padrão
 * da página Expansões"). Cópia fiel do `EditExpansionDialog` já corrigido
 * pelo ciclo de layout daquela tela (`expansoes-table.tsx`): campos
 * imutáveis (Jogo/Expansão/Código) saem do corpo do formulário e viram a
 * `DialogDescription` do cabeçalho — `"{Jogo} · {Expansão} · {Código}"`, um
 * nível a mais que Expansão porque Card Set tem mais um ancestral —, Dialog
 * `size="lg"` para não truncar nomes longos. Só Nome e Ordem de lançamento
 * são editáveis, mesmo escopo mínimo do Dialog de Expansão antes de ganhar a
 * logo — upload de logo de Card Set não faz parte deste pedido (o bucket
 * `card-set-logo`/`admin_set_card_set_logo()` já existe desde ADR-022, mas
 * sem nenhum uploader no frontend ainda; fica para um pedido futuro, se
 * Fabrício quiser o mesmo recurso aqui).
 */
export function EditCardSetDialog({
  open,
  cardSet,
  onSaved,
  onCancel,
}: {
  open: boolean;
  cardSet: CardSetWithLogo | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Card Set</DialogTitle>
          {/* Fallback estático só aparece durante o frame de saída do
              Dialog, quando `cardSet` já voltou a `null` mas o Radix ainda
              está animando o fechamento — nunca visível em uso normal (mesmo
              cuidado já aplicado em `EditExpansionDialog`). */}
          <DialogDescription>
            {cardSet
              ? `${cardSet.gameName} · ${cardSet.expansionName} · ${cardSet.code}`
              : "Jogo, Expansão e Código são imutáveis após o cadastro."}
          </DialogDescription>
        </DialogHeader>

        {/* `key={cardSet.id}` isola o estado por entidade — trocar qual Card
            Set está sendo editado remonta o formulário, mesmo padrão de
            Expansão/Game. */}
        {open && cardSet && (
          <EditCardSetForm key={cardSet.id} cardSet={cardSet} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditCardSetForm({
  cardSet,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  cardSet: CardSetWithLogo;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateCardSet, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Card Set atualizado com sucesso.", cardSet.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={cardSet.id} />
      <DialogBody className="space-y-4">
        <div className="space-y-1">
          <Label htmlFor={`edit-card-set-name-${cardSet.id}`}>Nome</Label>
          <Input
            id={`edit-card-set-name-${cardSet.id}`}
            name="name"
            defaultValue={cardSet.name}
            required
            maxLength={150}
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-card-set-order-${cardSet.id}`}>Ordem de lançamento</Label>
          <Input
            id={`edit-card-set-order-${cardSet.id}`}
            name="release_order"
            type="number"
            min={1}
            step={1}
            defaultValue={cardSet.releaseOrder}
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
