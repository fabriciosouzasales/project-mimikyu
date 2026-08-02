"use client";

import { useActionState, useEffect, useState } from "react";
import { updateCardSet } from "@/app/catalogo/card-sets/actions";
import { CardSetLogoUploader } from "@/components/catalogo/card-set-logo-uploader";
import { SET_TYPE_OPTIONS } from "@/components/catalogo/novo-catalogo-dialog";
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
 * `size="lg"` para não truncar nomes longos.
 *
 * Logo (2026-07-31, mesmo dia, pedido de Fabrício: "tela de edição não
 * permite inclusão, alteração e remoção da logo do card Set. Use o mesmo
 * padrão da tela de edição de Expansão") — `CardSetLogoUploader` incluído
 * no corpo do formulário, mesma posição de `ExpansaoLogoUploader` em
 * `EditExpansionForm`. `onLogoUpdated` só chama `router.refresh()`, sem
 * fechar o Dialog nem mostrar o banner de sucesso do formulário nome/ordem
 * — ações independentes, mesmo comportamento de Expansão.
 *
 * Ajuste 2026-07-31, rodada seguinte (pedido explícito de Fabrício: "na
 * tela de edição do set card deve ser permitido editar o tipo e a data de
 * lançamento. Da forma como está, só consigo editar o nome e a ordem de
 * lançamento") — campos Tipo (mesmo `SET_TYPE_OPTIONS` do formulário de
 * criação, `novo-catalogo-dialog.tsx`) e Data de lançamento adicionados.
 * `expansion_id`/`code`/`base_set_size`/`total_set_size` continuam de fora
 * (não pedidos, e ainda imutáveis/estruturais por decisão do ADR-023).
 *
 * Ajuste 2026-08-01 (ADR-023, emenda "Card Set: código editável sem Cards
 * cadastradas", Query 2048 v3.0/Migration 2091) — motivado por um erro real
 * de cadastro (Coleção "151" com código SV4 em vez de MEW): Código sai da
 * `DialogDescription` estática (onde vivia junto com Jogo/Expansão, os dois
 * ainda de fato imutáveis) e vira um campo editável no corpo do formulário,
 * como Nome — mas só quando `cardSet.cardsCatalogados === 0`
 * (`admin_update_card_set()` trava a mudança no banco assim que existe
 * qualquer Card cadastrada; o campo aqui é desabilitado com uma explicação
 * inline no mesmo cenário, antecipando o erro em vez de deixar o usuário
 * descobrir só depois de tentar salvar). `expansion_id` não é afetado — Jogo
 * e Expansão continuam imutáveis, só na descrição do cabeçalho.
 */
export function EditCardSetDialog({
  open,
  cardSet,
  onSaved,
  onCancel,
  onLogoUpdated,
}: {
  open: boolean;
  cardSet: CardSetWithLogo | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onLogoUpdated: () => void;
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
              ? `${cardSet.gameName} · ${cardSet.expansionName}`
              : "Jogo e Expansão são imutáveis após o cadastro."}
          </DialogDescription>
        </DialogHeader>

        {/* `key={cardSet.id}` isola o estado por entidade — trocar qual Card
            Set está sendo editado remonta o formulário, mesmo padrão de
            Expansão/Game. */}
        {open && cardSet && (
          <EditCardSetForm
            key={cardSet.id}
            cardSet={cardSet}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
            onLogoUpdated={onLogoUpdated}
          />
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
  onLogoUpdated,
}: {
  cardSet: CardSetWithLogo;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
  onLogoUpdated: () => void;
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
        <div className="space-y-1.5">
          <Label>Logo</Label>
          <CardSetLogoUploader
            cardSetId={cardSet.id}
            initialLogoPath={cardSet.logoStoragePath}
            initialLogoUrl={cardSet.logoUrl}
            onChanged={onLogoUpdated}
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-card-set-code-${cardSet.id}`}>Código</Label>
          {/* `readOnly`, não `disabled` (2026-08-01): um campo `disabled` não
              entra no `FormData` do submit — o servidor sempre precisa
              receber `code` (mesmo sem mudança), já que
              `admin_update_card_set()` grava o valor enviado. `readOnly`
              impede a edição sem excluir o campo do envio; o visual
              "desabilitado" (opacidade/cursor) é replicado manualmente, já
              que o CSS `disabled:` do componente `Input` só reage ao
              atributo `disabled` de verdade. */}
          <Input
            id={`edit-card-set-code-${cardSet.id}`}
            name="code"
            defaultValue={cardSet.code}
            readOnly={cardSet.cardsCatalogados > 0}
            aria-readonly={cardSet.cardsCatalogados > 0}
            className={cardSet.cardsCatalogados > 0 ? "cursor-not-allowed bg-surface-muted opacity-70" : undefined}
            required
            maxLength={50}
          />
          {cardSet.cardsCatalogados > 0 && (
            <p className="text-xs text-muted-foreground">
              Este Card Set já tem {cardSet.cardsCatalogados}{" "}
              {cardSet.cardsCatalogados === 1 ? "carta cadastrada" : "cartas cadastradas"} — o código não pode mais
              ser alterado.
            </p>
          )}
        </div>

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
          <Label htmlFor={`edit-card-set-type-${cardSet.id}`}>Tipo</Label>
          <select
            id={`edit-card-set-type-${cardSet.id}`}
            name="set_type"
            required
            defaultValue={cardSet.setType}
            className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
          >
            {SET_TYPE_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-3">
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
          <div className="space-y-1">
            <Label htmlFor={`edit-card-set-date-${cardSet.id}`}>Data de lançamento</Label>
            <Input
              id={`edit-card-set-date-${cardSet.id}`}
              name="release_date"
              type="date"
              defaultValue={cardSet.releaseDate ?? ""}
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
