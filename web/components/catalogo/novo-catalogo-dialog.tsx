"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createGame, type GameActionState } from "@/app/catalogo/jogos/actions";
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
import { CreateExpansionForm } from "@/components/catalogo/expansoes-table";
import { cn } from "@/lib/utils";
import type { GameOption } from "@/lib/catalogo/queries";

const initialGameState: GameActionState = { error: null };

type Entidade = "jogo" | "expansao" | "card-set";

const OPCOES: { value: Entidade; label: string }[] = [
  { value: "jogo", label: "Jogo" },
  { value: "expansao", label: "Expansão" },
  { value: "card-set", label: "Card Set" },
];

/**
 * Ação "Novo" cobrindo o domínio completo (ajuste aprovado 2026-07-31: "a
 * ação principal deve contemplar o domínio completo, não apenas Card Set").
 * Um único Dialog, escolha compacta no topo, campos do tipo escolhido
 * abaixo — nunca um Dialog por entidade.
 *
 * Jogo e Expansão reaproveitam as Server Actions e o formulário já
 * existentes (createGame, CreateExpansionForm) sem duplicar lógica de
 * negócio. Card Set fica desabilitado: admin_create_card_set() ainda não
 * existe no banco (só reservado em docs/ADR-023) — criar essa função é uma
 * migration, fora do escopo desta tela e das restrições da sessão. A opção
 * continua visível (preserva a intenção visual/funcional da especificação
 * aprovada); só a submissão é que não está disponível, com o motivo
 * declarado em vez de escondido.
 */
export function NovoCatalogoDialog({
  open,
  onOpenChange,
  jogos,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  jogos: GameOption[];
}) {
  const router = useRouter();
  const [entidade, setEntidade] = useState<Entidade>("jogo");
  const [pending, setPending] = useState(false);

  function handleClose() {
    if (pending) return;
    onOpenChange(false);
  }

  function handleSaved() {
    router.refresh();
    onOpenChange(false);
    setEntidade("jogo");
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && handleClose()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Novo no catálogo</DialogTitle>
          <DialogDescription>Escolha o que você está cadastrando.</DialogDescription>
        </DialogHeader>

        <div className="px-5">
          <div className="inline-flex rounded-md border border-border p-0.5">
            {OPCOES.map((opcao) => (
              <button
                key={opcao.value}
                type="button"
                disabled={pending}
                onClick={() => setEntidade(opcao.value)}
                className={cn(
                  "rounded-[5px] px-3 py-1 text-xs font-medium transition-colors",
                  entidade === opcao.value
                    ? "bg-accent text-accent-foreground"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                {opcao.label}
              </button>
            ))}
          </div>
        </div>

        {open && entidade === "jogo" && (
          <CreateGameFormInline onSaved={handleSaved} onCancel={handleClose} onPendingChange={setPending} />
        )}

        {open && entidade === "expansao" && (
          <CreateExpansionForm jogos={jogos} onSaved={handleSaved} onCancel={handleClose} onPendingChange={setPending} />
        )}

        {entidade === "card-set" && (
          <DialogBody className="space-y-3">
            <InlineFeedback tone="warning">
              Cadastro de Card Set ainda não disponível — depende de uma função de banco
              (admin_create_card_set) reservada, mas ainda não implementada.
            </InlineFeedback>
            <DialogFooter>
              <Button type="button" variant="outline" size="sm" onClick={handleClose}>
                Fechar
              </Button>
            </DialogFooter>
          </DialogBody>
        )}
      </DialogContent>
    </Dialog>
  );
}

function CreateGameFormInline({
  onSaved,
  onCancel,
  onPendingChange,
}: {
  onSaved: () => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createGame, initialGameState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-game-code">Código</Label>
            <Input id="new-game-code" name="code" placeholder="Ex.: PTCG" required maxLength={20} />
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
