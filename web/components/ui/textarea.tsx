import { forwardRef } from "react";
import type { TextareaHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  /** Marca o campo com estado de erro (borda destrutiva + aria-invalid). */
  invalid?: boolean;
}

/**
 * Campo de texto longo do Design System (V1-13 · E3-3: descrição da coleção).
 * Mesmos tokens de controle, foco, erro e desabilitado do `Input` (padrão do
 * Login), com altura livre e redimensionamento só vertical.
 */
export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(({ className, invalid, ...props }, ref) => {
  return (
    <textarea
      aria-invalid={invalid || undefined}
      className={cn(
        "flex min-h-20 w-full resize-y rounded-control border border-control-border bg-control-surface px-3 py-2 text-sm shadow-subtle transition-colors",
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
});
Textarea.displayName = "Textarea";
