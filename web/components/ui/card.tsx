import { forwardRef } from "react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/**
 * Fundação visual, Ciclo B (2026-07-30, ver STD-004): `Card` passa a ser o
 * único primitive de superfície do app, absorvendo a receita do `Panel`
 * (`components/catalogo/panel.tsx`) como a variante `density="compact"`, em
 * vez de manter dois componentes quase idênticos. `density="default"`
 * (implícita, sem prop) é byte-a-byte igual ao `Card` de antes — nenhuma
 * tela que já usa `Card` (Login, Perfil, Usuários, ComingSoonPage, Home)
 * muda visualmente. `Panel` continua existindo e intocado: Jogos e a Visão
 * Geral do Catálogo (que o usam hoje) só migram para este `Card` quando
 * essas telas forem replicadas (Ciclo E, com aprovação), não nesta rodada.
 */
export const Card = forwardRef<
  HTMLDivElement,
  HTMLAttributes<HTMLDivElement> & { density?: "default" | "compact" }
>(({ className, density = "default", ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      "rounded-lg border border-border bg-surface",
      density === "default" ? "shadow-panel" : "shadow-none",
      className,
    )}
    {...props}
  />
));
Card.displayName = "Card";

export const CardHeader = forwardRef<
  HTMLDivElement,
  HTMLAttributes<HTMLDivElement> & { density?: "default" | "compact" }
>(({ className, density = "default", ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      "flex flex-col gap-1.5",
      density === "default" ? "p-6" : "gap-0.5 px-4 pt-3.5 pb-2.5",
      className,
    )}
    {...props}
  />
));
CardHeader.displayName = "CardHeader";

export const CardTitle = forwardRef<
  HTMLParagraphElement,
  HTMLAttributes<HTMLHeadingElement> & { density?: "default" | "compact" }
>(({ className, density = "default", ...props }, ref) => (
  <h3
    ref={ref}
    className={cn(
      density === "default" ? "text-lg font-semibold leading-none tracking-tight" : "text-sm font-medium",
      "text-foreground",
      className,
    )}
    {...props}
  />
));
CardTitle.displayName = "CardTitle";

export const CardDescription = forwardRef<
  HTMLParagraphElement,
  HTMLAttributes<HTMLParagraphElement> & { density?: "default" | "compact" }
>(({ className, density = "default", ...props }, ref) => (
  <p
    ref={ref}
    className={cn(density === "default" ? "text-sm" : "text-xs", "text-muted-foreground", className)}
    {...props}
  />
));
CardDescription.displayName = "CardDescription";

export const CardContent = forwardRef<
  HTMLDivElement,
  HTMLAttributes<HTMLDivElement> & { density?: "default" | "compact" }
>(({ className, density = "default", ...props }, ref) => (
  <div ref={ref} className={cn(density === "default" ? "p-6 pt-0" : "px-4 pb-4", className)} {...props} />
));
CardContent.displayName = "CardContent";

export const CardFooter = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => (
    <div ref={ref} className={cn("flex items-center p-6 pt-0", className)} {...props} />
  ),
);
CardFooter.displayName = "CardFooter";
