import { forwardRef } from "react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/**
 * Superfície flat exclusiva do módulo Catálogo Editorial (validação de nova
 * linguagem visual, 2026-07-26) — deliberadamente separada de
 * `components/ui/card.tsx`, que continua servindo /usuarios, /perfil e o
 * resto do app sem alteração nenhuma, por instrução explícita de Fabrício
 * ("nesta sessão, concentre todas as alterações apenas no módulo
 * Editorial"). Se esta linguagem for validada, um segundo incremento evolui
 * `ui/card.tsx` e propaga para o app inteiro; até lá, os dois convivem.
 *
 * Diferenças deliberadas frente a `Card`: sem sombra (`shadow-panel`
 * removida — flat puro, só borda), padding reduzido (mais densidade,
 * mais informação na primeira dobra), sem tracking apertado forçado no
 * título.
 */
export const Panel = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => (
    <div ref={ref} className={cn("rounded-lg border border-border bg-surface", className)} {...props} />
  ),
);
Panel.displayName = "Panel";

export const PanelHeader = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => (
    <div ref={ref} className={cn("flex flex-col gap-0.5 px-4 pt-3.5 pb-2.5", className)} {...props} />
  ),
);
PanelHeader.displayName = "PanelHeader";

export const PanelTitle = forwardRef<HTMLParagraphElement, HTMLAttributes<HTMLHeadingElement>>(
  ({ className, ...props }, ref) => (
    <h3 ref={ref} className={cn("text-sm font-medium text-foreground", className)} {...props} />
  ),
);
PanelTitle.displayName = "PanelTitle";

export const PanelDescription = forwardRef<HTMLParagraphElement, HTMLAttributes<HTMLParagraphElement>>(
  ({ className, ...props }, ref) => (
    <p ref={ref} className={cn("text-xs text-muted-foreground", className)} {...props} />
  ),
);
PanelDescription.displayName = "PanelDescription";

export const PanelContent = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => <div ref={ref} className={cn("px-4 pb-4", className)} {...props} />,
);
PanelContent.displayName = "PanelContent";
