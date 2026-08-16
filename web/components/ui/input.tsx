import { forwardRef } from "react";
import type { InputHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  /** Marca o campo com estado de erro (borda destrutiva + aria-invalid). */
  invalid?: boolean;
}

/**
 * Estado de foco (2026-08-16, ver app/globals.css — "componentes de
 * formulário seguem o padrão visual aprovado no Login") — trocado de anel
 * sólido com offset (`ring-2 ring-ring ring-offset-2 ring-offset-background`,
 * padrão genérico usado em botões/elementos interativos em geral) para o
 * mesmo brilho suave sem offset já usado no input do Login
 * (`auth-form-kit.tsx`'s `authInputClassName`: borda + halo de 3px em baixa
 * opacidade na cor de destaque) — mesma linguagem, tokens globais em vez dos
 * tokens exclusivos do Auth. Dimensões (altura, radius) mantidas como
 * estavam — contexto de UI densa/tabular do backoffice, diferente do
 * formulário hero do Login (instrução explícita: não copiar dimensões
 * cegamente).
 *
 * Superfície/borda/radius/placeholder (2026-08-16, consolidação de
 * formulários): trocados de `bg-surface`/`border-input`/`rounded-md`/
 * `placeholder:text-muted-foreground` (tokens genéricos, também usados por
 * card/tabela/dialog) para `bg-control-surface`/`border-control-border`/
 * `rounded-control`/`placeholder:text-control-muted-foreground` — tokens
 * DEDICADOS a controle de formulário, com os mesmos valores já aprovados no
 * Login (`--control-*`, `app/globals.css`). Cor de texto/foco não mudaram de
 * classe (nenhuma classe de cor de texto era setada antes, e o foco já usava
 * `--primary`/`--ring`, que sempre foram idênticos a `--auth-accent`) — só
 * superfície/borda/radius/placeholder realmente divergiam do Login. Altura
 * continua `h-9` (não `h-11` do Login) — decisão já documentada acima.
 *
 * Ordem do `cn()` (mesma rodada): `invalid` movido para DEPOIS de
 * `className`. Antes, um `className` externo com cor de borda/foco própria
 * (ex.: a antiga `authInputClassName`, que ainda setava essas cores antes da
 * consolidação acima) vencia o estado de erro no merge do `tailwind-merge`
 * — um input `invalid` podia silenciosamente não mostrar a borda vermelha
 * se o consumidor passasse `className` com cor de borda. Erro sempre deve
 * vencer customização cosmética; corrigido aqui, não é mudança de
 * comportamento funcional (não altera validação, só a certeza de que o
 * estado de erro é visível).
 */
export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, invalid, ...props }, ref) => {
    return (
      <input
        type={type}
        aria-invalid={invalid || undefined}
        className={cn(
          "flex h-9 w-full rounded-control border border-control-border bg-control-surface px-3 py-1 text-sm shadow-subtle transition-colors",
          "placeholder:text-control-muted-foreground",
          "focus-visible:outline-none focus-visible:border-primary focus-visible:ring-[3px] focus-visible:ring-primary/15",
          "disabled:cursor-not-allowed disabled:opacity-50",
          className,
          invalid && "border-destructive focus-visible:border-destructive focus-visible:ring-destructive/15",
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Input.displayName = "Input";
