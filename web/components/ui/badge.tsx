import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef } from "react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center whitespace-nowrap rounded-full border px-2.5 py-0.5 text-xs font-medium",
  {
    variants: {
      variant: {
        default: "border-transparent bg-accent text-accent-foreground",
        outline: "border-border text-muted-foreground",
        /** Pílula com contorno na cor primária — usada para destacar um status importante (ex.: Administrador). */
        primary: "border-primary/40 bg-primary/5 text-primary",
        /** Pílula na cor de aviso — mais saturada que `primary`, usada para chamar atenção para uma restrição que o usuário precisa notar (ex.: "Fixo" em nome de usuário imutável). */
        warning: "border-warning/40 bg-warning/10 text-warning",
      },
    },
    defaultVariants: { variant: "default" },
  },
);

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export const Badge = forwardRef<HTMLSpanElement, BadgeProps>(({ className, variant, ...props }, ref) => (
  <span ref={ref} className={cn(badgeVariants({ variant }), className)} {...props} />
));
Badge.displayName = "Badge";
