import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef } from "react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

// Dimensões e fonte medidas via DevTools em dois badges de referência do
// Supabase (2026-07-26): font-size 9px/Inter, confirmado duas vezes pelo
// overlay de hover do Chrome sobre a caixa de texto crua — primeiro num pill
// genérico (56.05×11.25), depois reconfirmado no pill "PRODUÇÃO" do seletor
// de projeto (mesmos 56.05×11.25/9px). Padding (3px 5.5px) e `rounded-full`
// vieram do container real de um terceiro pill ("VOCÊ", 69.53×17.48px).
// `uppercase` adicionado por pedido explícito de Fabrício, também a partir
// da referência "PRODUÇÃO". Cor mantida — só dimensão, fonte e caixa (maiús-
// cula) mudaram.
const badgeVariants = cva(
  "inline-flex items-center whitespace-nowrap rounded-full border px-[5.5px] py-[3px] text-[9px] font-medium uppercase",
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
