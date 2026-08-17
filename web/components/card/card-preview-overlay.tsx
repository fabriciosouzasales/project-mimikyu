"use client";

import type { ReactNode } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";

/**
 * Backdrop/moldura do preview ampliado de uma carta — fonte única extraída
 * em 2026-08-17 do modal `Cartas` (`CartaZoomDialog`/`CartaZoomDialogReadOnly`,
 * ambos idênticos estruturalmente) para ser reutilizada por `/pesquisa`
 * (ver `card-image-preview.tsx` para o racional completo). `Dialog`/
 * `DialogContent` do Radix (`components/ui/dialog.tsx`) já cobrem, sem
 * código adicional aqui: fechar ao clicar no backdrop, fechar com `Escape`,
 * bloqueio de scroll da página por trás, foco preso dentro do overlay
 * enquanto aberto e restaurado ao elemento que abriu quando fecha — mesmo
 * comportamento herdado por toda tela que já usa `Dialog` no projeto (ver
 * `STD-004`).
 *
 * Sem "chrome" do Dialog padrão (fundo/borda/sombra do card do modal) —
 * `border-none bg-transparent p-0 shadow-none`, deixando só a carta em si
 * visível sobre o backdrop escurecido; `hideClose` porque o fechamento por
 * botão explícito não faz parte da experiência aprovada de `Cartas` (fecha
 * pelo backdrop/Escape). Sem rodapé de texto (nome/Card Set/raridade) —
 * `Cartas` nunca teve um; `title` alimenta só o `DialogTitle` `sr-only`
 * (acessibilidade), nunca aparece visualmente.
 */
export function CardPreviewOverlay({
  open,
  onClose,
  title,
  useViewTransition = false,
  children,
}: {
  open: boolean;
  onClose: () => void;
  /** Nome acessível do preview — só para leitor de tela (`DialogTitle sr-only`), nunca renderizado visualmente. */
  title: string;
  /**
   * `true` quando o chamador já está orquestrando o morph via View
   * Transitions API (`lib/view-transitions.ts`) — desliga o zoom+fade
   * padrão do `DialogContent` (prop `animated`), evitando as duas
   * animações competindo. `false` (default) usa o zoom+fade padrão do
   * Dialog — mesmo fallback que `Cartas` usa quando View Transitions não
   * está disponível ou `prefers-reduced-motion: reduce` está ativo.
   */
  useViewTransition?: boolean;
  children: ReactNode;
}) {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent
        hideClose
        animated={!useViewTransition}
        aria-describedby={undefined}
        className="w-full max-w-[380px] border-none bg-transparent p-0 shadow-none sm:max-w-[460px]"
      >
        <DialogTitle className="sr-only">{title}</DialogTitle>
        {children}
      </DialogContent>
    </Dialog>
  );
}
