"use client";

import { useActionState, useEffect, useState } from "react";
import { createCardSet, type CardSetActionState } from "@/app/catalogo/card-sets/actions";
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
import type { ExpansaoRow } from "@/lib/catalogo/queries";

const initialState: CardSetActionState = { error: null };

/** Exportado (2026-07-31) para reuso por `EditCardSetForm` (`card-set-dialogs.tsx`), que ganhou o mesmo seletor de tipo. */
export const SET_TYPE_OPTIONS: { value: string; label: string }[] = [
  { value: "REGULAR", label: "Regular" },
  { value: "SPECIAL", label: "Especial" },
  { value: "PROMO", label: "Promocional" },
  { value: "ENERGY", label: "Energia" },
];

/**
 * Ação "Novo" — restrita a Card Set por decisão explícita (2026-07-31):
 * cadastro de novos Jogos e Expansões não deve mais ser feito a partir
 * daqui (cada um já tem sua própria tela: /catalogo/jogos e
 * /catalogo/expansoes). Antes cobria o domínio completo com um seletor
 * segmentado (Jogo/Expansão/Card Set); com uma única opção restando, o
 * seletor foi removido — Dialog de propósito único.
 *
 * Cadastro de Card Set implementado em 2026-07-31, rodada seguinte (pedido
 * explícito de Fabrício: "ainda não consigo incluir novos itens pela própria
 * tela") — `admin_create_card_set()` (Query 2051, ADR-023) deixou de estar
 * fora de escopo. Diferente de `EditCardSetForm` (só nome/ordem de
 * lançamento), este formulário precisa cobrir todos os campos estruturais
 * obrigatórios de `card_set`: Expansão (seletor agrupado por Jogo, mesmo
 * padrão de `CreateExpansionForm`), código, nome, tipo (Regular/Especial/
 * Promocional/Energia), ordem de lançamento, data de lançamento (opcional)
 * e quantidades base/total. Até Fabrício confirmar a execução da Query 2051
 * (ritual de pareamento de SQL do projeto), a submissão retorna o erro
 * genuíno do Postgres (função inexistente) — mesma situação já vivida por
 * `EditCardSetForm` até a Query 2048 ser confirmada.
 *
 * Ajuste 2026-07-31, mesmo dia (teste real de Fabrício): opção "Energia"
 * (`ENERGY`) adicionada ao seletor — faltava, apesar de já ser um valor
 * válido de `set_type` desde a Migration 263 (ver `admin_create_card_set()`
 * v1.1, corrigida na mesma rodada). Rótulo de `PROMO` simplificado de
 * "Promocional (Black Star Promos)" para "Promocional" (pedido explícito).
 */
export function NovoCatalogoDialog({
  open,
  onOpenChange,
  expansoes,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  expansoes: ExpansaoRow[];
  onSaved: (message: string, id?: string) => void;
}) {
  const [pending, setPending] = useState(false);

  function handleClose() {
    if (pending) return;
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && handleClose()}>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>Nova Coleção</DialogTitle>
          <DialogDescription>Cadastre uma nova Coleção (Card Set) no catálogo.</DialogDescription>
        </DialogHeader>

        {open && (
          <CreateCardSetForm
            expansoes={expansoes}
            onSaved={(message, id) => {
              onSaved(message, id);
              onOpenChange(false);
            }}
            onCancel={handleClose}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function CreateCardSetForm({
  expansoes,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  expansoes: ExpansaoRow[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createCardSet, initialState);
  const [setType, setSetType] = useState("REGULAR");

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Card Set cadastrado com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  // Agrupado por Jogo, mesmo critério visual da galeria de Expansões
  // (`getExpansoesGroupedByGame`) — aqui só reordena o que já veio de
  // `getExpansoes()` (sem filtro), sem query nova.
  const gameNames = Array.from(new Set(expansoes.map((expansao) => expansao.gameName)));

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor="new-card-set-expansion">Expansão</Label>
          <select
            id="new-card-set-expansion"
            name="expansion_id"
            required
            defaultValue=""
            className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
          >
            <option value="" disabled>
              Selecione…
            </option>
            {gameNames.map((gameName) => (
              <optgroup key={gameName} label={gameName}>
                {expansoes
                  .filter((expansao) => expansao.gameName === gameName)
                  .map((expansao) => (
                    <option key={expansao.id} value={expansao.id}>
                      {expansao.name} ({expansao.code})
                    </option>
                  ))}
              </optgroup>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-card-set-code">Código</Label>
            <Input id="new-card-set-code" name="code" placeholder="Ex.: ME1" required maxLength={50} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-card-set-type">Tipo</Label>
            <select
              id="new-card-set-type"
              name="set_type"
              required
              value={setType}
              onChange={(event) => setSetType(event.target.value)}
              className="h-9 w-full rounded-md border border-border bg-background px-3 text-sm"
            >
              {SET_TYPE_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-card-set-name">Nome</Label>
          <Input id="new-card-set-name" name="name" placeholder="Ex.: Megaevolução" required maxLength={150} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-card-set-release-order">Ordem de lançamento</Label>
            <Input
              id="new-card-set-release-order"
              name="release_order"
              type="number"
              min={1}
              step={1}
              placeholder="Ex.: 1"
              required
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-card-set-release-date">Data de lançamento</Label>
            <Input id="new-card-set-release-date" name="release_date" type="date" />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-card-set-base-size">Quantidade base</Label>
            <Input
              id="new-card-set-base-size"
              name="base_set_size"
              type="number"
              min={1}
              step={1}
              placeholder="Ex.: 197"
              required
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-card-set-total-size">Quantidade total</Label>
            <Input
              id="new-card-set-total-size"
              name="total_set_size"
              type="number"
              min={1}
              step={1}
              placeholder="Ex.: 218"
              required
            />
          </div>
        </div>

        {setType === "PROMO" && (
          <InlineFeedback tone="warning">
            Card Sets promocionais exigem quantidade base igual à quantidade total, e só é permitido um por
            Expansão.
          </InlineFeedback>
        )}

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
