import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef } from "react";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import ctaStyles from "@/components/ui/button-cta.module.css";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        // CTA em gradiente dourado (2026-08-16, ver app/globals.css) —
        // substitui o teste de cor de 2026-07-31 (fundo/borda/texto
        // #A39475/#F7F5ED, contraste abaixo do mínimo recomendado, ver
        // histórico completo em git blame). A ação primária do sistema
        // passa a usar o mesmo tratamento visual aprovado no botão "Entrar"
        // do Login (`components/auth/auth-panel.module.css`'s `.cta`,
        // extraído para `button-cta.module.css` e reaplicado aqui via
        // tokens globais `--primary`/`--primary-hover`/`--primary-foreground`
        // — não duplica valores, já que esses tokens agora são o mesmo
        // dourado MMKYU do Auth). Escopo: só "default" — os demais variants
        // (destructive, outline, outline-primary, ghost, link) mantêm sua
        // função semântica própria (perigo, ação secundária/terciária); uma
        // única cor "para todos os botões" apagaria essa distinção.
        default: cn(ctaStyles.cta, "border border-transparent"),
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        // `text-foreground` explícito (2026-07-31, correção de contraste
        // pedida por Fabrício — ícone de "Editar" na tabela de Jogos ficou
        // invisível no tema escuro): sem cor de texto própria, um `<Button
        // variant="outline">` só com ícone (sem `text-destructive`/outra cor
        // explícita, como o botão de excluir já tinha) herdava cor de texto
        // insuficiente no tema escuro. Afeta todo botão outline sem cor
        // própria — inclui os mesmos ícones de editar em Expansões/Coleções
        // e as setas de paginação, que tinham o mesmo problema latente.
        outline: "border border-border bg-transparent text-foreground hover:bg-surface-muted",
        // Borda na mesma cor da fonte (não a borda neutra de `outline`) —
        // pedido explícito de Fabrício para o botão de criação de itens
        // (ex.: "Cadastrar novo jogo"), posicionado fora do card da tabela,
        // no padrão de ação primária de página do Supabase. Reutilizável
        // pelos ciclos seguintes (Expansion/Card Set/Card). `text-primary-ink`
        // (2026-08-16, não `text-primary` puro) — legibilidade como texto
        // corrido, ver app/globals.css.
        "outline-primary": "border border-primary bg-transparent text-primary-ink hover:bg-primary/5",
        ghost: "hover:bg-surface-muted",
        link: "text-primary-ink underline-offset-4 hover:underline",
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
