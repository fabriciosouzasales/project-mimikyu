import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef } from "react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

// Contraste no tema escuro (fix 2026-08-23, pedido de Fabrício a partir de
// captura real de "Valor por Set") — `destructive` e `warning` usavam o
// token "-foreground" (`text-destructive`/`text-warning-foreground`), que no
// tema escuro é uma cor MUITO escura (`--destructive: 6 64% 20%`,
// `--warning-foreground: 26 83% 10%` — pensados como texto SOBRE um
// preenchimento sólido claro, não como texto direto sobre o fundo
// translúcido `bg-*/10` que o Alert usa). Mesmo antipadrão já corrigido em
// `StateBadge`/`ui/badge.tsx` (`dark:text-destructive-foreground` no tone
// "danger"/"destructive") e replicado aqui: `destructive` ganha o mesmo
// override; `warning` troca para `text-warning` puro (a cor base, não a
// "-foreground") — mesma escolha já usada e validada em `ui/badge.tsx`
// (`variant="warning"`), com bom contraste nos dois temas sem precisar de
// override condicional.
const alertVariants = cva("relative w-full rounded-lg border p-4 text-sm [&>svg]:h-4 [&>svg]:w-4", {
  variants: {
    variant: {
      default: "border-border bg-surface-muted text-foreground",
      destructive: "border-destructive/30 bg-destructive/10 text-destructive dark:text-destructive-foreground",
      success: "border-border bg-surface-muted text-foreground",
      warning: "border-warning/30 bg-warning/10 text-warning",
    },
  },
  defaultVariants: { variant: "default" },
});

export interface AlertProps extends HTMLAttributes<HTMLDivElement>, VariantProps<typeof alertVariants> {}

export const Alert = forwardRef<HTMLDivElement, AlertProps>(({ className, variant, ...props }, ref) => (
  <div ref={ref} role="alert" className={cn(alertVariants({ variant }), className)} {...props} />
));
Alert.displayName = "Alert";
