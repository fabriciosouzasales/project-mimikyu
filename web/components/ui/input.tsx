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
 */
export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, invalid, ...props }, ref) => {
    return (
      <input
        type={type}
        aria-invalid={invalid || undefined}
        className={cn(
          "flex h-9 w-full rounded-md border border-input bg-surface px-3 py-1 text-sm shadow-subtle transition-colors",
          "placeholder:text-muted-foreground",
          "focus-visible:outline-none focus-visible:border-primary focus-visible:ring-[3px] focus-visible:ring-primary/15",
          "disabled:cursor-not-allowed disabled:opacity-50",
          invalid && "border-destructive focus-visible:border-destructive focus-visible:ring-destructive/15",
          className,
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Input.displayName = "Input";
