"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useRef, useState, useTransition } from "react";
import styles from "./acervo.module.css";

/**
 * Painel de detalhe de Meu acervo — painel lateral no desktop, tela cheia no
 * mobile (decisão de UX aprovada). Radix Dialog, a mesma base do Drawer mobile
 * do AppShell (`app-shell/mobile-nav.tsx`) e do `ui/dialog`: foco preso no
 * painel, Esc e clique fora fecham, foco volta ao card ao fechar.
 *
 * O conteúdo é renderizado no servidor (`?carta=` na URL — link direto e
 * voltar do navegador funcionam). Fechar = navegar para a mesma lista sem o
 * parâmetro, sem rolar a página.
 *
 * INVENTORY-DETAIL-REOPEN-FIX-01 — o painel às vezes não abria ao clicar numa
 * carta. Causa: ao fechar, o estado local `open` vira `false` na hora e a
 * navegação de fechamento roda em transição; se outra navegação com `?carta=`
 * chega antes dela terminar (clicar em outra carta logo após fechar, ou na
 * mesma), a de fechamento é descartada, o painel nunca desmonta e fica preso
 * em `open=false`. Duas defesas:
 *  1. o chamador passa `key` com a carta (`acervo-view.tsx`): carta diferente
 *     = painel novo, aberto;
 *  2. se a transição de fechamento termina e o painel ainda está montado, a
 *     URL ainda pede uma carta — então ele reabre.
 * Além disso, ao desmontar, devolve o `pointer-events` do <body> caso o Radix
 * não tenha tido chance de restaurá-lo (desmontagem com o painel aberto, p.ex.
 * ao remover o último exemplar), para a página nunca ficar "travada".
 */
export function AcervoDetailSheet({
  title,
  closeHref,
  children,
}: {
  title: string;
  closeHref: string;
  children: ReactNode;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(true);
  const [isClosing, startTransition] = useTransition();
  const closeRequested = useRef(false);

  useEffect(() => {
    if (isClosing || !closeRequested.current) return;
    closeRequested.current = false;
    // Ainda montado depois da navegação de fechamento: ela foi substituída por
    // outra que pede um detalhe. Mostrar o painel de novo.
    setOpen(true);
  }, [isClosing]);

  useEffect(
    () => () => {
      if (document.body.style.pointerEvents === "none") document.body.style.pointerEvents = "";
    },
    [],
  );

  return (
    <DialogPrimitive.Root
      open={open}
      onOpenChange={(next) => {
        if (next) return;
        closeRequested.current = true;
        setOpen(false);
        startTransition(() => router.replace(closeHref, { scroll: false }));
      }}
    >
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={styles.overlay} />
        <DialogPrimitive.Content
          className={styles.drawer}
          aria-describedby={undefined}
          onOpenAutoFocus={(event) => {
            // O foco vai direto ao campo marcado com data-autofocus (a quantidade
            // de exemplares), já selecionado para digitar por cima. Só com
            // ponteiro fino: no celular, focar abriria o teclado sem pedido.
            if (!window.matchMedia("(pointer: fine)").matches) return;
            const target = (event.currentTarget as HTMLElement | null)?.querySelector<HTMLInputElement>("[data-autofocus]");
            if (!target) return;
            event.preventDefault();
            target.focus();
            target.select();
          }}
        >
          <div className={styles.drawerHeader}>
            <DialogPrimitive.Title className="text-sm font-medium text-foreground">{title}</DialogPrimitive.Title>
            <DialogPrimitive.Close
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>
          <div className={styles.drawerBody}>{children}</div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
