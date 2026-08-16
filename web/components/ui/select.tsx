import { forwardRef } from "react";
import type { SelectHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  /** Marca o campo com estado de erro (borda destrutiva + aria-invalid) — mesmo contrato de `Input`. */
  invalid?: boolean;
}

/**
 * `<select>` nativo estilizado — mesma linguagem visual de `Input`, mesmos
 * tokens de controle de formulário (`--control-*`, ver `app/globals.css`,
 * 2026-08-16, consolidação "Login vira Design System global"). Criado para
 * substituir as ~17 ocorrências de `<select>` hardcoded espalhadas pelo
 * Catálogo Editorial (cada uma com sua própria classe local, nenhuma
 * alinhada ao `Input` nem entre si — a principal dívida identificada no
 * diagnóstico desta rodada).
 *
 * Deliberadamente um `<select>` nativo, não um componente de listbox custom
 * (Radix/cmdk/etc.): o pedido é governança visual (mesma superfície/borda/
 * radius/foco de `Input`), não substituir o controle nativo por um mais
 * complexo. `value`/`defaultValue`/`onChange`/`name`/`disabled`/`required`/
 * `<option>` continuam 100% comportamento nativo do browser — nenhuma lógica
 * nova.
 *
 * Sem seta customizada por cima do controle nativo — os `<select>` que este
 * componente substitui nunca tiveram uma (só a seta padrão do SO/browser);
 * não introduzida agora para não ampliar o escopo além de "consolidação
 * visual".
 */
export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, invalid, ...props }, ref) => {
    return (
      <select
        aria-invalid={invalid || undefined}
        className={cn(
          "flex h-9 w-full rounded-control border border-control-border bg-control-surface px-3 py-1 text-sm shadow-subtle transition-colors",
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
Select.displayName = "Select";
