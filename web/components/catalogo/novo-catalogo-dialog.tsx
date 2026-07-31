"use client";

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

/**
 * Ação "Novo" — restrita a Card Set por decisão explícita (2026-07-31):
 * cadastro de novos Jogos e Expansões não deve mais ser feito a partir
 * daqui (cada um já tem sua própria tela: /catalogo/jogos e
 * /catalogo/expansoes). Antes cobria o domínio completo com um seletor
 * segmentado (Jogo/Expansão/Card Set); com uma única opção restando, o
 * seletor foi removido — Dialog de propósito único.
 *
 * Card Set continua desabilitado: admin_create_card_set() ainda não existe
 * no banco (só reservado em docs/ADR-023) — criar essa função é uma
 * migration, fora do escopo desta tela e das restrições da sessão. O botão
 * "Novo" continua visível (preserva a ação principal já aprovada); só a
 * submissão é que não está disponível, com o motivo declarado.
 */
export function NovoCatalogoDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  function handleClose() {
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && handleClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Nova Coleção</DialogTitle>
          <DialogDescription>Cadastre uma nova Coleção (Card Set) no catálogo.</DialogDescription>
        </DialogHeader>

        <DialogBody className="space-y-3">
          <InlineFeedback tone="warning">
            Cadastro de Card Set ainda não disponível — depende de uma função de banco
            (admin_create_card_set) reservada, mas ainda não implementada.
          </InlineFeedback>
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={handleClose}>
            Fechar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
