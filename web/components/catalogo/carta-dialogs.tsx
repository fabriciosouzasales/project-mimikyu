"use client";

import { useActionState, useEffect, useState } from "react";
import { updateCard } from "@/app/catalogo/cartas/actions";
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
import type { CardActionState } from "@/app/catalogo/cartas/actions";
import type { CartaCompletaRow, CategoriaOption, RaridadeRow } from "@/lib/catalogo/queries";

const initialState: CardActionState = { error: null };

/**
 * Dialog de edição de Card — novo em 2026-08-07 (pedido de Fabrício:
 * "Encontrei duas cartas cadastradas com a raridade errada... vamos incluir
 * um botão de ação rápida abaixo de cada carta, no canto inferior direito
 * para abrir a tela de alteração do cadastro, possibilitando editar todas as
 * informações possíveis referente aquela carta específica, incluindo a sua
 * raridade" — mesmo padrão explícito de `EditCardSetDialog`: "Assim como
 * fizemos para Coleções"). Cópia fiel da estrutura de `EditCardSetDialog`:
 * campos imutáveis (Card Set + Número) saem do corpo do formulário e viram a
 * `DialogDescription` do cabeçalho, `key={carta.id}` isola o estado do
 * formulário por entidade.
 *
 * Campos editáveis: Nome, Total (opcional — nem toda Card tem denominador,
 * ver comentário de `collector_total` em `140_create_card_table.sql`), Ordem
 * editorial, Raridade e Categoria. `card_set_id` **e `collector_number`**
 * ficam de fora por decisão já registrada em ADR-023 ("Campos
 * estruturalmente protegidos nunca são alteráveis por atualização" —
 * mudar identidade não é o mesmo que corrigir conteúdo, mesmo sob decisão
 * administrativa explícita) — por isso o Número aparece só como texto no
 * cabeçalho, ao lado da Coleção, nunca como campo do formulário. `is_active`
 * (soft delete) também fica de fora — não pedido, e exclusão de Card é uma
 * ação distinta de edição.
 */
export function EditCardDialog({
  open,
  carta,
  cardSetLabel,
  raridades,
  categorias,
  onSaved,
  onCancel,
}: {
  open: boolean;
  carta: CartaCompletaRow | null;
  /** "{Coleção} ({Código})" — resolvido pelo componente pai, que já tem o Card Set selecionado em mãos; evita esta tela precisar buscar o Card Set de novo. */
  cardSetLabel: string;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
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
          <DialogTitle>Editar Card</DialogTitle>
          {/* Fallback estático só aparece durante o frame de saída do
              Dialog, quando `carta` já voltou a `null` mas o Radix ainda
              está animando o fechamento — mesmo cuidado de `EditCardSetDialog`.
              Número junto da Coleção (não um campo do formulário) — ver
              comentário acima sobre `collector_number` ser estruturalmente
              protegido (ADR-023). */}
          <DialogDescription>
            {carta ? `${cardSetLabel} · Nº ${carta.collectorNumber}` : "Coleção e número são imutáveis após o cadastro."}
          </DialogDescription>
        </DialogHeader>

        {open && carta && (
          <EditCardForm
            key={carta.id}
            carta={carta}
            raridades={raridades}
            categorias={categorias}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditCardForm({
  carta,
  raridades,
  categorias,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  carta: CartaCompletaRow;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateCard, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Card atualizada com sucesso.", carta.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={carta.id} />
      <DialogBody className="space-y-4">
        <div className="space-y-1">
          <Label htmlFor={`edit-card-name-${carta.id}`}>Nome</Label>
          <Input id={`edit-card-name-${carta.id}`} name="name" defaultValue={carta.name} required maxLength={150} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-card-total-${carta.id}`}>Total (opcional)</Label>
            <Input
              id={`edit-card-total-${carta.id}`}
              name="collector_total"
              type="number"
              min={1}
              step={1}
              defaultValue={carta.collectorTotal ?? ""}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-card-order-${carta.id}`}>Ordem editorial</Label>
            <Input
              id={`edit-card-order-${carta.id}`}
              name="collector_order"
              type="number"
              min={1}
              step={1}
              defaultValue={carta.collectorOrder}
              required
            />
          </div>
        </div>
        <p className="-mt-2 text-xs text-muted-foreground">
          Ordem editorial: posição da carta no checklist oficial do Card Set — define a ordem de exibição na galeria.
        </p>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-card-rarity-${carta.id}`}>Raridade</Label>
            <select
              id={`edit-card-rarity-${carta.id}`}
              name="rarity_id"
              required
              defaultValue={carta.rarityId}
              className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
            >
              {raridades.map((raridade) => (
                <option key={raridade.id} value={raridade.id}>
                  {raridade.name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-card-category-${carta.id}`}>Categoria</Label>
            <select
              id={`edit-card-category-${carta.id}`}
              name="category_id"
              required
              defaultValue={carta.categoryId}
              className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
            >
              {categorias.map((categoria) => (
                <option key={categoria.id} value={categoria.id}>
                  {categoria.name}
                </option>
              ))}
            </select>
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
