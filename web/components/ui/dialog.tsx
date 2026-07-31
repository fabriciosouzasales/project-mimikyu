"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { forwardRef } from "react";
import type { ComponentPropsWithoutRef, ElementRef, HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/**
 * Modal centralizado — Radix Dialog estilizado, mesma família visual do
 * Drawer mobile (`app-shell/mobile-nav.tsx`), mas com composição em vez de
 * um único componente monolítico. Fundação visual, Ciclo B (2026-07-30):
 * primeiro uso real substitui os formulários permanentes de Jogos/Expansões
 * por criação/edição em Dialog (ver STD-004).
 *
 * Fecha ao clicar fora, ao apertar Esc, ou pelo botão de fechar — exceto
 * durante `pending` (envio em andamento), quando o consumidor deve manter
 * `open` controlado e ignorar `onOpenChange(false)` para não perder um
 * envio em voo. Confirmação de descarte de dados não salvos (digitados,
 * mas não enviados) fica deliberadamente fora desta primeira versão —
 * formulários de Game/Expansion são curtos (2-4 campos); avaliar se vale a
 * pena quando um formulário maior (Card) precisar de Drawer.
 */
export const Dialog = DialogPrimitive.Root;
export const DialogTrigger = DialogPrimitive.Trigger;
export const DialogClose = DialogPrimitive.Close;

export const DialogContent = forwardRef<
  ElementRef<typeof DialogPrimitive.Content>,
  ComponentPropsWithoutRef<typeof DialogPrimitive.Content> & { hideClose?: boolean }
>(({ className, children, hideClose, ...props }, ref) => (
  <DialogPrimitive.Portal>
    <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-foreground/20 data-[state=open]:animate-overlay-in data-[state=closed]:animate-overlay-out" />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        "fixed left-1/2 top-1/2 z-50 w-full max-w-md -translate-x-1/2 -translate-y-1/2 rounded-lg border border-border bg-surface shadow-panel",
        "data-[state=open]:animate-dialog-in data-[state=closed]:animate-dialog-out",
        className,
      )}
      {...props}
    >
      {children}
      {!hideClose && (
        <DialogPrimitive.Close
          className="absolute right-3 top-3 rounded-md p-1 text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          aria-label="Fechar"
        >
          <X className="h-4 w-4" />
        </DialogPrimitive.Close>
      )}
    </DialogPrimitive.Content>
  </DialogPrimitive.Portal>
));
DialogContent.displayName = "DialogContent";

export function DialogHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-col gap-1 px-5 pt-5", className)} {...props} />;
}

export const DialogTitle = forwardRef<
  ElementRef<typeof DialogPrimitive.Title>,
  ComponentPropsWithoutRef<typeof DialogPrimitive.Title>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Title
    ref={ref}
    className={cn("pr-6 text-sm font-medium text-foreground", className)}
    {...props}
  />
));
DialogTitle.displayName = "DialogTitle";

export const DialogDescription = forwardRef<
  ElementRef<typeof DialogPrimitive.Description>,
  ComponentPropsWithoutRef<typeof DialogPrimitive.Description>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Description ref={ref} className={cn("text-xs text-muted-foreground", className)} {...props} />
));
DialogDescription.displayName = "DialogDescription";

export function DialogBody({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("px-5 py-4", className)} {...props} />;
}

export function DialogFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex justify-end gap-2 border-t border-border px-5 py-3.5", className)} {...props} />;
}
