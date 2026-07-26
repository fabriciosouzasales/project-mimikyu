import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef } from "react";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        // Fundo translúcido na cor primária, sem borda — mesmo padrão do
        // Badge variant="primary" (ex.: badge "Administrador" na coluna
        // Papel), pedido explícito de Fabrício em 2026-07-26 para unificar a
        // linguagem visual de "destaque na cor primária" entre botões e
        // badges, no lugar do preenchimento sólido anterior. `border-0`
        // confirmado via DevTools num botão "tiny" de referência do Supabase
        // ("Gerenciar membros"): todos os `border-*-width` computados são
        // `0px`, apesar de o elemento definir `border-color`/`border-style`
        // — a borda existe na folha de estilo, mas nunca é visível.
        default: "border-0 bg-primary/5 text-primary hover:bg-primary/10 active:bg-primary/15",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline: "border border-border bg-transparent hover:bg-surface-muted",
        // Borda na mesma cor da fonte (não a borda neutra de `outline`) —
        // pedido explícito de Fabrício para o botão de criação de itens
        // (ex.: "Cadastrar novo jogo"), posicionado fora do card da tabela,
        // no padrão de ação primária de página do Supabase. Reutilizável
        // pelos ciclos seguintes (Expansion/Card Set/Card).
        "outline-primary": "border border-primary bg-transparent text-primary hover:bg-primary/5",
        ghost: "hover:bg-surface-muted",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-4 py-2",
        // Dimensões e fonte medidas via DevTools num botão "tiny" de
        // referência do Supabase (2026-07-26, ex.: "Gerenciar membros"):
        // caixa externa 135.1×26px, padding 4px 10px (medição direta do
        // elemento, confiável). Font-size CORRIGIDO para 12px: a primeira
        // leitura (15px) veio do painel Computed com outro nó selecionado
        // (provavelmente um pai), não o texto do botão; medição direta sobre
        // o nó de texto (mesmo método usado no menu/badge) confirma 12px —
        // por coincidência, igual ao `text-xs` que já existia antes desta
        // rodada de ajustes. Cor mantida — só dimensão e borda mudaram de
        // fato, pedido explícito de Fabrício.
        sm: "h-[26px] rounded-md px-2.5 py-1 text-xs",
        lg: "h-10 rounded-md px-6",
        icon: "h-9 w-9",
        // Ícone isolado (ex.: editar/excluir numa linha de tabela), mesma
        // altura de `sm` — evita um botão-ícone visualmente maior que os
        // botões de texto ao lado dele na mesma linha.
        "icon-sm": "h-[26px] w-[26px] rounded-md p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />;
  },
);
Button.displayName = "Button";
